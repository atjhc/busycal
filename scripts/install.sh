#!/bin/bash
set -euo pipefail

LABEL="com.user.busycal"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
EXECUTABLE="$REPO_DIR/.build/release/BusyCal"

echo "==> Building BusyCal..."
swift build -c release --package-path "$REPO_DIR" 2>&1 | tail -5

if [ ! -f "$EXECUTABLE" ]; then
    echo "Error: Build failed. Executable not found at $EXECUTABLE"
    exit 1
fi

echo "==> Signing executable..."
codesign -s - "$EXECUTABLE"

echo "==> Build succeeded: $EXECUTABLE"
echo ""

# Prompt for configuration — defaults prefilled from env vars
echo "==> Configuration (press Enter to accept defaults):"
echo ""

read -p "Source calendar name [${BUSYCAL_SOURCE_CALENDAR:-Home}]: " input
BUSYCAL_SOURCE_CALENDAR="${input:-${BUSYCAL_SOURCE_CALENDAR:-Home}}"

read -p "Source account name (optional) [${BUSYCAL_SOURCE_ACCOUNT:-}]: " input
BUSYCAL_SOURCE_ACCOUNT="${input:-${BUSYCAL_SOURCE_ACCOUNT:-}}"

read -p "Destination calendar name [${BUSYCAL_DESTINATION_CALENDAR:-Busy}]: " input
BUSYCAL_DESTINATION_CALENDAR="${input:-${BUSYCAL_DESTINATION_CALENDAR:-Busy}}"

read -p "Destination account name (optional) [${BUSYCAL_DESTINATION_ACCOUNT:-}]: " input
BUSYCAL_DESTINATION_ACCOUNT="${input:-${BUSYCAL_DESTINATION_ACCOUNT:-}}"

read -p "Busy event title [${BUSYCAL_TITLE:-Busy}]: " input
BUSYCAL_TITLE="${input:-${BUSYCAL_TITLE:-Busy}}"

read -p "Include all-day events? (true/false) [${BUSYCAL_INCLUDE_ALL_DAY:-false}]: " input
BUSYCAL_INCLUDE_ALL_DAY="${input:-${BUSYCAL_INCLUDE_ALL_DAY:-false}}"

read -p "Filter weekends? (true/false) [${BUSYCAL_FILTER_WEEKENDS:-true}]: " input
BUSYCAL_FILTER_WEEKENDS="${input:-${BUSYCAL_FILTER_WEEKENDS:-true}}"

read -p "Filter non-work hours? (true/false) [${BUSYCAL_FILTER_NON_WORK_HOURS:-true}]: " input
BUSYCAL_FILTER_NON_WORK_HOURS="${input:-${BUSYCAL_FILTER_NON_WORK_HOURS:-true}}"

read -p "Work start hour (0-23) [${BUSYCAL_WORK_START_HOUR:-8}]: " input
BUSYCAL_WORK_START_HOUR="${input:-${BUSYCAL_WORK_START_HOUR:-8}}"

read -p "Work end hour (0-23) [${BUSYCAL_WORK_END_HOUR:-18}]: " input
BUSYCAL_WORK_END_HOUR="${input:-${BUSYCAL_WORK_END_HOUR:-18}}"

echo ""

# Unload existing agent if present
if launchctl list "$LABEL" &>/dev/null; then
    echo "==> Unloading existing launch agent..."
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
fi

echo "==> Installing launch agent to $PLIST_PATH..."
mkdir -p "$HOME/Library/LaunchAgents"

# Build EnvironmentVariables dict entries — omit empty optional values
ENV_ENTRIES="        <key>BUSYCAL_SOURCE_CALENDAR</key>
        <string>$BUSYCAL_SOURCE_CALENDAR</string>
        <key>BUSYCAL_DESTINATION_CALENDAR</key>
        <string>$BUSYCAL_DESTINATION_CALENDAR</string>
        <key>BUSYCAL_TITLE</key>
        <string>$BUSYCAL_TITLE</string>
        <key>BUSYCAL_INCLUDE_ALL_DAY</key>
        <string>$BUSYCAL_INCLUDE_ALL_DAY</string>
        <key>BUSYCAL_FILTER_WEEKENDS</key>
        <string>$BUSYCAL_FILTER_WEEKENDS</string>
        <key>BUSYCAL_FILTER_NON_WORK_HOURS</key>
        <string>$BUSYCAL_FILTER_NON_WORK_HOURS</string>
        <key>BUSYCAL_WORK_START_HOUR</key>
        <string>$BUSYCAL_WORK_START_HOUR</string>
        <key>BUSYCAL_WORK_END_HOUR</key>
        <string>$BUSYCAL_WORK_END_HOUR</string>"

if [ -n "$BUSYCAL_SOURCE_ACCOUNT" ]; then
    ENV_ENTRIES="$ENV_ENTRIES
        <key>BUSYCAL_SOURCE_ACCOUNT</key>
        <string>$BUSYCAL_SOURCE_ACCOUNT</string>"
fi

if [ -n "$BUSYCAL_DESTINATION_ACCOUNT" ]; then
    ENV_ENTRIES="$ENV_ENTRIES
        <key>BUSYCAL_DESTINATION_ACCOUNT</key>
        <string>$BUSYCAL_DESTINATION_ACCOUNT</string>"
fi

cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$EXECUTABLE</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
$ENV_ENTRIES
    </dict>
    <key>StartInterval</key>
    <integer>3600</integer>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
EOF

echo "==> Loading launch agent..."
launchctl load "$PLIST_PATH"

echo ""
echo "BusyCal installed successfully!"
echo ""
echo "The sync will run every hour and on login."
echo "Logs: log show --predicate 'subsystem == \"com.user.busycal\"' --last 1h"
echo ""
echo "NOTE: On first run, macOS will prompt you to grant Calendar access."
echo "If denied, go to System Settings > Privacy & Security > Calendars."
echo ""
echo "To reconfigure, re-run this script."
