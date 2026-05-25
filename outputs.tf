output "node_ips" {
  description = "Map of node key to DHCP-assigned IP address."
  value       = local.node_ips
}

output "machine_configurations" {
  description = "Generated Talos machine configuration YAML per node."
  value       = { for k, v in data.talos_machine_configuration.node : k => v.machine_configuration }
  sensitive   = true
}
