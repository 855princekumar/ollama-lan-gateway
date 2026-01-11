#!/usr/bin/env bash
set -e
sudo systemctl disable --now ollama-gateway 2>/dev/null || true
sudo rm -f /etc/systemd/system/ollama-gateway.service
sudo systemctl daemon-reload
sudo rm -rf /opt/ollama-gateway
echo "[✓] Ollama Gateway fully removed"
