# Disko configuration for s145.
# WARNING: nixos-anywhere will wipe /dev/nvme0n1 and apply this layout.
# s145 also has a 1TB HDD (/dev/sda) — not managed here.
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
