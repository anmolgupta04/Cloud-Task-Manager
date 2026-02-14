# ☁ Cloud Task Manager — Production Deployment Guide

Complete production-ready task management system with FastAPI, PostgreSQL, Redis, Docker, Kubernetes, and CI/CD.

---

## 🚀 Quick Start (Local with Docker)

**Prerequisites:** Docker + Docker Compose installed

### Option 1: One-Command Deploy
```bash
chmod +x scripts/quick-deploy.sh
./scripts/quick-deploy.sh
```

### Option 2: Manual Deploy
```bash
# 1. Create environment file
cp backend/.env.example backend/.env

# 2. Generate secure secret key
python3 -c "import secrets; print(secrets.token_hex(32))" > /tmp/secret.txt
# OR
openssl rand -hex 32 > /tmp/secret.txt

# 3. Update backend/.env with the secret key
# Replace SECRET_KEY=change-me... with your generated key

# 4. Start services
cd devops/docker
docker compose up -d --build

# 5. Check status
docker compose ps
```

**Access Points:**
- **Frontend:** http://localhost
- **API Docs:** http://localhost:8000/docs
- **Grafana:** http://localhost:3000 (admin / admin123)
- **Prometheus:** http://localhost:9090

**Default Login:**
- Email: `demo@cloudtask.io`
- Password: `Demo1234!`

---

## ☁ AWS Production Deployment

**Prerequisites:**
- AWS CLI configured (`aws configure`)
- Terraform >= 1.7
- kubectl installed
- Docker installed

### Automated Deployment
```bash
chmod +x scripts/deploy-aws.sh
./scripts/deploy-aws.sh
```

The script will:
1. ✅ Provision AWS infrastructure (EKS, RDS, ElastiCache, VPC)
2. ✅ Configure kubectl for your EKS cluster
3. ✅ Build and push Docker image to ECR
4. ✅ Create Kubernetes secrets
5. ✅ Deploy application to Kubernetes
6. ✅ Set up auto-scaling and monitoring

### Manual AWS Deployment

#### Step 1: Provision Infrastructure
```bash
cd infrastructure/terraform

# Initialize Terraform
terraform init

# Review plan
terraform plan -var="db_password=YOUR_SECURE_PASSWORD"

# Apply
terraform apply -var="db_password=YOUR_SECURE_PASSWORD"

# Save outputs
terraform output -json > outputs.json
```

#### Step 2: Build & Push Docker Image
```bash
# Get ECR URL from Terraform output
ECR_URL=$(terraform output -raw ecr_repository_url)
AWS_REGION="us-east-1"

# Login to ECR
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $ECR_URL

# Build image
docker build -t $ECR_URL:latest \
  -f devops/docker/Dockerfile \
  backend/

# Push to ECR
docker push $ECR_URL:latest
```

#### Step 3: Configure Kubernetes
```bash
# Get cluster name
CLUSTER_NAME=$(terraform output -raw eks_cluster_name)

# Update kubeconfig
aws eks update-kubeconfig --name $CLUSTER_NAME --region $AWS_REGION

# Verify connection
kubectl get nodes
```

#### Step 4: Create Secrets
```bash
# Get infrastructure endpoints from Terraform
RDS_ENDPOINT=$(terraform output -raw rds_endpoint)
REDIS_ENDPOINT=$(terraform output -raw redis_primary_endpoint)

# Generate secret key
SECRET_KEY=$(openssl rand -hex 32)

# Create secret
kubectl create secret generic task-secrets \
  --from-literal=database-url="postgresql+asyncpg://taskadmin:YOUR_PASSWORD@$RDS_ENDPOINT/taskdb" \
  --from-literal=redis-url="redis://$REDIS_ENDPOINT:6379/0" \
  --from-literal=secret-key="$SECRET_KEY" \
  -n task-manager
```

#### Step 5: Deploy to Kubernetes
```bash
# Apply manifests
kubectl apply -f devops/kubernetes/namespace.yaml

# Update deployment with your ECR image
sed "s|YOUR_ECR_REGISTRY/task-manager-api:latest|$ECR_URL:latest|" \
  devops/kubernetes/deployment.yaml | kubectl apply -f -

kubectl apply -f devops/kubernetes/service-hpa-ingress.yaml

# Watch deployment
kubectl rollout status deployment/task-api -n task-manager
```

#### Step 6: Get LoadBalancer URL
```bash
# Wait for LoadBalancer to provision
kubectl get ingress -n task-manager --watch

# Get URL
kubectl get ingress task-api-ingress -n task-manager -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

---

## 🔧 Development

### Run Backend Locally
```bash
cd backend

# Create virtual environment
python3 -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Start local PostgreSQL & Redis (or use Docker)
docker run -d --name postgres -p 5432:5432 \
  -e POSTGRES_PASSWORD=password \
  -e POSTGRES_DB=taskdb \
  postgres:15-alpine

docker run -d --name redis -p 6379:6379 redis:7-alpine

# Run API
uvicorn app.main:app --reload --port 8000
```

### Run Tests
```bash
cd backend
pytest tests/ -v --cov=app --cov-report=html

# View coverage report
open htmlcov/index.html
```

---

## 📊 Monitoring & Observability

### Access Dashboards
- **Grafana:** http://your-domain:3000
  - Username: `admin`
  - Password: `admin123` (change after first login)

- **Prometheus:** http://your-domain:9090

### View Logs
```bash
# Docker Compose
docker compose logs -f api

# Kubernetes
kubectl logs -f deployment/task-api -n task-manager
kubectl logs -f deployment/task-api -n task-manager --tail=100
```

### Check Metrics
```bash
# API health
curl http://localhost:8000/health

# Prometheus metrics
curl http://localhost:8000/metrics
```

---

## 🔄 CI/CD Pipeline

### GitHub Actions Setup

1. **Add Secrets to GitHub:**
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`

2. **Copy workflow file:**
```bash
mkdir -p .github/workflows
cp devops/ci-cd/github-actions.yml .github/workflows/deploy.yml
```

3. **Push to GitHub:**
```bash
git add .
git commit -m "Initial commit"
git push origin main
```

The pipeline will automatically:
- ✅ Run tests on every PR
- ✅ Build Docker image on merge to `main`
- ✅ Push to ECR
- ✅ Deploy to EKS with rolling update
- ✅ Run security scans

---

## 🛠 Useful Commands

### Docker Compose
```bash
# View all logs
docker compose logs -f

# Restart specific service
docker compose restart api

# Stop all services
docker compose down

# Remove all data (WARNING: destroys volumes)
docker compose down -v

# Access database
docker compose exec postgres psql -U postgres -d taskdb

# Access Redis CLI
docker compose exec redis redis-cli
```

### Kubernetes
```bash
# View pods
kubectl get pods -n task-manager

# Scale deployment
kubectl scale deployment/task-api --replicas=5 -n task-manager

# Port-forward to service
kubectl port-forward svc/task-api-svc 8000:80 -n task-manager

# Execute command in pod
kubectl exec -it deployment/task-api -n task-manager -- /bin/bash

# View HPA status
kubectl get hpa -n task-manager

# View ingress
kubectl describe ingress task-api-ingress -n task-manager
```

### Database Management
```bash
# Connect to PostgreSQL
docker compose exec postgres psql -U postgres -d taskdb

# Backup database
docker compose exec postgres pg_dump -U postgres taskdb > backup.sql

# Restore database
docker compose exec -T postgres psql -U postgres taskdb < backup.sql

# View all tables
docker compose exec postgres psql -U postgres -d taskdb -c "\dt"
```

---

## 🔒 Security Best Practices

### Environment Variables
- ✅ Never commit `.env` files
- ✅ Use strong, randomly generated `SECRET_KEY`
- ✅ Rotate secrets regularly
- ✅ Use AWS Secrets Manager for production

### Database
- ✅ Use strong passwords (min 16 chars)
- ✅ Enable SSL/TLS connections
- ✅ Restrict network access
- ✅ Regular backups

### Kubernetes
- ✅ Use RBAC for pod access
- ✅ Enable Pod Security Standards
- ✅ Scan images for vulnerabilities
- ✅ Use network policies

---

## 📈 Scaling

### Horizontal Pod Autoscaling
The HPA automatically scales pods from 2 to 10 based on:
- CPU usage (target: 70%)
- Memory usage (target: 80%)

### Manual Scaling
```bash
# Scale to specific number
kubectl scale deployment/task-api --replicas=8 -n task-manager

# Update HPA limits
kubectl edit hpa task-api-hpa -n task-manager
```

### Database Scaling
- Vertical: Increase RDS instance size in Terraform
- Read replicas: Add via Terraform

---

## 🐛 Troubleshooting

### API not starting
```bash
# Check logs
docker compose logs api

# Common issues:
# 1. Database not ready → Wait 10s and retry
# 2. Redis connection failed → Check redis container
# 3. Port already in use → Change port in docker-compose.yml
```

### Database connection errors
```bash
# Test connection
docker compose exec api python -c "from app.core.database import engine; print('OK')"

# Check DATABASE_URL
docker compose exec api env | grep DATABASE_URL
```

### Pod CrashLoopBackOff
```bash
# View pod logs
kubectl logs -f <pod-name> -n task-manager

# Describe pod for events
kubectl describe pod <pod-name> -n task-manager

# Common causes:
# 1. Missing secrets
# 2. Wrong image tag
# 3. Database unreachable
```

---

## 📚 API Documentation

Once deployed, access:
- **Swagger UI:** http://your-domain/docs
- **ReDoc:** http://your-domain/redoc
- **OpenAPI JSON:** http://your-domain/openapi.json

---

## 🤝 Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open Pull Request

---

## 📝 License

MIT License - see LICENSE file for details

---

## 🆘 Support

- 📖 Documentation: See `/docs` folder
- 🐛 Issues: GitHub Issues
- 💬 Discussions: GitHub Discussions

---

**Built with ❤️ using FastAPI, PostgreSQL, Redis, Docker, Kubernetes & AWS**
