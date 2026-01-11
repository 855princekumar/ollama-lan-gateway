<img width="1505" height="467" alt="Banner" src="https://github.com/user-attachments/assets/05fae78d-d46c-4a22-b706-20ce77d6fb74" />

---
# Ollama LAN AI Gateway

**Authenticated, Audited, Rate-Limited API for Local LLMs (On-Prem)**

![Status](https://img.shields.io/badge/status-active-success)
![Deployment](https://img.shields.io/badge/deployment-on--premise-critical)
![Privacy](https://img.shields.io/badge/privacy-local--only-important)
![Python](https://img.shields.io/badge/python-3.10%2B-blue)
![Ollama](https://img.shields.io/badge/LLM-Ollama-black)
![Auth](https://img.shields.io/badge/auth-user--based-green)
![Rate Limit](https://img.shields.io/badge/rate--limit-enabled-yellow)
![Audit Logs](https://img.shields.io/badge/audit-logged-blueviolet)

---

## 1. Why This Project Exists

This project was built to solve a **real in-house operational problem** encountered while working with AI/ML, Computer Vision, DevOps automation, and research workflows.

Teams were increasingly using:

- Free-tier cloud LLM APIs (privacy, cost, rate limits)
- Local LLMs via Ollama for offline validation
- Open WebUI for human interaction
- Automation tools (n8n, scripts, CI jobs) that **cannot safely rely on GUIs**

While Ollama is an excellent local inference engine, it is **not designed** for:

- Multi-user access
- Authentication
- Rate limiting
- Audit logging
- Automation safety

At one point, a single automation pipeline overwhelmed the local inference system, impacting other users. There was **no visibility** into who sent what, when, or why.

This gateway was built as a **lightweight, production-safe middleware** to:

- Protect the inference host
- Isolate users
- Enable automation
- Provide auditability
- Preserve privacy and offline operation

---

## 2. Design Philosophy

- Ollama remains **localhost-only**
- Users never access the inference API directly
- All access is authenticated and logged
- Rate limits protect system stability
- Minimal footprint, no system pollution
- Automation-first, UI-optional

---

## 3. High-Level Architecture

```mermaid
flowchart LR
    subgraph Host["Inference Host (Single Machine)"]
        OLLAMA["Ollama Core\n127.0.0.1:11434\nOffline Models"]
        WEBUI["Open WebUI\nPort 8080\nHuman UI"]
        GATEWAY["LAN AI Gateway\nPort 7000\nAuth • Logs • Rate Limit"]

        WEBUI -->|localhost| OLLAMA
        GATEWAY -->|localhost only| OLLAMA
    end

    subgraph LAN["LAN / Team / Automation"]
        USERS["Human Users"]
        SCRIPTS["Scripts"]
        N8N["n8n"]
        PIPE["AI / ML / CV Pipelines"]
    end

    USERS -->|HTTP| GATEWAY
    SCRIPTS -->|HTTP| GATEWAY
    N8N -->|HTTP| GATEWAY
    PIPE -->|HTTP| GATEWAY
````

---

## 4. Core Security Boundary (Important)

**The gateway must run on the same machine as Ollama.**

* Ollama listens only on:

  ```
  http://127.0.0.1:11434
  ```
* Ollama is never exposed over LAN
* All external access is mediated by the gateway

This boundary is intentional and enforced.

---

## 5. Components Overview

| Component      | Role                             |
| -------------- | -------------------------------- |
| Ollama         | Local inference engine           |
| Open WebUI     | Human interaction UI (port 8080) |
| LAN AI Gateway | Authenticated API (port 7000)    |
| SQLite (WAL)   | Users, logs, audit               |
| systemd        | Auto-start, auto-heal            |

---

## 6. What This Gateway Adds

| Capability         | Ollama | Gateway |
| ------------------ | ------ | ------- |
| LAN API            | No     | Yes     |
| Authentication     | No     | Yes     |
| Per-user isolation | No     | Yes     |
| Rate limiting      | No     | Yes     |
| Prompt logging     | No     | Yes     |
| Response logging   | No     | Yes     |
| CSV audit export   | No     | Yes     |

---

## 7. Control Plane & User Access (Gateway UI)

The gateway includes a **minimal control plane** for governance and security.
It does **not** perform inference.

### User Dashboard

<img width="1874" height="374" alt="Main-dashboard" src="https://github.com/user-attachments/assets/b771d35d-b49c-42b0-9f4e-8c725d1bc70f" />

Users can:

* Register with email
* Reset password (if known)
* Await admin approval

---

### Admin Panel

<img width="1897" height="580" alt="admin-pannel" src="https://github.com/user-attachments/assets/a4bf0275-f87e-4f86-a696-bbe898c121db" />

Admin can:

* Approve / disable users
* Reset user passwords to `admin123`
* Export per-user audit logs (CSV)
* Delete users (export enforced)
* Change admin password

---

## 8. Access & User Management

### Base URL

```
http://<HOST_IP>:7000
```

Example:

```
http://192.168.1.2:7000
```

### Default Admin

* Username: `admin`
* Password: `admin123`
* Mandatory password change on first login

---

## 9. Rate Limiting

* Default: **10 requests per minute per user**
* Enforced at gateway
* Protects inference host from overload

HTTP `429` is returned if exceeded.

---

## 10. API Endpoints

### Health

```
GET /health
```

### Inference

```
POST /chat
```

---

## 11. Request Format (Required Auth)

```json
{
  "auth": {
    "username": "user@company.com",
    "password": "password"
  },
  "model": "llama3.2:latest",
  "messages": [
    { "role": "user", "content": "Hello" }
  ]
}
```

---

## 12. Usage Examples

### Linux / macOS

```bash
curl http://192.168.1.2:7000/chat \
-H "Content-Type: application/json" \
-d '{
  "auth": {"username":"user@company.com","password":"password"},
  "messages":[{"role":"user","content":"Explain MQTT"}]
}'
```

### Windows PowerShell

```powershell
Invoke-RestMethod `
 -Uri "http://192.168.1.2:7000/chat" `
 -Method Post `
 -ContentType "application/json" `
 -Body '{
   "auth":{"username":"user@company.com","password":"password"},
   "messages":[{"role":"user","content":"Explain MQTT"}]
 }'
```

---

## 13. Logging & Audit

* Logs prompt, response, user, timestamp
* Stored in SQLite (WAL)
* CSV export required before deletion
* Suitable for audits, debugging, research validation

---

## 14. Installation & Rollback

* Install script sets up `/opt` isolated service
* Rollback removes gateway only
* Ollama and Open WebUI unaffected

---

## 15. Roadmap

Planned updates:

1. Admin-editable per-user rate limits
2. Model discovery API via gateway

---

## 16. Final Notes

This is not a cloud LLM platform.
It is not a UI replacement.

It is a **focused, lightweight solution** to safely expose local LLMs for automation, auditing, and team use.

Built because it was needed.
Shared because others face the same problem.
