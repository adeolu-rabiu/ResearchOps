locals {
  vms = {
    "submit-node" = {
      vmid   = 200
      memory = 2048
      cores  = 2
      disk   = 20
      ip     = "10.0.0.10"
    }
    "central-manager" = {
      vmid   = 201
      memory = 2048
      cores  = 2
      disk   = 20
      ip     = "10.0.0.11"
    }
    "execute-node-1" = {
      vmid   = 202
      memory = 4096
      cores  = 4
      disk   = 40
      ip     = "10.0.0.12"
    }
    "execute-node-2" = {
      vmid   = 203
      memory = 4096
      cores  = 4
      disk   = 40
      ip     = "10.0.0.13"
    }
    "nfs-server" = {
      vmid   = 204
      memory = 1024
      cores  = 1
      disk   = 100
      ip     = "10.0.0.14"
    }
    "monitoring" = {
      vmid   = 205
      memory = 2048
      cores  = 2
      disk   = 20
      ip     = "10.0.0.15"
    }
  }
}

resource "proxmox_virtual_environment_vm" "lab_vms" {
  for_each  = local.vms
  name      = each.key
  node_name = "rabtech"
  vm_id     = each.value.vmid

  clone {
    vm_id = var.vm_template_id
    full  = true
  }

  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    datastore_id = var.storage_pool
    size         = each.value.disk
    interface    = "scsi0"
    file_format  = "raw"
    iothread     = true
  }

  network_device {
    bridge = var.network_bridge
    model  = "virtio"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "${each.value.ip}/24"
        gateway = "10.0.0.1"
      }
    }
    user_account {
      keys = [trimspace(file("~/.ssh/id_rsa.pub"))]
    }
  }

  agent {
    enabled = true
  }

  lifecycle {
    ignore_changes = [clone]
  }
}
