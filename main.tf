locals {
  node_ip_candidates = [
    for addrs in proxmox_virtual_environment_vm.node.ipv4_addresses : addrs[0]
    if length(addrs) > 0 && !startswith(addrs[0], "127.")
  ]

  # null until the QEMU guest agent reports a non-loopback address; guarded by
  # the precondition on data.talos_machine_configuration.node below so a still-booting
  # VM produces one clear error instead of crashing on an empty-list index.
  node_ip = length(local.node_ip_candidates) > 0 ? local.node_ip_candidates[0] : null

  # For controlplane modules (cluster_endpoint = null), derive the endpoint from
  # this node's DHCP-assigned IP as reported by the QEMU guest agent.
  # Worker modules must pass cluster_endpoint explicitly (the controlplane's IP).
  cluster_endpoint = var.cluster_endpoint != null ? var.cluster_endpoint : "https://${local.node_ip}:6443"
}

resource "proxmox_virtual_environment_vm" "node" {
  tags            = ["terraform", "talos"]
  name            = var.vm_name
  node_name       = var.target_node
  description     = "Managed by Terraform — Talos ${var.node_type}"
  on_boot         = var.onboot
  stop_on_destroy = true

  # enabled = true enables the QEMU guest agent interface so Proxmox can read the
  # DHCP-assigned IP via ipv4_addresses. Requires a Talos image built
  # with the qemu-guest-agent extension (https://factory.talos.dev/).
  agent {
    enabled = true
  }

  cpu {
    cores = var.cores
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = var.memory
  }

  disk {
    datastore_id = var.storage_pool
    file_id      = var.image_id
    file_format  = "raw"
    interface    = "virtio0"
    iothread     = true
    discard      = "on"
    size         = var.disk_size
  }

  network_device {
    bridge  = "vmbr0"
    vlan_id = var.vlan_id == -1 ? null : var.vlan_id
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    # Talos installs its own bootloader and modifies the disk on first boot.
    # Ignore these after creation to prevent Terraform from fighting Talos.
    ignore_changes = [boot_order, disk]
  }
}

data "talos_machine_configuration" "node" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = local.cluster_endpoint
  machine_type       = var.node_type
  machine_secrets    = var.machine_secrets.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version

  lifecycle {
    precondition {
      condition     = local.node_ip != null
      error_message = "VM '${var.vm_name}' has no non-loopback IPv4 address yet. The QEMU guest agent hasn't reported an address — the VM may still be booting, or the Talos image is missing the qemu-guest-agent extension (https://factory.talos.dev/). Re-run apply once the VM is up."
    }
  }
}
