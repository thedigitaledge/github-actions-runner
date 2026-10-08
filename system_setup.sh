#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${SCRIPT_DIR}/.venv"
VAULT_PASS_FILE="${SCRIPT_DIR}/.secrets/ansible_vault_pass"
VARS_DIR="${SCRIPT_DIR}/vars"

# Pipeline playbooks in execution order
PLAYBOOKS=(
  "${SCRIPT_DIR}/deploy_github-runners_lima-vm.yml"
  "${SCRIPT_DIR}/deploy_cockpit.yml"
  "${SCRIPT_DIR}/diagnose_github-runner_system.yml"
)

ANSIBLE_ARGS=()

show_help() {
  cat << EOF
Usage: ./system_setup.sh [OPTIONS] [ANSIBLE_OPTIONS]

Options:
  -h, --help               Show this help message and exit
  -r, --recreate-runners   Force re-creation of GitHub runner containers
  -m, --recreate-vm        Force re-creation of the Lima VM and host container
  -a, --all                Force re-creation of BOTH runners and the Lima VM
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
      ANSIBLE_ARGS+=("-e" "recreate_runners=true")
      shift
      ;;
    -m|--recreate-vm)
      ANSIBLE_ARGS+=("-e" "recreate_vm=true")
      shift
      ;;
    -a|--all)
      ANSIBLE_ARGS+=("-e" "recreate_runners=true" "-e" "recreate_vm=true")
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

echo "==> Installing Python dependencies..."
pip install --quiet --upgrade pip
if [ -f "${SCRIPT_DIR}/pyproject.toml" ]; then
    pip install --quiet .
elif [ -f "${SCRIPT_DIR}/requirements.txt" ]; then
    pip install --quiet -r "${SCRIPT_DIR}/requirements.txt"
elif ! command -v ansible-playbook &>/dev/null; then
    pip install --quiet ansible
fi

echo "==> Installing Ansible Galaxy dependencies..."
if [ -f "${SCRIPT_DIR}/requirements.yml" ]; then
    ansible-galaxy collection install -r "${SCRIPT_DIR}/requirements.yml" --upgrade --quiet
fi

echo "==> Verifying configuration and secret files..."
VAULT_PASS_SCRIPT="${SCRIPT_DIR}/.secrets/vault_pass.sh"
if [ -f "${VAULT_PASS_SCRIPT}" ]; then
    chmod +x "${VAULT_PASS_SCRIPT}"
elif [ ! -f "${VAULT_PASS_FILE}" ] && [ -z "${ANSIBLE_VAULT_PASSWORD:-}" ]; then
    echo "Error: Vault password resolution mechanism missing (ensure .secrets/vault_pass.sh, .secrets/ansible_vault_pass, or ANSIBLE_VAULT_PASSWORD environment variable exists)." >&2
    exit 1
fi

if [ ! -f "${VARS_DIR}/vault.yml" ] || [ ! -f "${VARS_DIR}/runners.yml" ]; then
    echo "Error: Required variable files missing in ${VARS_DIR}/ (ensure vault.yml and runners.yml exist)." >&2
    exit 1
fi

for pb in "${PLAYBOOKS[@]}"; do
    if [ ! -f "${pb}" ]; then
        echo "Error: Playbook missing at ${pb}" >&2
        exit 1
    fi
done

echo "==> Enabling user session lingering on host..."
CURRENT_USER="${USER:-$(whoami)}"
LINGER_CMD=(loginctl enable-linger "${CURRENT_USER}")

if [ -f /run/.containerenv ] && command -v flatpak-spawn &>/dev/null; then
    LINGER_CMD=(flatpak-spawn --host loginctl enable-linger "${CURRENT_USER}")
fi

if ! "${LINGER_CMD[@]}" &>/dev/null; then
    echo "Notice: Could not set loginctl linger directly (if executing inside a container shell, ensure lingering is enabled on the host OS)."
fi

echo "==> Executing Ansible deployment and diagnostic playbooks..."

for pb in "${PLAYBOOKS[@]}"; do
    echo " -> Executing: ${pb}"
    ansible-playbook "${pb}" "${ANSIBLE_ARGS[@]}"
done

echo "==> System deployment complete."
