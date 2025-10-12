#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
export ANSIBLE_CONFIG="${PROJECT_ROOT}/ansible.cfg"
export ANSIBLE_INVENTORY="${PROJECT_ROOT}/inventory.ini"
set -euo pipefail

# install_ansible.sh
# Installs Ansible on a Debian/Raspberry Pi OS controller machine.
# Idempotent and minimal. Only supports apt-based systems.

say()  { echo -e "\e[1;32m==>\e[0m $*"; }
err()  { echo -e "\e[1;31m[err]\e[0m $*"; exit 1; }

if ! command -v apt-get >/dev/null 2>&1; then
  err "This installer only supports Debian/Raspberry Pi OS (apt-get not found)."
fi

say "Updating package lists ..."
sudo apt-get update -y

say "Installing Ansible and dependencies ..."
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  ansible python3 python3-pip sshpass openssh-client

say "Verifying installation ..."
ansible --version | head -n1
ansible-playbook --version | head -n1

say "Done. You can now run playbooks, e.g.:"
echo "  ansible-playbook -i ../inventory.ini ensure-env.yml"
