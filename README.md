# Nishant's DSA Setup

A one-click setup for C++ and DSA practice. It gives your computer the same coding setup as Nishant's: editor, compiler, terminal look and the CPH Plus extension for competitive programming.

Works on **Windows 10/11** and **macOS**. No admin rights are needed on Windows.

## What you get

| | |
|---|---|
| **VS Code** | Installed if you don't have it |
| **g++ compiler** | GCC 16 on Windows, Homebrew GCC on Mac. `#include <bits/stdc++.h>` works |
| **Extensions** | CPH Plus, C/C++, Code Runner, Auto Hide |
| **Look** | Tomorrow Night Blue theme, Hack font (size 20) in the editor, Fira Code in CPH test cases |
| **Terminal** | Colourful powerline prompt (oh-my-posh) with MesloLGM Nerd Font |
| **Snippets** | Type `cpts` (with test cases) or `cpnts` (single case) in a `.cpp` file and press Tab |

## Install

### Windows

1. Download **[NishantsDSASetup-Windows.exe](https://github.com/GamerNishant/nishants-dsa-setup/releases/latest/download/NishantsDSASetup-Windows.exe)**.
2. Double-click it. If Windows says *"Windows protected your PC"*, click **More info**, then **Run anyway**. This warning appears because the app isn't signed with a paid certificate.
3. Click through the installer. A blue PowerShell window shows each step. Wait until it says **All done**.
4. Close all VS Code and terminal windows, then open VS Code again.

### Mac

Open the **Terminal** app, paste this line and press Return:

```bash
curl -fsSL https://github.com/GamerNishant/nishants-dsa-setup/releases/latest/download/install-mac.sh | bash
```

It may ask for your Mac password to install Homebrew. Nothing appears on screen while you type; that's normal. When it finishes, quit VS Code and Terminal (Cmd+Q) and open them again.

<details>
<summary>Prefer double-clicking?</summary>

Download **[NishantsDSASetup-mac.zip](https://github.com/GamerNishant/nishants-dsa-setup/releases/latest/download/NishantsDSASetup-mac.zip)**, unzip it and double-click **Nishant's DSA Setup.command**.

If macOS says it can't verify the developer, open **System Settings → Privacy & Security**, scroll down and click **Open Anyway**.
</details>

## Already have a setup? It's safe

- **Steps already done are skipped.** If you already have VS Code, a modern g++ or the fonts, they aren't installed again. An old compiler, such as MinGW 6.3, is left exactly where it is; the new one is installed separately.
- **Nothing is overwritten blindly.** Only the specific settings listed above are changed. Your other VS Code settings, extensions and shell config stay as they are.
- **Everything is backed up first**, to `%LOCALAPPDATA%\NishantDSASetup\state\backups` on Windows and `~/.nishant-dsa/state/backups` on Mac.
- **Safe to run again** at any time, for example after a failed download.

## Don't like it? Go back to your old setup

- **Windows:** Start menu → *Nishant's DSA Setup* → **Restore my previous setup**. Uninstalling the app from *Settings → Apps* does the same.
- **Mac:** run
  ```bash
  curl -fsSL https://github.com/GamerNishant/nishants-dsa-setup/releases/latest/download/install-mac.sh | bash -s -- --restore
  ```
  or double-click **Restore Previous Setup.command** from the zip.

The restore puts back the exact values you had before, removes the fonts, extensions and prompt the setup added, and reinstalls anything it replaced (for example the original CPH extension). If you changed a setting yourself after running the setup, your newer value is kept. It asks before removing the compiler or VS Code. Your backups are never deleted.

## Troubleshooting

- **The terminal shows boxes or question marks:** close and reopen VS Code so it picks up the new font.
- **Something failed:** run the setup again; finished steps are skipped. The log is in `%LOCALAPPDATA%\NishantDSASetup\setup.log` (Windows) or `~/.nishant-dsa/setup.log` (Mac).
- **Mac, powerlevel10k users:** your powerlevel10k theme may still draw its own prompt. Remove `ZSH_THEME="powerlevel10k/powerlevel10k"` from `~/.zshrc` to use this one.

## Credits

- [CPH Plus](https://github.com/GamerNishant/cph-plus), based on [Competitive Programming Helper](https://github.com/agrawal-d/cph) by Divyanshu Agrawal (GPL-3.0)
- [WinLibs](https://winlibs.com) GCC builds, [Homebrew](https://brew.sh), [oh-my-posh](https://ohmyposh.dev)
- Fonts: [Meslo Nerd Font](https://www.nerdfonts.com) (Apache 2.0), [Hack](https://sourcefoundry.org/hack/) (MIT), [Fira Code](https://github.com/tonsky/FiraCode) (OFL 1.1). License files are in `payload/fonts/licenses`.
