#!/usr/bin/env bash
# Builds a release binary and assembles Port.app — a menu-bar agent
# (LSUIElement, no Dock icon) with the cleat app icon.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP="$ROOT/Port.app"
SRC_ICON="$ROOT/art/AppIcon-source.png"
VERSION="0.2.1"
# Same Developer ID as Blip ("Matt Wisniewski, F6ZAL7ANAD"). Override with
# SIGN_IDENTITY=- for an ad-hoc local build.
SIGN_IDENTITY="${SIGN_IDENTITY:-0948896DC970503ADEF5B5070E0BB3E9D9047757}"
DMG="$ROOT/Port-$VERSION.dmg"

echo "› swift build -c release"
swift build -c release
BIN="$(swift build -c release --show-bin-path)"

echo "› assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# App icon: source PNG → .iconset → .icns (native sips + iconutil)
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for spec in "16:16x16" "32:16x16@2x" "32:32x32" "64:32x32@2x" \
            "128:128x128" "256:128x128@2x" "256:256x256" "512:256x256@2x" \
            "512:512x512" "1024:512x512@2x"; do
  px="${spec%%:*}"; name="${spec##*:}"
  sips -z "$px" "$px" "$SRC_ICON" --out "$ICONSET/icon_${name}.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# Executable. SwiftPM emits a flat `*.bundle` that codesign rejects as a
# nested code bundle, so flatten its resources into Contents/Resources
# (loaded via Bundle.main in the .app; Bundle.module still serves `swift run`).
cp "$BIN/Port" "$APP/Contents/MacOS/Port"

# ── Embed + (below) sign the SuiteKit contract and this
# app's pane dylib so the MattsSoftware launcher can load
# the SAME code out of this installed .app. rpath lets the
# bundled exe find them under Contents/Frameworks.
mkdir -p "$APP/Contents/Frameworks"
cp "$BIN/libSuiteKit.dylib" "$APP/Contents/Frameworks/"
cp "$BIN/libPortPane.dylib" "$APP/Contents/Frameworks/"
if [ -d "$BIN/Port_PortPane.bundle" ]; then find "$BIN/Port_PortPane.bundle" -type f \( -name '*.png' -o -name '*.icns' \) -exec cp {} "$APP/Contents/Resources/" \; ; fi
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/Port" 2>/dev/null || true

if [ -d "$BIN/Port_Port.bundle" ]; then
  find "$BIN/Port_Port.bundle" -type f \( -name '*.png' -o -name '*.icns' \) \
    -exec cp {} "$APP/Contents/Resources/" \;
fi

# ── Widget extension (.appex) ─────────────────────────────────────
# Built by Xcode, not SwiftPM (SR-14944 — SwiftPM has no
# app-extension productType, so ExtensionFoundation fatal-errors at
# launch). Widget consumes PortShared via local-package dep so it
# shares the App Group + SharedPort model with the host.
# SKIP_WIDGET=1 to skip during fast iteration.
if [ "${SKIP_WIDGET:-0}" != "1" ]; then
  if command -v xcodegen >/dev/null; then
    ( cd "$ROOT/Widget" && xcodegen generate --quiet )
  fi
  echo "› xcodebuild PortWidgets.appex"
  XCB_OUT="$ROOT/.build/xcode"
  xcodebuild \
    -project "$ROOT/Widget/PortWidgets.xcodeproj" \
    -scheme PortWidgets \
    -configuration Release \
    -derivedDataPath "$XCB_OUT" \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$VERSION" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    -quiet \
    build
  WIDGET_APPEX="$XCB_OUT/Build/Products/Release/PortWidgets.appex"
  if [ -d "$WIDGET_APPEX" ]; then
    mkdir -p "$APP/Contents/PlugIns"
    rm -rf "$APP/Contents/PlugIns/PortWidgets.appex"
    ditto "$WIDGET_APPEX" "$APP/Contents/PlugIns/PortWidgets.appex"
    echo "✓ embedded $APP/Contents/PlugIns/PortWidgets.appex"
  else
    echo "⚠ widget build produced no .appex at $WIDGET_APPEX"
  fi
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Port</string>
  <key>CFBundleDisplayName</key><string>Port</string>
  <key>CFBundleIdentifier</key><string>com.mattssoftware.port</string>
  <key>CFBundleExecutable</key><string>Port</string>
  <key>CFBundleURLTypes</key>
  <array><dict>
    <key>CFBundleURLName</key><string>com.mattssoftware.port</string>
    <key>CFBundleURLSchemes</key><array><string>port</string></array>
  </dict></array>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSExceptionDomains</key>
    <dict>
      <key>ip-api.com</key>
      <dict>
        <key>NSExceptionAllowsInsecureHTTPLoads</key><true/>
        <key>NSIncludesSubdomains</key><true/>
      </dict>
    </dict>
  </dict>
  <key>NSHumanReadableCopyright</key><string>Port</string>
</dict>
</plist>
PLIST

# Inside-out signing (dylibs → widget exe + bundle → host exe + bundle).
# Host needs the App Group entitlement so SharedPortStore.write can
# resolve the Group Container URL; widget needs sandbox + the same
# group. Drift between the two entitlements files is a silent failure.
HOST_ENT="$ROOT/Port.entitlements"
WIDGET_ENT="$ROOT/Widget/Supporting Files/PortWidgets.entitlements"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
  codesign --force --options runtime --timestamp \
    --sign "$SIGN_IDENTITY" "$APP/Contents/Frameworks/libSuiteKit.dylib"
  codesign --force --options runtime --timestamp \
    --sign "$SIGN_IDENTITY" "$APP/Contents/Frameworks/libPortPane.dylib"
  if [ -d "$APP/Contents/PlugIns/PortWidgets.appex" ]; then
    codesign --force --options runtime --timestamp \
      --entitlements "$WIDGET_ENT" \
      --sign "$SIGN_IDENTITY" \
      "$APP/Contents/PlugIns/PortWidgets.appex/Contents/MacOS/PortWidgets"
    codesign --force --options runtime --timestamp \
      --entitlements "$WIDGET_ENT" \
      --sign "$SIGN_IDENTITY" \
      "$APP/Contents/PlugIns/PortWidgets.appex"
  fi
  codesign --force --options runtime --timestamp \
    --entitlements "$HOST_ENT" \
    --sign "$SIGN_IDENTITY" "$APP/Contents/MacOS/Port"
  codesign --force --options runtime --timestamp \
    --entitlements "$HOST_ENT" \
    --sign "$SIGN_IDENTITY" "$APP"
  codesign --verify --strict --verbose=1 "$APP" && echo "✓ signed: $SIGN_IDENTITY"
else
  echo "⚠ signing identity $SIGN_IDENTITY not found — ad-hoc signing instead"
  codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
fi

echo "✓ built $APP"

# ── Notarize + staple the .app (Developer ID builds only) ─────────
# Runs BEFORE the .dmg is built so the disk image wraps an
# already-stapled app — the copy a user drags to /Applications is
# Gatekeeper-trusted even offline. We notarize the zipped app, so the
# ticket rides on the .app; the .dmg is signed but not stapled (its
# first mount does a one-time online check, fine for a freshly
# downloaded installer). Non-fatal: a creds-less or rejected build
# still completes, just signed-only.
NOTARY_PROFILE="${NOTARY_PROFILE:-Notary}"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
  echo "› notarizing $APP (waits on Apple)…"
  NZIP="$(mktemp -d)/notarize.zip"
  ditto -c -k --keepParent "$APP" "$NZIP"
  if xcrun notarytool submit "$NZIP" \
       --keychain-profile "$NOTARY_PROFILE" --wait; then
    if xcrun stapler staple "$APP"; then
      if xcrun stapler validate "$APP"; then
        echo "✓ notarized + stapled $APP"
      else
        echo "⚠ staple validate failed for $APP"
      fi
    else
      echo "⚠ stapling failed for $APP"
    fi
  else
    echo "⚠ notarization skipped/failed — $APP signed but not notarized"
  fi
fi

# Build a downloadable .dmg from the (now-stapled) Port.app.
STAGE="$(mktemp -d)/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/Port.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "Port" -srcfolder "$STAGE" \
  -ov -format UDZO "$DMG"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$SIGN_IDENTITY"; then
  codesign --force --sign "$SIGN_IDENTITY" "$DMG" || true
fi
echo "✓ built $DMG"
