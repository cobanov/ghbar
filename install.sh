#!/bin/sh
# Installs the latest GHBar into /Applications and opens it.
#
#   curl -fsSL https://ghbar.cobanov.dev/install.sh | sh
#
# Everything runs inside main(), so a download cut short runs nothing.
set -eu

ZIP_URL="https://github.com/cobanov/ghbar/releases/latest/download/GHBar-macos.zip"
TEAM_ID="6U58AKY6F8"

say() { printf '%s\n' "$*"; }
fail() { printf 'ghbar: %s\n' "$*" >&2; exit 1; }

main() {
    [ "$(uname -s)" = Darwin ] || fail "GHBar runs on macOS only."
    version=$(sw_vers -productVersion)
    [ "${version%%.*}" -ge 14 ] || fail "GHBar needs macOS 14 or newer; this Mac has $version."

    dest=/Applications
    [ -w "$dest" ] || dest="$HOME/Applications"
    mkdir -p "$dest"

    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT

    say "Downloading GHBar..."
    curl -fsSL "$ZIP_URL" -o "$tmp/GHBar.zip" || fail "could not download $ZIP_URL"
    ditto -x -k "$tmp/GHBar.zip" "$tmp"
    app="$tmp/GHBar.app"
    [ -d "$app" ] || fail "the download does not contain GHBar.app."

    # Only install the app signed by GHBar's developer and notarized by Apple.
    codesign --verify --deep --strict "$app" 2>/dev/null || fail "GHBar.app's signature is not valid."
    codesign -dv "$app" 2>&1 | grep -q "TeamIdentifier=$TEAM_ID" || fail "GHBar.app is not signed by its developer."
    spctl --assess --type execute "$app" 2>/dev/null || fail "macOS does not accept GHBar.app (not notarized)."

    pkill -x GHBar 2>/dev/null || true
    rm -rf "$dest/GHBar.app" 2>/dev/null || fail "could not replace $dest/GHBar.app; remove it and run this again."
    ditto "$app" "$dest/GHBar.app"

    say "Installed $dest/GHBar.app"
    open "$dest/GHBar.app"
    say "GHBar is in the menu bar. Sign in with GitHub in the window that opened."
}

main "$@"
