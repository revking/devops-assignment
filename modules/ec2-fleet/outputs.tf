locals {
  all_instances = merge(aws_instance.standard, aws_instance.protected)
}

output "instance_ids" {
  description = "Map of instance name => EC2 instance ID."
  value       = { for name, inst in local.all_instances : name => inst.id }
}

output "private_ips" {
  description = "Map of instance name => private IPv4 address."
  value       = { for name, inst in local.all_instances : name => inst.private_ip }
}

output "protected_instances" {
  description = "Names of instances protected by lifecycle.prevent_destroy."
  value       = keys(aws_instance.protected)
}
