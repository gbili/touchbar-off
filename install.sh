#!/bin/bash
# Builds TouchBarOff, puts it in ~/Applications and starts it now and at every login.
set -euo pipefail

cd "$(dirname "$0")"

LABEL=io.github.gbili.TouchBarOff
APP="$HOME/Applications/TouchBarOff.app"
BINARY="$APP/Contents/MacOS/TouchBarOff"
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"

if ! command -v swiftc >/dev/null; then
    echo "swiftc not found: install Xcode's command-line tools with 'xcode-select --install'" >&2
    exit 1
fi

# Stop a running copy before replacing its binary.
if launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; then
    launchctl bootout "$DOMAIN/$LABEL"
    # bootout returns before launchd has let go of the job, and bootstrap fails until it has.
    for _ in $(seq 50); do
        launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1 || break
        sleep 0.2
    done
fi

mkdir -p "$APP/Contents/MacOS" "$HOME/Library/LaunchAgents"
cp Info.plist "$APP/Contents/Info.plist"
swiftc -O main.swift -o "$BINARY"
# An ad-hoc signature is enough for a binary built on the Mac that runs it.
codesign --force --sign - "$APP"

cat > "$AGENT" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BINARY</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
EOF

launchctl bootstrap "$DOMAIN" "$AGENT"

# The app stops itself with a fatal error when the private frameworks it needs are
# not what it expects, which is likely on a Mac or macOS it was never tried on.
sleep 2
if ! launchctl print "$DOMAIN/$LABEL" | grep -q 'state = running'; then
    echo "TouchBarOff did not stay running. Run '$BINARY off' to see the error." >&2
    exit 1
fi

echo "TouchBarOff is running: the crossed-out lightbulb in the menu bar."
