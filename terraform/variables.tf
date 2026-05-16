variable "proxmox_api_url" {
  description = "Proxmox API endpoint"
  default     = "https://192.168.1.235:8006/"
}

variable "proxmox_api_token" {
  description = "Proxmox API token in format user@realm!tokenid=secret"
  sensitive   = true
}

variable "vm_template_id" {
  description = "VMID of the Ubuntu 22.04 cloud-init template"
  default     = 9000
}

variable "storage_pool" {
  description = "Proxmox storage pool for VM disks"
  default     = "vmdata"
}

variable "network_bridge" {
  description = "Network bridge for VM NICs"
  default     = "vmbr1"
}
