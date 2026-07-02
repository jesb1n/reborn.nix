# hosts/s145/samba.nix — SMB access to the local 1 TB HDD.
#
# After first deploy, create the Samba password for the existing Unix user:
#   sudo smbpasswd -a duck
{ config, pkgs, ... }:

{
  services.samba = {
    enable = true;
    openFirewall = true;
    nmbd.enable = false;

    settings = {
      global = {
        "server string" = config.networking.hostName;
        "netbios name" = config.networking.hostName;
        "server role" = "standalone server";
        "workgroup" = "WORKGROUP";
        "security" = "user";
        "map to guest" = "Never";
        "usershare allow guests" = "no";

        # Allow authenticated clients from the Tailnet and normal private LANs.
        "hosts allow" = "100.64.0.0/10 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 127.0.0.1 ::1";
        "hosts deny" = "0.0.0.0/0 ::/0";

        # Modern SMB only; SMB1 is slow and unsafe.
        "server min protocol" = "SMB2_10";
        "server max protocol" = "SMB3";
        "server smb encrypt" = "desired";

        # Keep the service lean: this host is only serving files.
        "load printers" = "no";
        "printing" = "bsd";
        "printcap name" = "/dev/null";
        "disable spoolss" = "yes";
        "dns proxy" = "no";

        # Throughput-oriented defaults for a local/Tailscale file share.
        "use sendfile" = "yes";
        "aio read size" = 1;
        "aio write size" = 1;
        "min receivefile size" = 16384;
        "sync always" = "no";
        "deadtime" = 15;
        "getwd cache" = "yes";

        # Better metadata compatibility for macOS/Windows clients.
        "vfs objects" = "catia fruit streams_xattr";
        "fruit:aapl" = "yes";
        "fruit:metadata" = "stream";
        "fruit:resource" = "stream";
        "ea support" = "yes";
        "store dos attributes" = "yes";
      };

      sda = {
        path = "/home/duck/sda";
        comment = "s145 1TB HDD";
        browseable = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "valid users" = "duck";
        "force user" = "duck";
        "force group" = "users";
        "create mask" = "0664";
        "directory mask" = "0775";
        "inherit permissions" = "yes";
        "hide dot files" = "no";

        # Refuse the share if the nofail HDD mount is absent.
        "root preexec" = "${pkgs.util-linux}/bin/mountpoint -q /home/duck/sda";
        "root preexec close" = "yes";
      };
    };
  };

  # Windows network discovery for local-network clients.
  services.samba-wsdd = {
    enable = true;
    openFirewall = true;
  };
}
