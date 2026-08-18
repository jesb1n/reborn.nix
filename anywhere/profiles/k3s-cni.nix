# Keep k3s's stable CNI directory tied to the active NixOS generation.
#
# K3s only refreshes these links when it extracts a new runtime bundle. Reusing
# an older extracted bundle after a rollback can otherwise leave links to a Nix
# store path that garbage collection is allowed to remove.
{ config, lib, pkgs, ... }:

let
  cniBinary = "${config.services.k3s.package.k3sCNIPlugins}/bin/cni";
  managedPlugins = [
    "bandwidth"
    "bridge"
    "cni"
    "firewall"
    "flannel"
    "host-local"
    "loopback"
    "portmap"
  ];
in
{
  systemd.services.k3s.preStart = lib.mkIf config.services.k3s.enable ''
    cni_dir=/var/lib/rancher/k3s/data/cni
    ${pkgs.coreutils}/bin/install -d -m 0755 "$cni_dir"

    for plugin in ${lib.escapeShellArgs managedPlugins}; do
      destination="$cni_dir/$plugin"

      # Preserve explicit custom plugin binaries, matching upstream k3s behavior.
      if [ "$plugin" != cni ] && [ -e "$destination" ] && [ ! -L "$destination" ]; then
        continue
      fi

      ${pkgs.coreutils}/bin/ln -sfn ${lib.escapeShellArg cniBinary} "$destination"
    done

    for plugin in flannel loopback; do
      if [ ! -x "$cni_dir/$plugin" ]; then
        echo "k3s CNI plugin $plugin is not executable" >&2
        exit 1
      fi
    done
  '';
}
