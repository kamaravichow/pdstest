#!/usr/bin/env bash
#
# pdstest Linux installer
#
# Downloads the latest (or a specific) release build from GitHub and installs it.
# By default also enables XDG autostart + display-manager autologin (kiosk mode).
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
#   # Skip auto-launch on login:
#   curl -fsSL .../install.sh | AUTOSTART=0 bash
#
#   # Skip installing GStreamer runtime deps (needed for the live camera tab):
#   curl -fsSL .../install.sh | INSTALL_DEPS=0 bash
#
#   # Skip display-manager autologin (keep login screen):
#   curl -fsSL .../install.sh | KIOSK=0 bash
#
#   # Autologin as a specific user (default: current user):
#   curl -fsSL .../install.sh | KIOSK_USER=pi bash
#
# Tip: when piping from curl, sudo may not be able to prompt for a password.
# Prefer downloading first if kiosk setup needs credentials:
#   curl -fsSL .../install.sh -o /tmp/pdstest-install.sh
#   bash /tmp/pdstest-install.sh
#   # or: sudo -E bash /tmp/pdstest-install.sh
#
set -euo pipefail

# ---- Configuration ---------------------------------------------------------
# Set REPO to "owner/name" of your GitHub repository. Override via env if needed.
REPO="${REPO:-kamaravichow/pdstest}"
APP_NAME="pdstest"
APP_DISPLAY_NAME="Haven Smart Home"
VERSION="${VERSION:-latest}"
# Launch the app when the desktop session starts (1=yes, 0=no).
AUTOSTART="${AUTOSTART:-1}"
# Install GStreamer runtime libraries the live camera preview needs (1=yes, 0=no).
# camera_desktop captures via GStreamer + V4L2, so without these the Camera tab
# stays blank. Uses the system package manager (apt/dnf/pacman/zypper) via sudo.
INSTALL_DEPS="${INSTALL_DEPS:-1}"
# Configure display-manager autologin so boot skips the login screen (1=yes, 0=no).
# Requires root/sudo. Supported: gdm/gdm3, lightdm, sddm.
KIOSK="${KIOSK:-1}"
# User to autologin as (defaults to the invoking user, even under sudo).
KIOSK_USER="${KIOSK_USER:-${SUDO_USER:-$(id -un)}}"

# Install locations (user-local by default; set PREFIX=/usr/local for system-wide).
PREFIX="${PREFIX:-$HOME/.local}"
SHARE_DIR="$PREFIX/share/$APP_NAME"
BIN_DIR="$PREFIX/bin"
APPLICATIONS_DIR="$PREFIX/share/applications"
# XDG autostart: user-local -> ~/.config/autostart; system-wide -> /etc/xdg/autostart.
if [ "$PREFIX" = "$HOME/.local" ] || [ "$PREFIX" = "${HOME}/.local" ]; then
  # Prefer the kiosk user's config dir when installing as root via sudo.
  if [ -n "${SUDO_USER:-}" ] && [ "$(id -u)" -eq 0 ]; then
    kiosk_home="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
    AUTOSTART_DIR="${kiosk_home}/.config/autostart"
  else
    AUTOSTART_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/autostart"
  fi
else
  AUTOSTART_DIR="/etc/xdg/autostart"
fi
# ---------------------------------------------------------------------------

err()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; }
info() { printf '\033[36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33mwarn:\033[0m %s\n' "$*" >&2; }

# Run a command as root. Prefers an existing root shell, then passwordless sudo,
# then an interactive sudo prompt when a TTY is available.
run_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
    return
  fi
  if command -v sudo >/dev/null 2>&1; then
    if sudo -n true >/dev/null 2>&1; then
      sudo "$@"
      return
    fi
    if [ -t 0 ] || [ -t 1 ] || [ -t 2 ]; then
      info "sudo required for kiosk / display-manager changes — enter password if prompted"
      sudo "$@"
      return
    fi
  fi
  return 1
}

# Install the GStreamer runtime + V4L2 plugins the live camera preview relies on.
# camera_desktop builds its pipeline on GStreamer (v4l2src -> appsink), so these
# must be present at runtime on the device. We don't assume anything is already
# installed — the system package manager is invoked directly (idempotent). This
# is best-effort: on failure we warn but let the rest of the install proceed.
install_runtime_deps() {
  local pm=""
  for candidate in apt-get dnf yum pacman zypper; do
    if command -v "$candidate" >/dev/null 2>&1; then
      pm="$candidate"
      break
    fi
  done

  if [ -z "$pm" ]; then
    warn "no supported package manager found (apt/dnf/yum/pacman/zypper)"
    warn "install GStreamer + its V4L2/good plugins manually or the Camera tab stays blank"
    return 0
  fi

  info "Installing GStreamer runtime dependencies via $pm ..."
  local ok=1
  case "$pm" in
    apt-get)
      run_root apt-get update || warn "apt-get update failed; trying install anyway"
      run_root apt-get install -y \
        libgstreamer1.0-0 libgstreamer-plugins-base1.0-0 \
        gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
        gstreamer1.0-tools || ok=0
      ;;
    dnf|yum)
      run_root "$pm" install -y \
        gstreamer1 gstreamer1-plugins-base gstreamer1-plugins-good || ok=0
      ;;
    pacman)
      run_root pacman -Sy --needed --noconfirm \
        gstreamer gst-plugins-base gst-plugins-good || ok=0
      ;;
    zypper)
      run_root zypper --non-interactive install \
        gstreamer gstreamer-plugins-base gstreamer-plugins-good || ok=0
      ;;
  esac

  if [ "$ok" -eq 1 ]; then
    info "GStreamer runtime dependencies installed."
  else
    warn "could not install GStreamer runtime deps (need root/sudo, or package names differ)"
    warn "install them manually so the Camera tab can open the hardware camera, then re-run"
    warn "or skip this step with INSTALL_DEPS=0"
  fi
}

# Detect the active display manager: gdm | lightdm | sddm | unknown
detect_display_manager() {
  local unit=""
  if command -v systemctl >/dev/null 2>&1; then
    unit="$(systemctl -q show display-manager.service -p Id --value 2>/dev/null || true)"
  fi
  case "$unit" in
    gdm.service|gdm3.service) echo gdm; return ;;
    lightdm.service)          echo lightdm; return ;;
    sddm.service)             echo sddm; return ;;
  esac

  if [ -x /usr/sbin/gdm3 ] || [ -x /usr/sbin/gdm ] || [ -x /usr/bin/gdm ] || \
     [ -d /etc/gdm3 ] || [ -d /etc/gdm ]; then
    echo gdm; return
  fi
  if [ -x /usr/sbin/lightdm ] || [ -x /usr/bin/lightdm ] || [ -d /etc/lightdm ]; then
    echo lightdm; return
  fi
  if [ -x /usr/bin/sddm ] || [ -d /etc/sddm.conf.d ] || [ -f /etc/sddm.conf ]; then
    echo sddm; return
  fi
  echo unknown
}

# Pick a reasonable desktop session name for SDDM (optional but helpful).
detect_sddm_session() {
  local session=""
  for dir in /usr/share/wayland-sessions /usr/share/xsessions; do
    [ -d "$dir" ] || continue
    # Prefer common desktop sessions over greeter/openbox-only entries.
    for name in plasma plasma.desktop gnome gnome.desktop ubuntu ubuntu.desktop \
                cinnamon mate xfce lxqt; do
      base="${name%.desktop}"
      if [ -f "$dir/${base}.desktop" ]; then
        echo "$base"
        return
      fi
    done
    session="$(basename "$(find "$dir" -maxdepth 1 -name '*.desktop' | head -n1)" .desktop || true)"
    if [ -n "$session" ]; then
      echo "$session"
      return
    fi
  done
  echo ""
}

configure_gdm_autologin() {
  local user="$1"
  local conf=""
  if [ -d /etc/gdm3 ]; then
    conf="/etc/gdm3/custom.conf"
  elif [ -d /etc/gdm ]; then
    conf="/etc/gdm/custom.conf"
  else
    err "gdm config directory not found (/etc/gdm3 or /etc/gdm)"
    return 1
  fi

  run_root bash -c "
    set -euo pipefail
    conf='$conf'
    user='$user'
    if [ -f \"\$conf\" ]; then
      cp -a \"\$conf\" \"\${conf}.bak.\$(date +%Y%m%d%H%M%S)\"
    else
      mkdir -p \"\$(dirname \"\$conf\")\"
      printf '%s\n' '[daemon]' 'WaylandEnable=true' > \"\$conf\"
    fi
    # Ensure [daemon] exists, then set / replace AutomaticLogin* keys.
    if ! grep -q '^\[daemon\]' \"\$conf\"; then
      printf '\n[daemon]\n' >> \"\$conf\"
    fi
    tmp=\"\$(mktemp)\"
    awk -v user=\"\$user\" '
      BEGIN { in_daemon=0; seen_enable=0; seen_user=0 }
      /^\[/{
        if (in_daemon && !seen_enable) print \"AutomaticLoginEnable=true\"
        if (in_daemon && !seen_user)   print \"AutomaticLogin=\" user
        in_daemon = (\$0 == \"[daemon]\")
        print
        next
      }
      in_daemon && /^#?AutomaticLoginEnable[[:space:]]*=/ {
        print \"AutomaticLoginEnable=true\"; seen_enable=1; next
      }
      in_daemon && /^#?AutomaticLogin[[:space:]]*=/ {
        print \"AutomaticLogin=\" user; seen_user=1; next
      }
      { print }
      END {
        if (in_daemon && !seen_enable) print \"AutomaticLoginEnable=true\"
        if (in_daemon && !seen_user)   print \"AutomaticLogin=\" user
      }
    ' \"\$conf\" > \"\$tmp\"
    mv \"\$tmp\" \"\$conf\"
    chmod 644 \"\$conf\"
  "
  info "GDM autologin configured for user '$user' ($conf)"
}

configure_lightdm_autologin() {
  local user="$1"
  local conf_dir="/etc/lightdm/lightdm.conf.d"
  local conf="$conf_dir/99-${APP_NAME}-autologin.conf"

  run_root bash -c "
    set -euo pipefail
    mkdir -p '$conf_dir'
    cat > '$conf' <<EOF
[Seat:*]
autologin-user=$user
autologin-user-timeout=0
EOF
    chmod 644 '$conf'
    # LightDM typically requires membership in the autologin group.
    if getent group autologin >/dev/null 2>&1; then
      usermod -aG autologin '$user' || true
    else
      groupadd -r autologin 2>/dev/null || true
      usermod -aG autologin '$user' || true
    fi
  "
  info "LightDM autologin configured for user '$user' ($conf)"
}

configure_sddm_autologin() {
  local user="$1"
  local session
  session="$(detect_sddm_session)"
  local conf_dir="/etc/sddm.conf.d"
  local conf="$conf_dir/99-${APP_NAME}-autologin.conf"

  run_root bash -c "
    set -euo pipefail
    mkdir -p '$conf_dir'
    {
      echo '[Autologin]'
      echo 'User=$user'
      echo 'Relogin=true'
      if [ -n '$session' ]; then
        echo 'Session=$session'
      fi
    } > '$conf'
    chmod 644 '$conf'
  "
  if [ -n "$session" ]; then
    info "SDDM autologin configured for user '$user' session='$session' ($conf)"
  else
    info "SDDM autologin configured for user '$user' ($conf)"
    warn "no desktop session auto-detected; set Session= in $conf if login fails"
  fi
}

configure_kiosk_autologin() {
  local user="$1"
  local dm

  if ! id "$user" >/dev/null 2>&1; then
    err "kiosk user '$user' does not exist"
    return 1
  fi

  dm="$(detect_display_manager)"
  info "Detected display manager: $dm"

  case "$dm" in
    gdm)      configure_gdm_autologin "$user" ;;
    lightdm)  configure_lightdm_autologin "$user" ;;
    sddm)     configure_sddm_autologin "$user" ;;
    *)
      err "unsupported or undetected display manager"
      err "install/enable gdm, lightdm, or sddm, then re-run with KIOSK=1"
      return 1
      ;;
  esac
}

# The build workflow publishes x64 and arm64 Linux bundles.
os="$(uname -s)"
arch="$(uname -m)"
if [ "$os" != "Linux" ]; then
  err "this installer only supports Linux (detected: $os)"
  exit 1
fi
case "$arch" in
  x86_64|amd64)   asset_arch="x64" ;;
  aarch64|arm64)  asset_arch="arm64" ;;
  *)
    err "unsupported architecture: $arch (supported: x86_64, aarch64)"
    exit 1
    ;;
esac
# The build workflow publishes .tar.gz, but some releases carry a plain .tar;
# accept either and let tar auto-detect compression on extract.
ASSET_BASE="${APP_NAME}-linux-${asset_arch}.tar"

for cmd in curl tar; do
  command -v "$cmd" >/dev/null 2>&1 || { err "'$cmd' is required but not installed"; exit 1; }
done

# Install GStreamer runtime deps for the live camera preview (best-effort).
if [ "$INSTALL_DEPS" = "1" ]; then
  install_runtime_deps
else
  info "Skipping GStreamer runtime deps (INSTALL_DEPS=$INSTALL_DEPS)"
fi

# Resolve the download URL from the GitHub releases API.
if [ "$VERSION" = "latest" ]; then
  api_url="https://api.github.com/repos/$REPO/releases/latest"
else
  api_url="https://api.github.com/repos/$REPO/releases/tags/$VERSION"
fi

info "Looking up release ($VERSION) for $REPO ..."
release_json="$(curl -fsSL "$api_url")" || { err "failed to query GitHub API ($api_url)"; exit 1; }

# Pull the browser_download_url for our asset without requiring jq.
# Prefer the gzipped bundle, but fall back to a plain .tar if that's all
# the release ships. Anchor on a closing quote so ".tar" doesn't also match
# ".tar.gz" and grab a truncated URL.
download_url="$(printf '%s' "$release_json" \
  | grep -o "https://[^\"]*${ASSET_BASE}\.gz\"" \
  | head -n1 | tr -d '"')"
if [ -z "$download_url" ]; then
  download_url="$(printf '%s' "$release_json" \
    | grep -o "https://[^\"]*${ASSET_BASE}\"" \
    | head -n1 | tr -d '"')"
fi

if [ -z "$download_url" ]; then
  err "could not find asset '${ASSET_BASE}[.gz]' in release '$VERSION'"
  err "check that a release exists at https://github.com/$REPO/releases"
  exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

archive="$tmp_dir/${download_url##*/}"
info "Downloading $download_url"
curl -fsSL "$download_url" -o "$archive"

info "Installing to $SHARE_DIR"
rm -rf "$SHARE_DIR"
mkdir -p "$SHARE_DIR" "$BIN_DIR"
# tar auto-detects gzip vs. plain tar, so this works for .tar and .tar.gz.
tar -xf "$archive" -C "$SHARE_DIR"

# The executable inside the bundle is named after the app.
if [ ! -x "$SHARE_DIR/$APP_NAME" ]; then
  err "expected executable '$SHARE_DIR/$APP_NAME' not found in the archive"
  exit 1
fi
chmod +x "$SHARE_DIR/$APP_NAME"

# Symlink the binary onto PATH.
ln -sf "$SHARE_DIR/$APP_NAME" "$BIN_DIR/$APP_NAME"

info "Installed $APP_NAME -> $BIN_DIR/$APP_NAME"

# Desktop entry (menu launcher + optional session autostart).
desktop_file() {
  cat <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=$APP_DISPLAY_NAME
Comment=Smart home dashboard
Exec=$BIN_DIR/$APP_NAME
TryExec=$BIN_DIR/$APP_NAME
Path=$SHARE_DIR
Terminal=false
Categories=Utility;
StartupNotify=true
X-GNOME-Autostart-enabled=true
EOF
}

mkdir -p "$APPLICATIONS_DIR"
desktop_file > "$APPLICATIONS_DIR/${APP_NAME}.desktop"
chmod 644 "$APPLICATIONS_DIR/${APP_NAME}.desktop"
info "Desktop entry -> $APPLICATIONS_DIR/${APP_NAME}.desktop"

if [ "$AUTOSTART" = "1" ]; then
  mkdir -p "$AUTOSTART_DIR"
  # Same .desktop file in the autostart dir so the DE launches it on login.
  desktop_file > "$AUTOSTART_DIR/${APP_NAME}.desktop"
  chmod 644 "$AUTOSTART_DIR/${APP_NAME}.desktop"
  # If we created the file as root for another user, fix ownership of what we touched.
  if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
    chown "$SUDO_USER":"$SUDO_USER" "$AUTOSTART_DIR" "$AUTOSTART_DIR/${APP_NAME}.desktop" || true
  fi
  info "Autostart enabled -> $AUTOSTART_DIR/${APP_NAME}.desktop"
  info "The app will launch when the desktop session starts."
else
  # Remove a previously installed autostart entry if the user opted out.
  rm -f "$AUTOSTART_DIR/${APP_NAME}.desktop"
  info "Autostart skipped (AUTOSTART=$AUTOSTART)"
fi

# Kiosk: skip the login screen via display-manager autologin (needs sudo).
if [ "$KIOSK" = "1" ]; then
  info "Configuring kiosk autologin for user '$KIOSK_USER' ..."
  if configure_kiosk_autologin "$KIOSK_USER"; then
    info "Kiosk ready. Reboot to boot straight into the desktop (no login screen)."
    info "App autostart + DM autologin together bring up $APP_DISPLAY_NAME on boot."
  else
    warn "kiosk autologin could not be configured (sudo/root required, or unsupported DM)"
    warn "re-run with a TTY so sudo can prompt, e.g.:"
    warn "  curl -fsSL <install.sh-url> -o /tmp/${APP_NAME}-install.sh"
    warn "  bash /tmp/${APP_NAME}-install.sh"
    warn "or skip with KIOSK=0"
  fi
else
  info "Kiosk autologin skipped (KIOSK=$KIOSK)"
fi

# Ensure the bin dir is on PATH for this session.
case ":$PATH:" in
  *":$BIN_DIR:"*) : ;;
  *)
    export PATH="$BIN_DIR:$PATH"
    info "Added $BIN_DIR to PATH"
    ;;
esac

info "Done. Run '$APP_NAME' to start."
