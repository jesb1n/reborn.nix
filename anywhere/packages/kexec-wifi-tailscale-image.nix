# Wi-Fi + Tailscale-aware x86_64 kexec tarball for nixos-anywhere.
#
# Build from an x86_64-linux machine:
#   nix build .#packages.x86_64-linux.kexec-wifi-tailscale-image
#
# Use:
#   nixos-anywhere --kexec ./result --flake .#<host> <user>@<tailscale-or-wifi-ip>
#
# The bundled run script copies the running Debian system's SSH keys,
# NetworkManager/wpa_supplicant/iwd Wi-Fi state, and Tailscale state into the
# initrd before kexec. After the jump, the NixOS installer environment should
# reconnect Wi-Fi and appear as the same Tailscale node.
{ pkgs, lib }:

let
  sshKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMDHy9Gc18Osi7HFBiUMm+Da9JQ95cU1a7dsmyJCY5s1 jesbin@Duck.local"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJrNGTJviFWKFWJsvkD/0ajOflMSUKWIjP/N0Y39HY0S duck@s145"
  ];

  iprouteStatic = pkgs.pkgsStatic.iproute2.override { iptables = null; };
  modulesPath = "${pkgs.path}/nixos/modules";

  kexecConfig = pkgs.nixos ({ config, pkgs, lib, ... }: {
    imports = [
      (modulesPath + "/installer/netboot/netboot-minimal.nix")
    ];

    boot.initrd.compressor = "xz";

    boot.initrd.availableKernelModules = [
      "ahci"
      "ata_piix"
      "ehci_pci"
      "nvme"
      "sd_mod"
      "sr_mod"
      "uas"
      "usb_storage"
      "usbhid"
      "xhci_pci"
    ];

    hardware.enableRedistributableFirmware = true;

    networking = {
      useDHCP = lib.mkDefault true;
      firewall.enable = false;

      networkmanager = {
        enable = true;
        wifi.backend = "wpa_supplicant";
      };
    };

    systemd.services.NetworkManager-wait-online.enable = true;

    services.openssh = {
      enable = true;
      openFirewall = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "prohibit-password";
      };
    };

    users.users.root.openssh.authorizedKeys.keys = sshKeys;

    services.tailscale = {
      enable = true;
      openFirewall = true;
    };

    systemd.services.tailscaled = {
      after = [
        "NetworkManager.service"
        "NetworkManager-wait-online.service"
      ];
      wants = [
        "NetworkManager-wait-online.service"
      ];
    };

    systemd.services.kexec-import-network-state = {
      description = "Normalize imported Wi-Fi and Tailscale state";
      before = [
        "NetworkManager.service"
        "tailscaled.service"
      ];
      wantedBy = [ "multi-user.target" ];
      unitConfig.DefaultDependencies = false;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        mkdir -p /etc/NetworkManager/system-connections /var/lib/tailscale

        if [ -d /etc/NetworkManager/system-connections ]; then
          chmod 700 /etc/NetworkManager/system-connections
          find /etc/NetworkManager/system-connections -type f -exec chmod 600 {} \; 2>/dev/null || true
        fi

        if [ -f /var/lib/tailscale/tailscaled.state ]; then
          chmod 600 /var/lib/tailscale/tailscaled.state
        fi
      '';
    };

    environment.systemPackages = with pkgs; [
      bash
      coreutils
      iproute2
      iw
      networkmanager
      tailscale
      util-linux
      wpa_supplicant
    ];

    system.stateVersion = "26.05";

    system.build.kexecTarball = lib.mkForce (pkgs.runCommand "nixos-kexec-wifi-tailscale-x86_64-linux.tar.gz"
      {
        init = config.system.build.toplevel + "/init";
        kernelParams = builtins.toString config.boot.kernelParams;
        nativeBuildInputs = [
          pkgs.buildPackages.cpio
          pkgs.buildPackages.gnutar
          pkgs.buildPackages.gzip
          pkgs.buildPackages.shellcheck
        ];
      } ''
      mkdir kexec

      cp "${config.system.build.netbootRamdisk}/initrd" kexec/initrd
      cp "${config.system.build.kernel}/${config.system.boot.loader.kernelFile}" kexec/bzImage
      cp "${pkgs.kexec-tools}/bin/kexec" kexec/kexec
      cp "${iprouteStatic}/bin/ip" kexec/ip

      kexec/ip -V
      kexec/kexec --version

      substituteAll ${./kexec-wifi-tailscale-run.sh} kexec/run
      chmod +x kexec/run
      shellcheck -e SC3040 kexec/run

      tar -czvf "$out" kexec
    '');
  });
in
kexecConfig.config.system.build.kexecTarball
