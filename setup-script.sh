#!/bin/bash

# Check for root/sudo privileges
if ! [ $(id -u) = 0 ]; then
   echo "This script must be run with sudo"
   exit 1
fi

# Function to print usage
print_usage() {
    echo "Usage: $0 -g GITHUB_USERNAME -s SMB_SERVER -h SMB_SHARE -u SMB_USER -p SMB_PASS -m MOUNT_POINT"
    echo "  -g: Github username (to fetch SSH key)"
    echo "  -s: SMB server address"
    echo "  -h: SMB share name"
    echo "  -u: SMB username"
    echo "  -p: SMB password"
    echo "  -m: Local mount point"
    exit 1
}

# Parse command line arguments
while getopts "g:s:h:u:p:m:" opt; do
    case $opt in
        g) GITHUB_USER="$OPTARG";;
        s) SMB_SERVER="$OPTARG";;
        h) SMB_SHARE="$OPTARG";;
        u) SMB_USER="$OPTARG";;
        p) SMB_PASS="$OPTARG";;
        m) MOUNT_POINT="$OPTARG";;
        ?) print_usage;;
    esac
done

# Check if all required arguments are provided
if [ -z "$GITHUB_USER" ] || [ -z "$SMB_SERVER" ] || [ -z "$SMB_SHARE" ] || \
   [ -z "$SMB_USER" ] || [ -z "$SMB_PASS" ] || [ -z "$MOUNT_POINT" ]; then
    print_usage
fi

echo "Starting system setup..."

# System updates
echo "Updating system packages..."
if ! apt update && apt upgrade -y; then
    echo "Error: System update failed"
    exit 1
fi

# Install required packages
echo "Installing required packages..."
if ! apt install -y openssh-server curl ufw cifs-utils unattended-upgrades; then
    echo "Error: Package installation failed"
    exit 1
fi

# Configure automatic updates
echo "Configuring automatic security updates..."
if ! dpkg-reconfigure -f noninteractive unattended-upgrades; then
    echo "Error: Failed to configure unattended-upgrades"
    exit 1
fi

# Configure UFW
echo "Configuring firewall..."
if ! ufw allow 22/tcp || ! ufw --force enable; then
    echo "Error: Failed to configure firewall"
    exit 1
fi

# SSH setup
echo "Configuring SSH..."
mkdir -p "/home/$SUDO_USER/.ssh"
chmod 700 "/home/$SUDO_USER/.ssh"

# Download SSH key from GitHub
echo "Downloading SSH key from GitHub..."
if ! ping -c 1 github.com &> /dev/null; then
    echo "Error: Cannot reach GitHub"
    exit 1
fi
GITHUB_KEYS=$(curl -s "https://github.com/$GITHUB_USER.keys")
if [ -z "$GITHUB_KEYS" ]; then
    echo "Error: Failed to fetch SSH keys from GitHub"
    exit 1
fi

# Create or update authorized_keys
if [ ! -f "/home/$SUDO_USER/.ssh/authorized_keys" ]; then
    # If file doesn't exist, just write the keys
    echo "$GITHUB_KEYS" > "/home/$SUDO_USER/.ssh/authorized_keys"
else
    # If file exists, append keys but avoid duplicates
    echo "$GITHUB_KEYS" | while read -r key; do
        if ! grep -q "^$key$" "/home/$SUDO_USER/.ssh/authorized_keys"; then
            echo "$key" >> "/home/$SUDO_USER/.ssh/authorized_keys"
        fi
    done
fi
chmod 600 "/home/$SUDO_USER/.ssh/authorized_keys"
chown -R "$SUDO_USER:$SUDO_USER" "/home/$SUDO_USER/.ssh"

# Disable password authentication
echo "Disabling SSH password authentication..."
if ! cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup; then
    echo "Error: Failed to create sshd_config backup"
    exit 1
fi
sed -i '/^#*PasswordAuthentication/c\PasswordAuthentication no' /etc/ssh/sshd_config
if ! grep -q "^PasswordAuthentication no" /etc/ssh/sshd_config; then
    echo "PasswordAuthentication no" >> /etc/ssh/sshd_config
fi
systemctl restart sshd

# SMB setup
echo "Configuring SMB mount..."

# Create credentials file
echo "Creating SMB credentials file..."
CREDS_FILE="/home/$SUDO_USER/.smbcredentials"
echo "username=$SMB_USER" > "$CREDS_FILE"
echo "password=$SMB_PASS" >> "$CREDS_FILE"
chmod 600 "$CREDS_FILE"
chown "$SUDO_USER:$SUDO_USER" "$CREDS_FILE"

# Create mount point
echo "Creating mount point..."
if [[ ! "$MOUNT_POINT" =~ ^[a-zA-Z0-9/_-]+$ ]]; then
    echo "Error: Mount point contains invalid characters"
    exit 1
fi
if [[ "$MOUNT_POINT" != /* ]]; then
    echo "Error: Mount point must be an absolute path"
    exit 1
fi
if ! [ -d "${MOUNT_POINT}" ]; then
    mkdir -p "${MOUNT_POINT}"
fi
chown "$SUDO_USER:$SUDO_USER" "${MOUNT_POINT}"

# Add fstab entry
echo "Adding fstab entry..."
if ! cp /etc/fstab /etc/fstab.backup; then
    echo "Error: Failed to create fstab backup"
    exit 1
fi
FSTAB_ENTRY="//${SMB_SERVER}/${SMB_SHARE} ${MOUNT_POINT} cifs credentials=$CREDS_FILE,uid=1000,gid=1000,iocharset=utf8,file_mode=0777,dir_mode=0777,nobrl,mfsymlinks 0 0"
echo "$FSTAB_ENTRY" >> /etc/fstab

# Test mount
echo "Testing mount..."
if ! mount -a; then
    echo "Error: Mount failed"
    exit 1
fi

echo "Setup complete!"