#!/bin/sh
# Runtime half of the Wi-Fi + Tailscale kexec image.
#
# nixos-anywhere uploads this tarball to the target and executes this script on
# the running Debian system. We append sensitive, target-local state to the
# initrd on the target immediately before kexec, so secrets do not enter the
# flake or the Nix store.

set -eux
if set -o | grep -q pipefail; then
  set -o pipefail
fi

kexec_extra_flags=""

while [ $# -gt 0 ]; do
  case "$1" in
  --kexec-extra-flags)
    kexec_extra_flags="$2"
    shift
    ;;
  esac
  shift
done

init="@init@"
kernelParams="@kernelParams@"

SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
INITRD_TMP=$(TMPDIR="$SCRIPT_DIR" mktemp -d)

cleanup() {
  rm -rf "$INITRD_TMP"
}
trap cleanup EXIT

copy_dir_contents() {
  src="$1"
  dst="$2"
  if [ -d "$src" ]; then
    mkdir -p "$dst"
    cp -a "$src"/. "$dst"/
  fi
}

copy_file() {
  src="$1"
  dst="$2"
  if [ -f "$src" ]; then
    mkdir -p "$(dirname "$dst")"
    cp -a "$src" "$dst"
  fi
}

extractPubKeys() {
  home="$1"
  for file in .ssh/authorized_keys .ssh/authorized_keys2; do
    key="$home/$file"
    if [ -e "$key" ]; then
      grep -o '\(\(ssh\|ecdsa\|sk\)-[^ ]* .*\)' "$key" >> "$INITRD_TMP/ssh/authorized_keys" || true
    fi
  done
}

mkdir -p "$INITRD_TMP/ssh"
extractPubKeys /root

if [ -n "${DOAS_USER-}" ]; then
  SUDO_USER="$DOAS_USER"
fi

if [ -n "${SUDO_USER-}" ]; then
  sudo_home=$(sh -c "echo ~$SUDO_USER")
  extractPubKeys "$sudo_home"
fi

if [ -e /etc/ssh/authorized_keys.d/root ]; then
  cat /etc/ssh/authorized_keys.d/root >> "$INITRD_TMP/ssh/authorized_keys"
fi
if [ -n "${SUDO_USER-}" ] && [ -e "/etc/ssh/authorized_keys.d/$SUDO_USER" ]; then
  cat "/etc/ssh/authorized_keys.d/$SUDO_USER" >> "$INITRD_TMP/ssh/authorized_keys"
fi

for p in /etc/ssh/ssh_host_*; do
  [ -e "$p" ] || continue
  cp -a "$p" "$INITRD_TMP/ssh/"
done

"$SCRIPT_DIR/ip" --json addr > "$INITRD_TMP/addrs.json"
"$SCRIPT_DIR/ip" -4 --json route > "$INITRD_TMP/routes-v4.json"
"$SCRIPT_DIR/ip" -6 --json route > "$INITRD_TMP/routes-v6.json"

copy_file /etc/machine-id "$INITRD_TMP/machine-id"

# Preserve Wi-Fi state for the installer environment.
copy_dir_contents /etc/NetworkManager/system-connections "$INITRD_TMP/etc/NetworkManager/system-connections"
copy_dir_contents /etc/iwd "$INITRD_TMP/etc/iwd"
copy_file /etc/wpa_supplicant/wpa_supplicant.conf "$INITRD_TMP/etc/wpa_supplicant/wpa_supplicant.conf"
copy_file /etc/wpa_supplicant.conf "$INITRD_TMP/etc/wpa_supplicant.conf"

# Preserve Tailscale identity, so the kexec environment should come back as the
# same tailnet node and keep the same Tailscale IP.
copy_file /var/lib/tailscale/tailscaled.state "$INITRD_TMP/var/lib/tailscale/tailscaled.state"

if [ -d "$INITRD_TMP/etc/NetworkManager/system-connections" ]; then
  chmod 700 "$INITRD_TMP/etc/NetworkManager/system-connections"
  find "$INITRD_TMP/etc/NetworkManager/system-connections" -type f -exec chmod 600 {} \; 2>/dev/null || true
fi
if [ -f "$INITRD_TMP/var/lib/tailscale/tailscaled.state" ]; then
  chmod 600 "$INITRD_TMP/var/lib/tailscale/tailscaled.state"
fi

(
  cd "$INITRD_TMP"
  find . | cpio -o -H newc | gzip -9 >> "$SCRIPT_DIR/initrd"
)

kexecSyscallFlags=""
if printf "%s\n" "6.1" "$(uname -r)" | sort -c -V 2>&1; then
  kexecSyscallFlags="--kexec-syscall-auto"
fi

if ! sh -c "'$SCRIPT_DIR/kexec' --load '$SCRIPT_DIR/bzImage' \
  $kexecSyscallFlags \
  $kexec_extra_flags \
  --initrd='$SCRIPT_DIR/initrd' --no-checks \
  --command-line 'init=$init $kernelParams'"
then
  echo "kexec failed, dumping dmesg" >&2
  dmesg | tail -n 100
  exit 1
fi

echo "machine will boot into nixos in 6s..."
if [ -e /dev/kmsg ]; then
  exec > /dev/kmsg 2>&1
else
  exec > /dev/null 2>&1
fi

nohup sh -c "sleep 6 && '$SCRIPT_DIR/kexec' -e ${kexec_extra_flags}" &
