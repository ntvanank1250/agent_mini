.PHONY: help setup install start stop restart status logs logs-live monitor \
        db-backup db-cleanup db-export config-edit clean quick-install

# AI Agent Bot - Makefile
# Usage: make [target]

help:
	@echo ""
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║         AI AGENT BOT - Makefile Commands                       ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "INSTALLATION:"
	@echo "  make setup              Setup system (install all dependencies)"
	@echo "  make quick-install      Setup + Start (combined)"
	@echo ""
	@echo "SERVICE MANAGEMENT:"
	@echo "  make start              Start all services"
	@echo "  make stop               Stop all services"
	@echo "  make restart            Restart all services"
	@echo "  make status             Show system status"
	@echo ""
	@echo "MONITORING & LOGS:"
	@echo "  make logs               Show last 50 lines of logs"
	@echo "  make logs-live          Follow logs in real-time"
	@echo "  make monitor            Real-time system monitor"
	@echo ""
	@echo "DATABASE:"
	@echo "  make db-info            Show database info"
	@echo "  make db-backup          Backup database"
	@echo "  make db-cleanup         Clean old messages (>30 days)"
	@echo "  make db-export          Export database to CSV"
	@echo ""
	@echo "CONFIGURATION:"
	@echo "  make config-edit        Edit .env configuration"
	@echo "  make config-show        Show current configuration"
	@echo ""
	@echo "MAINTENANCE:"
	@echo "  make clean              Clean temporary files"
	@echo "  make help               Show this help message"
	@echo ""
	@echo "EXAMPLES:"
	@echo "  make start              # Start services"
	@echo "  make logs-live          # View logs live"
	@echo "  make db-backup          # Backup database"
	@echo ""

# Installation
setup:
	@sudo bash setup_system.sh

quick-install:
	@chmod +x quick-install.sh
	@./quick-install.sh

# Service Management
start:
	@chmod +x manage.sh
	@./manage.sh start

stop:
	@chmod +x manage.sh
	@./manage.sh stop

restart:
	@chmod +x manage.sh
	@./manage.sh restart

status:
	@chmod +x manage.sh
	@./manage.sh status

# Logs
logs:
	@chmod +x manage.sh
	@./manage.sh logs

logs-live:
	@chmod +x manage.sh
	@./manage.sh logs-live

# Monitor
monitor:
	@chmod +x manage.sh
	@./manage.sh monitor

# Database
db-info:
	@chmod +x manage.sh
	@./manage.sh db-info

db-backup:
	@chmod +x manage.sh
	@./manage.sh db-backup

db-cleanup:
	@chmod +x manage.sh
	@./manage.sh db-cleanup

db-export:
	@chmod +x manage.sh
	@./manage.sh db-export

# Configuration
config-edit:
	@chmod +x manage.sh
	@./manage.sh config-edit

config-show:
	@chmod +x manage.sh
	@./manage.sh config-show

# Maintenance
clean:
	@chmod +x manage.sh
	@./manage.sh cleanup
	@echo "Cleanup completed"
