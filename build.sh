#!/bin/zsh
# Build QuickPlay.app into ~/Applications and register it with Launch Services.
# Builds into a staging bundle first and keeps the old app until the new one is in place.
set -euo pipefail
here=${0:A:h}
app=~/Applications/QuickPlay.app
stage=$(mktemp -d ~/Applications/.QuickPlay.XXXXXX)
backup="$stage/old.app"
trap '[[ -e "$backup" && ! -e "$app" ]] && mv "$backup" "$app"; rm -rf "$stage"' EXIT

mkdir -p "$stage/QuickPlay.app/Contents/MacOS"
swiftc -O -target arm64-apple-macos14.0 -o "$stage/QuickPlay.app/Contents/MacOS/QuickPlay" "$here"/Sources/*.swift
plutil -lint -s "$here/Info.plist"
cp "$here/Info.plist" "$stage/QuickPlay.app/Contents/Info.plist"

# App icon: render once at 1024 px, downscale into an iconset, pack as .icns.
iconset="$stage/AppIcon.iconset"
mkdir -p "$iconset" "$stage/QuickPlay.app/Contents/Resources"
swift "$here/draw_icon.swift" "$stage/icon.png"
for s in 16 32 128 256 512; do
  sips -z $s $s "$stage/icon.png" --out "$iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) "$stage/icon.png" --out "$iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$stage/QuickPlay.app/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$stage/QuickPlay.app"
codesign --verify "$stage/QuickPlay.app"

[[ -e "$app" ]] && mv "$app" "$backup"
mv "$stage/QuickPlay.app" "$app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app"
echo "built $app"
