#!/usr/bin/env bash
# Let bubblewrap (bwrap) create user namespaces on Ubuntu 23.10+, so that the
# sandbox of `lake check` works.
#
# Ubuntu sets kernel.apparmor_restrict_unprivileged_userns=1. Then a program
# gets no capabilities in a new user namespace, unless an AppArmor profile
# grants it `userns`. This script installs such a profile for /usr/bin/bwrap
# only. It uses the same pattern as Ubuntu's own /etc/apparmor.d/flatpak.
#
# Usage:   sudo scripts/setup-bwrap-apparmor.sh
# Undo:    sudo scripts/setup-bwrap-apparmor.sh --remove
#
# Trade-off: every local program can use bwrap to get a user namespace.
# Details: wiki/lean/toolchain-v4-35.md

set -euo pipefail

BWRAP=/usr/bin/bwrap
PROFILE=/etc/apparmor.d/bwrap

if [[ $EUID -ne 0 ]]; then
  echo "error: run as root: sudo $0 ${*:-}" >&2
  exit 1
fi

if [[ ${1:-} == "--remove" ]]; then
  if [[ -f $PROFILE ]]; then
    apparmor_parser -R "$PROFILE" || true
    rm -f "$PROFILE"
    echo "Removed $PROFILE and unloaded the profile."
  else
    echo "Nothing to remove: $PROFILE does not exist."
  fi
  exit 0
fi

if [[ ! -x $BWRAP ]]; then
  echo "error: $BWRAP not found. Install it: apt install bubblewrap" >&2
  exit 1
fi

if [[ -e $PROFILE ]] && ! grep -q "cats-effect-in-lean" "$PROFILE"; then
  echo "error: $PROFILE exists and was not made by this script. Not changing it." >&2
  exit 1
fi

cat > "$PROFILE" <<'EOF'
# Installed by cats-effect-in-lean/scripts/setup-bwrap-apparmor.sh
# This profile allows everything. It only gives bwrap the `userns`
# permission, so that `lake check` can build its sandbox.

abi <abi/4.0>,
include <tunables/global>

profile bwrap /usr/bin/bwrap flags=(unconfined) {
  userns,

  # Site-specific additions and overrides. See local/README for details.
  include if exists <local/bwrap>
}
EOF
chmod 644 "$PROFILE"

apparmor_parser -r "$PROFILE"
echo "Installed and loaded $PROFILE."

# Test as the normal user (not root), because root does not need userns.
TEST_USER=${SUDO_USER:-}
if [[ -n $TEST_USER && $TEST_USER != root ]]; then
  if sudo -u "$TEST_USER" "$BWRAP" --unshare-user --ro-bind / / true; then
    echo "OK: bwrap creates a sandbox as user '$TEST_USER'."
  else
    echo "FAIL: bwrap still cannot create a sandbox as user '$TEST_USER'." >&2
    exit 1
  fi
else
  echo "Skipped the test (no SUDO_USER). Test it yourself: bwrap --unshare-user --ro-bind / / true"
fi
