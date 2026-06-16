# Output the "list" of all availability domains.
# output "all-availability-domains-in-your-tenancy" {
#   value = data.oci_identity_availability_domains.ads.availability_domains
# }

output "arm_instance_public_ip" {
  description = "Public IP of the ARM instance"
  value       = oci_core_public_ip.arm_reserved_ip.ip_address
}

output "micro_instances_public_ips" {
  description = "Public IPs of micro instances"
  value = {
    for k, v in oci_core_public_ip.micro_reserved_ip : k => v.ip_address
  }
}

# Individual outputs for convenience
output "micro1_public_ip" {
  description = "Public IP of micro1 instance"
  value       = oci_core_public_ip.micro_reserved_ip["micro1"].ip_address
}

output "micro2_public_ip" {
  description = "Public IP of micro2 instance"
  value       = oci_core_public_ip.micro_reserved_ip["micro2"].ip_address
}
