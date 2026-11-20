#!/bin/bash
# Builds "WeChat Channels Downloader.app". Pass --install to copy it into ~/Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product ChannelsDownloader
BIN="$(swift build -c release --show-bin-path)/ChannelsDownloader"

APP="build/WeChat Channels Downloader.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ChannelsDownloader"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f build/AppIcon.icns ] || swift scripts/make-icon.swift build/AppIcon.icns
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

plutil -lint "$APP/Contents/Info.plist"
codesign --force --deep -s - "$APP"
codesign -v "$APP" && echo "Signed: $APP"

if [ "${1:-}" = "--install" ]; then
    DEST="$HOME/Applications/WeChat Channels Downloader.app"
    # Quit a running copy first (it stops the downloader and restores the proxy on the way out).
    if pgrep -f "WeChat Channels Downloader.app/Contents/MacOS/ChannelsDownloader" >/dev/null; then
        osascript -e 'tell application id "local.wechat-channels-downloader" to quit'
        for _ in $(seq 1 50); do
            pgrep -f "WeChat Channels Downloader.app/Contents/MacOS/ChannelsDownloader" >/dev/null || break
            sleep 0.2
        done
    fi
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    echo "Installed: $DEST"
fi
