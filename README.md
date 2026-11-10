# hurubase

[![CI](https://github.com/wegweg7979/hurunagus-rebase/actions/workflows/ci.yml/badge.svg)](https://github.com/wegweg7979/hurunagus-rebase/actions/workflows/ci.yml)

A safe rebase helper for [hurunagus](https://github.com/wegweg7979) images and
other atomic Fedora/bootc distros.

Moving a machine from one atomic image to another — especially between
different desktop environments or display managers — is not just
`rpm-ostree rebase && reboot`. `hurubase` does the whole job: it reads the
running system and the target's registry metadata, decides from the local
policy whether the signed or the documented two-step rebase is needed, prints a
plan, and asks before changing anything. After the reboot it adopts the new
desktop's `/etc/skel` into `$HOME` and reports the session and display-manager
state.

```sh
git clone https://github.com/wegweg7979/hurunagus-rebase
cd hurunagus-rebase
./hurubase --list                 # known targets (hurunagus-hyprland is the flagship)
./hurubase --check hurunagus-ublue  # preflight + plan; changes nothing, asks nothing
sudo ./hurubase hurunagus-ublue     # apply (asks first)
sudo ./hurubase --continue          # only when a two-step rebase needed a reboot
./hurubase --finish                 # after the reboot: adopt the new /etc/skel
sudo ./hurubase --rollback
```

Nothing needs installing — it is one self-contained script that reads the
system it runs on.

## What it handles

- **Signature policy.** If `/etc/containers/policy.json` already trusts the
  target's repository (or accepts it, as ublue's permissive empty-repo fallback
  does), the signed rebase happens in one step. Otherwise it uses the documented
  two-step: rebase to the unsigned image, reboot, then rebase to the signed one.
- **Refusals, not warnings.** An already-staged deployment, too little space on
  `/var` or `/boot`, an image reference that will not resolve, and any
  `*-nvidia*` image all stop the run before anything changes.
- **The `/etc/skel` gap.** An atomic rebase never seeds `/etc/skel` into an
  existing `$HOME`, so the new desktop's configs never arrive and the new
  session looks bare. `--finish` writes files that are missing, leaves files
  that already exist alone, reports files that differ (or replaces them with
  `--adopt-differs`, after backing them up), and honours a per-target
  never-clobber list.
- **A stale session choice.** `~/.config/sddm/state.conf` (`LastSession=`) and
  `/var/lib/AccountsService/users/<user>` (`XSession=`) keep naming the old
  desktop's session after a rebase, which is how you end up at a black screen or
  bounced back to the greeter. Reported by default; `--finish --fix-session`
  resets them (with backups).
- **Direction and hardware.** Warns when the target is a Fedora major upgrade,
  when the target image is *older* than what you are running, when Secure Boot
  meets an unsigned kernel, and when the tag moved between the two steps of a
  two-step rebase (digest pinning; `--force` to accept).
- **Target surprises.** The plan prints what a target changes about your
  machine — a different display manager, user-level dotfile services such as
  Zirconium's chezmoi units, systemd presets that disable sshd.

## Targets

| Target | Desktop | Display manager |
|---|---|---|
| `hurunagus-hyprland` *(flagship)* | Hyprland + Omarchy | SDDM |
| `hurunagus-ublue` | niri + DMS | greetd |
| `hurunagus-silverblue` | niri + DMS | GDM |
| `zirconium` / `zirconium-jackrabbit` | niri + DMS | greetd |
| `bluefin`, `ublue-silverblue` | GNOME | GDM |
| `bazzite`, `aurora`, `kinoite` | KDE Plasma | SDDM |
| `bazzite-gnome` | GNOME | GDM |

`--image <ref>` takes any other image reference. Refused by design: every
`*-nvidia*` image, and the retired `hurunagus`, `hurunagus-umbriel` and
`hurunagus-hyprland-dms` images.

## What it never does

Deletes anything. Prunes a deployment. Edits `/etc/containers/policy.json` or
any other system file. Writes outside `$HOME` during `--finish`. Reboots without
asking. Proceeds past a refusal.

## Tests

```sh
test/hurubase-test.sh    # 103 checks; fake rpm-ostree/bootc/skopeo/systemctl/df,
                         # a fixture /etc, $HOME and /etc/skel — nothing real is touched
```

GitHub Actions runs the same suite on `ubuntu-24.04`, plus `bash -n`, shellcheck
(warning and up) on both scripts, the executable bit and shebang, and a check
that this README lists every target `--list` knows about.

Every environment seam (fixtures, command paths, dry-run, root gate) is
documented in the header of `hurubase`.
