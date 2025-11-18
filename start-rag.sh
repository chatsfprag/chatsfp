#!/bin/bash

# RAG System Startup Script
# This script will start the entire RAG system with Ollama and DeepSeek-R1

set -e

echo "🚀 Starting RAG System with Ollama and DeepSeek-R1..."
echo "=================================================="

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker first."
    echo "Visit: https://docs.docker.com/get-docker/"
    exit 1
fi

# Check if Docker Compose is available
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    echo "❌ Docker Compose is not installed. Please install Docker Compose first."
    exit 1
fi

# Create necessary directories
echo "📁 Creating necessary directories..."
mkdir -p data embeddings static tmp vector_store

# Stop any existing RAG containers
echo "🛑 Stopping any existing RAG containers..."
docker stop rag-streamlit-app 2>/dev/null || true
docker rm rag-streamlit-app 2>/dev/null || true
docker stop rag-ollama-setup 2>/dev/null || true
docker rm rag-ollama-setup 2>/dev/null || true

# Check if port 8503 is available
if lsof -Pi :8503 -sTCP:LISTEN -t >/dev/null 2>&1 ; then
    echo "⚠️  Port 8503 is already in use!"
    echo "Please stop the service using this port or choose a different port."
    exit 1
fi

# Remove any existing volumes if requested
read -p "🗑️  Do you want to remove existing Ollama data (models will be re-downloaded)? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🗑️  Removing existing Ollama data..."
    docker volume rm $(docker volume ls -q | grep ollama) 2>/dev/null || true
    docker stop rag-ollama 2>/dev/null || true
    docker rm rag-ollama 2>/dev/null || true
fi

# Use docker-compose or docker compose based on availability
if command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
else
    COMPOSE_CMD="docker compose"
fi

# Start Ollama if not already running
if ! docker ps | grep -q rag-ollama; then
    echo "📦 Starting Ollama service..."
    $COMPOSE_CMD up --build -d ollama

    echo "⏳ Waiting for Ollama to be ready..."
    timeout=60
    counter=0

    while ! curl -f http://localhost:11435/api/tags &>/dev/null; do
        if [ $counter -eq $timeout ]; then
            echo "❌ Timeout waiting for Ollama to start"
            $COMPOSE_CMD logs ollama
            exit 1
        fi
        echo "   Waiting... ($counter/$timeout seconds)"
        sleep 2
        counter=$((counter + 2))
    done

    echo "✅ Ollama is ready!"
else
    echo "✅ Ollama is already running!"
fi

# Check if DeepSeek model needs to be downloaded
echo "🔍 Checking for DeepSeek-R1 model..."
if docker exec rag-ollama ollama list | grep -q "deepseek-r1"; then
    echo "✅ DeepSeek-R1 model already downloaded!"
else
    echo "📥 Downloading DeepSeek-R1 model..."
    echo "   This may take 5-15 minutes depending on your internet connection..."
    $COMPOSE_CMD up ollama-setup
fi

echo "🏗️  Building and starting RAG application..."
$COMPOSE_CMD up --build -d rag-app

echo ""
echo "🎉 RAG System is starting up!"
echo "=================================================="
echo ""
echo "📊 Service Status:"
$COMPOSE_CMD ps

echo ""
echo "🌐 Access your application at:"
echo "   http://localhost:8503"
echo ""
echo "🔧 Useful commands:"
echo "   View logs:           $COMPOSE_CMD logs -f"
echo "   View app logs:       $COMPOSE_CMD logs -f rag-app"
echo "   View ollama logs:    $COMPOSE_CMD logs -f ollama"
echo "   Stop services:       $COMPOSE_CMD down"
echo "   Restart app:         $COMPOSE_CMD restart rag-app"
echo "   Update models:       docker exec rag-ollama ollama pull deepseek-r1:8b"
echo ""

# Wait for the application to be ready
echo "⏳ Waiting for RAG application to be ready..."
if timeout 60 bash -c 'while ! curl -f http://localhost:8503/_stcore/health &>/dev/null; do sleep 2; done'; then
    echo "✅ RAG Application is ready!"
    echo ""
    echo "🎯 Open your browser to: http://localhost:8503"
    echo "💡 The app includes DeepSeek-R1 model for local inference"
else
    echo "⚠️  Application might still be initializing..."
    echo "   Check the logs: $COMPOSE_CMD logs rag-app"
    echo "   Or try accessing: http://localhost:8503"
fi

echo ""
echo "📝 Note: Your other services remain running:"
echo "   - eScriptorium: http://localhost:8501"
echo "   - Flower: http://localhost:5555"
echo "   - Pandore: http://localhost:8550"