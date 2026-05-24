#!/usr/bin/env bash
# Download sing-box native libraries for Android and iOS.
# Run from the vpn_client project root: bash scripts/download_libs.sh
set -euo pipefail

VERSION="${SINGBOX_VERSION:-1.11.0}"

# ── Android (libbox.aar) ─────────────────────────────────────────────────────
ANDROID_OUT="android/app/libs"
mkdir -p "$ANDROID_OUT"

if [[ ! -f "$ANDROID_OUT/libbox.aar" ]]; then
  echo "Downloading libbox.aar for Android..."
  curl -fsSL \
    "https://github.com/SagerNet/sing-box/releases/download/v${VERSION}/libbox-${VERSION}-android-arm64.aar" \
    -o "$ANDROID_OUT/libbox.aar"
  echo "Saved: $ANDROID_OUT/libbox.aar"
else
  echo "libbox.aar already exists"
fi

# ── iOS (LibBox.xcframework) ──────────────────────────────────────────────────
IOS_OUT="ios"
mkdir -p "$IOS_OUT"

if [[ ! -d "$IOS_OUT/LibBox.xcframework" ]]; then
  echo "Downloading LibBox.xcframework for iOS..."
  TMP=$(mktemp -d)
  curl -fsSL \
    "https://github.com/SagerNet/sing-box/releases/download/v${VERSION}/LibBox.xcframework.zip" \
    -o "$TMP/LibBox.zip"
  unzip -q "$TMP/LibBox.zip" -d "$IOS_OUT"
  rm -rf "$TMP"
  echo "Saved: $IOS_OUT/LibBox.xcframework"
else
  echo "LibBox.xcframework already exists"
fi

echo ""
echo "Done. Now enable libbox in SingBoxVpnService.kt and PacketTunnelProvider.swift"
echo "(uncomment the import + LibboxNewService call in both files)."
