# Implementation Plan: AL2023 Migration Automation

## Overview

This plan outlines the implementation tasks for building the Storage Gateway AL2 to AL2023 migration automation. Tasks are organized to enable incremental contributions from the community.

## Tasks

- [ ] 1. Enhance ec2-sgw Module for Migration Support
  - [ ] 1.1 Add migration-related variables
    - Add `create_cache_volume` variable (default: true)
    - Add `create_eip` variable (default: true)
    - Add `iam_instance_profile` variable (default: null)
    - _Requirements: 9.1, 9.3, 9.5_

  - [ ] 1.2 Update ec2-sgw main.tf with conditional resources
    - Add count to `aws_ebs_volume.cache_disk`
    - Add count to `aws_volume_attachment.ebs_volume`
    - Add count to `aws_eip.ip` and `aws_eip_association.eip_assoc`
    - Add `iam_instance_profile` to `aws_instance.ec2_sgw`
    - _Requirements: 9.2, 9.4, 9.5_

  - [ ] 1.3 Add instance_id output
    - Add `instance_id` output to ec2-sgw module
    - _Requirements: 9.6_

  - [ ] 1.4 Update ec2-sgw outputs for conditional resources
    - Handle null values for public_ip when create_eip=false
    - _Requirements: 9.4_

- [ ] 2. Checkpoint - ec2-sgw Module Changes
  - Ensure terraform validate passes on ec2-sgw module
  - Verify existing examples still work (no breaking changes)
  - Ask the user if questions arise

- [ ] 3. Create EC2 Migration Example
  - [ ] 3.1 Create EC2 directory structure
    - Create `examples/sgw-al2023-migration/ec2/` directory
    - Create `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`
    - _Requirements: 3.1, 3.2_

  - [ ] 3.2 Implement EC2 pre-flight validation
    - Add data source for old instance
    - Add `terraform_data` resource with preconditions
    - Validate instance state is "stopped"
    - Add variable validations for resource ID formats
    - _Requirements: 1.1, 1.2, 1.4, 1.5, 1.6_

  - [ ] 3.3 Implement EBS snapshot backup
    - Add `aws_ebs_snapshot` resource with for_each
    - Implement conditional creation based on `create_snapshots` variable
    - Add appropriate tagging
    - _Requirements: 2.1, 2.3, 2.4_

  - [ ] 3.4 Implement EC2 instance provisioning using ec2-sgw module
    - Call ec2-sgw module with migration settings
    - Set create_cache_volume=false, create_eip=false
    - Implement instance type upgrade mapping
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8_

  - [ ] 3.5 Implement EBS cache volume attachment
    - Add `aws_volume_attachment` resources with for_each
    - Generate sequential device names
    - _Requirements: 5.1, 5.2, 5.3, 5.4_

- [ ] 4. Create VMware Migration Documentation
  - [ ] 4.1 Create VMware directory structure
    - Create `examples/sgw-al2023-migration/vmware/` directory
    - Create README.md, variables.tf, terraform.tfvars.example
    - _Requirements: 4.1_

  - [ ] 4.2 Document OVA deployment process
    - Add AL2023 OVA download URL
    - Document vSphere/ESXi deployment steps
    - Document network configuration
    - _Requirements: 4.2, 4.3, 4.4_

  - [ ] 4.3 Document VMDK cache disk migration
    - Document VMDK detachment from old VM
    - Document VMDK attachment to new VM
    - Document SCSI controller and disk_node configuration
    - _Requirements: 4.5, 6.1, 6.2, 6.3, 6.4_

- [ ] 5. Documentation
  - [ ] 5.1 Create main README.md
    - Overview covering both EC2 and VMware
    - Prerequisites for each platform
    - Quick start guides
    - _Requirements: 8.1, 8.2, 8.3_

  - [ ] 5.2 Create terraform.tfvars.example files
    - EC2 example with instance IDs and volume IDs
    - VMware example with gateway IP and SSH key path
    - _Requirements: 8.1_

  - [ ] 5.3 Document rollback procedures
    - EC2 rollback with EBS snapshot restoration
    - VMware rollback with VM snapshot restoration
    - _Requirements: 9.1, 9.2, 9.3, 9.4_

- [ ] 6. Checkpoint - Infrastructure Complete
  - Ensure terraform init/validate passes for EC2 example
  - Review VMware documentation is complete
  - Ask the user if questions arise

- [ ] 7. Ansible Migration Execution
  - [ ] 7.1 Create Ansible directory structure
    - Create `ansible/` directory with migrate.yml, verify.yml
    - Create `ansible/inventory/` with ec2.yml.example and vmware.yml.example
    - Create ansible.cfg and requirements.yml
    - _Requirements: 7.1, 7.2, 10.1, 10.2_

  - [ ] 7.2 Implement migration playbook
    - Add health check task with retries
    - Add migration API call task
    - Add error handling and result display
    - _Requirements: 7.3, 7.4, 7.5, 7.6_

  - [ ] 7.3 Implement verification playbook
    - Add gateway status verification
    - Add file share connectivity check
    - _Requirements: 8.1_

  - [ ] 7.4 Create inventory templates
    - EC2 template using AWS SSM connection plugin
    - VMware template using SSH connection
    - _Requirements: 7.7, 7.8, 10.3, 10.4_

- [ ] 8. Final Checkpoint
  - All files in place
  - Documentation complete for both EC2 and VMware
  - Terraform validate passes for EC2 example
  - Ansible playbooks syntax validated
  - ec2-sgw module backward compatible
  - Ask the user if questions arise

## Notes

- Task 1 modifies the existing ec2-sgw module (backward compatible changes)
- All new variables have defaults that preserve existing behavior
- EC2 migration is fully automated via Terraform + Ansible
- VMware migration is documentation + Ansible (OVA deployment is manual via vSphere)
- Ansible playbooks are shared between EC2 and VMware
- EC2 uses SSM Session Manager as Ansible connection (no SSH needed)
- VMware uses SSH connection
- ec2-sgw module changes should be tested with existing examples before proceeding
