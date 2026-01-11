#!/usr/bin/env bash
set -e

SERVICE="ollama-gateway"
BASE="/opt/ollama-gateway"
APP="$BASE/app"
TPL="$APP/templates"
DBDIR="$BASE/db"
VENV="$BASE/venv"

echo "[+] Installing Local AI Gateway (FINAL, CSV-FIXED, AUDIT-ENFORCED)"

# ------------------------------------------------------------
# Directories
# ------------------------------------------------------------
sudo mkdir -p "$APP" "$TPL" "$DBDIR"
sudo chown -R $USER:$USER "$BASE"

# ------------------------------------------------------------
# Python virtual environment
# ------------------------------------------------------------
python3 -m venv "$VENV"
"$VENV/bin/pip" install --upgrade pip >/dev/null
"$VENV/bin/pip" install quart httpx gunicorn uvicorn werkzeug >/dev/null

# ------------------------------------------------------------
# Application
# ------------------------------------------------------------
cat > "$APP/app.py" <<'PYCODE'
import asyncio, sqlite3, csv, io, time
from datetime import datetime
from quart import Quart, request, jsonify, render_template, redirect, session, Response
from werkzeug.security import generate_password_hash, check_password_hash
import httpx

BASE="/opt/ollama-gateway"
DB=f"{BASE}/db/gateway.db"
OLLAMA="http://127.0.0.1:11434/api/chat"

app = Quart(__name__)
app.secret_key = "local-ai-gateway-secret"

# ================= DATABASE =================
def db():
    c = sqlite3.connect(DB, timeout=30)
    c.row_factory = sqlite3.Row
    return c

def init_db():
    c=db()
    c.execute("PRAGMA journal_mode=WAL;")
    c.execute("""
    CREATE TABLE IF NOT EXISTS users(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      email TEXT UNIQUE,
      password_hash TEXT,
      status TEXT,
      rate_limit INTEGER,
      created_at TEXT
    )""")
    c.execute("""
    CREATE TABLE IF NOT EXISTS logs(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      user_id INTEGER,
      prompt TEXT,
      response TEXT,
      ts TEXT
    )""")
    if not c.execute("SELECT 1 FROM users WHERE email='admin'").fetchone():
        c.execute("""
          INSERT INTO users(email,password_hash,status,rate_limit,created_at)
          VALUES(?,?,?,?,?)
        """,(
          "admin",
          generate_password_hash("admin123"),
          "active",
          999999,
          datetime.utcnow().isoformat()
        ))
    c.commit()
    c.close()

init_db()

# ================= RATE LIMIT =================
def rate_allowed(uid, limit):
    minute = datetime.utcnow().strftime("%Y-%m-%d %H:%M")
    c=db()
    count=c.execute("""
      SELECT COUNT(*) c FROM logs
      WHERE user_id=? AND ts LIKE ?
    """,(uid, minute+"%")).fetchone()["c"]
    c.close()
    return count < limit

# ================= UI =================
@app.route("/")
async def index():
    return await render_template("index.html")

@app.route("/logout")
async def logout():
    session.clear()
    return redirect("/")

@app.route("/register", methods=["POST"])
async def register():
    f=await request.form
    if f["password"] != f["confirm"]:
        return "Password mismatch",400
    try:
        c=db()
        c.execute("""
          INSERT INTO users(email,password_hash,status,rate_limit,created_at)
          VALUES(?,?,?,?,?)
        """,(f["email"], generate_password_hash(f["password"]),
             "pending", 10, datetime.utcnow().isoformat()))
        c.commit(); c.close()
    except:
        return "User exists",400
    return redirect("/")

@app.route("/reset", methods=["POST"])
async def reset():
    f=await request.form
    c=db()
    u=c.execute("SELECT * FROM users WHERE email=?",(f["email"],)).fetchone()
    if not u or not check_password_hash(u["password_hash"],f["old"]):
        return "Invalid credentials",403
    c.execute("UPDATE users SET password_hash=? WHERE id=?",
              (generate_password_hash(f["new"]),u["id"]))
    c.commit(); c.close()
    return redirect("/")

# ================= ADMIN =================
@app.route("/admin", methods=["POST"])
async def admin_login():
    f=await request.form
    c=db()
    a=c.execute("SELECT * FROM users WHERE email='admin'").fetchone()
    c.close()
    if not check_password_hash(a["password_hash"],f["password"]):
        return "Forbidden",403
    session["admin"]=True
    return redirect("/admin/panel")

@app.route("/admin/panel")
async def admin_panel():
    if not session.get("admin"):
        return redirect("/")
    c=db()
    users=c.execute("SELECT * FROM users WHERE email!='admin'").fetchall()
    c.close()
    return await render_template("admin.html",users=users)

@app.route("/admin/change-password", methods=["POST"])
async def admin_change_password():
    if not session.get("admin"): return redirect("/")
    f=await request.form
    if f["new"]!=f["confirm"]:
        return "Mismatch",400
    c=db()
    a=c.execute("SELECT * FROM users WHERE email='admin'").fetchone()
    if not check_password_hash(a["password_hash"],f["current"]):
        return "Invalid password",403
    c.execute("UPDATE users SET password_hash=? WHERE email='admin'",
              (generate_password_hash(f["new"]),))
    c.commit(); c.close()
    return redirect("/admin/panel")

@app.route("/toggle/<int:uid>", methods=["POST"])
async def toggle(uid):
    if not session.get("admin"): return redirect("/")
    c=db()
    s=c.execute("SELECT status FROM users WHERE id=?",(uid,)).fetchone()["status"]
    c.execute("UPDATE users SET status=? WHERE id=?",
              ("active" if s!="active" else "disabled",uid))
    c.commit(); c.close()
    return redirect("/admin/panel")

@app.route("/admin/reset/<int:uid>", methods=["POST"])
async def admin_reset(uid):
    if session.get("admin"):
        c=db()
        c.execute("UPDATE users SET password_hash=? WHERE id=?",
                  (generate_password_hash("admin123"),uid))
        c.commit(); c.close()
    return redirect("/admin/panel")

# ================= CSV EXPORT (FIXED) =================
@app.route("/export/<int:uid>")
async def export(uid):
    if not session.get("admin"): return redirect("/")

    c=db()
    rows=c.execute("""
        SELECT id, prompt, response, ts
        FROM logs
        WHERE user_id=?
        ORDER BY ts ASC
    """,(uid,)).fetchall()
    c.close()

    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(["log_id","prompt","response","timestamp"])
    for r in rows:
        writer.writerow([r["id"],r["prompt"],r["response"],r["ts"]])

    session[f"exported_{uid}"] = True

    return Response(
        output.getvalue(),
        mimetype="text/csv",
        headers={
            "Content-Disposition": f"attachment; filename=user_{uid}_audit.csv",
            "Cache-Control": "no-store"
        }
    )

@app.route("/confirm-delete/<int:uid>")
async def confirm_delete(uid):
    if not session.get("admin"): return redirect("/")
    return await render_template("confirm_delete.html",uid=uid)

@app.route("/delete/<int:uid>", methods=["POST"])
async def delete(uid):
    if not session.get("admin"): return redirect("/")
    if not session.get(f"exported_{uid}"):
        return "Export required before delete",403
    c=db()
    c.execute("DELETE FROM logs WHERE user_id=?",(uid,))
    c.execute("DELETE FROM users WHERE id=?",(uid,))
    c.commit(); c.close()
    session.pop(f"exported_{uid}",None)
    return redirect("/admin/panel")

# ================= API =================
@app.route("/health")
async def health():
    return {"status":"ok"}

@app.route("/chat", methods=["POST"])
async def chat():
    data=await request.get_json()
    auth=data["auth"]
    c=db()
    u=c.execute("SELECT * FROM users WHERE email=?",(auth["username"],)).fetchone()
    if not u or u["status"]!="active" or not check_password_hash(u["password_hash"],auth["password"]):
        return jsonify({"error":"unauthorized"}),403
    if not rate_allowed(u["id"],u["rate_limit"]):
        return jsonify({"error":"rate limit exceeded"}),429

    async with httpx.AsyncClient(timeout=180) as h:
        r=await h.post(OLLAMA,json={
            "model":data.get("model","llama3.2:latest"),
            "messages":data["messages"],
            "stream":False
        })

    c.execute("INSERT INTO logs VALUES(NULL,?,?,?,?)",
              (u["id"],str(data["messages"]),str(r.json()),datetime.utcnow().isoformat()))
    c.commit(); c.close()
    return jsonify(r.json())
PYCODE

# ------------------------------------------------------------
# Templates
# ------------------------------------------------------------
cat > "$TPL/index.html" <<'HTML'
<!doctype html>
<html>
<head><script src="https://cdn.tailwindcss.com"></script></head>
<body class="bg-gray-100 p-10">
<h1 class="text-3xl font-bold mb-6">Local AI Gateway Portal</h1>
<div class="grid grid-cols-1 md:grid-cols-3 gap-6">
<form action="/register" method="post" class="bg-white p-6 rounded shadow space-y-2">
<h2 class="font-semibold">Register</h2>
<input name="email" class="border p-2 w-full" placeholder="Email">
<input type="password" name="password" class="border p-2 w-full" placeholder="Password">
<input type="password" name="confirm" class="border p-2 w-full" placeholder="Confirm">
<button class="bg-blue-600 text-white px-4 py-2 rounded">Register</button>
</form>
<form action="/reset" method="post" class="bg-white p-6 rounded shadow space-y-2">
<h2 class="font-semibold">Reset Password</h2>
<input name="email" class="border p-2 w-full" placeholder="Email">
<input type="password" name="old" class="border p-2 w-full" placeholder="Current">
<input type="password" name="new" class="border p-2 w-full" placeholder="New">
<button class="bg-yellow-600 text-white px-4 py-2 rounded">Reset</button>
</form>
<form action="/admin" method="post" class="bg-white p-6 rounded shadow space-y-2">
<h2 class="font-semibold">Admin Login</h2>
<input type="password" name="password" class="border p-2 w-full" placeholder="Admin password">
<button class="bg-black text-white px-4 py-2 rounded">Login</button>
</form>
</div>
</body>
</html>
HTML

cat > "$TPL/admin.html" <<'HTML'
<!doctype html>
<html>
<head><script src="https://cdn.tailwindcss.com"></script></head>
<body class="bg-gray-100 p-10">
<div class="flex justify-between mb-4">
<h1 class="text-2xl font-bold">Admin Panel</h1>
<a href="/logout" class="text-red-600">Logout</a>
</div>

<form action="/admin/change-password" method="post" class="bg-white p-4 mb-6 rounded shadow space-y-2">
<h2 class="font-semibold">Change Admin Password</h2>
<input type="password" name="current" class="border p-2 w-full" placeholder="Current password">
<input type="password" name="new" class="border p-2 w-full" placeholder="New password">
<input type="password" name="confirm" class="border p-2 w-full" placeholder="Confirm new password">
<button class="bg-purple-600 text-white px-4 py-2 rounded">Update Password</button>
</form>

<table class="bg-white w-full border">
<tr class="bg-gray-200">
<th>Email</th><th>Status</th><th>Rate/min</th><th>Actions</th>
</tr>
{% for u in users %}
<tr class="border-t">
<td>{{u.email}}</td>
<td>
<form action="/toggle/{{u.id}}" method="post">
<button class="px-2 py-1 rounded {{ 'bg-green-500 text-white' if u.status=='active' else 'bg-gray-400' }}">
{{ 'ACTIVE' if u.status=='active' else 'DISABLED' }}
</button>
</form>
</td>
<td>{{u.rate_limit}}</td>
<td class="space-x-2">
<form action="/admin/reset/{{u.id}}" method="post" style="display:inline">
<button class="text-orange-600">Reset Password</button>
</form>
<a href="/export/{{u.id}}" class="text-blue-600">Export CSV</a>
<a href="/confirm-delete/{{u.id}}" class="text-red-600">Delete</a>
</td>
</tr>
{% endfor %}
</table>
</body>
</html>
HTML

cat > "$TPL/confirm_delete.html" <<'HTML'
<!doctype html>
<html>
<head><script src="https://cdn.tailwindcss.com"></script></head>
<body class="bg-gray-100 p-10">
<div class="bg-white p-6 rounded shadow max-w-lg mx-auto">
<h2 class="text-xl font-bold text-red-600 mb-4">Confirm Deletion</h2>
<p class="mb-4">You must export user data before deletion.</p>
<a href="/export/{{uid}}" class="text-blue-600 underline">Download CSV</a>
<form action="/delete/{{uid}}" method="post" class="mt-4 space-x-4">
<button class="bg-red-600 text-white px-4 py-2 rounded">Delete Permanently</button>
<a href="/admin/panel" class="px-4 py-2 border rounded">Cancel</a>
</form>
</div>
</body>
</html>
HTML

# ------------------------------------------------------------
# Runner
# ------------------------------------------------------------
cat > "$BASE/run.sh" <<EOF
#!/usr/bin/env bash
exec $VENV/bin/gunicorn \
 -k uvicorn.workers.UvicornWorker \
 --workers 2 \
 --timeout 300 \
 --bind 0.0.0.0:7000 \
 app.app:app
EOF
chmod +x "$BASE/run.sh"

# ------------------------------------------------------------
# systemd
# ------------------------------------------------------------
sudo tee /etc/systemd/system/$SERVICE.service >/dev/null <<EOF
[Unit]
Description=Local AI Gateway
After=network.target ollama.service
Requires=ollama.service

[Service]
WorkingDirectory=$BASE
ExecStart=$BASE/run.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now $SERVICE

echo "[✓] Installation complete"
echo "Admin login: admin / admin123"
