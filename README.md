# kube-talos-node-module

Terraform module that provisions a single Talos Linux Kubernetes node on Proxmox VE. Each call creates one VM for one role (control plane or worker); call it once per node to build a full cluster.

Each call:
1. Creates a `proxmox_virtual_environment_vm` VM booted from the Talos ISO
2. Waits for the QEMU guest agent to report the node's DHCP-assigned IP
3. Generates the Talos machine config via the `siderolabs/talos` provider

Applying the machine config (`talos_machine_configuration_apply`) and bootstrapping the cluster (`talos_machine_bootstrap`) are intentionally left to the root module — this module only hands back what's needed (`ip` and `machine_configuration`) so the caller can drive that lifecycle itself, e.g. to sequence control-plane bootstrap before workers join.

## Prerequisites

- Proxmox VE with a Talos ISO uploaded to a datastore — **must include the `qemu-guest-agent` system extension** (see [Talos image factory](https://factory.talos.dev/)). The stock ISO does not include this extension; without it the provider cannot read DHCP-assigned IPs.
- A Proxmox API token with VM creation permissions
- Terraform >= 1.3.0

## Providers

| Name | Source | Version |
|---|---|---|
| proxmox | bpg/proxmox | >= 0.66.0 |
| talos | siderolabs/talos | ~> 0.7 |

## Usage

The node receives its IP address from DHCP automatically — no `ip_address` field is needed. For a control plane node, `cluster_endpoint` is also optional: it is auto-derived from the node's own DHCP-assigned IP. Worker nodes must receive the control plane IP explicitly.

```hcl
resource "talos_machine_secrets" "this" {}

module "controlplane" {
  source = "./kube-talos-node-module"

  node_type       = "controlplane"
  cluster_name    = "my-cluster"
  machine_secrets = talos_machine_secrets.this
  talos_version   = "v1.9.5"
  image_id        = "local:iso/talos-v1.9.5-amd64.iso"
  vm_name         = "cp-0"
  target_node     = "pve0"

  cores     = 2
  memory    = 4096
  disk_size = 20
  vlan_id   = 10
}

resource "talos_machine_configuration_apply" "controlplane" {
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = module.controlplane.machine_configuration
  node                        = module.controlplane.ip
}

resource "talos_machine_bootstrap" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                  = module.controlplane.ip
  depends_on            = [talos_machine_configuration_apply.controlplane]
}

module "worker" {
  source = "./kube-talos-node-module"

  node_type        = "worker"
  cluster_name     = "my-cluster"
  cluster_endpoint = "https://${module.controlplane.ip}:6443"
  machine_secrets  = talos_machine_secrets.this   # same secrets resource
  talos_version    = "v1.9.5"
  image_id         = "local:iso/talos-v1.9.5-amd64.iso"
  vm_name          = "worker-0"
  target_node      = "pve0"

  cores     = 4
  memory    = 8192
  disk_size = 50
}

resource "talos_machine_configuration_apply" "worker" {
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = module.worker.machine_configuration
  node                        = module.worker.ip
  depends_on                   = [talos_machine_bootstrap.this]
}
```

> **Important:** `talos_machine_secrets` must be created once and passed to every module call for the same cluster. Creating separate secrets per module call produces separate clusters.

## Variables

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `vm_name` | Name of the Proxmox VM. | `string` | — | yes |
| `target_node` | Proxmox node to place the VM on. | `string` | — | yes |
| `node_type` | Talos node role: `controlplane` or `worker`. | `string` | — | yes |
| `cluster_name` | Talos cluster name. | `string` | — | yes |
| `cluster_endpoint` | Talos cluster API endpoint URL, e.g. `https://192.168.1.10:6443`. When `null`, auto-derived from this node's DHCP-assigned IP — intended for controlplane modules. Worker modules must pass this explicitly. | `string` | `null` | no |
| `machine_secrets` | The `talos_machine_secrets` resource. Shared across all calls for the same cluster. | `any` | — | yes |
| `talos_version` | Talos version string, e.g. `v1.9.5`. Controls the machine config format. | `string` | — | yes |
| `image_id` | Proxmox datastore path to the Talos ISO, e.g. `local:iso/talos-v1.9.5-amd64.iso`. | `string` | — | yes |
| `kubernetes_version` | Kubernetes version to install. Defaults to the version bundled with `talos_version`. | `string` | `null` | no |
| `storage_pool` | Proxmox storage pool for the boot disk. | `string` | `"local-lvm"` | no |
| `vlan_id` | VLAN tag for the node NIC. `-1` for untagged. | `number` | `-1` | no |
| `cores` | Number of vCPU cores. | `number` | `2` | no |
| `memory` | Memory in MiB. | `number` | `2048` | no |
| `disk_size` | Boot disk size in GiB. | `number` | `20` | no |
| `onboot` | Start the VM automatically when the Proxmox host boots. | `bool` | `true` | no |

## Outputs

| Name | Description | Sensitive |
|---|---|---|
| `ip` | DHCP-assigned IP address of the node (read from QEMU guest agent). | no |
| `machine_configuration` | Generated Talos machine configuration YAML for the node. | yes |

## How first-boot works

The VM is created with `agent { enabled = true }`, which enables the QEMU guest agent interface in Proxmox. Once the VM boots and Talos's guest agent reports the DHCP-assigned IP, the provider populates `ipv4_addresses` and Terraform proceeds.

The caller is expected to take the `machine_configuration` output and apply it via its own `talos_machine_configuration_apply` resource, targeting the `ip` output — see the usage example above. Talos then installs itself to the virtio disk and reboots.

After that first cycle, `lifecycle.ignore_changes = [boot_order, disk]` prevents Terraform from resetting the boot order or disk state on subsequent applies.

For a control plane node (`cluster_endpoint = null`), the cluster API endpoint is computed as `https://<this-node-ip>:6443`. Worker nodes derive the same endpoint by referencing the control plane module's `ip` output.
