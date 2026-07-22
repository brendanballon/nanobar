#!/usr/bin/env bash
# Build NanoBar in release mode and stage artifacts into dist/.
# Output: dist/ directory + nanobar-<version>-arm64.tar.gz
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
VERSION="${1:-$(git -C "$REPO_ROOT" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "0.0.0-dev")}"
DIST="$REPO_ROOT/dist"
TARBALL="$REPO_ROOT/nanobar-${VERSION}-arm64.tar.gz"

echo "==> Building NanoBar ${VERSION}"

# Clean staging dir
rm -rf "$DIST"
mkdir -p "$DIST/libexec" "$DIST/bin"

cd "$REPO_ROOT"
swift build -c release 2>&1 | grep -E "error:|Build complete|warning: "

cp .build/release/NanoBar "$DIST/libexec/NanoBar"
echo "  NanoBar built"

# ── Wrapper script ─────────────────────────────────────────────────────────
cat > "$DIST/bin/nanobar" << 'WRAPPER'
#!/usr/bin/env bash
exec "$(dirname "$(realpath "$0")")/../libexec/NanoBar" "$@"
WRAPPER
chmod +x "$DIST/bin/nanobar"

# ── Tarball ────────────────────────────────────────────────────────────────
tar czf "$TARBALL" -C "$DIST" .
SHA256="$(shasum -a 256 "$TARBALL" | awk '{print $1}')"

echo ""
echo "==> Done"
echo "    Tarball : $TARBALL"
echo "    SHA256  : $SHA256"
echo "    Version : $VERSION"
echo ""
echo "Update homebrew-tap Formula/nanobar.rb:"
echo "  sha256 \"$SHA256\""
