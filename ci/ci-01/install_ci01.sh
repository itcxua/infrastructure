#!/usr/bin/env bash
set -euo pipefail

# =========================
# ci-01: CI/CD & Automation Server Bootstrap
# Ubuntu 22.04/24.04 (Hetzner Cloud)
#
# Installs:
# - Docker Engine + Compose plugin
# - Terraform
# - Ansible
# - Optional: GitLab Runner OR GitHub Actions Runner
# - Security baseline: UFW, Fail2ban, unattended-upgrades, SSH hardening
#
# Usage:
#   sudo bash install_ci01.sh
#
# After install:
# - Add your SSH key before/after running if needed.
# =========================

LOG_FILE="/var/log/ci01-bootstrap.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# ---------- Helpers ----------
info(){ echo -e "\n[INFO] $*"; }
warn(){ echo -e "\n[WARN] $*"; }
err(){ echo -e "\n[ERROR] $*" >&2; exit 1; }

require_root(){
  [[ "${EUID}" -eq 0 ]] || err "Run as root: sudo bash $0"
}

detect_distro(){
  source /etc/os-release
  DISTRO_ID="${ID:-ubuntu}"
  DISTRO_VER="${VERSION_ID:-}"
  [[ "$DISTRO_ID" == "ubuntu" ]] || warn "This script is optimized for Ubuntu. Detected: $DISTRO_ID"
}

apt_update(){
  info "Updating apt index..."
  apt-get update -y
}

apt_install(){
  info "Installing packages: $*"
  DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

cmd_exists(){ command -v "$1" >/dev/null 2>&1; }

# ---------- Config Defaults ----------
CI_USER="ci"
CI_HOME="/home/${CI_USER}"
CI_SSH_PORT="22"

# Optional: allow only your IP to SSH (recommended). Leave empty to allow 0.0.0.0/0
SSH_ALLOW_IP_CIDR=""

# Git runner options
RUNNER_CHOICE=""   # gitlab / github / none

# GitLab runner params
GITLAB_URL=""
GITLAB_REG_TOKEN=""

# GitHub runner params
GITHUB_OWNER=""
GITHUB_REPO=""
GITHUB_RUNNER_TOKEN=""
GITHUB_RUNNER_NAME="ci-01"
GITHUB_RUNNER_LABELS="ci,hetzner,ubuntu,docker"
GITHUB_RUNNER_WORKDIR="_work"

# Terraform version: "latest" or set exact (e.g. "1.9.8")
TERRAFORM_VERSION="latest"

# ---------- Prompt ----------
prompt_config(){
  info "CI-01 configuration (press Enter to accept default where available)"

  read -rp "CI user [${CI_USER}]: " v; CI_USER="${v:-$CI_USER}"
  CI_HOME="/home/${CI_USER}"

  read -rp "SSH port [${CI_SSH_PORT}]: " v; CI_SSH_PORT="${v:-$CI_SSH_PORT}"

  read -rp "Restrict SSH to your IP/CIDR (recommended, e.g. 1.2.3.4/32) [empty=allow all]: " v
  SSH_ALLOW_IP_CIDR="${v:-$SSH_ALLOW_IP_CIDR}"

  echo
  echo "Choose runner type:"
  echo "  1) GitLab Runner"
  echo "  2) GitHub Actions Runner"
  echo "  3) None (only Docker/Terraform/Ansible)"
  read -rp "Selection [1/2/3]: " v

  case "${v:-1}" in
    1) RUNNER_CHOICE="gitlab" ;;
    2) RUNNER_CHOICE="github" ;;
    3) RUNNER_CHOICE="none" ;;
    *) RUNNER_CHOICE="gitlab" ;;
  esac

  if [[ "$RUNNER_CHOICE" == "gitlab" ]]; then
    read -rp "GitLab URL (e.g. https://gitlab.com or https://gitlab.yourdomain.tld): " v
    GITLAB_URL="${v:-}"
    [[ -n "$GITLAB_URL" ]] || err "GitLab URL is required."

    read -rp "GitLab Runner registration token: " v
    GITLAB_REG_TOKEN="${v:-}"
    [[ -n "$GITLAB_REG_TOKEN" ]] || err "GitLab registration token is required."
  fi

  if [[ "$RUNNER_CHOICE" == "github" ]]; then
    read -rp "GitHub owner/org (e.g. myorg): " v
    GITHUB_OWNER="${v:-}"
    [[ -n "$GITHUB_OWNER" ]] || err "GitHub owner/org is required."

    read -rp "GitHub repo (e.g. myrepo): " v
    GITHUB_REPO="${v:-}"
    [[ -n "$GITHUB_REPO" ]] || err "GitHub repo is required."

    read -rp "GitHub runner token (from Settings -> Actions -> Runners): " v
    GITHUB_RUNNER_TOKEN="${v:-}"
    [[ -n "$GITHUB_RUNNER_TOKEN" ]] || err "GitHub runner token is required."

    read -rp "Runner name [${GITHUB_RUNNER_NAME}]: " v
    GITHUB_RUNNER_NAME="${v:-$GITHUB_RUNNER_NAME}"

    read -rp "Runner labels comma-separated [${GITHUB_RUNNER_LABELS}]: " v
    GITHUB_RUNNER_LABELS="${v:-$GITHUB_RUNNER_LABELS}"
  fi

  read -rp "Terraform version [${TERRAFORM_VERSION}]: " v
  TERRAFORM_VERSION="${v:-$TERRAFORM_VERSION}"
}

# ---------- System prep ----------
create_ci_user(){
  info "Creating CI user: ${CI_USER}"
  if id -u "$CI_USER" >/dev/null 2>&1; then
    warn "User ${CI_USER} already exists. Skipping creation."
  else
    adduser --disabled-password --gecos "" "$CI_USER"
  fi
  mkdir -p "${CI_HOME}/.ssh"
  chmod 700 "${CI_HOME}/.ssh"
  chown -R "${CI_USER}:${CI_USER}" "${CI_HOME}/.ssh"
}

install_security_baseline(){
  info "Installing security baseline (UFW, fail2ban, unattended-upgrades)..."
  apt_install ufw fail2ban unattended-upgrades ca-certificates curl gnupg lsb-release apt-transport-https software-properties-common

  info "Configuring UFW..."
  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing

  # SSH allow rule
  if [[ -n "$SSH_ALLOW_IP_CIDR" ]]; then
    ufw allow from "$SSH_ALLOW_IP_CIDR" to any port "$CI_SSH_PORT" proto tcp
  else
    ufw allow "$CI_SSH_PORT"/tcp
  fi

  # Enable firewall
  ufw --force enable

  info "Configuring fail2ban..."
  cat >/etc/fail2ban/jail.d/sshd.local <<EOF
[sshd]
enabled = true
port    = ${CI_SSH_PORT}
maxretry = 5
findtime = 10m
bantime  = 1h
EOF
  systemctl enable --now fail2ban

  info "Enabling unattended upgrades..."
  dpkg-reconfigure -f noninteractive unattended-upgrades || true
}

harden_ssh(){
  info "Hardening SSH (minimal)..."
  local sshd="/etc/ssh/sshd_config"

  # Backup once
  if [[ ! -f "${sshd}.ci01.bak" ]]; then
    cp -a "$sshd" "${sshd}.ci01.bak"
  fi

  # Apply settings idempotently
  set_sshd_kv() {
    local key="$1" val="$2"
    if grep -qE "^[#\s]*${key}\s+" "$sshd"; then
      sed -ri "s|^[#\s]*${key}\s+.*|${key} ${val}|g" "$sshd"
    else
      echo "${key} ${val}" >>"$sshd"
    fi
  }

  set_sshd_kv "Port" "${CI_SSH_PORT}"
  set_sshd_kv "PermitRootLogin" "no"
  set_sshd_kv "PasswordAuthentication" "no"
  set_sshd_kv "KbdInteractiveAuthentication" "no"
  set_sshd_kv "ChallengeResponseAuthentication" "no"
  set_sshd_kv "UsePAM" "yes"

  systemctl restart ssh || systemctl restart sshd
}

# ---------- Docker ----------
install_docker(){
  info "Installing Docker Engine + Compose plugin..."
  if cmd_exists docker; then
    warn "Docker already installed. Skipping."
  else
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    source /etc/os-release
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      ${VERSION_CODENAME} stable" > /etc/apt/sources.list.d/docker.list

    apt_update
    apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker
  fi

  info "Adding ${CI_USER} to docker group..."
  usermod -aG docker "$CI_USER" || true
}

# ---------- Terraform ----------
install_terraform(){
  info "Installing Terraform..."
  if cmd_exists terraform; then
    warn "Terraform already installed. Skipping."
    return
  fi

  curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
    > /etc/apt/sources.list.d/hashicorp.list

  apt_update
  if [[ "$TERRAFORM_VERSION" == "latest" ]]; then
    apt_install terraform
  else
    apt_install "terraform=${TERRAFORM_VERSION}*" || err "Terraform version ${TERRAFORM_VERSION} not found in apt repo."
  fi
}

# ---------- Ansible ----------
install_ansible(){
  info "Installing Ansible..."
  if cmd_exists ansible; then
    warn "Ansible already installed. Skipping."
  else
    apt_install ansible
  fi
}

# ---------- GitLab Runner ----------
install_gitlab_runner(){
  info "Installing GitLab Runner..."
  if cmd_exists gitlab-runner; then
    warn "GitLab Runner already installed. Skipping install."
  else
    curl -L --output /tmp/gitlab-runner-install.sh https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh
    bash /tmp/gitlab-runner-install.sh
    apt_install gitlab-runner
    systemctl enable --now gitlab-runner
  fi

  info "Registering GitLab Runner (Docker executor)..."
  # Non-interactive registration
  gitlab-runner register \
    --non-interactive \
    --url "$GITLAB_URL" \
    --registration-token "$GITLAB_REG_TOKEN" \
    --executor "docker" \
    --docker-image "docker:27" \
    --description "ci-01" \
    --tag-list "ci,hetzner,ubuntu,docker" \
    --run-untagged="true" \
    --locked="false" \
    --access-level="not_protected"

  # Ensure docker socket is available
  info "Configuring GitLab Runner to access Docker..."
  usermod -aG docker gitlab-runner || true
  systemctl restart gitlab-runner
}

# ---------- GitHub Actions Runner ----------
install_github_runner(){
  info "Installing GitHub Actions Runner..."
  local runner_dir="/opt/actions-runner"
  mkdir -p "$runner_dir"
  chown -R "${CI_USER}:${CI_USER}" "$runner_dir"

  # Determine latest runner version via GitHub API is not possible offline reliably without extra tooling,
  # so we use a stable pinned version. Update when needed.
  local RUNNER_VERSION="2.319.1"
  local ARCH="x64"

  info "Downloading GitHub runner v${RUNNER_VERSION}..."
  curl -L -o /tmp/actions-runner.tar.gz \
    "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${ARCH}-${RUNNER_VERSION}.tar.gz"

  tar xzf /tmp/actions-runner.tar.gz -C "$runner_dir"
  chown -R "${CI_USER}:${CI_USER}" "$runner_dir"

  # Dependencies
  info "Installing runner dependencies..."
  "$runner_dir/bin/installdependencies.sh" || true

  info "Configuring runner..."
  # Configure as CI_USER (required by GitHub runner)
  sudo -u "$CI_USER" bash -c "
    cd '$runner_dir'
    ./config.sh --unattended \
      --url 'https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}' \
      --token '${GITHUB_RUNNER_TOKEN}' \
      --name '${GITHUB_RUNNER_NAME}' \
      --labels '${GITHUB_RUNNER_LABELS}' \
      --work '${GITHUB_RUNNER_WORKDIR}'
  "

  info "Installing and starting runner service..."
  bash -c "cd '$runner_dir' && ./svc.sh install '${CI_USER}'"
  bash -c "cd '$runner_dir' && ./svc.sh start"
}

# ---------- Directories & sanity ----------
create_ci_dirs(){
  info "Creating CI directories..."
  mkdir -p /srv/ci/{work,artifacts,cache,ansible,terraform,logs}
  chown -R "${CI_USER}:${CI_USER}" /srv/ci
  chmod -R 750 /srv/ci
}

print_summary(){
  echo
  echo "========================================================="
  echo "CI-01 bootstrap completed."
  echo "User:            ${CI_USER}"
  echo "SSH port:        ${CI_SSH_PORT}"
  echo "SSH allow CIDR:  ${SSH_ALLOW_IP_CIDR:-"0.0.0.0/0"}"
  echo "Runner:          ${RUNNER_CHOICE}"
  echo "Log file:        ${LOG_FILE}"
  echo
  echo "Installed versions:"
  docker --version || true
  docker compose version || true
  terraform -version || true
  ansible --version | head -n 1 || true
  if [[ "$RUNNER_CHOICE" == "gitlab" ]]; then
    gitlab-runner --version || true
  fi
  if [[ "$RUNNER_CHOICE" == "github" ]]; then
    systemctl status actions.runner* --no-pager 2>/dev/null || true
  fi
  echo "========================================================="
  echo
  echo "Next steps:"
  echo "1) Re-login to apply docker group changes for ${CI_USER}."
  echo "2) Add your SSH key to ${CI_HOME}/.ssh/authorized_keys (if not yet)."
  echo "3) Store CI secrets securely (GitLab/GitHub secrets/variables)."
  echo
}

main(){
  require_root
  detect_distro
  apt_update
  apt_install git unzip jq

  prompt_config
  create_ci_user
  install_security_baseline
  harden_ssh
  install_docker
  install_terraform
  install_ansible
  create_ci_dirs

  case "$RUNNER_CHOICE" in
    gitlab)  install_gitlab_runner ;;
    github)  install_github_runner ;;
    none)    info "Runner installation skipped by choice." ;;
    *)       warn "Unknown runner choice; skipping." ;;
  esac

  print_summary
}

main "$@"
