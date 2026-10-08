#!/usr/bin/env bash
set -euo pipefail

# 1. Check environment variable
if [ -n "${ANSIBLE_VAULT_PASSWORD:-}" ]; then
    echo "$ANSIBLE_VAULT_PASSWORD"
    exit 0
fi

# 2. Check secret-tool (GNOME Keyring / Freedesktop Secret Service)
if command -v secret-tool &>/dev/null; then
    VAULT_SECRET=$(secret-tool lookup service ansible_vault user "${USER:-$(whoami)}" 2>/dev/null || true)
    if [ -n "$VAULT_SECRET" ]; then
        echo "$VAULT_SECRET"
        exit 0
    fi
fi

# 3. Fallback to reading disk secret file if present
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_FILE="${SCRIPT_DIR}/ansible_vault_pass"

if [ -f "$VAULT_FILE" ]; then
    cat "$VAULT_FILE"
    exit 0
fi

echo "Error: Vault password not found in ANSIBLE_VAULT_PASSWORD env, secret-tool keyring, or ${VAULT_FILE}" >&2
exit 1
