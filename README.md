# Zabbix Agent 2 Installation Script

This script automates the installation and configuration of the Zabbix agent on Ubuntu, Debian, and Alpine systems. It checks the system's distribution and version, downloads the appropriate Zabbix agent package, installs it, and configures the system with the provided agent config.

> **WARNING**: Server is hardcoded in the configuration file. If you want to use this for yourself, please fork the repo.

## Prerequisites

Before running this script, ensure that your system is one of the supported Ubuntu, Debian, or Alpine releases:

- Ubuntu 22.04 (Jammy)
- Ubuntu 24.04 (Lunar)
- Debian 11 (Bullseye)
- Debian 12 (Bookworm)
- Debian 13 (Trixie)
- Alpine (any, if it exists)

## Version

Current installing the latest 8.0 version.

## One-liner

```sh
curl --no-alpn -sL "https://raw.githubusercontent.com/ping-localhost/zabbix-agent/refs/heads/master/install.sh" | bash
```

## Post-installation

After installation, the Zabbix agent will be running and configured to start on boot. You can check the status of the Zabbix agent service with:

```sh
systemctl status zabbix-agent2
```

Or, for Alpine:

```sh
systemctl status zabbix-agent2
```
