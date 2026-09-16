# Disko configuration for s145.
# WARNING: applying this layout destroys all data on the GIGABYTE NVMe and WDC data SSD.
# The layout matches the existing partitions on the SSD moved from hp348.
# s145 also has a separate 512 GB data SSD.
{
  disko.devices.disk.nvme = {
    device = "/dev/disk/by-id/nvme-GIGABYTE_GP-GSM2NE3256GNTD_SN210408933996";
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

  disko.devices.disk.data = {
    device = "/dev/disk/by-id/ata-WDC_WDS500G2B0A_192878801084";
    type = "disk";

    content = {
      type = "gpt";

      partitions.data = {
        size = "100%";
        content = {
          type = "filesystem";
          format = "ext4";
          mountpoint = "/home/duck/sda";
          mountOptions = [ "noatime" ];
        };
      };
    };
  };
}
