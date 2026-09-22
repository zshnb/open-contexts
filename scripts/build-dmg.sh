#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ! -f VERSION ]]; then
    echo "VERSION is missing" >&2
    exit 1
fi
version="$(<VERSION)"
if [[ ! "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    echo "VERSION must contain a stable x.y.z version: $version" >&2
    exit 2
fi

app="$PWD/dist/OpenContexts.app"
binary="$app/Contents/MacOS/OpenContexts"
if [[ ! -d "$app" || ! -f "$binary" ]]; then
    echo "Built app is missing: $app" >&2
    exit 1
fi
app_version="$(plutil -extract CFBundleShortVersionString raw -o - "$app/Contents/Info.plist")"
if [[ "$app_version" != "$version" ]]; then
    echo "App version $app_version does not match VERSION $version" >&2
    exit 1
fi
codesign --verify --strict "$app"

archs="$(lipo -archs "$binary")"
case " $archs " in
    " arm64 ") artifact_arch="arm64" ;;
    " x86_64 ") artifact_arch="x86_64" ;;
    " arm64 x86_64 "|" x86_64 arm64 ") artifact_arch="universal" ;;
    *)
        echo "Unsupported app architectures: $archs" >&2
        exit 1
        ;;
esac

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/opencontexts-dmg.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
staging_dir="$work_dir/staging"
temporary_dmg="$work_dir/OpenContexts.dmg"
mkdir -p "$staging_dir"
ditto "$app" "$staging_dir/OpenContexts.app"
ln -s /Applications "$staging_dir/Applications"

hdiutil create \
    -volname "Open Contexts $version" \
    -srcfolder "$staging_dir" \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$temporary_dmg"
hdiutil verify "$temporary_dmg"

output="$PWD/dist/OpenContexts-${version}-${artifact_arch}.dmg"
mv -f "$temporary_dmg" "$output"
echo "$output"
