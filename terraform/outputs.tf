output "vm_inventory" {
  description = "All provisioned VMs with IPs"
  value = {
    for k, v in local.vms : k => {
      vmid = v.vmid
      ip   = v.ip
    }
  }
}
