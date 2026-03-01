#!/bin/bash
set -euo pipefail

LABEL="com.user.busycal"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"

if [ ! -f "$PLIST_PATH" ]; then
    echo "BusyCal is not installed (no plist at $PLIST_PATH)."
    exit 0
fi

echo "==> Unloading launch agent..."
launchctl unload "$PLIST_PATH" 2>/dev/null || true

echo "==> Removing $PLIST_PATH..."
rm "$PLIST_PATH"

echo ""
echo "BusyCal uninstalled. The launch agent has been removed."
echo ""
echo "Note: Existing 'Busy' events in your destination calendar are untouched."
echo "Delete them manually if needed."
