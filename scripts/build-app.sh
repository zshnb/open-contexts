#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

configuration="${1:-release}"
if [[ "$configuration" != release && "$configuration" != debug ]]; then
    echo "Usage: $0 [release|debug]" >&2
    exit 2
fi

requested_identity="${CODE_SIGN_IDENTITY:-}"
if [[ "$requested_identity" == "-" ]]; then
    signing_identity="-"
else
    identities=()
    while IFS=' ' read -r hash name; do
        [[ -n "$hash" ]] && identities+=("$hash" "$name")
    done < <(security find-identity -v -p codesigning 2>/dev/null \
        | sed -En 's/^[[:space:]]*[0-9]+\)[[:space:]]+([[:xdigit:]]{40})[[:space:]]+"(Apple Development:[^"]+)".*$/\1 \2/p')

    if [[ -n "$requested_identity" ]]; then
        signing_identity=""
        matches=0
        for ((i = 0; i < ${#identities[@]}; i += 2)); do
            if [[ "$requested_identity" == "${identities[i]}" || "$requested_identity" == "${identities[i + 1]}" ]]; then
                signing_identity="${identities[i]}"
                ((matches += 1))
            fi
        done
        if [[ $matches -eq 0 ]]; then
            echo "Apple Development signing identity not found: $requested_identity" >&2
            exit 1
        elif [[ $matches -gt 1 ]]; then
            echo "Apple Development signing identity is ambiguous: $requested_identity. Set CODE_SIGN_IDENTITY to the certificate SHA-1." >&2
            exit 1
        fi
    elif [[ ${#identities[@]} -eq 2 ]]; then
        signing_identity="${identities[0]}"
    elif [[ ${#identities[@]} -eq 0 ]]; then
        echo "No Apple Development signing identity found. Sign in to Xcode and create one, or set CODE_SIGN_IDENTITY=- for an ad-hoc build." >&2
        exit 1
    else
        echo "Multiple Apple Development signing identities found. Set CODE_SIGN_IDENTITY to the certificate SHA-1 or full name." >&2
        exit 1
    fi
fi

swift build -c "$configuration"
binary_dir="$(swift build -c "$configuration" --show-bin-path)"
app="$PWD/dist/OpenContexts.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/OpenContexts" "$app/Contents/MacOS/OpenContexts"
cp assets/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>OpenContexts</string>
    <key>CFBundleIdentifier</key><string>local.opencontexts.app</string>
    <key>CFBundleName</key><string>Open Contexts</string>
    <key>CFBundleDisplayName</key><string>Open Contexts</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign "$signing_identity" "$app"
codesign --verify --strict "$app"
echo "$app"
