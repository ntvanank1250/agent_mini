#!/bin/bash

##############################################################################
# quick-install.sh - All-in-one installation & start
# Run this after setting up .env file
##############################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "\n${BLUE}════════════════════════════════════════════${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

print_header "AI AGENT BOT - Quick Install & Start"

# Step 1: Check .env
print_header "Step 1: Checking Configuration"

if [ ! -f "$SCRIPT_DIR/.env" ]; then
    print_error ".env file not found!"
    print_warning "Creating from template..."
    cp "$SCRIPT_DIR/.env.example" "$SCRIPT_DIR/.env"
    print_warning "Please edit .env and add your Telegram credentials"
    nano "$SCRIPT_DIR/.env"
fi

# Verify required settings
if grep -q "your_telegram_bot_token_here" "$SCRIPT_DIR/.env"; then
    print_error ".env still has placeholder values!"
    echo "Please edit: nano $SCRIPT_DIR/.env"
    exit 1
fi

print_success ".env is configured"

# Step 2: Run setup if needed
print_header "Step 2: System Setup"

if [ ! -d "$SCRIPT_DIR/venv" ]; then
    print_warning "Virtual environment not found, running setup..."
    sudo bash "$SCRIPT_DIR/setup_system.sh"
else
    print_success "System already set up"
fi

# Step 3: Start services
print_header "Step 3: Starting Services"

bash "$SCRIPT_DIR/manage.sh" start

# Step 4: Show next steps
print_header "Installation Completed! 🎉"

echo -e "${GREEN}All services started successfully!${NC}\n"

echo "Next steps:"
echo "  1. Open Telegram and find your bot"
echo "  2. Send: /start"
echo "  3. Send: Hi (or any message)"
echo "  4. Bot will respond!"
echo ""
echo "Useful commands:"
echo "  ./manage.sh logs-live     - View logs in real-time"
echo "  ./manage.sh status        - Check system status"
echo "  ./manage.sh monitor       - Monitor resources"
echo "  ./manage.sh stop          - Stop all services"
echo ""
echo "Documentation:"
echo "  README.md                 - Full guide"
echo "  QUICK_REFERENCE.md        - Quick commands"
echo "  00_START_HERE.md          - Getting started"
echo ""
echo -e "${GREEN}✨ Bot is ready to chat! ✨${NC}"
