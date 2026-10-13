<p align="center">
  <img src="assets/ghbar-icon.png" alt="" width="96" height="96" />
</p>

<h1 align="center">GHBar</h1>

<p align="center">
  Pull requests and issues people open on your GitHub repositories, in the macOS menu bar.
</p>

<p align="center">
  <a href="https://github.com/cobanov/ghbar/releases/latest"><img src="https://img.shields.io/github/v/release/cobanov/ghbar?label=release&color=2eb857" alt="Latest release" /></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-000000?logo=apple" alt="macOS 14+" />
  <img src="https://img.shields.io/badge/license-MIT-2eb857" alt="MIT license" />
</p>

<p align="center">
  <img src="assets/panel.png" width="380" alt="The GHBar panel: tabs for reviews, pull requests and issues, each row with its author" />
</p>

## Install

```sh
curl -fsSL https://ghbar.cobanov.dev/install.sh | sh
```

Or with Homebrew:

```sh
brew install --cask cobanov/tap/ghbar
```

Or download `GHBar-macos.zip` from the [latest release](https://github.com/cobanov/ghbar/releases/latest)
and move GHBar to Applications.

Needs macOS 14 or newer. The app is signed and notarized by Apple.

## Use

Open GHBar and sign in with GitHub. If the [GitHub CLI](https://cli.github.com) is signed in,
you can continue as that account instead.

Click the icon in the menu bar. The panel shows pull requests waiting for your review, pull
requests and issues other people opened on your repositories, and your own open pull requests.
Green marks what you haven't seen yet.

| Key | |
| --- | --- |
| ↑ ↓, Return | Move between rows, open one on GitHub |
| ← → | Switch tabs |
| ⌘R | Refresh |
| ⌘, | Settings: organizations, hidden repositories, notifications, launch at login |

GHBar talks only to GitHub, with your own token, kept in the macOS Keychain. It has no server
and no analytics.

## Update or remove

Run the install command again to update, or `brew upgrade --cask ghbar`.
To remove GHBar, quit it and move it to the Trash, or run `brew uninstall --cask ghbar`.

## Build from source

```sh
git clone https://github.com/cobanov/ghbar && cd ghbar
make install
```

## License

MIT. GHBar is an independent project, not affiliated with GitHub, Inc.
