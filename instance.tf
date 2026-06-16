data "oci_core_images" "micro_ubuntu_2404" {
  compartment_id           = var.tenancy_ocid # Images are queried at tenancy level
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = "VM.Standard.E2.1.Micro"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

data "oci_core_images" "arm_ubuntu_2404" {
  compartment_id           = var.tenancy_ocid # Images are queried at tenancy level
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "24.04"
  shape                    = "VM.Standard.A1.Flex"
  filter {
    name   = "display_name"
    values = ["^.*-aarch64-.*$"]
    regex  = true
  }
  sort_by    = "TIMECREATED"
  sort_order = "DESC"
}


resource "oci_core_instance" "arm_instance" {
  # Try different availability domains if AD1 has no capacity
  availability_domain = length(data.oci_identity_availability_domains.ads.availability_domains) > 1 ? data.oci_identity_availability_domains.ads.availability_domains[1].name : data.oci_identity_availability_domains.ads.availability_domains[0].name
  compartment_id      = local.compartment_id
  shape               = "VM.Standard.A1.Flex"
  shape_config {
    ocpus         = 4
    memory_in_gbs = 24
  }
  source_details {
    boot_volume_size_in_gbs = 50 # or more, within free 200GB shared quota
    source_id               = local.arm_image_id
    source_type             = "image"
  }
  display_name = "${var.project}-arm-instance"
  create_vnic_details {
    assign_public_ip = false
    subnet_id        = oci_core_subnet.public.id
  }
  metadata = {
    ssh_authorized_keys = var.ssh_authorized_keys
  }
  freeform_tags = local.freeform_tags

  preserve_boot_volume = false

  lifecycle {
    create_before_destroy = true
    ignore_changes = [
      # Ignore changes to availability_domain to prevent recreation
      availability_domain
    ]
  }
}


resource "oci_core_instance" "micro_instances" {
  for_each = local.micro_instances

  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[each.value.availability_domain_index].name
  compartment_id      = local.compartment_id
  shape               = "VM.Standard.E2.1.Micro"
  shape_config {
    ocpus         = 1
    memory_in_gbs = 1
  }
  source_details {
    boot_volume_size_in_gbs = 50
    source_id               = local.micro_image_id
    source_type             = "image"
  }
  display_name = "${var.project}-${each.key}-instance"
  create_vnic_details {
    assign_public_ip = false
    subnet_id        = oci_core_subnet.public.id
  }
  metadata = {
    ssh_authorized_keys = var.ssh_authorized_keys
    user_data = base64encode(<<-EOF
#!/bin/bash
# This script will run only once on the first boot

MARKER_FILE="/etc/init_script_ran"

if [ -f "$MARKER_FILE" ]; then
    echo "Init script already ran. Exiting."
    exit 0
fi

# Update packages
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get upgrade -y

# Install Tailscale
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/noble.tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list

apt-get update
apt-get install -y tailscale

# Join Tailnet
tailscale up --authkey=${var.TAILSCALE_AUTH_KEY} --ssh

# Cleanup sensitive user-data
rm -f /var/lib/cloud/instance/user-data.txt

# Create marker file
touch "$MARKER_FILE"
EOF
    )
  }
  freeform_tags = local.freeform_tags

  preserve_boot_volume = false

  # lifecycle {
  #   create_before_destroy = true
  # }
}

# --- Reserved Public IPs ---

# ARM instance VNIC attachment and private IP
data "oci_core_vnic_attachments" "arm_vnic_attachments" {
  compartment_id = local.compartment_id
  instance_id    = oci_core_instance.arm_instance.id
}

data "oci_core_private_ips" "arm_private_ip" {
  vnic_id = data.oci_core_vnic_attachments.arm_vnic_attachments.vnic_attachments[0].vnic_id
}

resource "oci_core_public_ip" "arm_reserved_ip" {
  compartment_id = local.compartment_id
  display_name   = "${var.project}-arm-reserved-ip"
  lifetime       = "RESERVED"
  private_ip_id  = data.oci_core_private_ips.arm_private_ip.private_ips[0].id

  freeform_tags = local.freeform_tags

  lifecycle {
    prevent_destroy = true
  }
}

# Micro instances VNIC attachments and private IPs
data "oci_core_vnic_attachments" "micro_vnic_attachments" {
  for_each       = local.micro_instances
  compartment_id = local.compartment_id
  instance_id    = oci_core_instance.micro_instances[each.key].id
}

data "oci_core_private_ips" "micro_private_ip" {
  for_each = local.micro_instances
  vnic_id  = data.oci_core_vnic_attachments.micro_vnic_attachments[each.key].vnic_attachments[0].vnic_id
}

resource "oci_core_public_ip" "micro_reserved_ip" {
  for_each       = local.micro_instances
  compartment_id = local.compartment_id
  display_name   = "${var.project}-${each.key}-reserved-ip"
  lifetime       = "RESERVED"
  private_ip_id  = data.oci_core_private_ips.micro_private_ip[each.key].private_ips[0].id

  freeform_tags = local.freeform_tags

  lifecycle {
    prevent_destroy = true
  }
}
