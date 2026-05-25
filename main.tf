locals {
  node_ips = {
    for k, v in proxmox_virtual_environment_vm.node :
    k => [
      for addrs in v.ipv4_addresses : addrs[0]
      if length(addrs) > 0 && !startswith(addrs[0], "127.")
    ][0]
  }

  # For controlplane modules (cluster_endpoint = null), derive the endpoint from
  # the first node's DHCP-assigned IP as reported by the QEMU guest agent.
  # Worker modules must pass cluster_endpoint explicitly (the controlplane's IP).
  cluster_endpoint = var.cluster_endpoint != null ? var.cluster_endpoint : "https://${local.node_ips[keys(var.nodes)[0]]}:6443"
}

resource "proxmox_virtual_environment_vm" "node" {
  for_each = var.nodes
  tags            = ["terraform", "talos"]
  name            = each.value.name
  node_name       = each.value.target_node
  description     = "Managed by Terraform — Talos ${var.node_type}"
  on_boot         = var.onboot
  stop_on_destroy = true

  # enabled = true enables the QEMU guest agent interface so Proxmox can read the
  # DHCP-assigned IP via ipv4_addresses. Requires a Talos image built
  # with the qemu-guest-agent extension (https://factory.talos.dev/).
  agent {
    enabled = true
    timeout = "120s"
  }

  cpu {
    cores   = var.cores
    sockets = 1
  }

  memory {
    dedicated = var.memory
  }

  disk {
    interface    = "virtio0"
    datastore_id = var.storage_pool
    size         = var.disk_size
    file_id      = var.image
    iothread     = true
    discard      = "on"
  }

  initialization {
    datastore_id = var.storage_pool
  }

  network_device {
    bridge  = "vmbr0"
    model   = "virtio"
    vlan_id = var.vlan_id == -1 ? null : var.vlan_id
  }

  lifecycle {
    # Talos installs its own bootloader and modifies the disk on first boot.
    # Ignore these after creation to prevent Terraform from fighting Talos.
    ignore_changes = [boot_order, disk]
  }
}

data "talos_machine_configuration" "node" {
  for_each = var.nodes

  cluster_name       = var.cluster_name
  cluster_endpoint   = local.cluster_endpoint
  machine_type       = var.node_type
  machine_secrets    = var.machine_secrets.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
}

resource "talos_machine_configuration_apply" "node" {
  for_each = var.nodes

  client_configuration        = var.machine_secrets.client_configuration
  machine_configuration_input = data.talos_machine_configuration.node[each.key].machine_configuration
  node                        = local.node_ips[each.key]

  # Wait for the VM to exist before trying to reach the Talos maintenance API.
  depends_on = [proxmox_virtual_environment_vm.node]
}
