#!/bin/bash

##############################################################################
# setup_system.sh - AI Agent Setup Script for 8GB RAM System
# Tối ưu hóa hệ thống để chạy Ollama + Python Telegram Bot + Open WebUI
##############################################################################

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SWAP_SIZE=4096  # 4GB swap
VENV_PATH="./venv"
PYTHON_VERSION="3.11"

##############################################################################
# Helper Functions
##############################################################################

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

check_command() {
    if command -v $1 &> /dev/null; then
        return 0
    else
        return 1
    fi
}

##############################################################################
# 1. RAM Optimization - Create Swap File
##############################################################################

setup_swap() {
    print_header "1. SETUP SWAP FILE (4GB) untuk 8GB RAM System"
    
    SWAP_FILE="/swapfile"
    
    # Check if swap already exists
    if [ -f "$SWAP_FILE" ]; then
        print_warning "Swap file already exists at $SWAP_FILE"
        CURRENT_SWAP=$(sudo swapon --show | awk 'NR==2 {print $3}' | sed 's/G//')
        if [ ! -z "$CURRENT_SWAP" ]; then
            print_success "Current swap size: ${CURRENT_SWAP}GB"
            return 0
        fi
    fi
    
    print_warning "Creating ${SWAP_SIZE}MB swap file..."
    
    # Create swap file
    sudo fallocate -l ${SWAP_SIZE}M "$SWAP_FILE" || 
    sudo dd if=/dev/zero of="$SWAP_FILE" bs=1M count=$SWAP_SIZE
    
    sudo chmod 600 "$SWAP_FILE"
    sudo mkswap "$SWAP_FILE"
    sudo swapon "$SWAP_FILE"
    
    # Add to fstab for persistent swap
    if ! grep -q "$SWAP_FILE" /etc/fstab; then
        echo "$SWAP_FILE none swap sw 0 0" | sudo tee -a /etc/fstab > /dev/null
    fi
    
    print_success "Swap file created and enabled"
    
    # Show memory info
    free -h
}

##############################################################################
# 2. Install System Dependencies
##############################################################################

install_dependencies() {
    print_header "2. INSTALL SYSTEM DEPENDENCIES"
    
    print_warning "Updating package manager..."
    sudo apt-get update -qq
    
    # Core dependencies
    local packages=(
        "curl"
        "wget"
        "git"
        "python3"
        "python3-pip"
        "python3-venv"
        "python3-dev"
        "build-essential"
        "docker.io"
        "docker-compose"
        "htop"
        "sqlite3"
    )
    
    print_warning "Installing packages: ${packages[@]}"
    sudo apt-get install -y "${packages[@]}" > /dev/null 2>&1
    
    print_success "All dependencies installed"
}

##############################################################################
# 3. Install Ollama
##############################################################################

install_ollama() {
    print_header "3. INSTALL OLLAMA"
    
    if check_command ollama; then
        print_success "Ollama is already installed"
        ollama --version
        return 0
    fi
    
    print_warning "Downloading and installing Ollama..."
    curl -fsSL https://ollama.ai/install.sh | sh
    
    # Wait for ollama to be ready
    sleep 2
    
    print_success "Ollama installed successfully"
}

##############################################################################
# 4. Pull Qwen2.5:7B Model
##############################################################################

pull_model() {
    print_header "4. PULL QWEN2.5:7B MODEL"
    
    print_warning "Starting Ollama service..."
    sudo systemctl start ollama || true
    
    sleep 3
    
    # Check if model already exists
    if ollama list 2>/dev/null | grep -q "qwen2.5:7b"; then
        print_success "Model qwen2.5:7b already exists"
        return 0
    fi
    
    print_warning "Pulling qwen2.5:7b model (this may take 5-10 minutes)..."
    print_warning "Model size: ~5GB"
    
    ollama pull qwen2.5:7b
    
    print_success "Model pulled successfully"
    ollama list
}

##############################################################################
# 5. Install Docker & Setup Open WebUI
##############################################################################

setup_docker_webui() {
    print_header "5. SETUP DOCKER & OPEN WebUI"
    
    # Add user to docker group
    if ! groups $USER | grep -q docker; then
        print_warning "Adding $USER to docker group..."
        sudo usermod -aG docker $USER
        newgrp docker
    fi
    
    # Pull Open WebUI image
    print_warning "Pulling Open WebUI Docker image..."
    docker pull ghcr.io/open-webui/open-webui:latest
    
    print_success "Docker & Open WebUI setup complete"
    print_warning "To start Open WebUI, run:"
    echo -e "${YELLOW}docker run -d -p 3000:8080 --name open-webui \\${NC}"
    echo -e "${YELLOW}  -e OLLAMA_BASE_URL=http://localhost:11434 \\${NC}"
    echo -e "${YELLOW}  ghcr.io/open-webui/open-webui:latest${NC}"
}

##############################################################################
# 6. Setup Python Virtual Environment
##############################################################################

setup_python_env() {
    print_header "6. SETUP PYTHON VIRTUAL ENVIRONMENT"
    
    if [ -d "$VENV_PATH" ]; then
        print_warning "Virtual environment already exists"
    else
        print_warning "Creating Python $PYTHON_VERSION virtual environment..."
        python3 -m venv "$VENV_PATH"
    fi
    
    # Activate venv
    source "$VENV_PATH/bin/activate"
    
    # Upgrade pip
    print_warning "Upgrading pip..."
    pip install --upgrade pip setuptools wheel -q
    
    # Install required packages (optimized for 8GB RAM)
    print_warning "Installing Python packages..."
    pip install -q \
        "python-telegram-bot==20.7" \
        "ollama==0.1.48" \
        "aiohttp==3.9.2" \
        "asyncio-contextmanager==1.0.0" \
        "psutil==5.9.8" \
        "python-dotenv==1.0.0"
    
    print_success "Python environment setup complete"
    
    # Display installed packages
    echo -e "${BLUE}Installed packages:${NC}"
    pip list | grep -E "python-telegram-bot|ollama|aiohttp|psutil"
}

##############################################################################
# 7. Create Configuration Files
##############################################################################

create_config_files() {
    print_header "7. CREATE CONFIGURATION FILES"
    
    # Create .env file if it doesn't exist
    if [ ! -f ".env" ]; then
        print_warning "Creating .env file..."
        cat > .env << 'EOF'
# Telegram Bot Configuration
TELEGRAM_API_TOKEN=your_telegram_bot_token_here
ADMIN_CHAT_ID=your_chat_id_here

# Ollama Configuration
OLLAMA_URL=http://localhost:11434
OLLAMA_MODEL=qwen2.5:7b

# System Configuration
MAX_WORKERS=1
QUEUE_CHECK_INTERVAL=2
EOF
        print_warning ".env file created - Please update with your credentials"
    else
        print_success ".env file already exists"
    fi
    
    # Create database directory
    mkdir -p data
    chmod 755 data
    
    print_success "Configuration files ready"
}

##############################################################################
# 8. Verify Installation
##############################################################################

verify_installation() {
    print_header "8. VERIFY INSTALLATION"
    
    echo -e "${BLUE}System Information:${NC}"
    echo "CPU Cores: $(nproc)"
    echo "RAM:"
    free -h
    echo -e "\nSwap:"
    swapon --show 2>/dev/null || echo "No swap configured"
    
    echo -e "\n${BLUE}Installed Tools:${NC}"
    
    check_command ollama && print_success "Ollama: $(ollama --version 2>/dev/null || echo 'installed')"
    check_command docker && print_success "Docker: $(docker --version)"
    check_command python3 && print_success "Python: $(python3 --version)"
    
    echo -e "\n${BLUE}Ollama Model:${NC}"
    ollama list 2>/dev/null || echo "Ollama service not running"
    
    if [ -d "$VENV_PATH" ]; then
        print_success "Virtual environment: $VENV_PATH"
    fi
}

##############################################################################
# 9. Print Next Steps
##############################################################################

print_next_steps() {
    print_header "SETUP COMPLETED SUCCESSFULLY! 🚀"
    
    echo -e "${GREEN}Next Steps:${NC}\n"
    
    echo "1. Update configuration file:"
    echo -e "   ${YELLOW}nano .env${NC}"
    echo "   Add your Telegram API_TOKEN and ADMIN_CHAT_ID"
    echo ""
    
    echo "2. Ensure Ollama is running:"
    echo -e "   ${YELLOW}ollama serve${NC} (or let systemd manage it)"
    echo ""
    
    echo "3. Start Open WebUI (optional):"
    echo -e "   ${YELLOW}docker run -d -p 3000:8080 --name open-webui \\${NC}"
    echo -e "   ${YELLOW}  -e OLLAMA_BASE_URL=http://localhost:11434 \\${NC}"
    echo -e "   ${YELLOW}  ghcr.io/open-webui/open-webui:latest${NC}"
    echo ""
    
    echo "4. Activate virtual environment and start bot:"
    echo -e "   ${YELLOW}source venv/bin/activate${NC}"
    echo -e "   ${YELLOW}python3 tele_agent.py${NC}"
    echo ""
    
    echo "5. Access Web Interface:"
    echo -e "   ${YELLOW}http://localhost:3000${NC}"
    echo ""
    
    echo -e "${BLUE}Monitoring (in another terminal):${NC}"
    echo -e "   ${YELLOW}watch -n 1 'free -h && echo && ollama list'${NC}"
}

##############################################################################
# MAIN EXECUTION
##############################################################################

main() {
    print_header "AI AGENT SYSTEM SETUP - 8GB RAM Optimized"
    echo "Start time: $(date)"
    
    # Run setup functions
    setup_swap
    install_dependencies
    install_ollama
    pull_model
    setup_docker_webui
    setup_python_env
    create_config_files
    verify_installation
    print_next_steps
    
    echo -e "\n${GREEN}Completed at: $(date)${NC}\n"
}

# Run main function
main "$@"
