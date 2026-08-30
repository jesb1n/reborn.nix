{ pkgs }:

let
  testPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIC5RzsC93e9smx3mTQlK0TgDH2LKHSOiNWdz63OPfnhn nixos-ssh-access-test";
  testPrivateKey = ''
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
    QyNTUxOQAAACAuUc7Avd3vbJsd5k0JStE4Ax9iyh0jojVnc+tzj354ZwAAAJh/Bo+rfwaP
    qwAAAAtzc2gtZWQyNTUxOQAAACAuUc7Avd3vbJsd5k0JStE4Ax9iyh0jojVnc+tzj354Zw
    AAAECvEphCS6bvwwofrwOcRDF5O6bZOFIWLsR8ZhwBNRFyGy5RzsC93e9smx3mTQlK0TgD
    H2LKHSOiNWdz63OPfnhnAAAAFW5peG9zLXNzaC1hY2Nlc3MtdGVzdA==
    -----END OPENSSH PRIVATE KEY-----
  '';
in
pkgs.testers.runNixOSTest {
  name = "ssh-access";

  nodes.machine = { lib, pkgs, ... }: {
    imports = [
      ../profiles/base.nix
      ../profiles/server.nix
    ];

    networking.hostName = "ssh-access-test";

    # The shared server profile targets physical EFI hosts. The test VM boots
    # directly and uses the NixOS test network instead of NetworkManager.
    boot.loader.grub.enable = lib.mkForce false;
    boot.loader.systemd-boot.enable = lib.mkForce false;
    boot.loader.efi.canTouchEfiVariables = lib.mkForce false;
    boot.kernelParams = lib.mkForce [ ];
    networking.networkmanager.enable = lib.mkForce false;
    nix.gc.automatic = lib.mkForce false;
    nix.optimise.automatic = lib.mkForce false;
    services.fstrim.enable = lib.mkForce false;

    users.users.duck.openssh.authorizedKeys.keys = lib.mkForce [ testPublicKey ];
    users.users.root.openssh.authorizedKeys.keys = lib.mkForce [ testPublicKey ];

    environment.etc."ssh-access-test/id_ed25519" = {
      text = testPrivateKey;
      mode = "0400";
    };

    environment.systemPackages = [ pkgs.sshpass ];
    system.stateVersion = "26.05";
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("sshd.service")
    machine.wait_for_open_port(22)

    effective_sshd_config_text = machine.succeed(
        "${pkgs.openssh}/bin/sshd -T -f /etc/ssh/sshd_config"
    )
    effective_sshd_config = {
        line.lower() for line in effective_sshd_config_text.splitlines()
    }
    assert "passwordauthentication no" in effective_sshd_config, effective_sshd_config_text
    assert "kbdinteractiveauthentication no" in effective_sshd_config, effective_sshd_config_text
    assert "permitrootlogin no" in effective_sshd_config, effective_sshd_config_text

    ssh_options = (
        "-o BatchMode=yes "
        "-o ConnectTimeout=10 "
        "-o ControlMaster=no "
        "-o ControlPath=none "
        "-o ServerAliveCountMax=2 "
        "-o ServerAliveInterval=5 "
        "-o StdinNull=yes "
        "-o StrictHostKeyChecking=no "
        "-o UserKnownHostsFile=/dev/null "
        "-i /etc/ssh-access-test/id_ed25519"
    )

    machine.succeed(f"timeout 30 ssh {ssh_options} duck@127.0.0.1 true")
    machine.succeed(
        f"timeout 30 ssh {ssh_options} duck@127.0.0.1 'id -nG | grep -qw wheel'"
    )
    machine.succeed(f"timeout 30 ssh {ssh_options} duck@127.0.0.1 'sudo -n true'")
    machine.succeed(
        f"timeout 30 ssh {ssh_options} duck@127.0.0.1 'sudo -n id -u | grep -qx 0'"
    )

    password_options = (
        "-o ConnectTimeout=10 "
        "-o NumberOfPasswordPrompts=1 "
        "-o PreferredAuthentications=password "
        "-o PubkeyAuthentication=no "
        "-o StrictHostKeyChecking=no "
        "-o UserKnownHostsFile=/dev/null"
    )
    machine.fail(
        f"sshpass -p rejected-test-password ssh {password_options} duck@127.0.0.1 true"
    )

    keyboard_options = (
        "-o ConnectTimeout=10 "
        "-o KbdInteractiveAuthentication=yes "
        "-o NumberOfPasswordPrompts=1 "
        "-o PasswordAuthentication=no "
        "-o PreferredAuthentications=keyboard-interactive "
        "-o PubkeyAuthentication=no "
        "-o StrictHostKeyChecking=no "
        "-o UserKnownHostsFile=/dev/null"
    )
    machine.fail(
        f"sshpass -p rejected-test-password ssh {keyboard_options} duck@127.0.0.1 true"
    )

    machine.fail(f"ssh {ssh_options} root@127.0.0.1 true")

    machine.succeed("systemctl restart sshd.service")
    machine.wait_for_unit("sshd.service")
    machine.wait_for_open_port(22)
    machine.succeed(f"timeout 30 ssh {ssh_options} duck@127.0.0.1 true")

    machine.succeed("systemctl is-active --quiet sshd.service systemd-logind.service")
    machine.succeed(
        "! systemctl --failed --no-legend | grep -E '(sshd|systemd-logind|user@)'"
    )
  '';
}
