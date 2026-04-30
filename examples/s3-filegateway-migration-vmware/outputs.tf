################################################################################
# Migration Outputs
################################################################################

output "migration_summary" {
  description = "Summary of the migration process"
  value = {
    gateway_id    = var.gateway_id
    old_vm_name   = var.old_vm_name
    new_vm_name   = local.new_vm_name
    old_vm_cpus   = data.vsphere_virtual_machine.old_sgw.num_cpus
    new_vm_cpus   = local.new_cpus
    old_vm_memory = data.vsphere_virtual_machine.old_sgw.memory
    new_vm_memory = local.new_memory
    old_vm_disks  = local.old_vm_disks
    datacenter    = var.datacenter
    datastore     = var.datastore
    cluster       = var.cluster
    host          = var.host
    network       = var.network
  }
}

output "new_gateway_ip" {
  description = "IP address of the new gateway VM"
  value       = data.vsphere_virtual_machine.new_sgw_info.guest_ip_addresses[0]
}

output "old_vm_name" {
  description = "Name of the old gateway VM in vSphere"
  value       = var.old_vm_name
}

output "new_vm_name" {
  description = "Name of the new gateway VM in vSphere"
  value       = local.new_vm_name
}

output "gateway_id" {
  description = "The Storage Gateway ID being migrated"
  value       = var.gateway_id
}

output "aws_region" {
  description = "The AWS region where the gateway is registered"
  value       = data.aws_region.current.name
}

output "migration_url" {
  description = "URL to initiate the gateway migration process"
  value       = "http://${data.vsphere_virtual_machine.new_sgw_info.guest_ip_addresses[0]}/migrate?gatewayId=${var.gateway_id}"
}

output "next_steps" {
  description = "Next steps to complete the migration"
  value       = <<-EOT
    Migration Infrastructure Provisioned Successfully!
    
    AUTOMATED MIGRATION (Recommended):
    ===================================
    Run the Ansible playbook to automate the migration:
    
      cd ansible/
      chmod +x run-migration.sh
      ./run-migration.sh
    
    The playbook will automatically:
    - Power off the old gateway VM
    - Detach cache disks (VMDKs) from the old VM
    - Attach cache disks and old root disk to the new VM
    - Trigger the migration using the migration URL
    - Detach the old root disk after successful migration
    - Re-join the Gateway to the AD domain if previously joined
    - Complete the migration
  EOT
}
