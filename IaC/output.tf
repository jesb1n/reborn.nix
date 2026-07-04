# Output the "list" of all availability domains.
# output "all-availability-domains-in-your-tenancy" {
#   value = data.oci_identity_availability_domains.ads.availability_domains
# }

output "arm_instance_public_ip" {
  description = "Public IP of the ARM instance"
  value       = oci_core_instance.arm_instance.public_ip
}

output "micro_instances_public_ips" {
  description = "Public IPs of micro instances"
  value = {
    for k, v in oci_core_instance.micro_instances : k => v.public_ip
  }
}

# Individual outputs for convenience
output "micro1_public_ip" {
  description = "Public IP of micro1 instance"
  value       = oci_core_instance.micro_instances["micro1"].public_ip
}

output "micro2_public_ip" {
  description = "Public IP of micro2 instance"
  value       = oci_core_instance.micro_instances["micro2"].public_ip
}
