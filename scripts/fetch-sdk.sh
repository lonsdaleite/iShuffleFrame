#!/bin/sh
# Downloads the iOS 9.3 SDK used by the legacy build (armv7 + arm64, iOS 9+) into ~/theos/sdks.
#
# The SDK's .tbd stubs list device and simulator architectures together; the current Apple linker then
# treats them as simulator libraries ("built for 'iOS-simulator'") and refuses to link. Dropping the
# simulator architectures (i386, x86_64) from the stubs fixes that.
set -eu

SDK_NAME=iPhoneOS9.3.sdk
URL="https://github.com/theos/sdks/releases/download/master-146e41f/$SDK_NAME.tar.xz"
DEST="${THEOS_SDKS:-$HOME/theos/sdks}"

if [ -d "$DEST/$SDK_NAME" ]; then
    echo "$DEST/$SDK_NAME already exists"
    exit 0
fi

mkdir -p "$DEST"
curl -fL "$URL" | tar -xJ -C "$DEST"
find "$DEST/$SDK_NAME" -name '*.tbd' -print0 | xargs -0 perl -0pi -e \
    's/,\s*i386//g; s/,\s*x86_64//g; s/\[\s*i386,\s*/[ /g; s/\[\s*x86_64,\s*/[ /g'
echo "Installed $DEST/$SDK_NAME"
