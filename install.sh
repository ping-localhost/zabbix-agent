#!/bin/sh
set -eu

main() {
    # Ensure running as root
    if [ "$(id -u)" -ne 0 ]; then
        echo "Error: This script must be run as root (or via sudo)."
        exit 1
    fi

    # Prevent any interactive prompts from dpkg/apt
    export DEBIAN_FRONTEND=noninteractive
    # Logging helpers
    log()  { echo "[INFO]  $*"; }
    warn() { echo "[WARN]  $*" >&2; }
    die()  { echo "[ERROR] $*" >&2; exit 1; }

    # Cleanup temp files on exit
    WORK_DIR=$(mktemp -d)
    cleanup() { rm -rf "$WORK_DIR"; }
    trap cleanup EXIT

    # Detect OS and version
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=${ID:-}
        VERSION=${VERSION_ID:-}
    else
        die "Cannot detect OS: /etc/os-release not found."
    fi

    case "$OS:$VERSION" in
        ubuntu:20.04|ubuntu:22.04|ubuntu:24.04|ubuntu:26.04)
            ZABBIX_URL="https://repo.zabbix.com/zabbix/8.0/release/ubuntu/pool/main/z/zabbix-release/zabbix-release_latest_8.0+ubuntu${VERSION}_all.deb"
            PACKAGE_FAMILY=debian
            ;;
        debian:11|debian:12|debian:13)
            ZABBIX_URL="https://repo.zabbix.com/zabbix/8.0/release/debian/pool/main/z/zabbix-release/zabbix-release_latest_8.0+debian${VERSION}_all.deb"
            PACKAGE_FAMILY=debian
            ;;
        alpine:3.23|alpine:3.23.*|alpine:3.24|alpine:3.24.*)
            PACKAGE_FAMILY=alpine
            ;;
        *) die "Unsupported OS release: $OS $VERSION" ;;
    esac

    log "Detected: $OS $VERSION"

    # Install Zabbix agent2
    case "$PACKAGE_FAMILY" in
        debian)
            DEB_FILE="$WORK_DIR/$(basename "$ZABBIX_URL")"

            log "Downloading Zabbix release package…"
            curl -fsSL -o "$DEB_FILE" "$ZABBIX_URL" || die "Failed to download $ZABBIX_URL"

            RELEASE_VERSION=$(dpkg-deb -f "$DEB_FILE" Version)
            INSTALLED_RELEASE_VERSION=$(dpkg-query -W -f='${Version}' zabbix-release 2>/dev/null || true)
            if [ -n "$INSTALLED_RELEASE_VERSION" ] && dpkg --compare-versions "$INSTALLED_RELEASE_VERSION" ge "$RELEASE_VERSION"; then
                log "Installed Zabbix release package is current or newer; skipping."
            else
                log "Installing Zabbix release package…"
                dpkg -i "$DEB_FILE" || true  # apt fixes missing dependencies below
            fi

            log "Installing zabbix-agent2…"
            apt-get -qq update
            apt-get -y -qq -o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confdef" install zabbix-agent2

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
    CONF_TMP="$WORK_DIR/zabbix_agent2.conf"
    CONF_DEST="/etc/zabbix/zabbix_agent2.conf"

    mkdir -p /etc/zabbix/zabbix_agent2.d

    log "Downloading agent configuration…"
    curl -fsSL -o "$CONF_TMP" "$CONF_URL" || die "Failed to download $CONF_URL"
    sed -i "s/HOSTNAME-REPLACE-ME/$(hostname)/g" "$CONF_TMP"

    # Ensure required directories exist with correct permissions
    mkdir -p /var/log/zabbix/
    chown zabbix:zabbix /var/log/zabbix/
    chmod 755 /var/log/zabbix/

    # Backup existing config before overwriting
    if [ -f "$CONF_DEST" ]; then
        BACKUP="${CONF_DEST}.bak.$(date +%Y%m%d%H%M%S)"
        cp "$CONF_DEST" "$BACKUP"
        log "Existing config backed up to $BACKUP"
    fi

    mv "$CONF_TMP" "$CONF_DEST"
    chown root:zabbix "$CONF_DEST"
    chmod 640 "$CONF_DEST"

    # Enable and restart service
    log "Enabling and starting zabbix-agent2…"

    case "$PACKAGE_FAMILY" in
        debian)
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
                die "zabbix-agent2 failed to start. Check: rc-service zabbix-agent2 status"
            fi
            ;;
    esac

    log "Done — zabbix-agent2 is running."
}

main "$@"
