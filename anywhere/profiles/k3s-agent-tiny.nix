# profiles/k3s-agent-tiny.nix — k3s agent role for the 1 GB Oracle micro nodes.
#
# Layers tiny-specific constraints on top of the generic agent profile:
#   * --kubelet-arg=max-pods=10 (kubelet defaults to 110, way too many for 1 GB RAM)
#   * zramSwap at 50 % so OOMs don't take the node down before workloads
#
# The "tiny=true:NoSchedule" taint is applied out-of-band with kubectl after
# the node first registers — see MAINTENANCE.md "Tiny worker notes".
{ ... }:
{
  imports = [ ./k3s-agent.nix ];

  services.k3s.extraFlags = [
    "--kubelet-arg=max-pods=10"
  ];

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
  };
}
