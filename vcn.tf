resource "oci_core_vcn" "vcn" {
  compartment_id = local.compartment_id
  cidr_block     = var.vcn_cidr_block
  display_name   = "${var.project}-vcn"
  dns_label      = var.vcn_dns_label

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

  # Allow all traffic within VCN
  ingress_security_rules {
    protocol    = "all"
    source      = var.vcn_cidr_block
    stateless   = false
    description = "Allow all traffic within VCN"
  }

  # Allow all outbound traffic
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
    stateless   = false
    description = "Allow all outbound traffic"
  }

  freeform_tags = local.freeform_tags
}
