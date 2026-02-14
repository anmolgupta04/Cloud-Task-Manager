#!/bin/bash

echo "╔══════════════════════════════════════════════════════════╗"
echo "║   Cloud Task Manager - Pre-Deployment Check             ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

ERRORS=0
WARNINGS=0

# Function to check command
check_cmd() {
    if command -v $1 >/dev/null 2>&1; then
        echo "✅ $1 installed"
        return 0
    else
        echo "❌ $1 NOT installed"
        ERRORS=$((ERRORS + 1))
        return 1
    fi
}

# Function to check file
check_file() {
    if [ -f "$1" ]; then
        echo "✅ $1 exists"
        return 0
    else
        echo "❌ $1 MISSING"
        ERRORS=$((ERRORS + 1))
        return 1
    fi
}

echo "━━━ Checking Prerequisites ━━━"
check_cmd docker
check_cmd "docker compose"
echo ""

echo "━━━ Checking Project Structure ━━━"
check_file "backend/app/main.py"
check_file "backend/requirements.txt"
check_file "devops/docker/Dockerfile"
check_file "devops/docker/docker-compose.yml"
check_file "devops/kubernetes/deployment.yaml"
check_file "infrastructure/terraform/main.tf"
echo ""

echo "━━━ Checking Configuration ━━━"
if [ -f "backend/.env" ]; then
    echo "✅ backend/.env exists"
    
    # Check if SECRET_KEY was changed
    if grep -q "change-me-to-a-random-secure-string-in-production" backend/.env; then
        echo "⚠️  WARNING: SECRET_KEY not changed in .env"
        WARNINGS=$((WARNINGS + 1))
    else
        echo "✅ SECRET_KEY has been customized"
    fi
else
    echo "⚠️  WARNING: backend/.env not found (will be auto-generated)"
    WARNINGS=$((WARNINGS + 1))
fi
echo ""

echo "━━━ Checking Python Dependencies ━━━"
if check_cmd python3; then
    PYTHON_VERSION=$(python3 --version | awk '{print $2}')
    echo "   Version: $PYTHON_VERSION"
    
    # Check if version is 3.12+
    MAJOR=$(echo $PYTHON_VERSION | cut -d. -f1)
    MINOR=$(echo $PYTHON_VERSION | cut -d. -f2)
    
    if [ "$MAJOR" -eq 3 ] && [ "$MINOR" -ge 12 ]; then
        echo "   ✅ Python version is compatible (3.12+)"
    else
        echo "   ⚠️  Python 3.12+ recommended (current: $PYTHON_VERSION)"
        WARNINGS=$((WARNINGS + 1))
    fi
fi
echo ""

echo "━━━ Checking Docker ━━━"
if command -v docker >/dev/null 2>&1; then
    DOCKER_VERSION=$(docker --version | awk '{print $3}' | sed 's/,//')
    echo "   Version: $DOCKER_VERSION"
    
    # Check if Docker daemon is running
    if docker ps >/dev/null 2>&1; then
        echo "   ✅ Docker daemon is running"
    else
        echo "   ❌ Docker daemon is NOT running"
        ERRORS=$((ERRORS + 1))
    fi
fi
echo ""

echo "━━━ Optional: AWS Deployment Tools ━━━"
if check_cmd aws; then
    AWS_VERSION=$(aws --version 2>&1 | awk '{print $1}')
    echo "   $AWS_VERSION"
else
    echo "   ℹ️  AWS CLI not needed for local deployment"
fi

if check_cmd terraform; then
    TF_VERSION=$(terraform version | head -n1)
    echo "   $TF_VERSION"
else
    echo "   ℹ️  Terraform not needed for local deployment"
fi

if check_cmd kubectl; then
    KUBECTL_VERSION=$(kubectl version --client --short 2>/dev/null | head -n1)
    echo "   $KUBECTL_VERSION"
else
    echo "   ℹ️  kubectl not needed for local deployment"
fi
echo ""

echo "━━━ Summary ━━━"
if [ $ERRORS -eq 0 ]; then
    echo "✅ All required checks passed!"
    echo ""
    if [ $WARNINGS -gt 0 ]; then
        echo "⚠️  $WARNINGS warning(s) found (not critical)"
    fi
    echo ""
    echo "🚀 Ready to deploy! Run:"
    echo "   ./scripts/quick-deploy.sh"
    exit 0
else
    echo "❌ $ERRORS error(s) found"
    if [ $WARNINGS -gt 0 ]; then
        echo "⚠️  $WARNINGS warning(s) found"
    fi
    echo ""
    echo "Please fix the errors above before deploying."
    exit 1
fi
