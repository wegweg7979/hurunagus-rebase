# hurubase

[![CI](https://github.com/wegweg7979/hurunagus-rebase/actions/workflows/ci.yml/badge.svg)](https://github.com/wegweg7979/hurunagus-rebase/actions/workflows/ci.yml)

A safe rebase helper for [hurunagus](https://github.com/wegweg7979) images and
other atomic Fedora/bootc distros.

You give it the address of the image you want to be running. It checks the
system you are on, works out what that target means for your machine, prints a
plan, and asks before it changes anything. Run the same command again after each
reboot — it completes whatever the previous boot left staged, and once you are
booted on the target it walks the post-rebase fixes, one prompt at a time.

```sh
git clone https://github.com/wegweg7979/hurunagus-rebase
cd hurunagus-rebase

./hurubase --check ghcr.io/wegweg7979/hurunagus-hyprland:latest   # plan only, changes nothing
sudo ./hurubase ghcr.io/wegweg7979/hurunagus-hyprland:latest      # preflight, plan, apply
# reboot
sudo ./hurubase ghcr.io/wegweg7979/hurunagus-hyprland:latest      # continue, or run the fix checklist
sudo ./hurubase --rollback                                        # back to the previous deployment
```

The target is always an image address — `registry/owner/name[:tag]`. A bare name
is rejected, because the address is what gets resolved, pinned by digest, and
rebased onto. `--list` prints the addresses whose desktop this tool already
knows about; those get the desktop-specific warnings, the session name and the
never-clobber list.

Nothing needs installing: it is one self-contained script that reads the system
it runs on.

## What it checks before touching anything

- **Signature policy.** It reads `/etc/containers/policy.json` and decides from
  that: if the target's repository is already trusted (or accepted, as ublue's
  permissive empty-repo fallback does) it uses the signed rebase in one step;
  otherwise the documented two-step — unsigned rebase, reboot, signed rebase.
- **An already-staged deployment**, too little space on `/var` or `/boot`, an
  address that will not resolve, and any `*-nvidia*` image are refusals, not
  warnings. A rebase already in progress to a different address is refused too.
- **Direction, hardware, drift.** Fedora major upgrades, a target *older* than
  what you are running, Secure Boot meeting an unsigned kernel, and a `latest`
  tag that moved between the two halves of a two-step rebase (the digest is
  pinned at step 1; `--force` accepts a new one).

## What it asks you, after the reboot

Each of these is a question, never a silent change — `--yes` answers yes to all
of them, `--dry-run` prints instead of doing.

- **`$HOME` adoption.** An atomic rebase never seeds `/etc/skel` into an
  existing `$HOME`, so the new desktop's configs simply never arrive. Missing
  files are offered for writing; files that differ from the target's are left
  alone unless you say yes, in which case each is backed up as
  `<file>.pre-rebase-<timestamp>` first; a per-target never-clobber list
  (e.g. Zirconium's `~/.config/niri/local.kdl`) is always left alone.
- **A stale session choice.** `~/.config/sddm/state.conf` (`LastSession=`) and
  `/var/lib/AccountsService/users/<user>` (`XSession=`) keep naming the old
  desktop's session after a rebase — which is how a login ends up on a black
  screen or bounced back to the greeter. Offered as a reset, with the record
  backed up. Needs root; if you are not root it tells you to run the same
  command under sudo.
- **A display manager the target does not ship** that is still enabled in
  `/etc`, and a `display-manager.service` alias pointing at a unit that no
  longer exists, are offered as a disable / repoint.
- **The target's own dotfile machinery** (Zirconium ships user-level chezmoi
  services that manage `$HOME` on login) is offered as a `systemctl --user mask`,
  or printed for you to run in your session.
- **What the target changes about the machine** — a different display manager,
  systemd presets that disable sshd, and so on — is printed for information.

## Known addresses

| Address | Desktop | Display manager |
|---|---|---|
| `ghcr.io/wegweg7979/hurunagus-hyprland:latest` *(flagship)* | Hyprland + Omarchy | SDDM |
| `ghcr.io/wegweg7979/hurunagus-ublue:latest` | niri + DMS | greetd |
| `ghcr.io/wegweg7979/hurunagus-silverblue:latest` | niri + DMS | GDM |
| `ghcr.io/zirconium-dev/zirconium:latest` | niri + DMS | greetd |
| `ghcr.io/zirconium-dev/zirconium-jackrabbit:latest` | niri + DMS (gaming) | greetd |
| `ghcr.io/ublue-os/bluefin:latest` | GNOME | GDM |
| `ghcr.io/ublue-os/silverblue-main:latest` | GNOME | GDM |
| `ghcr.io/ublue-os/bazzite:latest` | KDE Plasma | SDDM |
| `ghcr.io/ublue-os/bazzite-gnome:latest` | GNOME | GDM |
| `ghcr.io/ublue-os/aurora:latest` | KDE Plasma | SDDM |
| `ghcr.io/ublue-os/kinoite-main:latest` | KDE Plasma | SDDM |

Any other address works too, minus the desktop-specific knowledge. Refused by
design: every `*-nvidia*` image, and the retired `hurunagus`,
`hurunagus-umbriel` and `hurunagus-hyprland-dms` images.

## What it never does

Deletes anything. Prunes a deployment. Edits `/etc/containers/policy.json` or
any other system file. Writes outside `$HOME` during the checklist. Reboots
without asking. Proceeds past a refusal.

## Tests

```sh
test/hurubase-test.sh    # 133 checks; fake rpm-ostree/bootc/skopeo/systemctl/df,
                         # a fixture /etc, $HOME and /etc/skel — nothing real is touched
```

GitHub Actions runs the same suite on `ubuntu-24.04`, plus `bash -n`, shellcheck
(warning and up) on both scripts, the executable bit and shebang, and a check
that this README lists every address `--list` knows about.

Every environment seam — fixtures, command paths, scripted prompt answers
(`HURUBASE_ANSWERS`), dry-run, root gate — is documented in the header of
`hurubase`.
