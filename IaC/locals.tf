locals {
  # Use compartment_id if provided, otherwise fall back to tenancy_ocid for backward compatibility
  compartment_id = coalesce(var.compartment_id, var.tenancy_ocid)

  # Common tags for all resources
  common_tags = {
    Project     = var.project
    ManagedBy   = "Terraform"
    Environment = "production" # Could be made a variable
  }

  # Common freeform tags
  freeform_tags = local.common_tags

  # Extract image IDs from data sources
  # These will be null if no images are found, causing Terraform to fail during apply
  micro_image_id = length(data.oci_core_images.micro_ubuntu_2404.images) > 0 ? data.oci_core_images.micro_ubuntu_2404.images[0].id : null
  arm_image_id   = length(data.oci_core_images.arm_ubuntu_2404.images) > 0 ? data.oci_core_images.arm_ubuntu_2404.images[0].id : null

  # Micro instances configuration
  micro_instances = {
    micro1 = {
      availability_domain_index = 0
    }
    micro2 = {
      availability_domain_index = 0
    }
  }

  # IPv6: Oracle allocates the VCN a /56; the public subnet takes the first /64.
  #
  # ipv6cidr_blocks is only populated after the VCN update has been applied and
  # the provider does not mark it unknown at plan time, so this is a two-pass
  # rollout. Pass 1 must be targeted, otherwise the prefix becomes known mid-apply
  # and OpenTofu aborts the security list with "inconsistent final plan":
  #   tofu apply -target=oci_core_vcn.vcn ...
  # Pass 2 is a normal plan/apply; everything gated on `ipv6_ready` (subnet
  # prefix, IPv6 route and security rules, per-instance addresses) is picked up.
  vcn_ipv6_cidr           = try(oci_core_vcn.vcn.ipv6cidr_blocks[0], null)
  ipv6_ready              = local.vcn_ipv6_cidr != null
  public_subnet_ipv6_cidr = local.ipv6_ready ? cidrsubnet(local.vcn_ipv6_cidr, 8, 0) : null
}
