# kube-talos-node-module

Terraform module that provisions Talos Linux Kubernetes nodes on Proxmox VE. A single module call provisions one role (control plane or worker); call it twice to build a full cluster.

Each call:
1. Creates `proxmox_vm_qemu` VMs booted from the Talos ISO
2. Waits for the QEMU guest agent to report each node's DHCP-assigned IP
3. Generates per-node Talos machine configs via the `siderolabs/talos` provider
4. Applies those configs to each node over the Talos maintenance API

Bootstrapping (`talos_bootstrap`) is intentionally left to the root module so it only runs once across the whole cluster.

## Prerequisites

- Proxmox VE with a Talos ISO uploaded to a datastore — **must include the `qemu-guest-agent` system extension** (see [Talos image factory](https://factory.talos.dev/)). The stock ISO does not include this extension; without it the provider cannot read DHCP-assigned IPs.
- A Proxmox API token with VM creation permissions
- Terraform >= 1.3.0

## Providers

| Name | Source | Version |
|---|---|---|
| proxmox | telmate/proxmox | ~> 3.0 |
| talos | siderolabs/talos | ~> 0.7 |

## Usage

Nodes receive their IP addresses from DHCP automatically — no `ip_address` field is needed. For the control plane module, `cluster_endpoint` is also optional: it is auto-derived from the first control plane node's DHCP-assigned IP. Worker modules must receive the control plane IP explicitly.

```hcl
resource "talos_machine_secrets" "this" {}

module "controlplane" {
  source = "./kube-talos-node-module"

  node_type       = "controlplane"
  cluster_name    = "my-cluster"
  machine_secrets = talos_machine_secrets.this
  talos_version   = "v1.9.5"
  iso_image       = "local:iso/talos-v1.9.5-amd64.iso"

  nodes = {
    cp0 = { name = "cp-0", target_node = "pve0" }
    cp1 = { name = "cp-1", target_node = "pve1" }
    cp2 = { name = "cp-2", target_node = "pve2" }
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
  cluster_endpoint = "https://${module.controlplane.node_ips["cp0"]}:6443"
  machine_secrets  = talos_machine_secrets.this   # same secrets resource
  talos_version    = "v1.9.5"
  iso_image        = "local:iso/talos-v1.9.5-amd64.iso"

  nodes = {
    w0 = { name = "worker-0", target_node = "pve0" }
    w1 = { name = "worker-1", target_node = "pve1" }
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
| `nodes` | Map of nodes to provision. Key is a stable resource identifier. Each value has `name` and `target_node`. | `map(object)` | — | yes |
| `node_type` | Talos node role: `controlplane` or `worker`. | `string` | — | yes |
| `cluster_name` | Talos cluster name. | `string` | — | yes |
| `cluster_endpoint` | Talos cluster API endpoint URL, e.g. `https://192.168.1.10:6443`. When `null`, auto-derived from the first node's DHCP-assigned IP — intended for controlplane modules. Worker modules must pass this explicitly. | `string` | `null` | no |
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
| `node_ips` | Map of node key to DHCP-assigned IP address (read from QEMU guest agent). | no |
| `machine_configurations` | Generated Talos machine configuration YAML per node. | yes |

## How first-boot works

VMs are created with `agent = 1`, which enables the QEMU guest agent interface in Proxmox. Once the VM boots and Talos's guest agent reports the DHCP-assigned IP, the provider populates `default_ipv4_address` and Terraform proceeds.

The `talos_machine_configuration_apply` resource uses that IP to push the machine config over the Talos maintenance API. Talos then installs itself to the virtio disk and reboots.

After that first cycle, `lifecycle.ignore_changes = [boot, disks]` prevents Terraform from resetting the boot order or disk state on subsequent applies.

For the control plane module (`cluster_endpoint = null`), the cluster API endpoint is computed as `https://<first-cp-node-ip>:6443` using `keys(var.nodes)[0]` (alphabetically first key). Worker modules derive the same endpoint by referencing the control plane module's `node_ips` output.
