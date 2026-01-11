<img width="1505" height="467" alt="Banner" src="https://github.com/user-attachments/assets/05fae78d-d46c-4a22-b706-20ce77d6fb74" />

---
# Ollama LAN AI Gateway

**Authenticated, Audited, Rate-Limited API Gateway for Local LLMs (On-Prem, Privacy-First)**

![Status](https://img.shields.io/badge/status-active-success)
![Deployment](https://img.shields.io/badge/deployment-on--premise-critical)
![Privacy](https://img.shields.io/badge/privacy-local--only-important)
![Python](https://img.shields.io/badge/python-3.10%2B-blue)
![LLM](https://img.shields.io/badge/LLM-Ollama-black)
![Auth](https://img.shields.io/badge/auth-user--based-green)
![Rate Limit](https://img.shields.io/badge/rate--limit-enabled-yellow)
![Audit Logs](https://img.shields.io/badge/audit-logged-blueviolet)

---

## 1. Why This Project Exists (The Real Story)

This project was built to solve a **real in-house operational problem**, not as a demo or abstraction exercise.

As teams increasingly adopted AI/ML, Computer Vision, DevOps automation, and research workflows, the usage pattern evolved rapidly:

- Local LLMs (via Ollama) for offline validation and privacy-sensitive work
- Open WebUI for human interaction and exploration
- Automation tools (n8n, scripts, CI jobs) that **cannot depend on GUIs**
- Occasional use of cloud LLM APIs with privacy and cost constraints

While Ollama is an excellent **local inference engine**, it is intentionally **not designed** for:

- Multi-user access
- Authentication or user isolation
- Rate limiting
- Audit logging
- Automation safety
- Governance or accountability

At one point, a single automation pipeline overwhelmed the local inference host.
There was **no visibility** into:
- Who sent the requests
- Which pipeline caused the issue
- How frequently the system was being used
- Whether misuse or misconfiguration occurred

The system recovered-but the problem was clear.

This gateway was built as a **lightweight, production-safe control layer** to:

- Protect the core inference engine
- Isolate users and automation pipelines
- Enable safe API-based access
- Provide auditability and traceability
- Preserve privacy and offline operation
- Avoid touching or destabilizing the inference stack itself

---

## 2. Design Philosophy

This project follows a **governance-first, minimal-footprint philosophy**:

- Ollama remains **localhost-only**
- Users never interact with the inference engine directly
- All access is authenticated and logged
- Rate limits protect system stability
- UI exists only for governance, not inference
- Automation is a first-class use case
- The gateway is intentionally lightweight
- No system Python pollution
- Clean isolation under `/opt`

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
        SCRIPTS["Scripts (Python / Bash / PowerShell)"]
        N8N["n8n Workflows"]
        PIPE["AI / ML / CV Pipelines"]
    end

    USERS -->|HTTP| GATEWAY
    SCRIPTS -->|HTTP| GATEWAY
    N8N -->|HTTP| GATEWAY
    PIPE -->|HTTP| GATEWAY
````

---

## 4. Core Security Boundary (Critical)

**The gateway must be installed on the same machine where Ollama is running.**

* Ollama listens only on:

  ```
  http://127.0.0.1:11434
  ```
* Ollama is never exposed over LAN
* All external access is mediated by the gateway
* Users cannot bypass authentication or rate limits

This boundary is **intentional and enforced by design**.

---

## 5. Components Overview

| Component      | Role                                             |
| -------------- | ------------------------------------------------ |
| Ollama         | Local inference engine (multi-model, offline)    |
| Open WebUI     | Optional human UI (port 8080)                    |
| LAN AI Gateway | Authenticated API & governance layer (port 7000) |
| SQLite (WAL)   | Users, logs, audit storage                       |
| systemd        | Auto-start, auto-heal                            |

---

## 6. What This Gateway Adds

| Capability         | Ollama Native | Gateway |
| ------------------ | ------------- | ------- |
| LAN API            | No            | Yes     |
| Authentication     | No            | Yes     |
| Per-user isolation | No            | Yes     |
| Rate limiting      | No            | Yes     |
| Prompt logging     | No            | Yes     |
| Response logging   | No            | Yes     |
| CSV audit export   | No            | Yes     |
| Automation-safe    | Limited       | Yes     |

---

## 7. Control Plane & User Access (Gateway UI)

The gateway includes a **minimal control plane** focused on governance and security.
It does **not perform inference**.

### User Dashboard

<img width="1874" height="374" alt="Main-dashboard" src="https://github.com/user-attachments/assets/b771d35d-b49c-42b0-9f4e-8c725d1bc70f" />

Users can:

* Register using email
* Reset password (if known)
* Await admin approval

---

### Admin Panel

<img width="1897" height="580" alt="admin-pannel" src="https://github.com/user-attachments/assets/a4bf0275-f87e-4f86-a696-bbe898c121db" />

Admin can:

* Approve or disable users
* Reset user passwords to `admin123`
* Export per-user audit logs (CSV)
* Permanently delete users (export enforced)
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

### Default Admin Account

* Username: `admin`
* Password: `admin123`
* **Mandatory password change after first login**

---

## 9. Rate Limiting

* Default: **10 requests per minute per user**
* Enforced at the gateway
* Applies to scripts, automation, and pipelines
* Prevents runaway workloads

HTTP `429` is returned if exceeded.

---

## 10. API Endpoints

### Health Check

```
GET /health
```

### Inference

```
POST /chat
```

---

## 11. Request Format (Authentication Required)

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
  "auth":{"username":"user@company.com","password":"password"},
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

## 13. Logging, Audit & Compliance

* Logs:

  * User
  * Prompt
  * Model response
  * Timestamp
* Stored in SQLite (WAL mode)
* Per-user CSV export supported
* Export required before deletion

Suitable for:

* Research validation
* Automation debugging
* Incident investigation
* Compliance review

---

## 14. Installation & Rollback

* Install script:

  * Creates isolated environment under `/opt`
  * Sets up database and systemd service
* Rollback script:

  * Removes gateway only
  * Ollama and Open WebUI remain untouched

---

## 15. Project Versioning & Evolution

This project has evolved in **intentional phases**, each solving a specific problem.

| Version  | Focus                                  | Status    |
| -------- | -------------------------------------- | --------- |
| **v1.0** | Headless API gateway (PoC)             | Completed |
| **v2.x** | Auth, UI, audit, rate limiting         | Current   |
| **v3.x** | Hybrid local + cloud LLM control plane | Planned   |

### v1.0 – Headless Gateway

* Validated API design
* Automation safety
* No UI, no auth
* Used for internal proof-of-concept

### v2.x – Governance Layer (Current)

* User authentication
* Admin control plane
* Rate limiting
* Audit logging
* Production stability

### v3.x – Hybrid Local + Cloud (Planned)

* Unified access to:

  * Local LLMs (Ollama)
  * Cloud APIs (OpenAI, Claude, Gemini)
* Server-side API key management
* Per-user usage visibility
* Cost and governance controls

---

## 16. Cloud & Hybrid Capability (Planned)

The gateway is architecturally designed to support **cloud LLM APIs** without exposing raw credentials.

Planned capabilities:

* Provider routing per request
* Centralized API key storage
* Unified auth, logging, rate limits
* Safe internal sharing of paid accounts
* Hybrid local + cloud workloads

---

## 17. Roadmap

Planned enhancements:

1. Admin-editable per-user rate limits
2. Authenticated model discovery API
3. Hybrid provider routing (local + cloud)
4. Usage metrics & observability dashboard

---

## 18. Capacity, Limits & Operational Expectations (Important)

This project is intentionally designed as a **lightweight governance and control layer** for local and hybrid LLM usage.
It is **not** a high-throughput inference platform or a public multi-tenant service.

The following limits and expectations are provided to ensure **correct usage, stability, and realistic planning**.

---

### 18.1 Intended Usage Profile

This gateway is best suited for:

* Small to mid-sized teams (research, AI/ML, CV, DevOps)
* Shared on-prem GPU environments
* Automation pipelines requiring **auditability and safety**
* Privacy-first or offline-first deployments

It is **not intended** for:

* High-bandwidth public APIs
* Large-scale SaaS inference
* Unbounded concurrency workloads
* Multi-region or HA inference clusters

---

### 18.2 Tested & Practical Capacity (Realistic Numbers)

These numbers reflect **safe operating ranges**, not theoretical maximums.

#### User Scale

| Metric                  | Supported Range |
| ----------------------- | --------------- |
| Active users            | 5 – 20          |
| Concurrent active users | 2 – 5           |
| Admin users             | 1 – 2           |

Inference capacity, not the gateway, becomes the bottleneck beyond this.

---

#### Request Rate

| Metric                    | Value                           |
| ------------------------- | ------------------------------- |
| Default rate limit        | **10 requests / minute / user** |
| Aggregate safe throughput | ~50–200 requests / minute       |
| Enforcement point         | Gateway                         |

If exceeded, HTTP `429` is returned to protect system stability.

---

### 18.3 Concurrency Model

| Layer        | Constraint                       |
| ------------ | -------------------------------- |
| Gateway      | Async, handles many HTTP clients |
| SQLite (WAL) | Single writer, many readers      |
| Ollama       | GPU-bound, model dependent       |

Requests may queue naturally; rate limiting prevents cascading failures.

---

### 18.4 Token Length & Prompt Size

* Token limits are enforced by the model (not the gateway)
* Recommended usage:

| Prompt Type        | Suggested Limit |
| ------------------ | --------------- |
| Automation prompts | <1k tokens      |
| Analysis tasks     | 2k–4k tokens    |
| Large context      | Use sparingly   |

Excessive prompts can monopolize GPU time.

---

### 18.5 Multimodal (Images, Attachments)

If using models like LLaVA:

| Factor             | Practical Limit |
| ------------------ | --------------- |
| Images per request | 1               |
| Image size         | <5 MB           |
| Concurrent users   | 1–2             |

Multimodal inference is significantly more resource-intensive.

---

### 18.6 Logging & Storage

Each request logs:

* User identity
* Prompt
* Model response
* Timestamp

| Component    | Notes                      |
| ------------ | -------------------------- |
| SQLite (WAL) | Safe for concurrent access |
| Growth       | Linear with usage          |
| CSV export   | Mandatory before deletion  |

Avoid network-mounted filesystems for the DB.

---

### 18.7 Known Constraints (By Design)

This gateway does **not attempt** to handle:

| Scenario                     | Outcome               |
| ---------------------------- | --------------------- |
| Hundreds of concurrent users | Inference starvation  |
| Public traffic               | Rate-limited / denied |
| Large file uploads           | GPU contention        |
| Unbounded token use          | Latency spikes        |

These are deliberate design boundaries.

---

### 18.8 Positioning vs Large-Scale Platforms

| Aspect      | This Gateway   | SaaS Platforms |
| ----------- | -------------- | -------------- |
| Privacy     | Full (on-prem) | Partial        |
| Audit depth | Full           | Limited        |
| Cost        | Hardware-only  | Usage-based    |
| Scale       | Limited        | Very high      |
| Control     | Full           | Partial        |

This system optimizes for **control and accountability**, not raw throughput.

---

## 19. Final Notes

This is not a cloud LLM platform.
It is not a UI replacement.

It is a **focused, lightweight LLM control plane** designed to safely expose inference capabilities to humans and automation.

Built because it was needed.
Shared because others face the same problem.

---

