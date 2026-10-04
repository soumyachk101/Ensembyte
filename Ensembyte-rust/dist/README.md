# Packaging

## Linux

```sh
scripts/package-linux.sh            # release build (thin LTO, stripped)
PROFILE=debug scripts/package-linux.sh   # fast smoke package
```

Produces `target/package/ensembyte-<version>-linux-<arch>.tar.gz` containing:

- `ensembyte` — the binary (headed by default; `ensembyte headless` runs the engine alone)
- `ensembyte.desktop` — XDG desktop entry template (`Exec=ensembyte` for packagers;
  the installers rewrite `Exec`, `TryExec`, and `Icon` to absolute paths under
  `~/.ensembyte/app/current`, since `~/.local/bin` is often not on a desktop
  session's `PATH`)
- `ensembyte.png` — 1024×1024 Ensembyte app icon
- `install.sh` — installs into `~/.ensembyte/app/<version>` behind a `current`
  symlink (the curl installer's layout, which the in-app updater manages),
  links `~/.local/bin/ensembyte` to it, and writes the desktop entry and icon under
  `$XDG_DATA_HOME` (default `~/.local/share`). The curl installer does the same
  from the extracted tarball; `scripts/test-linux-desktop-entry.sh` checks both.

The release profile in the root `Cargo.toml` sets `lto = "thin"` and
`strip = "symbols"` for distribution builds.

## macOS (from Linux — not used in the Rust repo's macOS build)

```sh
scripts/package-macos.sh    # → target/package/ensembyte-<version>-macos-<arch>.dmg
```

Builds the release binary, assembles `Ensembyte.app` (Info.plist + icns), ad-hoc
signs it (set `CODESIGN_IDENTITY` for a real Developer ID), and wraps it in a
dmg. The auto-update tarball retains an internal `Ensembyte.app` path so older
installed builds can update into Ensembyte.

## Windows

```powershell
./scripts/package-windows.ps1 -ReleasesUrl https://github.com/soumyachk101/Ensembyte-rust/releases/latest/download
```

Produces, under `target/package/`:

- `ensembyte-<version>-windows-<arch>-setup.exe` — the per-user installer built
  from `dist/windows/ensembyte.iss` with Inno Setup 6
- `ensembyte-<version>-windows-<arch>.zip` — the portable package
- `ensembyte-<version>-windows-<arch>.exe` — the bare executable the in-app
  updater downloads

The installer and the zip both carry `ensembyte-update.json`, the marker that lets
the app update itself in place. CI runs `scripts/test-windows-installer.ps1`
against the setup on every Windows build.
