# Disko configuration for hp348.
# WARNING: nixos-anywhere will wipe both disks and apply this layout.
# /dev/sda is the 500GB external USB drive.
# The Intel Optane NVMe is a dedicated local data disk.
{
  disko.devices = {
    disk.main = {
      device = "/dev/sda";
      type = "disk";

      content = {
        type = "gpt";

        partitions = {
          ESP = {
            size = "512M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [
                "umask=0077"
              ];
            };
          };

          swap = {
            size = "8G";
            content = {
              type = "swap";
              resumeDevice = true;
            };
          };

          root = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };
        };
      };
    };

    disk.nvme = {
      device = "/dev/disk/by-id/nvme-INTEL_MEMPEK1J016GA_BTBT83041CQ0016N";
      type = "disk";

      content = {
        type = "gpt";
        partitions.data = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/home/duck/nvme";
            mountOptions = [
              "defaults"
              "nofail"
              "x-systemd.automount"
              "x-systemd.device-timeout=5s"
            ];
          };
        };
      };
    };
  };
}
