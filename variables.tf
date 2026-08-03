variable "vm_name" {
  description = "Name of the Proxmox VM."
  type        = string
}

variable "target_node" {
  description = "Proxmox node to place the VM on."
  type        = string
}

variable "node_type" {
  description = "Talos node role: 'controlplane' or 'worker'."
  type        = string
  validation {
    condition     = contains(["controlplane", "worker"], var.node_type)
    error_message = "node_type must be 'controlplane' or 'worker'."
  }
}

variable "cluster_name" {
  description = "Talos cluster name."
  type        = string
}

variable "cluster_endpoint" {
  description = "Talos cluster API endpoint URL, e.g. https://192.168.1.10:6443. When null (controlplane modules), auto-derived from the first node's DHCP-assigned IP."
  type        = string
  default     = null
}

variable "machine_secrets" {
  description = "The talos_machine_secrets resource. Must be shared across all node module calls for the same cluster."
  type        = any
  sensitive   = true
}

variable "talos_version" {
  description = "Talos version string, e.g. v1.9.5. Controls the generated machine config format."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version to install. Defaults to the version bundled with talos_version when null."
  type        = string
  default     = null
}

variable "image_id" {
  description = "Proxmox datastore path to the Talos ISO, e.g. local:iso/talos-v1.9.5-amd64.iso."
  type        = string
}

variable "storage_pool" {
  description = "Proxmox storage pool for the node boot disk."
  type        = string
  default     = "local-lvm"
}

variable "vlan_id" {
  description = "VLAN tag for the node NIC. -1 means untagged."
  type        = number
  default     = -1
}

variable "cores" {
  description = "Number of vCPU cores per node."
  type        = number
  default     = 2
}

variable "memory" {
  description = "Memory per node in MiB."
  type        = number
  default     = 2048
}

variable "disk_size" {
  description = "Boot disk size per node in GiB."
  type        = number
  default     = 20
}

variable "onboot" {
  description = "Start the VM automatically when the Proxmox host boots."
  type        = bool
  default     = true
}
