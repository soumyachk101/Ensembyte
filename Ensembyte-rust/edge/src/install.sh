#!/bin/sh
# Ensembyte (native) headless installer.
#
#   curl -fsSL https://ensembyte.vercel.app/install.sh | sh
#
# Installs the native binary (requires the system ALSA runtime) to
# ~/.ensembyte/app, puts `ensembyte` on PATH, adds a launcher entry and icon under
# $XDG_DATA_HOME (default ~/.local/share), and runs it as a local-only
# systemd user service that survives reboots. Signing in is optional and
# enables sync after a restart. Re-running
# upgrades in place; ~/.ensembyte state is preserved.
#
# The binary ships with production endpoints baked in: no ENSEMBYTE_EDGE_URL or
# client-id configuration needed. Overrides (if any) go in ~/.ensembyte/env.
set -eu

BASE="${ENSEMBYTE_BASE_URL:-https://ensembyte.vercel.app}"

# --- platform ---------------------------------------------------------------
os="$(uname -s)"
arch="$(uname -m)"
case "$os" in
  Linux) plat=linux ;;
  Darwin)
    echo "ensembyte install: on macOS, download the desktop app instead:" >&2
    echo "  $BASE/releases/latest.txt → $BASE/releases/ensembyte-<version>-macos-arm64.dmg" >&2
    exit 1
    ;;
  *)
    echo "ensembyte install: unsupported OS '$os' — only Linux for now." >&2
    exit 1
    ;;
esac
case "$arch" in
  x86_64 | amd64) arch=x86_64 ;;
  aarch64 | arm64) arch=aarch64 ;;
  *)
    echo "ensembyte install: unsupported architecture '$arch'." >&2
    exit 1
    ;;
esac

# --- download ----------------------------------------------------------------
ver="$(curl -fsSL "$BASE/releases/latest.txt" | tr -d '[:space:]')"
[ -n "$ver" ] || { echo "ensembyte install: could not resolve latest version" >&2; exit 1; }
file="ensembyte-$ver-$plat-$arch.tar.gz"
data_root="$HOME/.ensembyte"
app_root="$data_root/app"
dest="$app_root/$ver"

if [ -x "$dest/ensembyte" ]; then
  echo "ensembyte $ver already downloaded — relinking."
else
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  echo "downloading ensembyte $ver ($plat-$arch)…"
  curl -fSL --progress-bar "$BASE/releases/$file" -o "$tmp/$file"
  mkdir -p "$dest"
  tar -xzf "$tmp/$file" -C "$dest" --strip-components=1
fi

# Probe before changing a working installation or starting its service. The
# desktop and headless modes share one binary, including CPAL's ALSA linkage.
if ! "$dest/ensembyte" --version >/dev/null; then
  echo "ensembyte install: the downloaded executable could not start; see the loader error above." >&2
  echo "Install the missing runtime libraries (including ALSA, libasound.so.2), then rerun this installer." >&2
  exit 1
fi

ln -sfn "$dest" "$app_root/current"
mkdir -p "$HOME/.local/bin"
ln -sf "$app_root/current/ensembyte" "$HOME/.local/bin/ensembyte"

# --- desktop entry -------------------------------------------------------------
# Launchers list Ensembyte through a per-user .desktop entry. The one in the tarball
# says `Exec=ensembyte` and `TryExec=ensembyte`, which only resolve when ~/.local/bin is
# on the PATH of the desktop session and TryExec then hides the entry outright.
# So write it with absolute paths through the `current` symlink.
install_desktop_entry() {
  src="$1"
  app="$2"
  [ -f "$src/ensembyte.desktop" ] && [ -f "$src/ensembyte.png" ] || return 1
  case "${XDG_DATA_HOME:-}" in
    /*) data_home="$XDG_DATA_HOME" ;;
    *) data_home="$HOME/.local/share" ;;
  esac
  apps_dir="$data_home/applications"
  icon_dir="$data_home/icons/hicolor/1024x1024/apps"
  bin="$app/current/ensembyte"
  icon="$app/current/ensembyte.png"
  case "$bin" in
    *[!A-Za-z0-9_./-]*)
      exec_bin="\"$(printf '%s' "$bin" | sed -e 's/\\/\\\\\\\\/g' -e 's/["`$]/\\\\&/g' -e 's/%/%%/g')\""
      ;;
    *) exec_bin="$bin" ;;
  esac
  try_bin="$(printf '%s' "$bin" | sed 's/\\/\\\\/g')"
  icon_val="$(printf '%s' "$icon" | sed 's/\\/\\\\/g')"

  mkdir -p "$apps_dir" "$icon_dir" || return 1
  entry_tmp="$apps_dir/.ensembyte.desktop.$$"
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      Exec=*) printf 'Exec=%s %%u\n' "$exec_bin" ;;
      TryExec=*) printf 'TryExec=%s\n' "$try_bin" ;;
      Icon=*) printf 'Icon=%s\n' "$icon_val" ;;
      *) printf '%s\n' "$line" ;;
    esac
  done <"$src/ensembyte.desktop" >"$entry_tmp" || { rm -f "$entry_tmp"; return 1; }
  mv -f "$entry_tmp" "$apps_dir/ensembyte.desktop" || { rm -f "$entry_tmp"; return 1; }
  cp "$src/ensembyte.png" "$icon_dir/.ensembyte.png.$$" \
    && mv -f "$icon_dir/.ensembyte.png.$$" "$icon_dir/ensembyte.png" || return 1

  command -v update-desktop-database >/dev/null 2>&1 \
    && update-desktop-database "$apps_dir" >/dev/null 2>&1 || true
  [ -f "$data_home/icons/hicolor/icon-theme.cache" ] \
    && command -v gtk-update-icon-cache >/dev/null 2>&1 \
    && gtk-update-icon-cache -q -t -f "$data_home/icons/hicolor" >/dev/null 2>&1 || true
  return 0
}
# A missing desktop entry must never fail an otherwise good install.
install_desktop_entry "$dest" "$app_root" \
  || echo "warn: could not install the desktop entry — Ensembyte won't appear in application launchers"

# --- service -----------------------------------------------------------------
# The daemon is useful before auth: without a saved session it serves the local
# profile. Login only changes which profile the next daemon start selects.

service=manual
if command -v systemctl >/dev/null 2>&1 && [ -n "${XDG_RUNTIME_DIR:-}" ]; then
  mkdir -p "$HOME/.config/systemd/user"
  cat >"$HOME/.config/systemd/user/ensembyte.service" <<'UNIT'
[Unit]
Description=Ensembyte headless engine
After=network-online.target
StartLimitIntervalSec=60
StartLimitBurst=5

[Service]
ExecStart=%h/.ensembyte/app/current/ensembyte headless
Restart=on-failure
RestartSec=5
EnvironmentFile=-%h/.ensembyte/env

[Install]
WantedBy=default.target
UNIT
  systemctl --user daemon-reload
  systemctl --user enable ensembyte
  systemctl --user restart ensembyte
  service=running
  # Keep the user manager (and the engine) running without an active login.
  loginctl enable-linger "$USER" 2>/dev/null \
    || sudo -n loginctl enable-linger "$USER" 2>/dev/null \
    || echo "warn: could not enable linger — the engine stops when you log out (run: sudo loginctl enable-linger $USER)"
else
  echo "warn: systemd user session not available — run the engine manually with: ensembyte headless"
fi

# --- agent CLIs ---------------------------------------------------------------
command -v claude >/dev/null 2>&1 || \
  echo "note: Claude Code CLI not found — install it with: curl -fsSL https://claude.ai/install.sh | bash"

case ":$PATH:" in
  *":$HOME/.local/bin:"*) path_hint="" ;;
  *) path_hint=' (add ~/.local/bin to your PATH)' ;;
esac

echo ""
echo "✓ ensembyte $ver installed$path_hint"
echo ""
case "$service" in
  running)
    echo "the engine is running with the new version (local-only unless sync is enabled)."
    echo "  systemctl --user status ensembyte    check the service"
    echo ""
    echo "optional sync (local sessions stay local):"
    echo "  systemctl --user stop ensembyte"
    echo "  ensembyte login"
    echo "  systemctl --user restart ensembyte"
    ;;
  manual)
    echo "next: run the local-only engine with \`ensembyte headless\`."
    echo "optional sync: run \`ensembyte login\` before starting the engine."
    ;;
esac
