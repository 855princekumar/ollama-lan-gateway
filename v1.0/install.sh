#!/usr/bin/env bash
set -e

BASE_DIR="/opt/ollama-gateway"
VENV_DIR="$BASE_DIR/venv"
PYTHON_BIN="/usr/bin/python3"
SERVICE_NAME="ollama-gateway"

echo "[+] Installing Ollama LAN Gateway..."

# Ensure base dir
sudo mkdir -p "$BASE_DIR"
sudo chown -R $USER:$USER "$BASE_DIR"

cd "$BASE_DIR"

# Create venv if missing
if [ ! -d "$VENV_DIR" ]; then
  echo "[+] Creating Python venv"
  $PYTHON_BIN -m venv venv
fi

# Upgrade pip safely inside venv
"$VENV_DIR/bin/pip" install --upgrade pip wheel >/dev/null

# Requirements
cat > requirements.txt <<EOF
flask
requests
gunicorn
EOF

# Install deps if missing
"$VENV_DIR/bin/pip" install -r requirements.txt >/dev/null

# Flask app
cat > app.py <<'EOF'
from flask import Flask, request, jsonify, abort
import requests, time

OLLAMA_URL = "http://127.0.0.1:11434/api/chat"
DEFAULT_MODEL = "llama3.2:latest"

app = Flask(__name__)

@app.route("/health", methods=["GET"])
def health():
    return {"status": "ok"}

@app.route("/chat", methods=["POST"])
def chat():
    data = request.get_json(force=True)

    payload = {
        "model": data.get("model", DEFAULT_MODEL),
        "messages": data.get("messages"),
        "stream": False,
        "options": {
            "temperature": data.get("temperature", 0.1),
            "top_p": 0.9
        }
    }

    if not payload["messages"]:
        return jsonify({"error": "messages required"}), 400

    for _ in range(3):
        try:
            r = requests.post(OLLAMA_URL, json=payload, timeout=180)
            r.raise_for_status()
            return jsonify(r.json())
        except Exception as e:
            last_error = str(e)
            time.sleep(1)

    return jsonify({"error": last_error}), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=7000)
EOF

# Run wrapper (no manual venv activation ever)
cat > run.sh <<EOF
#!/usr/bin/env bash
exec $VENV_DIR/bin/gunicorn \\
  --workers 1 \\
  --bind 0.0.0.0:7000 \\
  app:app
EOF

chmod +x run.sh

# systemd service
sudo tee /etc/systemd/system/${SERVICE_NAME}.service > /dev/null <<EOF
[Unit]
Description=Ollama Flask LAN Gateway
After=network.target ollama.service
Requires=ollama.service

[Service]
Type=simple
WorkingDirectory=$BASE_DIR
ExecStart=$BASE_DIR/run.sh
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now ${SERVICE_NAME}

echo "[✓] Ollama Gateway installed & running on port 7000"
