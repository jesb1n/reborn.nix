resource "oci_core_vcn" "vcn" {
  compartment_id = local.compartment_id
  cidr_block     = var.vcn_cidr_block
  display_name   = "${var.project}-vcn"
  dns_label      = var.vcn_dns_label
  # Dual-stack: Oracle allocates a /56 GUA prefix. One-way change on OCI.
  is_ipv6enabled = true

  freeform_tags = local.freeform_tags

  lifecycle {
    create_before_destroy = true
  }
}

# Internet Gateway for public subnet
resource "oci_core_internet_gateway" "igw" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.vcn.id
  display_name   = "${var.project}-internet-gateway"
  enabled        = true

  freeform_tags = local.freeform_tags

  lifecycle {
    create_before_destroy = true
  }
}

# Public Subnet
resource "oci_core_subnet" "public" {
  compartment_id    = local.compartment_id
  vcn_id            = oci_core_vcn.vcn.id
  cidr_block        = var.public_subnet_cidr
  ipv6cidr_block    = local.public_subnet_ipv6_cidr
  display_name      = "${var.project}-public-subnet"
  dns_label         = "public"
  route_table_id    = oci_core_route_table.public_route_table.id
  security_list_ids = [oci_core_security_list.public_security_list.id]

  freeform_tags = local.freeform_tags

  lifecycle {
    create_before_destroy = true
  }
}

# Public Subnet Route Table
resource "oci_core_route_table" "public_route_table" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.vcn.id
  display_name   = "${var.project}-public-rt"
  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.igw.id
  }
  dynamic "route_rules" {
    for_each = local.ipv6_ready ? ["::/0"] : []

    content {
      destination       = route_rules.value
      destination_type  = "CIDR_BLOCK"
      network_entity_id = oci_core_internet_gateway.igw.id
    }
  }

  freeform_tags = local.freeform_tags
}

# Security Lists
resource "oci_core_security_list" "public_security_list" {
  compartment_id = local.compartment_id
  vcn_id         = oci_core_vcn.vcn.id
  display_name   = "${var.project}-public-security-list"

  # SSH access from whitelisted IP
  ingress_security_rules {
    protocol    = "6" # TCP
    source      = var.user_ip_address
    stateless   = false
    description = "SSH access from whitelisted IP"
    tcp_options {
      min = 22
      max = 22
    }
  }

  dynamic "ingress_security_rules" {
    for_each = toset(var.instance_peer_ssh_cidrs)

    content {
      protocol    = "6" # TCP
      source      = ingress_security_rules.value
      stateless   = false
      description = "SSH access from peer/admin IP"
      tcp_options {
        min = 22
        max = 22
      }
    }
  }

  dynamic "ingress_security_rules" {
    for_each = local.ipv6_ready ? toset(var.instance_peer_ssh_ipv6_cidrs) : []

    content {
      protocol    = "6" # TCP
      source      = ingress_security_rules.value
      stateless   = false
      description = "SSH access from peer/admin IPv6"
      tcp_options {
        min = 22
        max = 22
      }
    }
  }

  # Allow all traffic within VCN
  ingress_security_rules {
    protocol    = "all"
    source      = var.vcn_cidr_block
    stateless   = false
    description = "Allow all traffic within VCN"
  }

  dynamic "ingress_security_rules" {
    for_each = local.ipv6_ready ? [local.vcn_ipv6_cidr] : []

    content {
      protocol    = "all"
      source      = ingress_security_rules.value
      stateless   = false
      description = "Allow all IPv6 traffic within VCN"
    }
  }

  # ICMPv6 Packet Too Big (type 2) is required for path MTU discovery
  dynamic "ingress_security_rules" {
    for_each = local.ipv6_ready ? ["::/0"] : []

    content {
      protocol    = "58" # ICMPv6
      source      = ingress_security_rules.value
      stateless   = false
      description = "ICMPv6 Packet Too Big for PMTUD"
      icmp_options {
        type = 2
        code = 0
      }
    }
  }

  # Allow all outbound traffic
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
    stateless   = false
    description = "Allow all outbound traffic"
  }

  # IPv6 egress. When tailscale_ipv6_underlay is false this is split into
  # TCP/ICMPv6/UDP rules so that UDP from the Tailscale port is NOT allowed
  # (see the variable description for why).
  dynamic "egress_security_rules" {
    for_each = local.ipv6_ready && var.tailscale_ipv6_underlay ? ["::/0"] : []

    content {
      protocol    = "all"
      destination = egress_security_rules.value
      stateless   = false
      description = "Allow all outbound IPv6 traffic"
    }
  }

  dynamic "egress_security_rules" {
    for_each = local.ipv6_ready && !var.tailscale_ipv6_underlay ? ["6", "58"] : []

    content {
      protocol    = egress_security_rules.value
      destination = "::/0"
      stateless   = false
      description = egress_security_rules.value == "6" ? "Allow all outbound IPv6 TCP" : "Allow all outbound ICMPv6"
    }
  }

  dynamic "egress_security_rules" {
    for_each = local.ipv6_ready && !var.tailscale_ipv6_underlay ? {
      below = { min = 1, max = var.tailscale_port - 1 }
      above = { min = var.tailscale_port + 1, max = 65535 }
    } : {}

    content {
      protocol    = "17" # UDP
      destination = "::/0"
      stateless   = false
      description = "Allow outbound IPv6 UDP except from the Tailscale port (${egress_security_rules.key} ${var.tailscale_port})"
      udp_options {
        source_port_range {
          min = egress_security_rules.value.min
          max = egress_security_rules.value.max
        }
      }
    }
  }

  freeform_tags = local.freeform_tags
}
