#!/bin/bash
# logs.sh - View AI Agent logs

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANAGE_SCRIPT="$SCRIPT_DIR/manage.sh"

if [ ! -f "$MANAGE_SCRIPT" ]; then
    echo "❌ manage.sh not found"
    exit 1
fi

chmod +x "$MANAGE_SCRIPT"

# If argument provided, pass it to manage
if [ $# -gt 0 ]; then
    "$MANAGE_SCRIPT" logs-$1
else
    # Default: show live logs
    "$MANAGE_SCRIPT" logs-live
fi
