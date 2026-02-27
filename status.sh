#!/bin/bash
# status.sh - Show AI Agent system status

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANAGE_SCRIPT="$SCRIPT_DIR/manage.sh"

if [ ! -f "$MANAGE_SCRIPT" ]; then
    echo "❌ manage.sh not found"
    exit 1
fi

chmod +x "$MANAGE_SCRIPT"
"$MANAGE_SCRIPT" status
