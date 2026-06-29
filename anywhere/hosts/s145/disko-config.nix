# Disko configuration for s145.
# WARNING: nixos-anywhere will wipe the selected device.
# Verify the target with:
#   lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
#
# s145 has an NVMe SSD (/dev/nvme0n1, ~238G) and a 1TB HDD (/dev/sda).
# Only the NVMe is managed here.
{
  disko.devices = {
    disk.main = {
      device = "/dev/nvme0n1";
      type = "disk";

      content = {
        type = "gpt";

        partitions = {
          esp = {
            size = "1G";
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
            size = "6G";
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
  };
}
