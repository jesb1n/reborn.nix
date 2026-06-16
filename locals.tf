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
}
