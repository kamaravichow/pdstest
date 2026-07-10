#!/usr/bin/env bash
#
# pdstest Linux installer
#
# Downloads the latest (or a specific) release build from GitHub and installs it.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/<owner>/<repo>/main/install.sh | bash
#
#   # Install a specific version:
#   curl -fsSL .../install.sh | VERSION=v1.0.0 bash
#
#   # Install system-wide (needs sudo/root):
#   curl -fsSL .../install.sh | PREFIX=/usr/local bash
#
set -euo pipefail

# ---- Configuration ---------------------------------------------------------
# Set REPO to "owner/name" of your GitHub repository. Override via env if needed.
REPO="${REPO:-aravind/pdstest}"
APP_NAME="pdstest"
ASSET_NAME="pdstest-linux-x64.tar.gz"
VERSION="${VERSION:-latest}"

# Install locations (user-local by default; set PREFIX=/usr/local for system-wide).
PREFIX="${PREFIX:-$HOME/.local}"
SHARE_DIR="$PREFIX/share/$APP_NAME"
BIN_DIR="$PREFIX/bin"
# ---------------------------------------------------------------------------

err()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; }
info() { printf '\033[36m==>\033[0m %s\n' "$*"; }

# Only x86_64 Linux is published by the build workflow.
os="$(uname -s)"
arch="$(uname -m)"
if [ "$os" != "Linux" ]; then
  err "this installer only supports Linux (detected: $os)"
  exit 1
fi
if [ "$arch" != "x86_64" ] && [ "$arch" != "amd64" ]; then
  err "only x86_64 is supported (detected: $arch)"
  exit 1
fi

for cmd in curl tar; do
  command -v "$cmd" >/dev/null 2>&1 || { err "'$cmd' is required but not installed"; exit 1; }
done

# Resolve the download URL from the GitHub releases API.
if [ "$VERSION" = "latest" ]; then
  api_url="https://api.github.com/repos/$REPO/releases/latest"
else
  api_url="https://api.github.com/repos/$REPO/releases/tags/$VERSION"
fi

info "Looking up release ($VERSION) for $REPO ..."
release_json="$(curl -fsSL "$api_url")" || { err "failed to query GitHub API ($api_url)"; exit 1; }

# Pull the browser_download_url for our asset without requiring jq.
download_url="$(printf '%s' "$release_json" \
  | grep -o "https://[^\"]*$ASSET_NAME" \
  | head -n1)"

if [ -z "$download_url" ]; then
  err "could not find asset '$ASSET_NAME' in release '$VERSION'"
  err "check that a release exists at https://github.com/$REPO/releases"
  exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

info "Downloading $download_url"
curl -fsSL "$download_url" -o "$tmp_dir/$ASSET_NAME"

info "Installing to $SHARE_DIR"
rm -rf "$SHARE_DIR"
mkdir -p "$SHARE_DIR" "$BIN_DIR"
tar -xzf "$tmp_dir/$ASSET_NAME" -C "$SHARE_DIR"

# The executable inside the bundle is named after the app.
if [ ! -x "$SHARE_DIR/$APP_NAME" ]; then
  err "expected executable '$SHARE_DIR/$APP_NAME' not found in the archive"
  exit 1
fi
chmod +x "$SHARE_DIR/$APP_NAME"

# Symlink the binary onto PATH.
ln -sf "$SHARE_DIR/$APP_NAME" "$BIN_DIR/$APP_NAME"

info "Installed $APP_NAME -> $BIN_DIR/$APP_NAME"

# Nudge the user if the bin dir isn't on PATH.
case ":$PATH:" in
  *":$BIN_DIR:"*) : ;;
  *)
    printf '\n\033[33mnote:\033[0m %s is not on your PATH.\n' "$BIN_DIR"
    printf '  Add this to your ~/.bashrc or ~/.profile:\n'
    printf '    export PATH="%s:$PATH"\n\n' "$BIN_DIR"
    ;;
esac

info "Done. Run '$APP_NAME' to start."
