## Install

1. Install the GitHub CLI if you don't have it: `brew install gh` (requires macOS 14 or later).
2. Download **GitAccountSwitch-{{VERSION}}.zip** below and unzip it.
3. Move **GitAccountSwitch.app** to your Applications folder.
4. The app isn't notarized by Apple yet, so the first time, **right-click it → Open → Open**.
   If macOS says the app is damaged, run `xattr -dr com.apple.quarantine /Applications/GitAccountSwitch.app` and open it again.
5. Click the menu bar item → **Manage Accounts & Folders…** and follow the steps in the README.

Checksum: compare `shasum -a 256 GitAccountSwitch-{{VERSION}}.zip` with the `.sha256` file.
