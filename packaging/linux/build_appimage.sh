#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <bundle> <version> <output.AppImage>" >&2
  exit 1
fi

bundle=$1
version=$2
output=$3
if [[ ! -x "$bundle/kovetz" ]]; then
  echo "Missing executable: $bundle/kovetz" >&2
  exit 1
fi

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
appdir="$scratch/Kovetz.AppDir"

mkdir -p "$appdir/usr/lib/kovetz"
cp -a -- "$bundle/." "$appdir/usr/lib/kovetz/"
cp -- "$repo_root/app/assets/images/app_icon.png" "$appdir/kovetz.png"

cat > "$appdir/AppRun" <<'EOF'
#!/bin/sh
appdir=$(dirname -- "$(readlink -f -- "$0")") || exit 1
exec "$appdir/usr/lib/kovetz/kovetz" "$@"
EOF
chmod +x "$appdir/AppRun"

cat > "$appdir/kovetz.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Kovetz
Exec=kovetz
Icon=kovetz
Categories=Utility;
Terminal=false
EOF

appimagetool="$scratch/appimagetool"
curl --fail --silent --show-error --location --retry 3 --output "$appimagetool" \
  https://github.com/AppImage/appimagetool/releases/download/1.9.0/appimagetool-x86_64.AppImage
chmod +x "$appimagetool"
APPIMAGE_EXTRACT_AND_RUN=1 ARCH=x86_64 VERSION="$version" \
  "$appimagetool" "$appdir" "$output"
