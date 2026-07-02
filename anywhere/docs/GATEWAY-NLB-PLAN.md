# OCI Network Load Balancer + Kubernetes Gateway API plan

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

## Current cluster addresses

Cluster traffic should continue to use Tailscale.

Public ingress traffic should use OCI networking.

| Node | Role | Tailscale IP | OCI private IP | Static public IP |
| --- | --- | --- | --- | --- |
| `oci-nixos` | control-plane | `100.84.230.4` | `10.0.0.225` | `129.159.222.42` |
| `oracle-eu-micro1` | worker | `100.96.237.114` | `10.0.0.133` | `92.5.98.162` |
| `oracle-eu-micro2` | worker | `100.67.95.26` | `10.0.0.6` | `89.168.126.35` |

Confirm private IPs before applying Terraform:

```bash
tofu output
ssh ubuntu@oci-nixos 'ip -4 addr'
ssh ubuntu@oracle-eu-micro1 'ip -4 addr'
ssh ubuntu@oracle-eu-micro2 'ip -4 addr'
```

## Recommendation

Start small:

```text
OCI NLB -> oci-nixos only -> Gateway controller
```

Do not put the tiny 1GB workers behind public ingress on day one. Keep them for explicitly scheduled tiny workloads.

After the Gateway controller is stable, optionally add `oracle-eu-micro1` and `oracle-eu-micro2` as NLB backends.

## Phase 1: Terraform/OpenTofu NLB plan

Create a public OCI Network Load Balancer in the existing public subnet.

Proposed listeners:

| Listener | Backend set | Backend port |
| --- | --- | --- |
| TCP `80` | `gateway-http` | `80` |
| TCP `443` | `gateway-https` | `443` |

Initial backends:

```text
10.0.0.225:80
10.0.0.225:443
```

Optional later backends:

```text
10.0.0.133:80
10.0.0.133:443
10.0.0.6:80
10.0.0.6:443
```

### Terraform resource sketch

Create a new file such as:

```text
nlb.tf
```

Sketch:

```hcl
locals {
  gateway_backends = {
    oci-nixos = {
      ip = "10.0.0.225"
    }
    # Add these later only if gateway pods run on those nodes too:
    # oracle-eu-micro1 = { ip = "10.0.0.133" }
    # oracle-eu-micro2 = { ip = "10.0.0.6" }
  }
}

resource "oci_network_load_balancer_network_load_balancer" "k3s_gateway" {
  compartment_id = local.compartment_id
  display_name   = "${var.project}-k3s-gateway-nlb"
  subnet_id       = oci_core_subnet.public.id
  is_private      = false

  freeform_tags = local.freeform_tags
}

resource "oci_network_load_balancer_backend_set" "gateway_http" {
  name                     = "gateway-http"
  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.k3s_gateway.id
  policy                   = "FIVE_TUPLE"

  health_checker {
    protocol = "TCP"
    port     = 80
  }
}

resource "oci_network_load_balancer_backend_set" "gateway_https" {
  name                     = "gateway-https"
  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.k3s_gateway.id
  policy                   = "FIVE_TUPLE"

  health_checker {
    protocol = "TCP"
    port     = 443
  }
}

resource "oci_network_load_balancer_listener" "gateway_http" {
  name                     = "gateway-http"
  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.k3s_gateway.id
  default_backend_set_name = oci_network_load_balancer_backend_set.gateway_http.name
  port                     = 80
  protocol                 = "TCP"
}

resource "oci_network_load_balancer_listener" "gateway_https" {
  name                     = "gateway-https"
  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.k3s_gateway.id
  default_backend_set_name = oci_network_load_balancer_backend_set.gateway_https.name
  port                     = 443
  protocol                 = "TCP"
}

resource "oci_network_load_balancer_backend" "gateway_http" {
  for_each                 = local.gateway_backends
  name                     = each.key
  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.k3s_gateway.id
  backend_set_name         = oci_network_load_balancer_backend_set.gateway_http.name
  ip_address               = each.value.ip
  port                     = 80
}

resource "oci_network_load_balancer_backend" "gateway_https" {
  for_each                 = local.gateway_backends
  name                     = each.key
  network_load_balancer_id = oci_network_load_balancer_network_load_balancer.k3s_gateway.id
  backend_set_name         = oci_network_load_balancer_backend_set.gateway_https.name
  ip_address               = each.value.ip
  port                     = 443
}
```

Add output:

```hcl
output "k3s_gateway_nlb_ip" {
  description = "Public IP address of the k3s Gateway Network Load Balancer"
  value       = oci_network_load_balancer_network_load_balancer.k3s_gateway.ip_addresses
}
```

### Security list changes

Because OCI Network Load Balancer is L3/L4 and can preserve client source IPs, the backend nodes must allow public HTTP/HTTPS traffic.

Add security list ingress rules for:

```text
TCP 80  from 0.0.0.0/0
TCP 443 from 0.0.0.0/0
```

Keep k3s control-plane, kubelet, and flannel traffic private over Tailscale. Do not open k3s ports publicly.

### Terraform validation flow

From repo root:

```bash
tofu fmt -check
tofu validate
tofu plan -out=tfplan
```

Review the plan. Expected changes:

- one OCI Network Load Balancer;
- two listeners;
- two backend sets;
- backend entries for selected nodes;
- security list ingress for TCP 80/443;
- output for the NLB IP.

Apply only after plan review:

```bash
tofu apply tfplan
```

## Phase 2: NixOS firewall plan

Only nodes that run the Gateway controller need host firewall ports open.

For initial rollout, open `80` and `443` only on `oci-nixos`:

```nix
networking.firewall.allowedTCPPorts = [
  80
  443
];
```

Deploy:

```bash
cd ~/oracle-cloud-free-tier/anywhere
nix develop -c deploy .#oci-nixos
```

Do not open ports on micro1/micro2 unless Gateway pods will actually run there.

## Phase 3: Kubernetes Gateway controller plan

Use Traefik Gateway API first.

Reason:

- lighter than Envoy Gateway for this tiny cluster;
- suitable for HTTP/HTTPS routing;
- reasonable fit for k3s;
- avoids starting new work on retired `ingress-nginx`.

Install in a namespace such as:

```text
gateway-system
```

Pin the chart and Gateway API CRD versions. Do not install unpinned `latest`.

Before installing, inspect the actual chart values:

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update
helm show values traefik/traefik | grep -Ei 'gateway|hostNetwork|nodeSelector|tolerations'
```

Desired deployment properties:

```text
hostNetwork: true
listen on :80 and :443
nodeSelector: kubernetes.io/hostname=oci-nixos
tolerations: none needed for oci-nixos
replicas: 1 initially
```

Do not schedule the Gateway controller on the tiny tainted workers initially.

## Phase 4: Gateway API resources

Create one shared public Gateway.

Example:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: public-gateway
  namespace: gateway-system
spec:
  gatewayClassName: traefik
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces:
          from: All
    - name: https
      protocol: HTTPS
      port: 443
      allowedRoutes:
        namespaces:
          from: All
      # TLS config depends on the certificate strategy.
```

Example app route:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: example
  namespace: default
spec:
  parentRefs:
    - name: public-gateway
      namespace: gateway-system
  hostnames:
    - "app.example.com"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: example-service
          port: 80
```

## Phase 5: DNS

After Terraform creates the NLB, point public DNS at the NLB IP:

```text
app.example.com A <NLB_PUBLIC_IP>
```

Do not point app DNS directly at the node public IPs once the NLB is in use.

## Phase 6: Validation

Check OCI NLB health in the OCI console or CLI.

Check Kubernetes:

```bash
ssh ubuntu@oci-nixos 'sudo k3s kubectl get gatewayclass,gateway,httproute -A'
ssh ubuntu@oci-nixos 'sudo k3s kubectl get pods -n gateway-system -o wide'
```

Check node ports:

```bash
ssh ubuntu@oci-nixos 'sudo ss -lntp | grep -E ":80|:443"'
```

Check public HTTP:

```bash
curl -I http://app.example.com
curl -Iv https://app.example.com
```

Check cluster health:

```bash
ssh ubuntu@oci-nixos 'sudo k3s kubectl get nodes -o wide'
ssh ubuntu@oci-nixos 'sudo k3s kubectl get pods -A'
```

## Rollback plan

Kubernetes rollback:

```bash
kubectl delete httproute -A --all
kubectl delete gateway -n gateway-system public-gateway
helm uninstall traefik -n gateway-system
```

NixOS rollback:

```bash
cd ~/oracle-cloud-free-tier/anywhere
nix develop -c deploy .#oci-nixos
```

or roll back the host generation:

```bash
ssh ubuntu@oci-nixos 'sudo nixos-rebuild switch --rollback'
```

Terraform rollback:

- remove the NLB resources and HTTP/HTTPS security list rules from code;
- run `tofu plan -out=tfplan`;
- review destroy scope carefully;
- run `tofu apply tfplan`.

Do not destroy reserved public IP resources for the nodes.

## Later HA expansion

After the single-node path is stable:

1. Decide whether the tiny nodes should run Gateway pods.
2. If yes, open TCP 80/443 in their NixOS firewalls.
3. Add tolerations if Gateway pods should run on tainted nodes.
4. Add `10.0.0.133` and `10.0.0.6` as NLB backends.
5. Validate memory pressure on both tiny nodes.

If memory pressure appears, keep public Gateway only on `oci-nixos`.
