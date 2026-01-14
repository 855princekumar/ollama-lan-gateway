#!/usr/bin/env bash
set -e

SERVICE_NAME="ollama-gateway"
BASE_DIR="/opt/ollama-gateway"

echo "[!] Removing Ollama Gateway..."

sudo systemctl disable --now ${SERVICE_NAME} || true
sudo rm -f /etc/systemd/system/${SERVICE_NAME}.service
sudo systemctl daemon-reload

sudo rm -rf "$BASE_DIR"

echo "[✓] Rollback complete. Ollama untouched."
