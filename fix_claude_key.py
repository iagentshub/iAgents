#!/usr/bin/env python3
"""
Script para diagnosticar y reparar problemas de encriptación de API keys.

El problema: las API keys se encriptan con GAIA_AGENTS_SECRET (o jwt_secret del settings.json).
Si este secreto cambia, las keys existentes no se pueden desencriptar correctamente.

Uso:
    python fix_claude_key.py check          # Diagnosticar
    python fix_claude_key.py decrypt <id>   # Ver la API key desencriptada
    python fix_claude_key.py reencrypt <id> # Re-encriptar con nuevo secreto
"""

import json
import sys
from pathlib import Path

# Setup paths
DATA_DIR = Path(__file__).parent / "data"
DB_PATH = DATA_DIR / "hub.db"
SETTINGS_PATH = DATA_DIR / "settings.json"


def get_secret():
    """Obtener el secreto actual."""
    import os

    env_secret = os.environ.get("GAIA_AGENTS_SECRET")
    if env_secret:
        return env_secret

    if SETTINGS_PATH.exists():
        settings = json.loads(SETTINGS_PATH.read_text())
        return settings.get("jwt_secret", "")
    return ""


def decrypt_key(encrypted: str, secret: str) -> str:
    """Desencriptar una API key."""
    if not encrypted or not encrypted.startswith("enc:"):
        return encrypted

    import base64
    import hashlib
    from cryptography.fernet import Fernet

    # Mismo algoritmo que en crypto.py
    SALT = b"iagentshub-api-keys-v1"
    ITERATIONS = 100_000

    key_bytes = hashlib.pbkdf2_hmac(
        "sha256", secret.encode("utf-8"), SALT, ITERATIONS, dklen=32
    )
    fernet = Fernet(base64.urlsafe_b64encode(key_bytes))

    try:
        return fernet.decrypt(encrypted[4:].encode("utf-8")).decode("utf-8")
    except Exception as e:
        return f"<ERROR: {e}>"


def encrypt_key(plaintext: str, secret: str) -> str:
    """Encriptar una API key."""
    if not plaintext:
        return plaintext

    import base64
    import hashlib
    from cryptography.fernet import Fernet

    SALT = b"iagentshub-api-keys-v1"
    ITERATIONS = 100_000

    key_bytes = hashlib.pbkdf2_hmac(
        "sha256", secret.encode("utf-8"), SALT, ITERATIONS, dklen=32
    )
    fernet = Fernet(base64.urlsafe_b64encode(key_bytes))

    token = fernet.encrypt(plaintext.encode("utf-8")).decode("utf-8")
    return "enc:" + token


def check_connections():
    """Diagnosticar conexiones existentes."""
    import sqlite3

    if not DB_PATH.exists():
        print(f"❌ Base de datos no encontrada: {DB_PATH}")
        return

    secret = get_secret()
    print(f"✓ Secreto actual: {secret[:8]}...{secret[-8:]}")
    print()

    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    cur.execute("SELECT id, data FROM connections")
    rows = cur.fetchall()

    claude_conns = []
    for row in rows:
        data = json.loads(row["data"])
        if data.get("type") == "claude":
            claude_conns.append((row["id"], data))

    if not claude_conns:
        print("ℹ No hay conexiones Claude configuradas.")
        return

    print(f"Conexiones Claude encontradas: {len(claude_conns)}\n")

    for conn_id, data in claude_conns:
        name = data.get("name", "Sin nombre")
        api_key_enc = data.get("api_key", "")

        print(f"📦 Conexión: {name} (ID: {conn_id})")
        print(f"   Tipo: {data.get('type')}")
        print(f"   Modelo: {data.get('model', 'N/A')}")
        print(f"   URL: {data.get('url', 'N/A')}")
        print(
            f"   API Key (encriptada): {api_key_enc[:20] if api_key_enc else 'N/A'}..."
        )

        # Intentar desencriptar
        if api_key_enc:
            api_key_dec = decrypt_key(api_key_enc, secret)
            if api_key_dec.startswith("<ERROR:"):
                print(f"   ❌ PROBLEMA: {api_key_dec}")
                print(f"   💡 Solución: python fix_claude_key.py reencrypt {conn_id}")
            elif api_key_dec.startswith("sk-ant-"):
                print(f"   ✓ API Key válida: {api_key_dec[:15]}...{api_key_dec[-8:]}")
            else:
                print(f"   ⚠ API Key desencriptada: {api_key_dec[:50]}...")
                print(f"   (No parece una API key válida de Anthropic)")
        else:
            print(f"   ⚠ No hay API Key configurada")
        print()

    conn.close()


def show_decrypted(conn_id: str):
    """Mostrar la API key desencriptada para una conexión."""
    import sqlite3

    if not DB_PATH.exists():
        print(f"❌ Base de datos no encontrada: {DB_PATH}")
        return

    secret = get_secret()

    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    cur.execute("SELECT id, data FROM connections WHERE id = ?", (conn_id,))
    row = cur.fetchone()

    if not row:
        print(f"❌ Conexión no encontrada: {conn_id}")
        return

    data = json.loads(row["data"])
    api_key_enc = data.get("api_key", "")
    api_key_dec = decrypt_key(api_key_enc, secret)

    print(f"Conexión: {data.get('name', 'Sin nombre')}")
    print(f"API Key desencriptada: {api_key_dec}")
    conn.close()


def reencrypt_connection(conn_id: str, new_plaintext: str = None):
    """Re-encriptar la API key de una conexión con el secreto actual."""
    import sqlite3

    if not DB_PATH.exists():
        print(f"❌ Base de datos no encontrada: {DB_PATH}")
        return

    secret = get_secret()

    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    cur.execute("SELECT id, data FROM connections WHERE id = ?", (conn_id,))
    row = cur.fetchone()

    if not row:
        print(f"❌ Conexión no encontrada: {conn_id}")
        return

    data = json.loads(row["data"])

    if new_plaintext:
        # Usar nueva API key proporcionada
        plaintext = new_plaintext
        print(f"✓ Usando nueva API key proporcionada")
    else:
        # Intentar desencriptar la existente
        api_key_enc = data.get("api_key", "")
        plaintext = decrypt_key(api_key_enc, secret)

        if plaintext.startswith("<ERROR:"):
            print(f"❌ No se puede desencriptar la API key existente.")
            print(f"   Proporciona la API key en texto plano:")
            print(f"   python fix_claude_key.py reencrypt {conn_id} sk-ant-...")
            return

        print(f"✓ API Key desencriptada: {plaintext[:15]}...{plaintext[-8:]}")

    # Re-encriptar con el secreto actual
    new_encrypted = encrypt_key(plaintext, secret)
    data["api_key"] = new_encrypted

    cur.execute(
        "UPDATE connections SET data = ? WHERE id = ?", (json.dumps(data), conn_id)
    )
    conn.commit()
    conn.close()

    print(f"✓ Conexión '{data.get('name', 'Sin nombre')}' re-encriptada correctamente.")
    print(f"  Ahora debería funcionar con el secreto actual.")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return

    cmd = sys.argv[1]

    if cmd == "check":
        check_connections()
    elif cmd == "decrypt" and len(sys.argv) >= 3:
        show_decrypted(sys.argv[2])
    elif cmd == "reencrypt" and len(sys.argv) >= 3:
        new_key = sys.argv[3] if len(sys.argv) >= 4 else None
        reencrypt_connection(sys.argv[2], new_key)
    else:
        print(__doc__)


if __name__ == "__main__":
    main()
