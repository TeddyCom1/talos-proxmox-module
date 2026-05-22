resource "proxmox_vm_qemu" "node" {
  for_each = var.nodes

  name        = each.value.name
  target_node = each.value.target_node
  desc        = "Managed by Terraform — Talos ${var.node_type}"

  agent   = 0
  onboot  = var.onboot
  cores   = var.cores
  memory  = var.memory
  cpu     = "host"
  sockets = 1

  # Boot from CD first so Talos can install, then fall back to disk.
  # After first boot Talos writes its own bootloader; this order is then irrelevant.
  boot = "order=ide0;virtio0"

  disks {
    virtio {
      virtio0 {
        disk {
          size    = var.disk_size
          storage = var.storage_pool
        }
      }
    }
    ide {
      ide0 {
        cdrom {
          iso = var.iso_image
        }
      }
    }
  }

  network {
    bridge = "vmbr0"
    model  = "virtio"
    tag    = var.vlan_id
  }

  lifecycle {
    # Talos installs its own bootloader and modifies the disk on first boot.
    # Ignore these after creation to prevent Terraform from fighting Talos.
    ignore_changes = [boot, disks]
  }
}

resource "talos_machine_configuration" "node" {
  for_each = var.nodes

  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  machine_type       = var.node_type
  machine_secrets    = var.machine_secrets.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
}

resource "talos_machine_configuration_apply" "node" {
  for_each = var.nodes

  client_configuration        = var.machine_secrets.client_configuration
  machine_configuration_input = talos_machine_configuration.node[each.key].machine_configuration
  node                        = each.value.ip_address

  # Wait for the VM to exist before trying to reach the Talos maintenance API.
  depends_on = [proxmox_vm_qemu.node]
}
