# kube-talos-node-module

Terraform module that provisions Talos Linux Kubernetes nodes on Proxmox VE. A single module call provisions one role (control plane or worker); call it twice to build a full cluster.

Each call:
1. Creates `proxmox_vm_qemu` VMs booted from the Talos ISO
2. Generates per-node Talos machine configs via the `siderolabs/talos` provider
3. Applies those configs to each node over the Talos maintenance API

Bootstrapping (`talos_bootstrap`) is intentionally left to the root module so it only runs once across the whole cluster.

## Prerequisites

- Proxmox VE with the Talos ISO uploaded to a datastore (download from [github.com/siderolabs/talos/releases](https://github.com/siderolabs/talos/releases))
- DHCP reservations so each node IP is known before `terraform apply`
- A Proxmox API token with VM creation permissions
- Terraform >= 1.3.0

## Providers

| Name | Source | Version |
|---|---|---|
| proxmox | telmate/proxmox | ~> 3.0 |
| talos | siderolabs/talos | ~> 0.7 |

## Usage

```hcl
resource "talos_machine_secrets" "this" {}

module "controlplane" {
  source = "./kube-talos-node-module"

  node_type        = "controlplane"
  cluster_name     = "my-cluster"
  cluster_endpoint = "https://192.168.1.10:6443"
  machine_secrets  = talos_machine_secrets.this
  talos_version    = "v1.9.5"
  iso_image        = "local:iso/talos-v1.9.5-amd64.iso"

  nodes = {
    cp0 = { name = "cp-0", target_node = "pve0", ip_address = "192.168.1.10" }
    cp1 = { name = "cp-1", target_node = "pve1", ip_address = "192.168.1.11" }
    cp2 = { name = "cp-2", target_node = "pve2", ip_address = "192.168.1.12" }
  }

  cores     = 2
  memory    = 4096
  disk_size = 20
  vlan_id   = 10
}

resource "talos_bootstrap" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = module.controlplane.node_ips["cp0"]
  depends_on           = [module.controlplane]
}

module "workers" {
  source = "./kube-talos-node-module"

  node_type        = "worker"
  cluster_name     = "my-cluster"
  cluster_endpoint = "https://192.168.1.10:6443"
  machine_secrets  = talos_machine_secrets.this   # same secrets resource
  talos_version    = "v1.9.5"
  iso_image        = "local:iso/talos-v1.9.5-amd64.iso"

  nodes = {
    w0 = { name = "worker-0", target_node = "pve0", ip_address = "192.168.1.20" }
    w1 = { name = "worker-1", target_node = "pve1", ip_address = "192.168.1.21" }
  }

  cores     = 4
  memory    = 8192
  disk_size = 50

  depends_on = [talos_bootstrap.this]
}
```

> **Important:** `talos_machine_secrets` must be created once and passed to every module call for the same cluster. Creating separate secrets per module call produces separate clusters.

## Variables

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `nodes` | Map of nodes to provision. Key is a stable resource identifier. Each value has `name`, `target_node`, and `ip_address`. | `map(object)` | — | yes |
| `node_type` | Talos node role: `controlplane` or `worker`. | `string` | — | yes |
| `cluster_name` | Talos cluster name. | `string` | — | yes |
| `cluster_endpoint` | Talos cluster API endpoint URL, e.g. `https://192.168.1.10:6443`. | `string` | — | yes |
| `machine_secrets` | The `talos_machine_secrets` resource. Shared across all calls for the same cluster. | `any` | — | yes |
| `talos_version` | Talos version string, e.g. `v1.9.5`. Controls the machine config format. | `string` | — | yes |
| `iso_image` | Proxmox datastore path to the Talos ISO, e.g. `local:iso/talos-v1.9.5-amd64.iso`. | `string` | — | yes |
| `kubernetes_version` | Kubernetes version to install. Defaults to the version bundled with `talos_version`. | `string` | `null` | no |
| `storage_pool` | Proxmox storage pool for the boot disk. | `string` | `"local-lvm"` | no |
| `vlan_id` | VLAN tag for the node NIC. `-1` for untagged. | `number` | `-1` | no |
| `cores` | Number of vCPU cores per node. | `number` | `2` | no |
| `memory` | Memory per node in MiB. | `number` | `2048` | no |
| `disk_size` | Boot disk size per node in GiB. | `number` | `20` | no |
| `onboot` | Start VMs automatically when the Proxmox host boots. | `bool` | `true` | no |

## Outputs

| Name | Description | Sensitive |
|---|---|---|
| `node_ips` | Map of node key to IP address. | no |
| `machine_configurations` | Generated Talos machine configuration YAML per node. | yes |

## How first-boot works

VMs are created with the CD-ROM as the first boot device. On first boot, Talos runs in maintenance mode and the `talos_machine_configuration_apply` resource connects to each node's IP to push its machine config. Talos then installs itself to the virtio disk and reboots from disk.

After that first cycle, `lifecycle.ignore_changes = [boot, disks]` prevents Terraform from resetting the boot order or disk state on subsequent applies.
