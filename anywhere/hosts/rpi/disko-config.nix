# Disko configuration for the Raspberry Pi.
# WARNING: nixos-anywhere will wipe the selected device.
# Verify the target with:
#   lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
#
# Raspberry Pi SD cards are usually /dev/mmcblk0. If this Pi boots from USB
# storage, change this to the matching disk, often /dev/sda.
{
  disko.devices = {
    disk.main = {
      device = "/dev/mmcblk0";
      type = "disk";

      content = {
        type = "gpt";

        partitions = {
          boot = {
            size = "512M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot/firmware";
              mountOptions = [
                "umask=0077"
              ];
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
