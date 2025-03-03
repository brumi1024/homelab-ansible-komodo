#!/usr/bin/env bash

set -e

curl -sSL https://raw.githubusercontent.com/mbecker20/komodo/main/scripts/setup-periphery.py | python3
systemctl enable periphery