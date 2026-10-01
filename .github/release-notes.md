## Install

1. Install the GitHub CLI if you don't have it: `brew install gh` (requires macOS 14 or later).
2. Download **GitAccountSwitch-{{VERSION}}.zip** below and unzip it.
3. Move **GitAccountSwitch.app** to your Applications folder.
4. Open it. The app isn't notarized by Apple yet, so macOS shows *"GitAccountSwitch" Not Opened*. Click **Done** (not Move to Trash), then either:
   - go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to GitAccountSwitch, or
   - run `xattr -dr com.apple.quarantine /Applications/GitAccountSwitch.app` in Terminal and open it again.

   This is needed once per downloaded version.
5. Click the menu bar item → **Manage Accounts & Folders…** and follow the steps in the README.

Checksum: compare `shasum -a 256 GitAccountSwitch-{{VERSION}}.zip` with the `.sha256` file.
