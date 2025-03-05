#!/usr/bin/env bash

set -e

docker compose -p komodo -f postgres.compose.yaml --env-file compose.env up -d