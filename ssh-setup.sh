#!/bin/bash

if ! command -v curl &> /dev/null; then
    echo "curl is required but not installed"
    exit 1
fi

GITHUB_USER=$1

if [ -z "$GITHUB_USER" ]; then
    echo "Usage: $0 github_username"
    exit 1
fi

mkdir -p ~/.ssh
chmod 700 ~/.ssh

if curl -sf https://github.com/${GITHUB_USER}.keys >> ~/.ssh/authorized_keys; then
    chmod 600 ~/.ssh/authorized_keys
    echo "Keys successfully added for ${GITHUB_USER}"
else
    echo "Failed to fetch keys for ${GITHUB_USER}"
    exit 1
fi
