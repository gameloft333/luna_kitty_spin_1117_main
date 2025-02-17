#!/bin/bash

# Set color codes and ensure UTF-8 encoding
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
GREEN='\033[0;32m'
NC='\033[0m'
YELLOW='\033[1;33m'

# Project configuration
PROJECT_NAME="luna_kitty_spin_1117_main"
GITHUB_REPO="https://github.com/gameloft333/luna_kitty_spin_1117_main.git"
PROJECT_PATH="/var/www/$PROJECT_NAME"

echo -e "${GREEN}===== Starting deployment: $PROJECT_NAME =====${NC}"

# Stop and clean current services
echo -e "${YELLOW}Stopping current services...${NC}"
cd $PROJECT_PATH
docker-compose -f docker-compose-250217.yml down
docker system prune -f

# Check port usage
echo -e "${YELLOW}Checking port usage...${NC}"
PORT_PID=$(lsof -ti:42891)
if [ ! -z "$PORT_PID" ]; then
    echo "Terminating process using port 42891..."
    kill -9 $PORT_PID
fi

# Pull latest code
echo -e "${YELLOW}Pulling latest code...${NC}"
git fetch origin main
git reset --hard origin/main

# Rebuild and start services
echo -e "${YELLOW}Rebuilding and starting services...${NC}"
docker-compose up -f docker-compose-250217.yml -d --build

# Wait for service startup
echo -e "${YELLOW}Waiting for service startup...${NC}"
sleep 5

# Restart Nginx
# echo -e "${YELLOW}Restarting Nginx service...${NC}"
# sudo systemctl restart nginx

# Check service status
echo -e "${YELLOW}Checking service status...${NC}"
docker-compose ps
curl -I http://localhost:42891

echo -e "${GREEN}===== Deployment completed =====${NC}"