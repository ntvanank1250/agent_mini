#!/bin/bash

##############################################################################
# manage.sh - AI Agent System Management Script
# Quản lý toàn bộ hệ thống: Start, Stop, Monitor, Logs, Cleanup, etc.
##############################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_PATH="$SCRIPT_DIR/venv"
BOT_FILE="$SCRIPT_DIR/tele_agent.py"
BOT_LOG="$SCRIPT_DIR/bot_agent.log"
DB_PATH="$SCRIPT_DIR/data/chat_history.db"
PID_FILE="$SCRIPT_DIR/.bot.pid"

# Configuration
OLLAMA_PORT=11434
BOT_CHECK_INTERVAL=2

##############################################################################
# Utility Functions
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

print_info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

is_process_running() {
    pgrep -f "$1" > /dev/null 2>&1
}

##############################################################################
# Service Status Functions
##############################################################################

check_ollama() {
    if is_process_running "ollama"; then
        print_success "Ollama is running (PID: $(pgrep -f ollama | head -1))"
        return 0
    else
        print_error "Ollama is NOT running"
        return 1
    fi
}

check_bot() {
    if [ -f "$PID_FILE" ]; then
        BOT_PID=$(cat "$PID_FILE")
        if kill -0 "$BOT_PID" 2>/dev/null; then
            print_success "Bot is running (PID: $BOT_PID)"
            return 0
        else
            rm -f "$PID_FILE"
            print_error "Bot is NOT running (stale PID file removed)"
            return 1
        fi
    else
        if is_process_running "tele_agent.py"; then
            PID=$(pgrep -f "tele_agent.py" | head -1)
            echo "$PID" > "$PID_FILE"
            print_success "Bot is running (PID: $PID)"
            return 0
        else
            print_error "Bot is NOT running"
            return 1
        fi
    fi
}

check_port_available() {
    local port=$1
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
        return 1  # Port in use
    else
        return 0  # Port available
    fi
}

##############################################################################
# Start Functions
##############################################################################

start_ollama() {
    print_header "Starting Ollama Service"
    
    if check_ollama; then
        print_warning "Ollama is already running"
        return 0
    fi
    
    # Check if port is available
    if ! check_port_available $OLLAMA_PORT; then
        print_error "Port $OLLAMA_PORT is in use by another process"
        print_info "Trying to kill existing process..."
        sudo fuser -k $OLLAMA_PORT/tcp 2>/dev/null || true
        sleep 2
    fi
    
    # Start Ollama in background
    print_warning "Starting Ollama in background..."
    ollama serve > /tmp/ollama.log 2>&1 &
    OLLAMA_PID=$!
    
    # Wait for Ollama to be ready
    sleep 3
    
    for i in {1..10}; do
        if check_ollama; then
            print_success "Ollama started successfully"
            return 0
        fi
        print_warning "Waiting for Ollama to be ready... ($i/10)"
        sleep 1
    done
    
    print_error "Ollama failed to start"
    cat /tmp/ollama.log
    return 1
}

start_bot() {
    print_header "Starting Telegram Bot"
    
    if check_bot; then
        print_warning "Bot is already running"
        return 0
    fi
    
    # Check virtual environment
    if [ ! -d "$VENV_PATH" ]; then
        print_error "Virtual environment not found at $VENV_PATH"
        print_info "Run: sudo ./setup_system.sh"
        return 1
    fi
    
    # Check .env file
    if [ ! -f "$SCRIPT_DIR/.env" ]; then
        print_error ".env file not found"
        print_info "Run: cp .env.example .env && nano .env"
        return 1
    fi
    
    # Check Ollama
    if ! check_ollama; then
        print_warning "Ollama is not running, starting it..."
        if ! start_ollama; then
            return 1
        fi
    fi
    
    # Start bot in background
    print_warning "Starting bot in background..."
    source "$VENV_PATH/bin/activate"
    nohup python3 "$BOT_FILE" >> "$BOT_LOG" 2>&1 &
    BOT_PID=$!
    echo "$BOT_PID" > "$PID_FILE"
    
    # Wait for bot to start
    sleep 2
    
    if check_bot; then
        print_success "Bot started successfully (PID: $BOT_PID)"
        return 0
    else
        print_error "Bot failed to start"
        tail -20 "$BOT_LOG"
        return 1
    fi
}

##############################################################################
# Stop Functions
##############################################################################

stop_ollama() {
    print_header "Stopping Ollama"
    
    if ! check_ollama; then
        print_warning "Ollama is not running"
        return 0
    fi
    
    print_warning "Stopping Ollama..."
    pkill -f ollama || true
    
    # Wait for graceful shutdown
    sleep 2
    
    if check_ollama; then
        print_warning "Force killing Ollama..."
        pkill -9 -f ollama || true
    fi
    
    print_success "Ollama stopped"
}

stop_bot() {
    print_header "Stopping Bot"
    
    if ! check_bot; then
        print_warning "Bot is not running"
        return 0
    fi
    
    BOT_PID=$(cat "$PID_FILE" 2>/dev/null)
    
    if [ ! -z "$BOT_PID" ]; then
        print_warning "Stopping bot (PID: $BOT_PID)..."
        kill "$BOT_PID" 2>/dev/null || true
        
        # Wait for graceful shutdown
        sleep 2
        
        # Force kill if still running
        if kill -0 "$BOT_PID" 2>/dev/null; then
            print_warning "Force killing bot..."
            kill -9 "$BOT_PID" 2>/dev/null || true
        fi
    fi
    
    rm -f "$PID_FILE"
    print_success "Bot stopped"
}

##############################################################################
# Status Functions
##############################################################################

show_status() {
    print_header "System Status"
    
    echo -e "${CYAN}Services:${NC}"
    check_ollama && echo "" || echo ""
    check_bot && echo "" || echo ""
    
    echo -e "\n${CYAN}Memory Usage:${NC}"
    free -h
    
    echo -e "\n${CYAN}Swap:${NC}"
    swapon --show 2>/dev/null || echo "No swap configured"
    
    echo -e "\n${CYAN}CPU Usage:${NC}"
    echo "Cores: $(nproc)"
    echo "Load: $(cat /proc/loadavg)"
    
    if check_ollama; then
        echo -e "\n${CYAN}Ollama Models:${NC}"
        ollama list || true
    fi
    
    if check_bot; then
        echo -e "\n${CYAN}Bot Logs (last 10 lines):${NC}"
        tail -10 "$BOT_LOG" 2>/dev/null || echo "No logs yet"
    fi
}

##############################################################################
# Log Functions
##############################################################################

show_logs_live() {
    print_header "Bot Logs (Live)"
    print_info "Press Ctrl+C to stop"
    sleep 1
    tail -f "$BOT_LOG"
}

show_logs_tail() {
    local lines=${1:-50}
    print_header "Bot Logs (Last $lines lines)"
    tail -n "$lines" "$BOT_LOG"
}

show_ollama_logs() {
    print_header "Ollama Logs"
    tail -n 50 /tmp/ollama.log
}

clear_all_logs() {
    print_header "Clearing Logs"
    print_warning "This will clear all log files"
    read -p "Are you sure? (yes/no): " confirm
    
    if [ "$confirm" = "yes" ]; then
        > "$BOT_LOG"
        > /tmp/ollama.log
        print_success "Logs cleared"
    else
        print_warning "Cancelled"
    fi
}

##############################################################################
# Restart Functions
##############################################################################

restart_all() {
    print_header "Restarting All Services"
    
    stop_bot
    stop_ollama
    
    sleep 2
    
    start_ollama || return 1
    start_bot || return 1
    
    print_success "All services restarted"
}

restart_bot() {
    stop_bot
    sleep 1
    start_bot
}

restart_ollama() {
    stop_ollama
    sleep 2
    start_ollama
}

##############################################################################
# Database Functions
##############################################################################

db_info() {
    print_header "Database Information"
    
    if [ ! -f "$DB_PATH" ]; then
        print_error "Database not found at $DB_PATH"
        return 1
    fi
    
    # Count messages
    msg_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM conversations;" 2>/dev/null || echo "0")
    
    # Count users
    user_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM users;" 2>/dev/null || echo "0")
    
    # Database size
    db_size=$(du -h "$DB_PATH" | cut -f1)
    
    echo "Total Messages: $msg_count"
    echo "Total Users: $user_count"
    echo "Database Size: $db_size"
    
    # Recent messages
    echo -e "\n${CYAN}Recent Messages:${NC}"
    sqlite3 "$DB_PATH" "SELECT timestamp, user, role, substr(content, 1, 50) FROM conversations ORDER BY timestamp DESC LIMIT 5;" 2>/dev/null || true
}

db_backup() {
    print_header "Creating Database Backup"
    
    if [ ! -f "$DB_PATH" ]; then
        print_error "Database not found"
        return 1
    fi
    
    backup_file="$SCRIPT_DIR/data/chat_history_$(date +%Y%m%d_%H%M%S).backup"
    cp "$DB_PATH" "$backup_file"
    
    print_success "Database backed up to: $backup_file"
}

db_cleanup() {
    print_header "Database Cleanup"
    
    if [ ! -f "$DB_PATH" ]; then
        print_error "Database not found"
        return 1
    fi
    
    print_warning "Deleting messages older than 30 days..."
    
    sqlite3 "$DB_PATH" "
    DELETE FROM conversations 
    WHERE datetime(timestamp) < datetime('now', '-30 days');
    VACUUM;
    "
    
    print_success "Cleanup completed"
}

db_export() {
    print_header "Exporting Database"
    
    if [ ! -f "$DB_PATH" ]; then
        print_error "Database not found"
        return 1
    fi
    
    export_file="$SCRIPT_DIR/data/export_$(date +%Y%m%d_%H%M%S).csv"
    sqlite3 "$DB_PATH" ".mode csv" "SELECT * FROM conversations;" > "$export_file"
    
    print_success "Database exported to: $export_file"
}

db_reset() {
    print_header "Database Reset"
    print_warning "This will DELETE ALL conversation history!"
    read -p "Type 'YES' to confirm: " confirm
    
    if [ "$confirm" = "YES" ]; then
        sqlite3 "$DB_PATH" "DELETE FROM conversations; DELETE FROM users; VACUUM;"
        print_success "Database reset"
    else
        print_warning "Cancelled"
    fi
}

##############################################################################
# Cleanup Functions
##############################################################################

cleanup_temp_files() {
    print_header "Cleanup Temporary Files"
    
    if [ -d "$SCRIPT_DIR/data/temp_files" ]; then
        rm -rf "$SCRIPT_DIR/data/temp_files"/*
        print_success "Temporary files cleaned"
    else
        print_warning "No temporary files found"
    fi
}

cleanup_cache() {
    print_header "Cleanup Cache & Memory"
    
    print_warning "Cleaning Python cache..."
    find "$SCRIPT_DIR" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
    find "$SCRIPT_DIR" -type f -name "*.pyc" -delete 2>/dev/null || true
    
    print_warning "Running garbage collection..."
    python3 -c "import gc; gc.collect()"
    
    print_success "Cache cleaned"
}

cleanup_all() {
    print_header "Full Cleanup"
    
    cleanup_temp_files
    cleanup_cache
    
    print_success "Full cleanup completed"
}

##############################################################################
# Monitor Functions
##############################################################################

monitor_system() {
    print_header "System Monitor (Press Ctrl+C to stop)"
    
    while true; do
        clear
        echo -e "${BLUE}=== AI AGENT SYSTEM MONITOR ===${NC}"
        echo "Time: $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        
        echo -e "${CYAN}SERVICES:${NC}"
        if check_ollama 2>/dev/null; then
            echo -e "${GREEN}✓ Ollama${NC}"
        else
            echo -e "${RED}✗ Ollama${NC}"
        fi
        
        if check_bot 2>/dev/null; then
            echo -e "${GREEN}✓ Bot${NC}"
        else
            echo -e "${RED}✗ Bot${NC}"
        fi
        
        echo ""
        echo -e "${CYAN}RESOURCES:${NC}"
        echo "Memory: $(free -h | grep Mem | awk '{print $3 "/" $2}')"
        echo "Swap: $(free -h | grep Swap | awk '{print $3 "/" $2}')"
        echo "CPU Load: $(cat /proc/loadavg | awk '{print $1, $2, $3}')"
        
        if check_ollama 2>/dev/null; then
            echo ""
            echo -e "${CYAN}OLLAMA:${NC}"
            ollama ps 2>/dev/null | tail -5 || echo "No models running"
        fi
        
        echo ""
        echo -e "${YELLOW}(Refreshing in 5 seconds... Press Ctrl+C to exit)${NC}"
        sleep 5
    done
}

##############################################################################
# Configuration Functions
##############################################################################

show_env() {
    print_header "Current Configuration"
    
    if [ -f "$SCRIPT_DIR/.env" ]; then
        echo -e "${CYAN}Loaded from .env:${NC}"
        grep -E "^[A-Z]" "$SCRIPT_DIR/.env" | sed 's/=.*/=**REDACTED**/' || true
    else
        print_error ".env file not found"
    fi
}

edit_env() {
    print_header "Editing Configuration"
    
    if [ ! -f "$SCRIPT_DIR/.env" ]; then
        print_warning ".env not found, creating from template..."
        cp "$SCRIPT_DIR/.env.example" "$SCRIPT_DIR/.env"
    fi
    
    nano "$SCRIPT_DIR/.env"
    print_success "Configuration updated"
}

##############################################################################
# Help Function
##############################################################################

show_help() {
    cat << 'EOF'

╔════════════════════════════════════════════════════════════════════════════╗
║                   AI AGENT BOT - Management Tool                          ║
║                                                                            ║
║  Usage: ./manage.sh [command] [options]                                   ║
╚════════════════════════════════════════════════════════════════════════════╝

CORE COMMANDS:
──────────────
  status              Show system status
  start               Start all services (Ollama + Bot)
  stop                Stop all services
  restart             Restart all services

SERVICE COMMANDS:
────────────────
  start-ollama        Start Ollama only
  stop-ollama         Stop Ollama only
  restart-ollama      Restart Ollama

  start-bot           Start Bot only
  stop-bot            Stop Bot only
  restart-bot         Restart Bot only

LOG COMMANDS:
─────────────
  logs                Show bot logs (last 50 lines)
  logs-live           Follow bot logs live (Ctrl+C to exit)
  logs-tail [N]       Show last N lines of bot logs
  logs-ollama         Show Ollama logs
  logs-clear          Clear all logs

DATABASE COMMANDS:
──────────────────
  db-info             Show database information
  db-backup           Backup database
  db-cleanup          Delete messages older than 30 days
  db-export           Export database to CSV
  db-reset            ⚠️  RESET all conversations (destructive!)

MAINTENANCE:
────────────
  cleanup             Clean temporary files & cache
  cleanup-temp        Clean only temporary files
  cleanup-cache       Clean only cache files
  monitor             Real-time system monitor

CONFIGURATION:
───────────────
  config-show         Show current configuration
  config-edit         Edit .env configuration

SYSTEM:
───────
  help                Show this help message
  version             Show version information

EXAMPLES:
─────────
  ./manage.sh status              # Check system status
  ./manage.sh start               # Start all services
  ./manage.sh logs-live           # Follow logs in real-time
  ./manage.sh db-backup           # Backup database
  ./manage.sh monitor             # Monitor system resources
  ./manage.sh restart-bot         # Restart bot only
  ./manage.sh db-cleanup          # Clean old messages

TIPS:
─────
  • Run with 'sudo' if you need to stop/start Ollama service
  • Use 'logs-live' to debug issues in real-time
  • Use 'monitor' to watch system resources
  • Back up database before cleaning
  • Check 'config-show' to verify settings

EOF
}

show_version() {
    cat << 'EOF'

╔════════════════════════════════════════════════════════════════════════════╗
║                 AI AGENT BOT - System Information                          ║
╚════════════════════════════════════════════════════════════════════════════╝

Version:            1.0
Release Date:       2024-02-26
Status:             Production Ready

Components:
  • Ollama (Local AI Engine)
  • python-telegram-bot (Bot Framework)
  • SQLite (Database)
  • Docker (Web UI optional)

Optimizations:
  • 8GB RAM optimized
  • Single worker queue
  • Auto memory cleanup
  • Conversation memory (20 msgs)
  • File processing support

System Requirements:
  • RAM: 8GB minimum
  • CPU: 4 cores minimum
  • Disk: 20GB minimum
  • OS: Ubuntu 20.04+ / Debian

Documentation:
  • README.md - Full documentation
  • QUICK_REFERENCE.md - Quick commands
  • 00_START_HERE.md - Getting started

For more info, see: README.md

EOF
}

##############################################################################
# Main Command Dispatcher
##############################################################################

main() {
    local command="${1:-help}"
    
    case "$command" in
        # Status
        status)
            show_status
            ;;
        
        # Core services
        start)
            start_ollama && start_bot
            ;;
        stop)
            stop_bot && stop_ollama
            ;;
        restart)
            restart_all
            ;;
        
        # Ollama
        start-ollama)
            start_ollama
            ;;
        stop-ollama)
            stop_ollama
            ;;
        restart-ollama)
            restart_ollama
            ;;
        
        # Bot
        start-bot)
            start_bot
            ;;
        stop-bot)
            stop_bot
            ;;
        restart-bot)
            restart_bot
            ;;
        
        # Logs
        logs)
            show_logs_tail "${2:-50}"
            ;;
        logs-tail)
            show_logs_tail "${2:-50}"
            ;;
        logs-live)
            show_logs_live
            ;;
        logs-ollama)
            show_ollama_logs
            ;;
        logs-clear)
            clear_all_logs
            ;;
        
        # Database
        db-info)
            db_info
            ;;
        db-backup)
            db_backup
            ;;
        db-cleanup)
            db_cleanup
            ;;
        db-export)
            db_export
            ;;
        db-reset)
            db_reset
            ;;
        
        # Cleanup
        cleanup)
            cleanup_all
            ;;
        cleanup-temp)
            cleanup_temp_files
            ;;
        cleanup-cache)
            cleanup_cache
            ;;
        
        # Monitor
        monitor)
            monitor_system
            ;;
        
        # Configuration
        config-show)
            show_env
            ;;
        config-edit)
            edit_env
            ;;
        
        # Help & Info
        help)
            show_help
            ;;
        version)
            show_version
            ;;
        
        *)
            print_error "Unknown command: $command"
            echo "Run './manage.sh help' for available commands"
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"
