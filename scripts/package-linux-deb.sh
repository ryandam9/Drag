#!/usr/bin/env bash
# Builds a Debian package (.deb) from a Flutter Linux release bundle.
#
#   scripts/package-linux-deb.sh <bundle-dir> <version> <output.deb>
#
# The app and its bundled data/libs are installed under /usr/lib/drag, with a
# launcher at /usr/bin/drag, a .desktop entry and an icon — so it shows up in
# the application menu and `drag` works from a terminal.
set -euo pipefail

BUNDLE="${1:?usage: package-linux-deb.sh <bundle-dir> <version> <output.deb>}"
VERSION="${2:?missing version}"
OUTPUT="${3:?missing output path}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# ── Layout ──
install -d "$WORK/DEBIAN" \
           "$WORK/usr/lib/drag" \
           "$WORK/usr/bin" \
           "$WORK/usr/share/applications" \
           "$WORK/usr/share/icons/hicolor/512x512/apps"

cp -r "$BUNDLE"/. "$WORK/usr/lib/drag/"

# Launcher: exec the real binary so Flutter resolves its bundled resources and
# rpath ($ORIGIN/lib) from /usr/lib/drag.
cat > "$WORK/usr/bin/drag" <<'EOF'
#!/usr/bin/env bash
exec /usr/lib/drag/drag "$@"
EOF
chmod 755 "$WORK/usr/bin/drag"

cp "$ROOT/assets/icons/drag_512.png" "$WORK/usr/share/icons/hicolor/512x512/apps/drag.png"

cat > "$WORK/usr/share/applications/drag.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Drag
GenericName=File Transfer
Comment=Cross-platform file-transfer client for Local, Amazon S3 and SFTP
Exec=drag
Icon=drag
Terminal=false
Categories=Utility;Network;FileTransfer;
EOF

# Installed-Size in KiB (dpkg convention).
SIZE_KB="$(du -ks "$WORK/usr" | cut -f1)"

cat > "$WORK/DEBIAN/control" <<EOF
Package: drag
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: amd64
Maintainer: ryandam <ryandam.explorer@gmail.com>
Installed-Size: ${SIZE_KB}
Depends: libgtk-3-0, libsqlite3-0, libsecret-1-0, libnotify4
Description: Drag — cross-platform file-transfer client
 A desktop client for transferring files between Local, Amazon S3 and
 SFTP endpoints, with a dual-pane browser, queued transfers and history.
EOF

dpkg-deb --root-owner-group --build "$WORK" "$OUTPUT"
echo "Built $OUTPUT"
