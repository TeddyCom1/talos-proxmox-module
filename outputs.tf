output "node_ips" {
  description = "Map of node key to IP address."
  value       = { for k, v in var.nodes : k => v.ip_address }
}

output "machine_configurations" {
  description = "Generated Talos machine configuration YAML per node."
  value       = { for k, v in talos_machine_configuration.node : k => v.machine_configuration }
  sensitive   = true
}
