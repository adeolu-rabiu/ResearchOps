terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.61.1"
    }
  }
  required_version = ">= 1.7.0"
}

provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = var.proxmox_api_token
  insecure  = true
}
