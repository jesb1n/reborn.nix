# profiles/smartd.nix — SMART disk health monitoring for bare-metal hosts
#
# Import only on hosts whose disks expose SMART (s145 and nuc7i3).
# Do not import on OCI VMs or SD-card-backed hosts such as rpi.
{ pkgs, ... }:
{
  # Surface impending disk failure before data loss.
  services.smartd = {
    enable = true;
    autodetect = true;
    notifications.test = false;
  };

  # smartd runs from the store; put smartctl on PATH for ad-hoc checks
  # (`sudo smartctl -t short /dev/sda`, `smartctl -H`, ...).
  environment.systemPackages = [ pkgs.smartmontools ];
}
