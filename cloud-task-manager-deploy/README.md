# ☁ Cloud Task Manager

> **Production-ready task management API** with JWT authentication, PostgreSQL, Redis caching, Dockerized microservices, Kubernetes auto-scaling, and full AWS infrastructure as code.

---

## ✨ Features

- 🔐 JWT authentication with refresh tokens
- ⚡ FastAPI async backend with PostgreSQL & Redis
- 🐳 Docker multi-stage builds (<150MB images)
- ☸️ Kubernetes auto-scaling (2-10 pods)
- ☁️ Complete AWS infrastructure (Terraform)
- 📊 Prometheus + Grafana monitoring
- 🚀 GitHub Actions CI/CD pipeline

---

## 🚀 Quick Start

### **Deploy Locally (2 Commands)**

```bash
chmod +x scripts/quick-deploy.sh
./scripts/quick-deploy.sh
```

**Access:**
- Frontend: http://localhost
- API Docs: http://localhost:8000/docs
- Grafana: http://localhost:3000

**Login:** `demo@cloudtask.io` / `Demo1234!`

---

## ☁️ Deploy to AWS

```bash
chmod +x scripts/deploy-aws.sh
./scripts/deploy-aws.sh
```

See **[DEPLOY.md](DEPLOY.md)** for complete deployment guide.

---

## 📁 Project Structure

```
├── backend/           # FastAPI app (API, models, services)
├── devops/
│   ├── docker/        # Dockerfile, docker-compose, NGINX
│   ├── kubernetes/    # K8s manifests (deployment, HPA, ingress)
│   └── ci-cd/         # GitHub Actions workflow
├── infrastructure/
│   ├── terraform/     # AWS IaC (EKS, RDS, ElastiCache)
│   └── monitoring/    # Prometheus & Grafana configs
└── scripts/           # Deployment automation
```

---

## 🛠 Tech Stack

| Component     | Technology                        |
|---------------|-----------------------------------|
| API           | FastAPI + Python 3.12             |
| Database      | PostgreSQL 15 (async SQLAlchemy)  |
| Cache         | Redis 7                           |
| Auth          | JWT (bcrypt)                      |
| Containers    | Docker multi-stage                |
| Orchestration | Kubernetes (EKS) + HPA            |
| IaC           | Terraform                         |
| CI/CD         | GitHub Actions                    |
| Monitoring    | Prometheus + Grafana              |

---

## 🔌 API Endpoints

**Auth:** `/api/v1/auth/` — register, login, refresh  
**Tasks:** `/api/v1/tasks/` — CRUD with pagination & filters  
**Users:** `/api/v1/users/me` — profile management

**Docs:** http://localhost:8000/docs

---

## 🧪 Testing

```bash
cd backend
pytest tests/ -v --cov=app
```

---

## 📝 License

MIT — Free to use and modify

---

**⭐ Star this repo if you find it useful!**
