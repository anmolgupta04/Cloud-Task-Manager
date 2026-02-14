#!/bin/bash
set -e

echo "╔══════════════════════════════════════════════════════════╗"
echo "║   Cloud Task Manager - AWS EKS Deployment               ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Check prerequisites
command -v aws >/dev/null 2>&1 || { echo "❌ AWS CLI required. Install: https://aws.amazon.com/cli/"; exit 1; }
command -v terraform >/dev/null 2>&1 || { echo "❌ Terraform required. Install: https://terraform.io/downloads"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "❌ kubectl required. Install: https://kubernetes.io/docs/tasks/tools/"; exit 1; }

echo "✅ Prerequisites check passed"
echo ""

# Configuration
read -p "AWS Region [us-east-1]: " AWS_REGION
AWS_REGION=${AWS_REGION:-us-east-1}

read -p "Environment [production]: " ENV
ENV=${ENV:-production}

read -sp "Database Password (min 8 chars): " DB_PASSWORD
echo ""

if [ ${#DB_PASSWORD} -lt 8 ]; then
    echo "❌ Password must be at least 8 characters"
    exit 1
fi

echo ""
echo "📋 Configuration:"
echo "   Region: $AWS_REGION"
echo "   Environment: $ENV"
echo ""

# Step 1: Terraform Infrastructure
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 1: Provisioning AWS Infrastructure with Terraform"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

cd infrastructure/terraform

terraform init

echo ""
read -p "Review plan and continue? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Deployment cancelled"
    exit 0
fi

terraform apply -auto-approve \
    -var="aws_region=$AWS_REGION" \
    -var="environment=$ENV" \
    -var="db_password=$DB_PASSWORD"

# Get outputs
ECR_URL=$(terraform output -raw ecr_repository_url)
EKS_CLUSTER=$(terraform output -raw eks_cluster_name)
RDS_ENDPOINT=$(terraform output -raw rds_endpoint)
REDIS_ENDPOINT=$(terraform output -raw redis_primary_endpoint)

echo ""
echo "✅ Infrastructure provisioned:"
echo "   EKS Cluster: $EKS_CLUSTER"
echo "   ECR: $ECR_URL"
echo ""

cd ../..

# Step 2: Configure kubectl
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 2: Configuring kubectl"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

aws eks update-kubeconfig --name $EKS_CLUSTER --region $AWS_REGION

echo "✅ kubectl configured for $EKS_CLUSTER"
echo ""

# Step 3: Build and Push Docker Image
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 3: Building and Pushing Docker Image"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Login to ECR
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_URL

# Build
docker build -t $ECR_URL:latest -f devops/docker/Dockerfile backend/

# Push
docker push $ECR_URL:latest

echo "✅ Image pushed to ECR"
echo ""

# Step 4: Generate Secrets
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 4: Creating Kubernetes Secrets"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

SECRET_KEY=$(openssl rand -hex 32)
DATABASE_URL="postgresql+asyncpg://taskadmin:$DB_PASSWORD@$RDS_ENDPOINT/taskdb"
REDIS_URL="redis://$REDIS_ENDPOINT:6379/0"

# Create secret YAML
cat > /tmp/secrets.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: task-secrets
  namespace: task-manager
type: Opaque
stringData:
  database-url: "$DATABASE_URL"
  redis-url: "$REDIS_URL"
  secret-key: "$SECRET_KEY"
EOF

kubectl apply -f /tmp/secrets.yaml
rm /tmp/secrets.yaml

echo "✅ Secrets created"
echo ""

# Step 5: Deploy to Kubernetes
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STEP 5: Deploying to Kubernetes"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

kubectl apply -f devops/kubernetes/namespace.yaml

# Update deployment with ECR image
sed "s|YOUR_ECR_REGISTRY/task-manager-api:latest|$ECR_URL:latest|" devops/kubernetes/deployment.yaml | kubectl apply -f -

kubectl apply -f devops/kubernetes/service-hpa-ingress.yaml

echo ""
echo "⏳ Waiting for deployment to complete..."
kubectl rollout status deployment/task-api -n task-manager --timeout=300s

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║              ✅ DEPLOYMENT SUCCESSFUL                    ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "📊 Cluster Status:"
kubectl get pods -n task-manager
echo ""
kubectl get svc -n task-manager
echo ""
echo "🌐 Get LoadBalancer URL:"
echo "   kubectl get ingress -n task-manager"
echo ""
echo "📝 Useful commands:"
echo "   View logs:     kubectl logs -f deployment/task-api -n task-manager"
echo "   Scale pods:    kubectl scale deployment/task-api --replicas=5 -n task-manager"
echo "   Shell access:  kubectl exec -it deployment/task-api -n task-manager -- /bin/bash"
echo ""
