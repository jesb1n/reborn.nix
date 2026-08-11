# Disko configuration for hp348.
# WARNING: applying this layout destroys all data on the GIGABYTE NVMe.
# The external USB HDD is intentionally absent and remains the rollback disk.
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
}
