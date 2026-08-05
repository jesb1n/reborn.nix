# profiles/smartd.nix — SMART disk health monitoring for bare-metal hosts
#
# Import only on physical machines (s145, hp348, rpi). Do not import on OCI
# VMs — cloud block devices usually lack useful SMART data.
{
  # Surface impending disk failure before data loss.
  services.smartd = {
    enable = true;
    autodetect = true;
    notifications.test = false;
  };
}
