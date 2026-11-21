#!/usr/bin/env bash
# Phase 1 — Install Docker Engine and Docker Compose
# Run as the operator user (with sudo) after configure-firewall.sh.
#
# Installs:
#   - Docker Engine (from Docker's official APT repo, pinned version)
#   - Docker Compose plugin (v2, supports !override tag >= 2.24.4)
#   - Adds the operator user to the docker group
#
# Does NOT:
#   - Start any application containers.
#   - Pull any Supabase images.
#   - Create any compose stacks.
#
set -euo pipefail

DOCKER_VERSION_REQUIREMENT=">= 28.0"
COMPOSE_VERSION_REQUIREMENT=">= 2.24.4 (!override tag support)"

echo "== Phase 1: Docker Engine + Compose installation =="

# ---------------------------------------------------------------- prerequisites
echo "[1/6] installing prerequisites"
sudo apt-get update -qq
sudo apt-get install -y -qq ca-certificates curl gnupg lsb-release

# ---------------------------------------------------------------- Docker GPG key + repo
echo "[2/6] adding Docker's official APT repository"
sudo install -m 0755 -d /etc/apt/keyrings
if [ ! -f /etc/apt/keyrings/docker.asc ]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        sudo gpg --dearmor -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
fi

ARCH="$(dpkg --print-architecture)"
CODENAME="$(lsb_release -cs)"
echo "  arch: $ARCH, codename: $CODENAME"

if ! grep -q "download.docker.com" /etc/apt/sources.list.d/docker.list 2>/dev/null; then
    echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${CODENAME} stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
fi

sudo apt-get update -qq

# ---------------------------------------------------------------- install Docker Engine + Compose
echo "[3/6] installing Docker Engine, CLI, and Compose plugin"
sudo apt-get install -y -qq \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

# ---------------------------------------------------------------- verify versions
echo "[4/6] verifying versions"
DOCKER_VER="$(docker version --format '{{.Server.Version}}')"
COMPOSE_VER="$(docker compose version --short)"
echo "  Docker Engine:   $DOCKER_VER (requirement: $DOCKER_VERSION_REQUIREMENT)"
echo "  Docker Compose:  $COMPOSE_VER (requirement: $COMPOSE_VERSION_REQUIREMENT)"

# Verify compose meets the !override requirement
COMPOSE_MAJOR="$(echo "$COMPOSE_VER" | cut -d. -f1)"
COMPOSE_MINOR="$(echo "$COMPOSE_VER" | cut -d. -f2)"
if [ "$COMPOSE_MAJOR" -lt 2 ] || { [ "$COMPOSE_MAJOR" -eq 2 ] && [ "$COMPOSE_MINOR" -lt 24 ]; }; then
    echo "  FAIL: Docker Compose $COMPOSE_VER is older than 2.24.4 (!override not supported)"
    exit 1
fi
echo "  OK: Compose >= 2.24.4 (!override tag supported)"

# ---------------------------------------------------------------- operator to docker group
echo "[5/6] adding operator to docker group"
OPERATOR="${LUMO_OPERATOR:-lumo}"
if id "$OPERATOR" &>/dev/null; then
    sudo usermod -aG docker "$OPERATOR"
    echo "  Added $OPERATOR to the docker group."
    echo "  NOTE: Log out and back in as $OPERATOR for the group change to take effect."
else
    echo "  WARNING: operator user '$OPERATOR' not found. Skipping group add."
fi

# ---------------------------------------------------------------- Docker daemon hardening
echo "[6/6] applying Docker daemon hardening"
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json > /dev/null <<'EOF'
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "live-restore": true,
    "userland-proxy": false,
    "no-new-privileges": true,
    "icc": false
}
EOF
sudo systemctl enable docker
sudo systemctl enable containerd
sudo systemctl restart docker

echo ""
echo "== Verification =="
docker info --format 'Server Version: {{.ServerVersion}}'
docker info --format 'Storage Driver: {{.Driver}}'
docker info --format 'Logging Driver: {{.LoggingDriver}}'
docker info --format 'Live Restore: {{.LiveRestoreEnabled}}'
docker compose version
echo ""
echo "docker run hello-world:"
docker run --rm hello-world 2>&1 | head -5
echo ""
echo "== Docker is installed. No application containers are running. =="
echo ""
echo "NEXT: sh deploy/vps/verify-phase1.sh"
