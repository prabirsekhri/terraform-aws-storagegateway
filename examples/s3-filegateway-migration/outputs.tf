################################################################################
# Migration Outputs
################################################################################

output "migration_summary" {
  description = "Summary of the migration process"
  value = {
    gateway_id        = var.gateway_id
    old_instance_id   = data.aws_instance.old_sgw.id
    new_instance_id   = module.new_sgw.instance_id
    old_instance_type = data.aws_instance.old_sgw.instance_type
    new_instance_type = local.new_instance_type
    vpc_id            = local.vpc_id
    subnet_id         = data.aws_instance.old_sgw.subnet_id
    availability_zone = data.aws_instance.old_sgw.availability_zone
    cache_volumes     = data.aws_ebs_volumes.cache_volumes.ids
  }
}

output "new_gateway_instance_id" {
  description = "The EC2 instance ID of the new AL2023 Storage Gateway"
  value       = module.new_sgw.instance_id
}

output "new_gateway_private_ip" {
  description = "The private IP address of the new Storage Gateway"
  value       = module.new_sgw.private_ip
}

output "new_gateway_public_ip" {
  description = "The public IP address of the new Storage Gateway"
  value       = module.new_sgw.public_ip
  sensitive   = true
}

output "old_instance_id" {
  description = "The EC2 instance ID of the old AL2 Storage Gateway"
  value       = data.aws_instance.old_sgw.id
}

output "gateway_id" {
  description = "The Storage Gateway ID being migrated"
  value       = var.gateway_id
}

output "aws_region" {
  description = "The AWS region where the migration is taking place"
  value       = regex("^([a-z]+-[a-z]+-[0-9]+)", data.aws_instance.old_sgw.availability_zone)
}

output "migration_url" {
  description = "URL to initiate the gateway migration process"
  value       = "http://${module.new_sgw.private_ip}/migrate?gatewayId=${var.gateway_id}"
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
    - Stop old gateway instance
    - Detach and reattach volumes from old gateway instance to new gateway instance 
    - Trigger the migration using URL
    - Complete the process
  EOT
}
