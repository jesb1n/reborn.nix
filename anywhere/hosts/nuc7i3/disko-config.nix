# Disko configuration for nuc7i3.
# WARNING: applying this layout destroys all data on the Samsung 860 EVO SSD.
{
  disko.devices.disk.ssd = {
    device = "/dev/disk/by-id/ata-Samsung_SSD_860_EVO_500GB_S4FNNF0N153584K";
    type = "disk";

    content = {
      type = "gpt";

      partitions = {
        ESP = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };

        swap = {
          size = "8G";
          content = {
            type = "swap";
            resumeDevice = false;
          };
        };

        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
            mountOptions = [ "noatime" ];
          };
        };
      };
    };
  };
}
