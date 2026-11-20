# IPv6 addresses for the existing instances.
#
# Deliberately NOT done via create_vnic_details.assign_ipv6ip: that attribute is
# ForceNew in the OCI provider and would replace every instance. Instead we look
# up each instance's primary VNIC and attach an oci_core_ipv6 object to it, which
# is an additive change on the running VM.

data "oci_core_vnic_attachments" "arm" {
  compartment_id = local.compartment_id
  instance_id    = oci_core_instance.arm_instance.id
}

data "oci_core_vnic_attachments" "micro" {
  for_each = local.micro_instances

  compartment_id = local.compartment_id
  instance_id    = oci_core_instance.micro_instances[each.key].id
}

resource "oci_core_ipv6" "arm" {
  count = local.ipv6_ready ? 1 : 0

  vnic_id      = data.oci_core_vnic_attachments.arm.vnic_attachments[0].vnic_id
  display_name = "${var.project}-arm-ipv6"

  # The subnet must carry its IPv6 prefix before an address can be drawn from it.
  depends_on = [oci_core_subnet.public]
}

resource "oci_core_ipv6" "micro" {
  for_each = local.ipv6_ready ? local.micro_instances : {}

  vnic_id      = data.oci_core_vnic_attachments.micro[each.key].vnic_attachments[0].vnic_id
  display_name = "${var.project}-${each.key}-ipv6"

  depends_on = [oci_core_subnet.public]
}
