#!/bin/bash

# Ensure the script is running with Bash version 4 or higher
if (( BASH_VERSINFO[0] < 4 )); then
    echo "This script requires Bash version 4 or higher. Please upgrade your Bash."
    exit 1
fi

declare -A zabbix_releases=(
    ["jammy"]="https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_7.0-2+ubuntu22.04_all.deb"
    ["noble"]="https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_7.0-2+ubuntu24.04_all.deb"
    ["bullseye"]="https://repo.zabbix.com/zabbix/7.0/debian/pool/main/z/zabbix-release/zabbix-release_7.0-2+debian11_all.deb"
    ["bookworm"]="https://repo.zabbix.com/zabbix/7.0/debian/pool/main/z/zabbix-release/zabbix-release_7.0-2+debian12_all.deb"
)

# Detect OS and version
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
    DISTRO_CODENAME=${VERSION_CODENAME:-}
else
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    VERSION=$(uname -r)
fi

# Map version to codename if necessary
if [ -z "$DISTRO_CODENAME" ]; then
    case "$OS:$VERSION" in
        ubuntu:22.04) DISTRO_CODENAME="jammy" ;;
        ubuntu:24.04) DISTRO_CODENAME="noble" ;;
        debian:11) DISTRO_CODENAME="bullseye" ;;
        debian:12) DISTRO_CODENAME="bookworm" ;;
        alpine:*) DISTRO_CODENAME="alpine" ;;
        *) echo "Unsupported $OS version $VERSION"; exit 1 ;;
    esac
fi

# Install Zabbix agent2
case "$DISTRO_CODENAME" in
    jammy|noble|bullseye|bookworm)
        ZABBIX_URL=${zabbix_releases[$DISTRO_CODENAME]}
        curl -O "$ZABBIX_URL"
        dpkg -i "$(basename "$ZABBIX_URL")"
        apt update && apt -y install zabbix-agent2
        gpasswd -a zabbix docker
        ;;
    alpine)
        apk update && apk add zabbix-agent2 zabbix-agent2-openrc
        addgroup zabbix docker
        ;;
    *)
        echo "Non-compatible OS release ($OS)"
        exit 1
        ;;
esac

# Configure Zabbix agent
mkdir -p /etc/zabbix/zabbix_agent2.d
curl -o /tmp/zabbix_agent2.conf "https://raw.githubusercontent.com/ping-localhost/zabbix-agent/master/zabbix_agent2.conf"
sed -i "s/HOSTNAME-REPLACE-ME/$(hostname)/g" /tmp/zabbix_agent2.conf

# Backup and move the Zabbix agent configuration file
if [ -f /etc/zabbix/zabbix_agent2.conf ]; then
    cp /etc/zabbix/zabbix_agent2.conf "/etc/zabbix/zabbix_agent2.conf.bak.$(date +%Y%m%d%H%M%S)"
fi
mv /tmp/zabbix_agent2.conf /etc/zabbix/zabbix_agent2.conf

# Enable and restart Zabbix agent service
case "$DISTRO_CODENAME" in
    jammy|noble|bullseye|bookworm)
        systemctl daemon-reload
        systemctl enable zabbix-agent2
        if systemctl restart zabbix-agent2; then
            systemctl status zabbix-agent2
        fi
        ;;
    alpine)
        rc-update add zabbix-agent2
        if rc-service zabbix-agent2 restart; then
            rc-service zabbix-agent2 status
        fi
        ;;
esac
