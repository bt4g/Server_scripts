# Server Scripts Collection

![GitHub last commit](https://img.shields.io/github/last-commit/gopnikgame/Server_scripts)
![GitHub license](https://img.shields.io/github/license/gopnikgame/Server_scripts)

A collection of shell scripts for server optimization and kernel management, focused on Xanmod kernel installation and system performance enhancement.

## 📌 Table of Contents
- [Features](#-features)
- [Requirements](#-requirements)
- [Installation Scripts](#-installation-scripts)
  - [Xanmod Kernel Installation](#xanmod-kernel-installation)
  - [Kernel Restoration](#kernel-restoration)
- [Safety Features](#-safety-features)
- [Logging](#-logging)
- [Recovery Guide](#-recovery-guide)
- [Contributing](#-contributing)
- [License](#-license)

## 🚀 Features

### Xanmod Kernel Installation Script
- Full system update and upgrade before installation
- Automatic kernel backup creation
- Xanmod kernel installation with PSABI version detection
- BBR3 TCP congestion control configuration
- Automated system cleanup
- Multi-stage installation with proper reboots
- Detailed logging of all operations

### Kernel Restoration Script
- Automatic detection of available kernel backups
- Simple restoration process
- GRUB configuration update
- Safe recovery options

## 📋 Requirements

- Ubuntu/Debian based system
- Root access (sudo)
- Internet connection
- Bash shell

## 💻 Installation Scripts

### Xanmod Kernel Installation

```bash
bash <(wget -qO- https://raw.githubusercontent.com/gopnikgame/Server_scripts/main/install_xanmod.sh)
