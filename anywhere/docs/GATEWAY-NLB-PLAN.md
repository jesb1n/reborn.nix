# OCI Network Load Balancer + Kubernetes Gateway API plan

> **Status: planned, not executed.** This plan predates the k3s control-plane
> migration to `s145` (see `K3S-S145-MIGRATION.md`) — the "Current cluster
> addresses" table below refers to `oracle-eu-arm1` by its old hostname
> `oci-nixos` and is stale; `s145`, not `oracle-eu-arm1`/`oci-nixos`, is now
> the control-plane. Re-verify all node roles, IPs, and cluster topology
> against the current flake and `README.md` host table before acting on any
> step in this document.

This is the rollout plan for exposing HTTP/HTTPS apps from the self-managed k3s cluster using an OCI Network Load Balancer and Kubernetes Gateway API.

The goal is:

```text
Internet
  ↓
OCI public Network Load Balancer
  ↓
OCI private IP of selected k3s node(s)
  ↓
Gateway API controller
  ↓
Gateway / HTTPRoute
  ↓
Kubernetes Services / Pods
```

## Why Gateway API instead of ingress-nginx

Use Gateway API for new work.

- The Kubernetes Ingress API is GA but frozen; Kubernetes recommends Gateway API for new designs.
- `ingress-nginx` specifically is being retired. It should not be the starting point for this cluster.
- Gateway API gives cleaner separation:
  - infrastructure/operator owns `GatewayClass` and `Gateway`;
  - application manifests own `HTTPRoute`;
  - OCI NLB remains infrastructure managed by Terraform/OpenTofu.

References:

- Kubernetes Ingress note: https://kubernetes.io/docs/concepts/services-networking/ingress/
- Kubernetes Gateway API: https://kubernetes.io/docs/concepts/services-networking/gateway/
- ingress-nginx retirement notice: https://kubernetes.github.io/ingress-nginx/
- OCI Network Load Balancer overview: https://docs.oracle.com/en-us/iaas/Content/NetworkLoadBalancer/overview.htm

## Current topology to re-discover

The original plan targeted the former OCI control plane and recorded addresses
that are no longer authoritative. Before redesigning this path, derive the
current OCI private IPs from a reviewed environment plan and inspect the live
NixOS workers through Tailscale:

```bash
make -C ../../IaC ENV=beijnseu check-auth
make -C ../../IaC ENV=beijnseu init
make -C ../../IaC ENV=beijnseu plan
ssh duck@oracle-eu-arm1 'ip -4 addr'
ssh duck@oracle-eu-micro1 'ip -4 addr'
ssh duck@oracle-eu-micro2 'ip -4 addr'
```

Do not reuse the historical public or private IPs from the original design.
The current control plane is the on-premises `s145`; exposing OCI workers
through an NLB therefore needs a fresh controller placement and failure-domain
design.

## Recommendation

Do not implement the original `OCI NLB -> oci-nixos` recommendation: that
node name and role no longer exist. Start a new design by selecting a standard
OCI worker for the Gateway controller and confirming how traffic reaches
services whose endpoints may run outside OCI.

Do not put the tiny 1 GB workers behind public ingress. Keep them for explicitly
scheduled, low-resource workloads.

## Historical design outline

The original proposal would have:

1. Provisioned an OCI network load balancer, public listeners, health checks,
   and backends with OpenTofu.
2. Opened ports 80 and 443 on selected OCI workers.
3. Installed a Gateway API controller and pinned it to those workers.
4. Added `GatewayClass`, `Gateway`, and `HTTPRoute` resources.
5. Changed DNS and validated failover before retiring the existing ingress.

Those steps are intentionally non-actionable here. They referenced a removed
host, stale addresses, an old control-plane topology, and controller/chart
versions that have not been revalidated. The current cluster instead uses
Traefik for ingress and Cloudflare DNS-01 ACME, with Cloudflare Tunnel as a
separate path.

## Requirements for a revived proposal

A new design must begin from current configuration and explicitly resolve:

- whether the existing Traefik Gateway API support is sufficient, avoiding a
  second ingress controller;
- how an OCI NLB reaches workloads and endpoints placed on non-OCI nodes;
- which standard-sized OCI worker runs ingress without tolerating `tiny` nodes;
- preserving the global HTTP-to-HTTPS redirect and namespace-scoped security
  middleware;
- OCI security-list scope, health checks, source-address handling, and cost;
- coexistence and rollback for existing Traefik and Cloudflare Tunnel routes;
- Flux ownership for every new Kubernetes resource;
- certificate ownership, with no cert-manager assumption.

Before any implementation, refresh the OpenTofu plan using the supported
SOPS-integrated flow, inspect the live cluster, pin current controller/chart
versions, and write a new reviewed runbook. Applying OpenTofu, deploying NixOS,
reconciling Flux, and changing DNS are all state-changing actions requiring
explicit operator confirmation.

## Historical rollback principle

The safe principle from the original exploration remains useful: keep the
existing ingress and DNS path working until the replacement is proven, and
remove the new DNS records and listeners before tearing down their supporting
resources. Exact rollback commands must be derived from the new implementation,
not copied from this record.
