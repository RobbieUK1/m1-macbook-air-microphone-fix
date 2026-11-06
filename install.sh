#!/usr/bin/env bash
# M1 MacBook Air Microphone Fix — MIT licensed
set -euo pipefail

usage() {
  cat <<'HELP'
Usage: bash install.sh [--check | --uninstall | --help]
Install the read-only Secure Enclave startup fix for an M1 MacBook Air
running Linux with the Aurora apple-sep driver. No packages are downloaded.
  --check      Check compatibility without changing anything
  --uninstall  Remove this fix (takes effect after reboot)
HELP
}
mode=${1:-install}
[[ $# -le 1 ]] || { usage >&2; exit 2; }
case "$mode" in
  --help|-h) usage; exit 0 ;;
  install|--check|--uninstall) ;;
  *) usage >&2; exit 2 ;;
esac
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
[[ $(uname -s) == Linux && $(uname -m) == aarch64 ]] || fail 'This fix requires Apple Silicon Linux.'
[[ -d /run/systemd/system ]] || fail 'This fix requires systemd.'
command -v systemctl >/dev/null || fail 'systemctl is missing.'
unit=omarchy-m1-microphone.service
unit_path=/etc/systemd/system/$unit
marker='# Managed by M1 MacBook Air Microphone Fix'
# Accept the exact earlier locally installed fix when adopting or removing it.
managed_unit() {
  grep -Fxq "$marker" "$unit_path" ||
    { grep -Fxq 'Description=Start the Secure Enclave read-only for the M1 microphone' "$unit_path" &&
      grep -Fxq 'ExecStart=/usr/bin/modprobe apple-sep xart_writes=0 provision_keybag=0' "$unit_path"; }
}
if [[ -e $unit_path || -L $unit_path ]]; then
  [[ -f $unit_path && ! -L $unit_path ]] && managed_unit || fail "Refusing to replace an unrecognized $unit_path"
fi
if [[ $mode != --uninstall ]]; then
  [[ -r /proc/device-tree/compatible ]] || fail 'No Apple device tree was found.'
  grep -azqx 'apple,j313' /proc/device-tree/compatible || fail 'This installer supports only the M1 MacBook Air (J313).'
  [[ ! -e /etc/omarchy-mac/touchid-on ]] || fail 'Touch ID owns the Secure Enclave configuration on this machine.'
  [[ -d /sys/bus/platform/devices/242400000.sep ]] || fail 'The Secure Enclave device is unavailable.'
  for tool in modinfo modprobe udevadm install grep; do
    command -v "$tool" >/dev/null || fail "Required command is missing: $tool"
  done
  parameters=$(modinfo -p apple-sep) || fail 'The apple-sep driver is missing; install a compatible Aurora kernel first.'
  grep -q '^xart_writes:' <<<"$parameters" && grep -q '^provision_keybag:' <<<"$parameters" || fail 'This driver does not support the required read-only options.'
  [[ -e /dev/disk/by-partlabel/iBootSystemContainer ]] || fail 'The iBoot System Container is unavailable.'
fi
if [[ $mode == --check ]]; then
  printf 'Compatible: M1 MacBook Air (J313), systemd, and read-only driver options found.\n'
  exit 0
fi
# The complete privileged payload is supplied on stdin, so curl-to-bash and
# downloaded copies work equally well. Never download code as administrator.
if [[ $EUID -eq 0 ]]; then
  elevate=(bash)
elif command -v sudo >/dev/null && [[ -t 0 || -t 1 ]]; then
  elevate=(sudo bash)
elif command -v pkexec >/dev/null; then
  elevate=(pkexec /usr/bin/bash)
else
  fail 'Run this downloaded installer using sudo, or install pkexec.'
fi
"${elevate[@]}" -s -- "$mode" <<'ROOT'
set -euo pipefail
mode=$1
unit=omarchy-m1-microphone.service
path=/etc/systemd/system/$unit
if [[ -e $path || -L $path ]]; then
  [[ -f $path && ! -L $path ]] &&
    { grep -Fxq '# Managed by M1 MacBook Air Microphone Fix' "$path" ||
      { grep -Fxq 'Description=Start the Secure Enclave read-only for the M1 microphone' "$path" &&
        grep -Fxq 'ExecStart=/usr/bin/modprobe apple-sep xart_writes=0 provision_keybag=0' "$path"; }; } ||
    { echo 'Refusing to replace an unrecognized service.' >&2; exit 1; }
fi
if [[ $mode == --uninstall ]]; then
  if [[ -f $path ]]; then
    systemctl disable --now "$unit"
    rm -- "$path"
    systemctl daemon-reload
  fi
  echo 'Fix removed. The currently loaded driver is left running; reboot to return to the normal startup configuration.'
  exit 0
fi
[[ ! -e /etc/omarchy-mac/touchid-on ]] || { echo 'Touch ID owns this configuration.' >&2; exit 1; }
tmp=$(mktemp /etc/systemd/system/.m1-microphone.XXXXXX)
trap 'rm -f -- "$tmp"' EXIT
cat > "$tmp" <<'UNIT'
# Managed by M1 MacBook Air Microphone Fix
[Unit]
Description=Start the Secure Enclave read-only for the M1 microphone
ConditionPathExists=/sys/bus/platform/devices/242400000.sep
ConditionPathExists=!/etc/omarchy-mac/touchid-on
After=local-fs.target omarchy-mac-touchid-status.service
Before=display-manager.service

[Service]
Type=oneshot
ExecCondition=/usr/bin/grep -a -z -q -x apple,j313 /proc/device-tree/compatible
ExecStartPre=/usr/bin/udevadm wait --timeout=20 /dev/disk/by-partlabel/iBootSystemContainer
ExecStart=/usr/bin/modprobe apple-sep xart_writes=0 provision_keybag=0
TimeoutStartSec=30s
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT
chmod 0644 "$tmp"
chown root:root "$tmp"
mv -f -- "$tmp" "$path"
systemctl daemon-reload
systemctl enable --now "$unit"
echo 'Installed. The read-only microphone startup fix is enabled for future boots.'
echo 'Try recording or dictation using MacBook Microphone. Reopen the app if needed.'
ROOT
