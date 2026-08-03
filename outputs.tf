output "ip" {
  description = "DHCP-assigned IP address of the node."
  value       = local.node_ip
}

output "machine_configuration" {
  description = "Generated Talos machine configuration YAML for the node."
  value       = data.talos_machine_configuration.node.machine_configuration
  sensitive   = true
}
