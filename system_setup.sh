#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${SCRIPT_DIR}/.venv"
VAULT_PASS_FILE="${SCRIPT_DIR}/.secrets/ansible_vault_pass"
VARS_DIR="${SCRIPT_DIR}/vars"
PLAYBOOK_RUNNERS="${SCRIPT_DIR}/deploy_github-runners_lima-vm.yml"
PLAYBOOK_COCKPIT="${SCRIPT_DIR}/deploy_cockpit.yml"
PLAYBOOK_DIAGNOSE="${SCRIPT_DIR}/diagnose_github-runner_system.yml" 
EXTRA_VARS=()
ANSIBLE_ARGS=()

show_help() {
  cat << EOF
Usage: ./system_setup.sh [OPTIONS] [ANSIBLE_OPTIONS]

Options:
  -h, --help               Show this help message and exit
  -r, --recreate-runners   Force re-creation of GitHub runner containers
  -c, --check, --dry-run   Run Ansible in check mode (preview changes across all playbooks)
  -v, --verbose            Run Ansible in verbose mode (-v)
  -s, --syntax-check       Validate playbook syntax only without executing

Note:
  Unrecognized flags will be passed directly through to ansible-playbook.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      show_help
      exit 0
      ;;
    -r|--recreate-runners)
      EXTRA_VARS+=("recreate_runners=true")
      shift
      ;;
    -c|--check|--dry-run)
      ANSIBLE_ARGS+=("--check" "--diff")
      shift
      ;;
    -v|--verbose)
      ANSIBLE_ARGS+=("-v")
      shift
      ;;
    -s|--syntax-check)
      ANSIBLE_ARGS+=("--syntax-check")
      shift
      ;;
    *)
      ANSIBLE_ARGS+=("$1")
      shift
      ;;
  esac
done

# Inject aggregated extra-vars if present
if [ ${#EXTRA_VARS[@]} -gt 0 ]; then
  VARS_JOINED=$(IFS=, ; echo "${EXTRA_VARS[*]}")
  ANSIBLE_ARGS+=("-e" "$VARS_JOINED")
fi

echo "==> Checking Python 3 availability..."
if ! command -v python3 &>/dev/null; then
    echo "Error: Python 3 is required but not installed." >&2
    exit 1
fi

echo "==> Setting up Python virtual environment..."
if [ ! -d "${VENV_DIR}" ]; then
    python3 -m venv "${VENV_DIR}"
fi

# Activate python virtual environment
# shellcheck source=/dev/null
source "${VENV_DIR}/bin/activate"

echo "==> Installing dependencies from pyproject.toml..."
pip install --quiet --upgrade pip
if [ -f "${SCRIPT_DIR}/pyproject.toml" ]; then
    pip install --quiet .
elif [ -f "${SCRIPT_DIR}/requirements.txt" ]; then
    pip install --quiet -r "${SCRIPT_DIR}/requirements.txt"
else
    if ! command -v ansible-playbook &>/dev/null; then
        pip install --quiet ansible
    fi
fi

echo "==> Verifying configuration and secret files..."
if [ ! -f "${VAULT_PASS_FILE}" ]; then
    echo "Error: Vault password file missing at ${VAULT_PASS_FILE}" >&2
    exit 1
fi

if [ ! -f "${VARS_DIR}/vault.yml" ] || [ ! -f "${VARS_DIR}/runners.yml" ]; then
    echo "Error: Required variable files missing in ${VARS_DIR}/ (ensure vault.yml and runners.yml exist)." >&2
    exit 1
fi

if [ ! -f "${PLAYBOOK_RUNNERS}" ] || [ ! -f "${PLAYBOOK_COCKPIT}" ] || [ ! -f "${PLAYBOOK_DIAGNOSE}" ]; then
    echo "Error: Playbooks missing in ${SCRIPT_DIR}/." >&2
    exit 1
fi

echo "==> Enabling user session lingering on host..."
CURRENT_USER="${USER:-$(whoami)}"
if [ -f /run/.containerenv ] && command -v flatpak-spawn &>/dev/null; then
    if ! flatpak-spawn --host loginctl enable-linger "${CURRENT_USER}" &>/dev/null; then
        echo "Notice: Could not set loginctl linger directly (if executing inside a container shell, ensure lingering is enabled on the host OS)."
    fi
else
    if ! loginctl enable-linger "${CURRENT_USER}" &>/dev/null; then
        echo "Notice: Could not set loginctl linger directly (if executing inside a container shell, ensure lingering is enabled on the host OS)."
    fi
fi

echo "==> Executing Ansible deployment and diagnostic playbooks..."

echo " -> Executing: ${PLAYBOOK_RUNNERS}"
ansible-playbook "${PLAYBOOK_RUNNERS}" "${ANSIBLE_ARGS[@]}"

echo " -> Executing: ${PLAYBOOK_COCKPIT}"
ansible-playbook "${PLAYBOOK_COCKPIT}" "${ANSIBLE_ARGS[@]}"

echo " -> Executing: ${PLAYBOOK_DIAGNOSE}"
ansible-playbook "${PLAYBOOK_DIAGNOSE}" "${ANSIBLE_ARGS[@]}"

echo "==> System deployment complete."
