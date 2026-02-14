#!/bin/bash
set -e

echo "╔══════════════════════════════════════════════════════════╗"
echo "║   Cloud Task Manager - Quick Deploy Script              ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Check prerequisites
command -v docker >/dev/null 2>&1 || { echo "❌ Docker is required but not installed. Aborting."; exit 1; }
command -v docker compose >/dev/null 2>&1 || { echo "❌ Docker Compose is required but not installed. Aborting."; exit 1; }

echo "✅ Prerequisites check passed"
echo ""

# Generate secure secret key if .env doesn't exist
if [ ! -f backend/.env ]; then
    echo "📝 Creating .env file..."
    cp backend/.env.example backend/.env
    
    # Generate random secret key
    SECRET_KEY=$(openssl rand -hex 32 2>/dev/null || python3 -c "import secrets; print(secrets.token_hex(32))" 2>/dev/null || echo "CHANGE-ME-$(date +%s)-RANDOM-KEY")
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/change-me-to-a-random-secure-string-in-production/$SECRET_KEY/" backend/.env
    else
        sed -i "s/change-me-to-a-random-secure-string-in-production/$SECRET_KEY/" backend/.env
    fi
    
    echo "✅ .env file created with random SECRET_KEY"
else
    echo "✅ .env file already exists"
fi

echo ""
echo "🚀 Starting services with Docker Compose..."
echo ""

cd devops/docker

# Build and start all services
docker compose up -d --build

echo ""
echo "⏳ Waiting for services to be healthy..."
sleep 8

# Check health
docker compose ps

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║                   ✅ DEPLOYMENT READY                    ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "🌐 Access the application:"
echo "   Frontend:    http://localhost"
echo "   API Docs:    http://localhost:8000/docs"
echo "   Grafana:     http://localhost:3000 (admin/admin123)"
echo "   Prometheus:  http://localhost:9090"
echo ""
echo "📊 Service Status:"
docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
echo ""
echo "📝 Useful commands:"
echo "   View logs:        cd devops/docker && docker compose logs -f"
echo "   Stop services:    cd devops/docker && docker compose down"
echo "   Restart:          cd devops/docker && docker compose restart"
echo "   View DB:          cd devops/docker && docker compose exec postgres psql -U postgres -d taskdb"
echo ""
echo "🎉 Happy task managing!"
