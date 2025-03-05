#!/usr/bin/env bash

set -e

docker compose -p komodo-periphery -f periphery.compose.yaml --env-file compose.env up -d