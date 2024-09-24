# Zabbix Agent Installation Script

This script automates the installation and configuration of the Zabbix agent on Ubuntu, Debian, and Alpine systems. It checks the system's distribution and version, downloads the appropriate Zabbix agent package, installs it, and configures the system with the provided agent config.

## Prerequisites

Before running this script, ensure that your system is one of the supported Ubuntu, Debian, or Alpine releases:

- Ubuntu 22.04 (Jammy)
- Ubuntu 24.04 (Lunar)
- Debian 11 (Bullseye)
- Debian 12 (Bookworm)
- Alpine (any, if it exists)

## One-liner

```sh
curl -sL https://raw.githubusercontent.com/ping-localhost/zabbix-agent/master/install.sh | bash
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
