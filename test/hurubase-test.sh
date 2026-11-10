#!/usr/bin/env bash
# hurubase test suite.
#
# Fully sandboxed: fake rpm-ostree / bootc / skopeo / systemctl / df / mokutil, a
# fixture /etc, a fixture $HOME and a fixture /etc/skel, all under one temp dir.
# Nothing outside the sandbox is read, and nothing is written outside it.
#
# Run: test/hurubase-test.sh

set -uo pipefail

HERE=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT=$HERE/hurubase
SB=$(mktemp -d "${TMPDIR:-/tmp}/hurubase-test.XXXXXX")
trap 'rm -rf "$SB"' EXIT

PASS=0
FAIL=0
CURRENT=""
FAILED_NAMES=()

# --------------------------------------------------------------------------- #
# harness
# --------------------------------------------------------------------------- #

t() {
  CURRENT=$1
  t_failed=0
}
ok() { PASS=$((PASS + 1)); }
bad() {
  FAIL=$((FAIL + 1))
  t_failed=1
  printf 'FAIL  %s\n      %s\n' "$CURRENT" "$1"
  [[ " ${FAILED_NAMES[*]} " == *" $CURRENT "* ]] || FAILED_NAMES+=("$CURRENT")
}

assert_rc() {
  local want=$1
  [[ $RC == "$want" ]] && ok || bad "expected exit $want, got $RC (output: $(tr '\n' '|' <<<"$OUT" | cut -c1-400))"
}
assert_contains() { [[ $OUT == *"$1"* ]] && ok || bad "output does not contain: $1 ... $(tr '\n' '|' <<<"$OUT" | cut -c1-400)"; }
assert_not_contains() { [[ $OUT != *"$1"* ]] && ok || bad "output should not contain: $1"; }
assert_file() { [[ -e $1 ]] && ok || bad "expected file: $1"; }
assert_no_file() { [[ ! -e $1 ]] && ok || bad "file should not exist: $1"; }
assert_content() { [[ -r $1 && $(cat "$1") == "$2" ]] && ok || bad "expected $1 to be '$2' (got '$( [[ -r $1 ]] && cat "$1" || echo '<missing>')')"; }
assert_is_link() { [[ -L $1 && $(readlink "$1") == "$2" ]] && ok || bad "expected symlink $1 -> $2"; }
assert_glob_count() {
  local pat=$1 want=$2 n
  n=$(find $(dirname "$pat") -maxdepth 1 -name "$(basename "$pat")" 2>/dev/null | wc -l)
  [[ $n == "$want" ]] && ok || bad "expected $want matches for $pat, got $n"
}
assert_logged() {
  grep -qxF "$1" "$SB/log/fake.log" && ok ||
    bad "expected the fake commands to run: $1 (log: $(tr '\n' '|' <"$SB/log/fake.log"))"
}
assert_not_logged() {
  grep -qF "$1" "$SB/log/fake.log" && bad "command should not have run: $1" || ok
}

run() {
  OUT=$(env "${ENVS[@]}" "${EXTRA[@]}" bash "$SCRIPT" "$@" 2>&1)
  RC=$?
}

# --------------------------------------------------------------------------- #
# fixtures
# --------------------------------------------------------------------------- #

ENVS=()
EXTRA=()
FAB=$SB/fab
mkdir -p "$FAB" "$SB/etc/containers" "$SB/etc/pki/containers" "$SB/etc/systemd/system" \
  "$SB/home" "$SB/skel" "$SB/varstate" "$SB/accounts" "$SB/sessions" "$SB/fixtures" \
  "$SB/var" "$SB/boot" "$SB/log"

cat >"$SB/etc/os-release" <<'EOF'
NAME="hurunagus-hyprland"
VERSION="45.20261109.0 (Forty Five)"
VERSION_ID=45
ID=fedora
EOF

cat >"$SB/etc/containers/policy.json" <<'EOF'
{
  "default": [{"type": "reject"}],
  "transports": {
    "docker": {
      "ghcr.io/ublue-os": [{"type": "sigstoreSigned", "keyPath": "/etc/pki/containers/ublue-os.pub"}],
      "": [{"type": "insecureAcceptAnything"}]
    }
  }
}
EOF
: >"$SB/etc/pki/containers/ublue-os.pub"
ln -sf /usr/lib/systemd/system/sddm.service "$SB/etc/systemd/system/display-manager.service"

# a policy that trusts nothing: forces the two-step
cat >"$SB/fixtures/policy-strict.json" <<'EOF'
{
  "default": [{"type": "reject"}],
  "transports": {"docker": {}}
}
EOF

cat >"$SB/fixtures/ostree-booted-hyprland.json" <<'EOF'
{"deployments": [
  {"booted": true, "staged": false, "version": "latest.20261109-107d504",
   "container-image-reference": "ostree-image-signed:docker://ghcr.io/wegweg7979/hurunagus-hyprland:latest",
   "origin": "ostree-image-signed:docker://ghcr.io/wegweg7979/hurunagus-hyprland:latest"},
  {"booted": false, "staged": false, "version": "latest.20261108-dd111f3",
   "container-image-reference": "ostree-image-signed:docker://ghcr.io/wegweg7979/hurunagus-hyprland:latest"}
]}
EOF

sed 's/"booted": false, "staged": false, "version": "latest.20261108-dd111f3"/"booted": false, "staged": true, "version": "latest.20261110-e9af102"/' \
  "$SB/fixtures/ostree-booted-hyprland.json" >"$SB/fixtures/ostree-staged.json"

cat >"$SB/fixtures/ostree-booted-ublue-unsigned.json" <<'EOF'
{"deployments": [
  {"booted": true, "staged": false, "version": "20261110",
   "container-image-reference": "ostree-unverified-registry:ghcr.io/wegweg7979/hurunagus-ublue:latest"}
]}
EOF

cat >"$SB/fixtures/ostree-booted-ublue-signed.json" <<'EOF'
{"deployments": [
  {"booted": true, "staged": false, "version": "20261110",
   "container-image-reference": "ostree-image-signed:docker://ghcr.io/wegweg7979/hurunagus-ublue:latest"}
]}
EOF

cat >"$SB/fixtures/ostree-booted-zirconium.json" <<'EOF'
{"deployments": [
  {"booted": true, "staged": false, "version": "44.20261109.0",
   "container-image-reference": "ostree-image-signed:docker://ghcr.io/zirconium-dev/zirconium:latest"}
]}
EOF

cat >"$SB/fixtures/skopeo-ublue.json" <<'EOF'
{"Digest": "sha256:bbbb1111", "Labels": {"org.opencontainers.image.version": "44.20260825.0", "org.opencontainers.image.created": "2026-08-25T06:00:00Z"}}
EOF
cat >"$SB/fixtures/skopeo-ublue-moved.json" <<'EOF'
{"Digest": "sha256:cccc2222", "Labels": {"org.opencontainers.image.version": "44.20261110.0", "org.opencontainers.image.created": "2026-11-10T06:00:00Z"}}
EOF
cat >"$SB/fixtures/skopeo-flagship.json" <<'EOF'
{"Digest": "sha256:aaaa9999", "Labels": {"org.opencontainers.image.version": "45.20261110.0", "org.opencontainers.image.created": "2026-11-10T06:00:00Z"}}
EOF
cat >"$SB/fixtures/skopeo-zirconium.json" <<'EOF'
{"Digest": "sha256:dddd3333", "Labels": {"org.opencontainers.image.version": "44.20261101.0", "org.opencontainers.image.created": "2026-11-01T06:00:00Z"}}
EOF
cat >"$SB/fixtures/skopeo-nolabels.json" <<'EOF'
{"Digest": "sha256:eeee4444", "Labels": {}}
EOF

# ---- fake commands ---------------------------------------------------------
cat >"$FAB/rpm-ostree" <<'EOF'
#!/bin/bash
printf 'rpm-ostree %s\n' "$*" >>"${FAKE_LOG:-/dev/null}"
case "${1:-}" in
status)
  [[ -n ${FAKE_OSTREE_JSON:-} ]] && cat "$FAKE_OSTREE_JSON"
  ;;
esac
exit 0
EOF

cat >"$FAB/bootc" <<'EOF'
#!/bin/bash
printf 'bootc %s\n' "$*" >>"${FAKE_LOG:-/dev/null}"
case "${1:-}" in
status)
  [[ -n ${FAKE_BOOTC_JSON:-} ]] && cat "$FAKE_BOOTC_JSON"
  ;;
esac
exit 0
EOF

cat >"$FAB/skopeo" <<'EOF'
#!/bin/bash
printf 'skopeo %s\n' "$*" >>"${FAKE_LOG:-/dev/null}"
if [[ ${FAKE_SKOPEO_FAIL:-0} == 1 ]]; then
  echo "skopeo: no such host / unauthorized reference" >&2
  exit 1
fi
cat "${FAKE_SKOPEO_JSON:-/dev/null}"
exit 0
EOF

cat >"$FAB/systemctl" <<'EOF'
#!/bin/bash
printf 'systemctl %s\n' "$*" >>"${FAKE_LOG:-/dev/null}"
if [[ ${1:-} == is-enabled ]]; then
  unit=${2%.service}
  for u in ${FAKE_DM_ENABLED:-sddm}; do
    [[ $u == "$unit" ]] && exit 0
  done
  exit 1
fi
exit 0
EOF

cat >"$FAB/df" <<'EOF'
#!/bin/bash
kb=${FAKE_FREE_VAR_KB:-20000000}
case "$*" in
*boot*) kb=${FAKE_FREE_BOOT_KB:-500000} ;;
esac
printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/fake 40000000 100 %s 1%% /\n' "$kb"
EOF

cat >"$FAB/mokutil" <<'EOF'
#!/bin/bash
echo "SecureBoot ${FAKE_SB:-enabled}"
EOF
chmod +x "$FAB"/*

# ---- fixture $HOME / skel / accounts ---------------------------------------
printf 'XSession=hurunagus\nSystemAccount=false\n' >"$SB/accounts/dan"
: >"$SB/sessions/hurunagus.desktop"
: >"$SB/sessions/gnome.desktop"

mkdir -p "$SB/skel/a" "$SB/skel/b" "$SB/skel/.config/niri"
printf 'new\n' >"$SB/skel/a/new.conf"
printf 'same\n' >"$SB/skel/b/same.conf"
printf 'stock\n' >"$SB/skel/b/diff.conf"
ln -s /usr/share/backgrounds/hurunagus/leaf.jpg "$SB/skel/link.conf"
printf 'user-tuned\n' >"$SB/skel/.config/niri/local.kdl"
printf 'weird\n' >"$SB/skel/weird..name"

printf 'same\n' >"$SB/home/b-same-placeholder" 2>/dev/null || true
mkdir -p "$SB/home/b" "$SB/home/.config"
printf 'same\n' >"$SB/home/b/same.conf"
printf 'mine\n' >"$SB/home/b/diff.conf"

base_env() {
  ENVS=(
    HURUBASE_ETC="$SB/etc"
    HURUBASE_OS_RELEASE="$SB/etc/os-release"
    HURUBASE_POLICY="$SB/etc/containers/policy.json"
    HURUBASE_HOME="$SB/home"
    HURUBASE_SKEL="$SB/skel"
    HURUBASE_SESSIONS_DIR="$SB/sessions"
    HURUBASE_ACCOUNTS_DIR="$SB/accounts"
    HURUBASE_VAR_STATE="$SB/varstate"
    HURUBASE_RPM_OSTREE="$FAB/rpm-ostree"
    HURUBASE_BOOTC="$FAB/bootc"
    HURUBASE_SKOPEO="$FAB/skopeo"
    HURUBASE_SYSTEMCTL="$FAB/systemctl"
    HURUBASE_DF="$FAB/df"
    HURUBASE_MOKUTIL="$FAB/mokutil"
    HURUBASE_TTY="$SB/no-such-tty"
    HURUBASE_EUID=0
    HURUBASE_BOOT_PART="$SB/boot"
    HURUBASE_VAR_PART="$SB/var"
    FAKE_LOG="$SB/log/fake.log"
    FAKE_OSTREE_JSON="$SB/fixtures/ostree-booted-hyprland.json"
    FAKE_SKOPEO_JSON="$SB/fixtures/skopeo-ublue.json"
    FAKE_DM_ENABLED="sddm"
    FAKE_SB="enabled"
  )
  EXTRA=()
}
reset_state() { rm -f "$SB/varstate/state"; : >"$SB/log/fake.log"; }

base_env

# --------------------------------------------------------------------------- #
# tests
# --------------------------------------------------------------------------- #

t "--list shows the flagship first, the known targets, and no retired/nvidia rows"
run --list
assert_rc 0
# assert against the TABLE region only (the footer deliberately names what is refused)
OUT_TABLE=$(sed -n '1,/^$/p' <<<"$OUT")
OUT_SAVED=$OUT
OUT=$OUT_TABLE
assert_contains "[flagship]"
assert_contains "zirconium"
assert_contains "ghcr.io/ublue-os/aurora:latest"
assert_not_contains "nvidia"
assert_not_contains "umbriel"
assert_not_contains "hyprland-dms"
OUT=$OUT_SAVED
assert_contains "Unsupported by design"

t "--help documents the dangerous flags"
run --help
assert_rc 0
assert_contains "--adopt-differs"
assert_contains "--fix-session"
assert_contains "Refused by design: any *-nvidia* image."

t "an nvidia image is refused, not warned about"
run --image ghcr.io/ublue-os/bluefin-nvidia:latest --check
assert_rc 1
assert_contains "NVIDIA images are not supported"

t "an nvidia image passed by name is refused before any registry call"
run --image ghcr.io/zirconium-dev/zirconium-nvidia:latest --check
assert_rc 1
assert_contains "NVIDIA images are not supported"

t "--check on a stale, older target plans the signed path and warns backwards + stale"
run hurunagus-ublue --check
assert_rc 0
assert_contains "policy.json already permits ghcr.io/wegweg7979/hurunagus-ublue"
assert_contains "moves the OS BACKWARDS"
assert_contains "older than the running deployment"
assert_contains "display manager changes: sddm.service -> greetd.service"
assert_contains "Preflight only (--check): nothing was changed."
assert_not_contains "hurubase --continue"

t "--check on the flagship does not warn about a version change"
EXTRA=(FAKE_SKOPEO_JSON="$SB/fixtures/skopeo-flagship.json")
run hurunagus-hyprland --check
assert_rc 0
assert_contains "Target"
assert_not_contains "BACKWARDS"
assert_not_contains "MAJOR version upgrade"
EXTRA=()

t "a staged deployment is refused"
EXTRA=(FAKE_OSTREE_JSON="$SB/fixtures/ostree-staged.json")
run hurunagus-ublue --check
assert_rc 1
assert_contains "a deployment is already staged"
EXTRA=()

t "not enough free space is refused"
EXTRA=(FAKE_FREE_VAR_KB=1024)
run hurunagus-ublue --check
assert_rc 1
assert_contains "at least 8192 MiB is required"
EXTRA=()

t "an unresolvable target is refused (fail closed)"
EXTRA=(FAKE_SKOPEO_FAIL=1)
run hurunagus-ublue --check
assert_rc 1
assert_contains "cannot resolve ghcr.io/wegweg7979/hurunagus-ublue:latest"
EXTRA=()

t "a strict policy forces the documented two-step"
EXTRA=(HURUBASE_POLICY="$SB/fixtures/policy-strict.json")
run hurunagus-ublue --check
assert_rc 0
assert_contains "the documented two-step is used"
assert_contains "step 2  reboot, then 'hurubase --continue'"
EXTRA=()

t "an unknown image is accepted but flagged as unknown desktop"
run --image ghcr.io/example/some-atomic:latest --check
assert_rc 0
assert_contains "not in the target table"

t "a target whose registry metadata carries no version label still plans cleanly"
EXTRA=(FAKE_SKOPEO_JSON="$SB/fixtures/skopeo-nolabels.json")
run --image ghcr.io/zirconium-dev/zirconium:latest --check
assert_rc 0
assert_contains "Preflight only (--check): nothing was changed."
EXTRA=()

t "an undeterminable free space is warned about, not silently skipped"
EXTRA=(FAKE_FREE_VAR_KB=notanumber)
run hurunagus-ublue --check
assert_rc 0
assert_contains "space guard did not run"
EXTRA=()

t "--dry-run prints the rebase command and writes no state"
reset_state
run hurunagus-ublue --dry-run --yes
assert_rc 0
assert_contains "rpm-ostree rebase ostree-image-signed:docker://ghcr.io/wegweg7979/hurunagus-ublue:latest"
assert_contains "dry run: state not written"
assert_no_file "$SB/varstate/state"

t "applying under a strict policy runs the unsigned first step and records step 1"
reset_state
EXTRA=(HURUBASE_POLICY="$SB/fixtures/policy-strict.json")
run hurunagus-ublue --yes
assert_rc 0
assert_logged "rpm-ostree rebase ostree-unverified-registry:ghcr.io/wegweg7979/hurunagus-ublue:latest"
assert_contains "step 1"
grep -q '^step=1$' "$SB/varstate/state" && ok || bad "state should record step=1"
grep -q '^target=hurunagus-ublue$' "$SB/varstate/state" && ok || bad "state should record the target"
grep -q '^digest=sha256:bbbb1111$' "$SB/varstate/state" && ok || bad "state should pin the resolved digest"
EXTRA=()

t "--status reports the pending step"
run --status
assert_rc 0
assert_contains "step    1"
assert_contains "--continue"

t "--continue refuses while the booted deployment is not the target"
run --continue
assert_rc 1
assert_contains "not the rebase target"

t "--continue on the unverified target applies the signed rebase and records step 2"
reset_state
printf 'step=1\ntarget=hurunagus-ublue\nref=ghcr.io/wegweg7979/hurunagus-ublue:latest\ndigest=sha256:bbbb1111\nsession=\n' >"$SB/varstate/state"
EXTRA=(FAKE_OSTREE_JSON="$SB/fixtures/ostree-booted-ublue-unsigned.json")
run --continue --yes
assert_rc 0
assert_logged "rpm-ostree rebase ostree-image-signed:docker://ghcr.io/wegweg7979/hurunagus-ublue:latest"
grep -q '^step=2$' "$SB/varstate/state" && ok || bad "state should record step=2"
EXTRA=()

t "--continue refuses when the tag moved since step 1"
reset_state
printf 'step=1\ntarget=hurunagus-ublue\nref=ghcr.io/wegweg7979/hurunagus-ublue:latest\ndigest=sha256:bbbb1111\n' >"$SB/varstate/state"
EXTRA=(FAKE_OSTREE_JSON="$SB/fixtures/ostree-booted-ublue-unsigned.json" FAKE_SKOPEO_JSON="$SB/fixtures/skopeo-ublue-moved.json")
run --continue --yes
assert_rc 1
assert_contains "the tag moved"
EXTRA=()

t "--continue --force accepts the moved tag"
reset_state
printf 'step=1\ntarget=hurunagus-ublue\nref=ghcr.io/wegweg7979/hurunagus-ublue:latest\ndigest=sha256:bbbb1111\n' >"$SB/varstate/state"
EXTRA=(FAKE_OSTREE_JSON="$SB/fixtures/ostree-booted-ublue-unsigned.json" FAKE_SKOPEO_JSON="$SB/fixtures/skopeo-ublue-moved.json")
run --continue --yes --force
assert_rc 0
assert_contains "digest moved"
EXTRA=()

t "--finish refuses when the booted deployment is not the recorded target"
reset_state
printf 'step=2\ntarget=hurunagus-ublue\nref=ghcr.io/wegweg7979/hurunagus-ublue:latest\n' >"$SB/varstate/state"
run --finish
assert_rc 1
assert_contains "not the recorded target"

t "--finish adopts missing files, leaves identical ones, reports differing ones, and honours the never-clobber list"
reset_state
printf 'step=2\ntarget=zirconium\nref=ghcr.io/zirconium-dev/zirconium:latest\ndigest=sha256:dddd3333\nsession=\n' >"$SB/varstate/state"
EXTRA=(FAKE_OSTREE_JSON="$SB/fixtures/ostree-booted-zirconium.json" FAKE_SKOPEO_JSON="$SB/fixtures/skopeo-zirconium.json")
run --finish
assert_rc 0
assert_file "$SB/home/a/new.conf"
assert_is_link "$SB/home/link.conf" "/usr/share/backgrounds/hurunagus/leaf.jpg"
assert_content "$SB/home/b/diff.conf" "mine"
assert_no_file "$SB/home/.config/niri/local.kdl"
assert_no_file "$SB/home/weird.name"
assert_contains "already identical 1"
assert_contains "differs, left alone: ~/b/diff.conf"
assert_contains "kept (never-clobber): ~/.config/niri/local.kdl"
assert_contains "skipping 'weird..name' (unsafe path)"
assert_contains "re-run with --adopt-differs"
assert_no_file "$SB/varstate/state"
EXTRA=()

t "--finish --adopt-differs backs the file up before replacing it"
reset_state
printf 'step=2\ntarget=zirconium\nref=ghcr.io/zirconium-dev/zirconium:latest\n' >"$SB/varstate/state"
printf 'mine\n' >"$SB/home/b/diff.conf"
EXTRA=(FAKE_OSTREE_JSON="$SB/fixtures/ostree-booted-zirconium.json" FAKE_SKOPEO_JSON="$SB/fixtures/skopeo-zirconium.json")
run --finish --adopt-differs
assert_rc 0
assert_content "$SB/home/b/diff.conf" "stock"
assert_glob_count "$SB/home/b/diff.conf.pre-rebase-*" 1
assert_contains "replaced (backed up): ~/b/diff.conf"
EXTRA=()

t "--finish leaves nothing outside the target home and never deletes"
reset_state
printf 'step=2\ntarget=zirconium\nref=ghcr.io/zirconium-dev/zirconium:latest\n' >"$SB/varstate/state"
skel_hash_before=$(find "$SB/skel" | sort | md5sum)
EXTRA=(FAKE_OSTREE_JSON="$SB/fixtures/ostree-booted-zirconium.json" FAKE_SKOPEO_JSON="$SB/fixtures/skopeo-zirconium.json")
run --finish
assert_rc 0
skel_hash_after=$(find "$SB/skel" | sort | md5sum)
[[ $skel_hash_before == "$skel_hash_after" ]] && ok || bad "/etc/skel was modified"
assert_file "$SB/home/b/diff.conf"
EXTRA=()

t "--finish --fix-session rewrites a stale XSession and backs the record up"
reset_state
printf 'XSession=gnome\nSystemAccount=false\n' >"$SB/accounts/dan"
printf 'step=2\ntarget=hurunagus-hyprland\nref=ghcr.io/wegweg7979/hurunagus-hyprland:latest\n' >"$SB/varstate/state"
EXTRA=(FAKE_OSTREE_JSON="$SB/fixtures/ostree-booted-hyprland.json" FAKE_SKOPEO_JSON="$SB/fixtures/skopeo-flagship.json")
run --finish --fix-session --no-adopt
assert_rc 0
grep -q '^XSession=hurunagus$' "$SB/accounts/dan" && ok || bad "XSession was not reset to hurunagus"
assert_glob_count "$SB/accounts/dan.pre-rebase-*" 1
assert_contains "set XSession=hurunagus"
EXTRA=()

t "--fix-session is reported (not applied) by a plain --finish"
reset_state
printf 'XSession=gnome\nSystemAccount=false\n' >"$SB/accounts/dan"
printf 'step=2\ntarget=hurunagus-hyprland\nref=ghcr.io/wegweg7979/hurunagus-hyprland:latest\n' >"$SB/varstate/state"
EXTRA=(FAKE_OSTREE_JSON="$SB/fixtures/ostree-booted-hyprland.json" FAKE_SKOPEO_JSON="$SB/fixtures/skopeo-flagship.json")
run --finish
assert_rc 0
assert_contains "recorded: dan: XSession=gnome"
assert_contains "sudo hurubase --finish --fix-session"
grep -q '^XSession=gnome$' "$SB/accounts/dan" && ok || bad "a plain --finish must not rewrite XSession"
EXTRA=()

t "--finish with no state and no target refuses"
reset_state
run --finish
assert_rc 1
assert_contains "no rebase state"

t "--rollback refuses without root"
reset_state
EXTRA=(HURUBASE_EUID=1000)
run --rollback --yes
assert_rc 1
assert_contains "rollback needs root"
EXTRA=()

t "--rollback asks and runs rpm-ostree rollback"
reset_state
: >"$SB/log/fake.log"
run --rollback --yes
assert_rc 0
assert_logged "rpm-ostree rollback"

t "applying without root is refused"
reset_state
EXTRA=(HURUBASE_EUID=1000)
run hurunagus-ublue --yes
assert_rc 1
assert_contains "needs root"
EXTRA=()

t "an unreadable policy falls back to the two-step instead of assuming trust"
EXTRA=(HURUBASE_POLICY="$SB/fixtures/nope.json")
run hurunagus-ublue --check
assert_rc 0
assert_contains "no-policy-file"
EXTRA=()

# --------------------------------------------------------------------------- #
# summary
# --------------------------------------------------------------------------- #

printf '\n%s\n' "-----------------------------------------"
printf 'checks passed: %d, failed: %d\n' "$PASS" "$FAIL"
if ((FAIL)); then
  printf 'failing tests:\n'
  for n in "${FAILED_NAMES[@]}"; do printf '  - %s\n' "$n"; done
  exit 1
fi
exit 0
