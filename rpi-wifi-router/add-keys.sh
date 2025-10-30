#!/usr/bin/env bash
######################################
# Created by : Meir
# Purpose : Create an Ed25519 SSH keypair and copy the public key to remote hosts; prompts for password at runtime
# Date : 2025-10-29
# Version : 1
######################################

set -Eeuo pipefail

# Defaults
KEY_PATH_DEFAULT="${HOME}/.ssh/id_ed25519"
COMMENT_DEFAULT="${USER}@${HOSTNAME}"
SSH_PORT_DEFAULT="22"

usage() {
  cat <<'EOF'
Usage:
  add-keys.sh -u USER -H host1,host2[,hostN] [-f KEY_PATH] [-c COMMENT] [--port PORT] [--force]

Required:
  -u USER         Remote login user on the target hosts (e.g., user, pi, ubuntu)
  -H HOSTS        Comma-separated IPs/hostnames (e.g., 192.168.50.101,192.168.50.102)

Optional:
  -f KEY_PATH     Private key path (default: ~/.ssh/id_ed25519)
  -c COMMENT      Public key comment (default: "$USER@$HOSTNAME")
  --port PORT     SSH port (default: 22)
  --force         Overwrite an existing local keypair if found
  -h, --help      Show this help

Behavior:
- Creates an Ed25519 keypair if missing (idempotent).
- Prompts for the remote account PASSWORD once at runtime and uses it for all hosts.
- Copies the public key to each host via ssh-copy-id (idempotent).
- Verifies key-only login after copying.
- Logs per-host output under: ~/sshcopy-logs/
EOF
}

# Parse args
KEY_PATH="${KEY_PATH_DEFAULT}"
COMMENT="${COMMENT_DEFAULT}"
SSH_PORT="${SSH_PORT_DEFAULT}"
FORCE="no"
REMOTE_USER=""
HOSTS_CSV=""

while (( "$#" )); do
  case "$1" in
    -u) REMOTE_USER="${2:-}"; shift 2;;
    -H) HOSTS_CSV="${2:-}"; shift 2;;
    -f) KEY_PATH="${2:-}"; shift 2;;
    -c) COMMENT="${2:-}"; shift 2;;
    --port) SSH_PORT="${2:-}"; shift 2;;
    --force) FORCE="yes"; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown option: $1" >&2; usage; exit 2;;
  esac
done

# Validate required args
if [[ -z "${REMOTE_USER}" || -z "${HOSTS_CSV}" ]]; then
  echo "Missing -u USER and/or -H HOSTS." >&2
  usage
  exit 2
fi

# Split hosts into array
IFS=',' read -r -a HOSTS <<< "${HOSTS_CSV}"

# Paths
SSH_DIR="$(dirname -- "${KEY_PATH}")"
PUB_PATH="${KEY_PATH}.pub"
KNOWN_HOSTS="${SSH_DIR}/known_hosts"
LOGDIR="${HOME}/sshcopy-logs"

# Ensure required tools exist; best-effort install if possible
ensure_pkg() {
  local bin="$1" pkg="$2"
  if command -v "${bin}" >/dev/null 2>&1; then
    return 0
  fi
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update -y && sudo apt-get install -y "${pkg}"
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y "${pkg}"
  elif command -v yum >/dev/null 2>&1; then
    sudo yum install -y "${pkg}"
  elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -Sy --noconfirm "${pkg}"
  else
    echo "Package manager not detected; please install ${pkg} manually." >&2
    return 1
  fi
}

ensure_pkg ssh-keygen openssh-client || true
ensure_pkg ssh-copy-id openssh-client || true
ensure_pkg sshpass sshpass || true

# Verify commands now exist
for cmd in ssh ssh-keygen ssh-copy-id sshpass; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing dependency: ${cmd}. Install it and re-run." >&2
    exit 1
  fi
done

# Prepare ~/.ssh with strict perms
umask 077
mkdir -p "${SSH_DIR}"
chmod 700 "${SSH_DIR}"
touch "${KNOWN_HOSTS}"
chmod 600 "${KNOWN_HOSTS}"

# Create keypair if absent or if overwrite requested
if [[ -f "${KEY_PATH}" || -f "${PUB_PATH}" ]]; then
  if [[ "${FORCE}" == "yes" ]]; then
    rm -f -- "${KEY_PATH}" "${PUB_PATH}"
  else
    echo "Keypair exists at ${KEY_PATH}; skipping creation (use --force to recreate)."
  fi
fi

if [[ ! -f "${KEY_PATH}" || ! -f "${PUB_PATH}" ]]; then
  ssh-keygen -t ed25519 -a 100 -f "${KEY_PATH}" -N "" -C "${COMMENT}"
  chmod 600 "${KEY_PATH}"
  chmod 644 "${PUB_PATH}"
fi

# Ask for the password once (hidden); reused for all hosts
echo -n "Password for ${REMOTE_USER} (used for all hosts): "
read -rs REMOTE_PASS
echo

# Prepare logs directory
mkdir -p "${LOGDIR}"

# Helper: key-only login test (non-interactive)
test_key_login() {
  local target="$1"
  ssh -p "${SSH_PORT}" \
      -o BatchMode=yes \
      -o StrictHostKeyChecking=accept-new \
      -i "${KEY_PATH}" \
      "${target}" exit >/dev/null 2>&1
}

# Iterate hosts
for host in "${HOSTS[@]}"; do
  target="${REMOTE_USER}@${host}"
  log_file="${LOGDIR}/sshcopy_${host}.log"

  echo ">>> Testing key-based SSH to ${target} (port ${SSH_PORT})"
  if test_key_login "${target}"; then
    echo "Key-based auth already works for ${target}; skipping ssh-copy-id."
    continue
  fi

  echo ">>> Bootstrapping key to ${target} with ssh-copy-id"
  SSHPASS="${REMOTE_PASS}" sshpass -e \
    ssh-copy-id -f \
      -i "${PUB_PATH}" \
      -p "${SSH_PORT}" \
      -o StrictHostKeyChecking=accept-new \
      "${target}" >"${log_file}" 2>&1 || {
        echo "ssh-copy-id failed for ${target}. See ${log_file}" >&2
        if grep -q "Permission denied" "${log_file}" 2>/dev/null; then
          echo "Hint: Wrong password/username, or PasswordAuthentication is disabled on ${host}." >&2
        fi
        exit 4
      }

  # Re-test after copy
  if test_key_login "${target}"; then
    echo "Key-based auth confirmed for ${target}."
  else
    echo "Key-based auth still failing for ${target} after ssh-copy-id. See ${log_file}" >&2
    exit 5
  fi
done

echo
echo "All hosts processed successfully."
echo "Private key: ${KEY_PATH}"
echo "Public  key: ${PUB_PATH}"
echo "Logs     : ${LOGDIR}"
echo "You can now run Ansible with:  -e ansible_ssh_private_key_file='${KEY_PATH}'"

