# GitAccountSwitch

A macOS menu bar app for switching between GitHub accounts, for `git` and `gh` alike, with per-folder overrides.

- **Log in once per account.** It uses `gh auth login` in the browser, and tokens stay in gh's keychain storage.
- **Switch from the menu bar.** Switching runs `gh auth switch` and changes the global git commit name and email.
- **Per-folder accounts.** Every repo inside a folder commits *and pushes* as the account you assign to it, whatever the global account is. Nested folders override their parents.
- **`gh` per folder.** A shell wrapper makes `gh pr create` etc. use the folder's account too. It turns on with your first folder rule.

## Download

Get the latest zip from [Releases](https://github.com/SnowyFoxStudios/git-acc-switch/releases), unzip it and move **GitAccountSwitch.app** to Applications. It isn't notarized yet, so the first launch shows *"GitAccountSwitch" Not Opened*: click **Done**, then **System Settings → Privacy & Security → Open Anyway** (or run `xattr -dr com.apple.quarantine /Applications/GitAccountSwitch.app`). You also need `gh` (`brew install gh`).

## Build & install


Requires macOS 14+, Xcode command line tools and `gh` (`brew install gh`).

```bash
./scripts/build-app.sh --install    # builds, copies to ~/Applications, launches
```

Then click the menu bar item → **Manage Accounts & Folders…**:

1. **Accounts**: add accounts. You can import logins `gh` already has, or **Sign in with Browser**. The one-time code is copied to your clipboard and the device page opens. Then set the label, commit name and commit email. The email defaults to GitHub's noreply address.
2. **Setup → Install Git Integration**: makes the app's identity and folder rules take effect. It backs up `~/.gitconfig` first.
3. **Folders → Add Folder…**: pick a folder and an account. This also turns on the shell integration, so `gh` follows folder rules (turn it off under **Setup** if you don't want it). Open a new terminal tab afterwards.
4. Optionally, **Setup → Launch at login**.

## How it works

```
~/.gitconfig
  [include] path = ~/.config/gh-acc-switch/gitconfig      ← added at the very top
  ...the rest of your config (still wins over the include)

~/.config/gh-acc-switch/
  config.json                accounts, folder rules, active account
  gitconfig                  [user] of the global account
                             credential helper for github.com / gist.github.com
                             [includeIf "gitdir/i:<folder>/"] → accounts/<id>.gitconfig
  accounts/<id>.gitconfig    [user] + ghswitch.folderUser for that account
  init.sh                    gh() wrapper, sourced from ~/.zshenv
  bin/gh-acc-switch          symlink to the app binary (CLI + credential helper)
```

**Why a custom credential helper:** `gh auth git-credential` only returns the token of gh's *active* account. Asking it for any other user returns nothing, so per-folder pushes would fail. `gh-acc-switch credential` picks the account in this order, then fetches that account's token with `gh auth token --user`:

1. the username in the remote URL (`https://user@github.com/...`),
2. the folder rule (`ghswitch.folderUser`, set by the includeIf),
3. the global account.

**Shell wrapper:** inside a folder whose account differs from the global one, `gh` runs with `GH_TOKEN` set to that account's token. `gh auth …` is never wrapped. It's sourced from `~/.zshenv` rather than `~/.zshrc`, so non-interactive zsh (scripts, IDE tasks, coding agents) gets it too. Bash and other shells don't.

The app watches gh's `hosts.yml`, so running `gh auth switch` in a terminal updates the menu bar and the global git identity.

## CLI

```bash
gh-acc-switch status          # global account, folder override, commit identity here
gh-acc-switch list
gh-acc-switch switch Work     # by label or GitHub login
```

## Notes

- Folder rules for git use `gitdir`, so they apply inside git repositories. The `gh` wrapper also matches folders that aren't repos.
- Hand-written `includeIf` blocks later in `~/.gitconfig` override the app for their folders. Move them into folder rules, or delete them.
- **Uninstall:** Setup → Uninstall Git Integration puts a plain `[user]` and gh's credential helper back, turn off the shell integration, then delete the app and `~/.config/gh-acc-switch`.

## Development

```bash
swift build
.build/debug/GitAccountSwitch          # run the app unbundled
.build/debug/GitAccountSwitch status   # run as CLI
swift scripts/make-icon.swift     # regenerate Resources/AppIcon.icns
```

## Releasing

Every push and pull request is built on GitHub's macOS runners (`.github/workflows/build.yml`), and the zipped app is attached to the run. To publish a release, tag a commit on `main`:

```bash
git tag v0.1.0 && git push origin v0.1.0
```

The workflow writes the tag's version into the app, then creates the GitHub Release with `GitAccountSwitch-<version>.zip` and its SHA-256 checksum.

## License

MIT © 2026 Snowy Fox SRL. See [LICENSE](LICENSE).
