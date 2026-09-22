#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

configuration="${1:-release}"
app_arch="${APP_ARCH:-native}"
build_number="${BUILD_NUMBER:-1}"
signing_mode_was_set="${SIGNING_MODE+x}"
signing_mode="${SIGNING_MODE:-development}"
requested_identity="${CODE_SIGN_IDENTITY:-}"

if [[ "$configuration" != release && "$configuration" != debug ]]; then
    echo "Usage: $0 [release|debug]" >&2
    exit 2
fi
if [[ "$app_arch" != native && "$app_arch" != arm64 && "$app_arch" != x86_64 && "$app_arch" != universal ]]; then
    echo "APP_ARCH must be native, arm64, x86_64, or universal: $app_arch" >&2
    exit 2
fi
if [[ ! "$build_number" =~ ^[1-9][0-9]*$ ]]; then
    echo "BUILD_NUMBER must be a positive integer: $build_number" >&2
    exit 2
fi
if [[ "$signing_mode" != development && "$signing_mode" != developer-id && "$signing_mode" != adhoc ]]; then
    echo "SIGNING_MODE must be development, developer-id, or adhoc: $signing_mode" >&2
    exit 2
fi
if [[ ! -f VERSION ]]; then
    echo "VERSION is missing" >&2
    exit 1
fi
version="$(<VERSION)"
if [[ ! "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    echo "VERSION must contain a stable x.y.z version: $version" >&2
    exit 2
fi
if [[ ! -f assets/AppIcon.icns ]]; then
    echo "App icon is missing: assets/AppIcon.icns" >&2
    exit 1
fi

if [[ "$signing_mode" == adhoc ]]; then
    if [[ -n "$requested_identity" && "$requested_identity" != "-" ]]; then
        echo "SIGNING_MODE=adhoc only accepts CODE_SIGN_IDENTITY=-" >&2
        exit 2
    fi
    signing_identity="-"
elif [[ "$requested_identity" == "-" ]]; then
    if [[ -n "$signing_mode_was_set" ]]; then
        echo "CODE_SIGN_IDENTITY=- is incompatible with SIGNING_MODE=$signing_mode" >&2
        exit 2
    fi
    # Preserve the original explicit opt-in for local ad-hoc builds.
    signing_identity="-"
else
    if [[ "$signing_mode" == development ]]; then
        identity_prefix="Apple Development:"
        identity_description="Apple Development"
    else
        identity_prefix="Developer ID Application:"
        identity_description="Developer ID Application"
    fi

    identity_hashes=("")
    identity_names=("")
    identity_count=0
    while IFS=' ' read -r hash name; do
        if [[ -n "$hash" ]]; then
            ((identity_count += 1))
            identity_hashes+=("$hash")
            identity_names+=("$name")
        fi
    done < <(security find-identity -v -p codesigning 2>/dev/null \
        | sed -En "s/^[[:space:]]*[0-9]+\\)[[:space:]]+([[:xdigit:]]{40})[[:space:]]+\"(${identity_prefix}[^\"]+)\".*$/\\1 \\2/p")

    if [[ -n "$requested_identity" ]]; then
        signing_identity=""
        matches=0
        for ((i = 1; i <= identity_count; i += 1)); do
            if [[ "$requested_identity" == "${identity_hashes[i]}" || "$requested_identity" == "${identity_names[i]}" ]]; then
                signing_identity="${identity_hashes[i]}"
                ((matches += 1))
            fi
        done
        if [[ $matches -eq 0 ]]; then
            echo "$identity_description signing identity not found: $requested_identity" >&2
            exit 1
        elif [[ $matches -gt 1 ]]; then
            echo "$identity_description signing identity is ambiguous: $requested_identity. Set CODE_SIGN_IDENTITY to the certificate SHA-1." >&2
            exit 1
        fi
    elif [[ $identity_count -eq 1 ]]; then
        signing_identity="${identity_hashes[1]}"
    elif [[ $identity_count -eq 0 ]]; then
        echo "No $identity_description signing identity found. Set CODE_SIGN_IDENTITY to one installed certificate." >&2
        exit 1
    else
        echo "Multiple $identity_description signing identities found. Set CODE_SIGN_IDENTITY to the certificate SHA-1 or full name." >&2
        exit 1
    fi
fi

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/opencontexts-build.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
app="$work_dir/OpenContexts.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"

build_binary() {
    local arch="$1"
    swift build -c "$configuration" --arch "$arch" >&2 || return
    local binary_dir
    binary_dir="$(swift build -c "$configuration" --arch "$arch" --show-bin-path)" || return
    printf '%s/OpenContexts\n' "$binary_dir"
}

if [[ "$app_arch" == universal ]]; then
    arm64_binary="$(build_binary arm64)"
    arm64_snapshot="$work_dir/OpenContexts-arm64"
    cp "$arm64_binary" "$arm64_snapshot"
    x86_64_binary="$(build_binary x86_64)"
    lipo -create "$arm64_snapshot" "$x86_64_binary" -output "$app/Contents/MacOS/OpenContexts"
elif [[ "$app_arch" == native ]]; then
    swift build -c "$configuration"
    binary_dir="$(swift build -c "$configuration" --show-bin-path)"
    cp "$binary_dir/OpenContexts" "$app/Contents/MacOS/OpenContexts"
else
    built_binary="$(build_binary "$app_arch")"
    cp "$built_binary" "$app/Contents/MacOS/OpenContexts"
fi

cp assets/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleExecutable</key><string>OpenContexts</string>
    <key>CFBundleIdentifier</key><string>local.opencontexts.app</string>
    <key>CFBundleName</key><string>Open Contexts</string>
    <key>CFBundleDisplayName</key><string>Open Contexts</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$version</string>
    <key>CFBundleVersion</key><string>$build_number</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

if [[ "$signing_mode" == developer-id ]]; then
    codesign --force --sign "$signing_identity" --options runtime --timestamp "$app"
else
    codesign --force --sign "$signing_identity" "$app"
fi
codesign --verify --strict "$app"

mkdir -p dist
rm -rf dist/OpenContexts.app
mv "$app" dist/OpenContexts.app
echo "$PWD/dist/OpenContexts.app"
