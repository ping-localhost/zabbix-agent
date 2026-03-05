#!/bin/bash
set -euo pipefail

# Ensure the script is running with Bash version 4 or higher
if (( BASH_VERSINFO[0] < 4 )); then
    echo "This script requires Bash version 4 or higher. Please upgrade your Bash."
    exit 1
fi

# Ensure running as root
if [[ $EUID -ne 0 ]]; then
    echo "Error: This script must be run as root (or via sudo)."
    exit 1
fi

# Prevent any interactive prompts from dpkg/apt
export DEBIAN_FRONTEND=noninteractive
APT_DPKG_OPTS=(-o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confdef")

# Logging helpers
log()  { echo "[INFO]  $*"; }
warn() { echo "[WARN]  $*" >&2; }
die()  { echo "[ERROR] $*" >&2; exit 1; }

# Cleanup temp files on exit
TMPDIR=$(mktemp -d)
cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

# Zabbix release URLs per distro codename
declare -A zabbix_releases=(
    ["jammy"]="https://repo.zabbix.com/zabbix/8.0/release/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_8.0+ubuntu22.04_all.deb"
    ["noble"]="https://repo.zabbix.com/zabbix/8.0/release/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_8.0+ubuntu24.04_all.deb"
    ["bullseye"]="https://repo.zabbix.com/zabbix/8.0/release/debian/pool/main/z/zabbix-release/zabbix-release_latest_8.0+debian11_all.deb"
    ["bookworm"]="https://repo.zabbix.com/zabbix/8.0/release/debian/pool/main/z/zabbix-release/zabbix-release_latest_8.0+debian12_all.deb"
    ["trixie"]="https://repo.zabbix.com/zabbix/8.0/release/debian/pool/main/z/zabbix-release/zabbix-release_latest_8.0+debian13_all.deb"
)

# Detect OS and version
if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    OS=$ID
    VERSION=${VERSION_ID:-}
    DISTRO_CODENAME=${VERSION_CODENAME:-}
else
    die "Cannot detect OS: /etc/os-release not found."
fi

# Map version to codename if VERSION_CODENAME was empty
if [[ -z "$DISTRO_CODENAME" ]]; then
    case "$OS:$VERSION" in
        ubuntu:22.04) DISTRO_CODENAME="jammy" ;;
        ubuntu:24.04) DISTRO_CODENAME="noble" ;;
        debian:11)    DISTRO_CODENAME="bullseye" ;;
        debian:12)    DISTRO_CODENAME="bookworm" ;;
        debian:13)    DISTRO_CODENAME="trixie" ;;
        alpine:*)     DISTRO_CODENAME="alpine" ;;
        *)            die "Unsupported OS: $OS $VERSION" ;;
    esac
fi

log "Detected: $OS ($DISTRO_CODENAME)"

# Install Zabbix agent2
case "$DISTRO_CODENAME" in
        DEB_FILE="$TMPDIR/$(basename "$ZABBIX_URL")"

        log "Downloading Zabbix release package…"
        curl -fsSL -o "$DEB_FILE" "$ZABBIX_URL" || die "Failed to download $ZABBIX_URL"

        log "Installing Zabbix release package…"
        dpkg -i "$DEB_FILE" || true  # may warn about missing deps, apt fixes below

        log "Installing zabbix-agent2…"
        apt-get -qq update
        apt-get -y -qq "${APT_DPKG_OPTS[@]}" install zabbix-agent2

        # Only add zabbix to docker group if it exists
        if getent group docker >/dev/null 2>&1; then
            gpasswd -a zabbix docker
            log "Added zabbix user to docker group."
        else
            warn "Docker group not found — skipping group membership."
        fi
        ;;
    alpine)
        log "Installing zabbix-agent2 via apk…"
        apk update && apk add zabbix-agent2 zabbix-agent2-openrc

        if getent group docker >/dev/null 2>&1; then
            addgroup zabbix docker
            log "Added zabbix user to docker group."
        else
            warn "Docker group not found — skipping group membership."
        fi
        ;;
    *)
        die "Non-compatible OS release ($OS)"
        ;;
esac

# Configure Zabbix agent
CONF_URL="https://raw.githubusercontent.com/ping-localhost/zabbix-agent/master/zabbix_agent2.conf"
CONF_TMP="$TMPDIR/zabbix_agent2.conf"
CONF_DEST="/etc/zabbix/zabbix_agent2.conf"

mkdir -p /etc/zabbix/zabbix_agent2.d

log "Downloading agent configuration…"
curl -fsSL -o "$CONF_TMP" "$CONF_URL" || die "Failed to download $CONF_URL"
sed -i "s/HOSTNAME-REPLACE-ME/$(hostname)/g" "$CONF_TMP"

# Ensure run directory exists
mkdir -p /var/run/zabbix/
chown zabbix:zabbix /var/run/zabbix/

# Backup existing config before overwriting
if [[ -f "$CONF_DEST" ]]; then
    BACKUP="${CONF_DEST}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$CONF_DEST" "$BACKUP"
    log "Existing config backed up to $BACKUP"
fi

mv "$CONF_TMP" "$CONF_DEST"
chown root:zabbix "$CONF_DEST"
chmod 640 "$CONF_DEST"

# Enable and restart service
log "Enabling and starting zabbix-agent2…"
case "$DISTRO_CODENAME" in
    jammy|noble|bullseye|bookworm|trixie)
        systemctl daemon-reload
        systemctl enable zabbix-agent2
        if systemctl restart zabbix-agent2; then
            systemctl --no-pager status zabbix-agent2
        else
            die "zabbix-agent2 failed to start. Check: journalctl -xeu zabbix-agent2"
        fi
        ;;
    alpine)
        rc-update add zabbix-agent2
        if rc-service zabbix-agent2 restart; then
            rc-service zabbix-agent2 status
        else
            die "zabbix-agent2 failed to start."
        fi
        ;;
esac

log "Done — zabbix-agent2 is running."
