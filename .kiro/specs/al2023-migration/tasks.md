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

- [ ] 2. Enhance vmware-sgw Module for Migration Support
  - [ ] 2.1 Add migration-related variables
    - Add `create_cache_disk` variable (default: true)
    - Add `existing_cache_disk_path` variable (default: null)
    - _Requirements: 12.1, 12.3_

  - [ ] 2.2 Update vmware-sgw main.tf with dynamic disk blocks
    - Convert cache disk to dynamic block
    - Add dynamic block for existing disk attachment
    - _Requirements: 12.2, 12.4_

  - [ ] 2.3 Add vm_id output
    - Add `vm_id` output to vmware-sgw module
    - _Requirements: 12.5_

  - [ ] 2.4 Update vmware-sgw lifecycle ignores
    - Handle conditional disk blocks in lifecycle
    - _Requirements: 12.2_

- [ ] 3. Checkpoint - Module Changes Complete
  - Ensure terraform validate passes on both modules
  - Verify existing examples still work (no breaking changes)
  - Ask the user if questions arise

- [ ] 4. Create EC2 Migration Example
  - [ ] 4.1 Create EC2 directory structure
    - Create `examples/sgw-al2023-migration/ec2/` directory
    - Create `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`
    - _Requirements: 3.1, 3.2_

  - [ ] 4.2 Implement EC2 pre-flight validation
    - Add data source for old instance
    - Add `terraform_data` resource with preconditions
    - Validate instance state is "stopped"
    - Add variable validations for resource ID formats
    - _Requirements: 1.1, 1.2, 1.4, 1.5, 1.6_

  - [ ] 4.3 Implement EBS snapshot backup
    - Add `aws_ebs_snapshot` resource with for_each
    - Implement conditional creation based on `create_snapshots` variable
    - Add appropriate tagging
    - _Requirements: 2.1, 2.3, 2.4_

  - [ ] 4.4 Implement EC2 instance provisioning using ec2-sgw module
    - Call ec2-sgw module with migration settings
    - Set create_cache_volume=false, create_eip=false
    - Implement instance type upgrade mapping
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8_

  - [ ] 4.5 Implement EBS cache volume attachment
    - Add `aws_volume_attachment` resources with for_each
    - Generate sequential device names
    - _Requirements: 5.1, 5.2, 5.3, 5.4_

- [ ] 5. Create VMware Migration Example
  - [ ] 5.1 Create VMware directory structure
    - Create `examples/sgw-al2023-migration/vmware/` directory
    - Create `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`
    - _Requirements: 4.1, 4.2_

  - [ ] 5.2 Implement VMware pre-flight validation
    - Add data source for old VM
    - Validate VM is powered off
    - _Requirements: 1.1, 1.3, 1.4, 1.5_

  - [ ] 5.3 Implement VMware VM provisioning using vmware-sgw module
    - Call vmware-sgw module with migration settings
    - Set create_cache_disk=false
    - Pass existing_cache_disk_path for disk attachment
    - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5_

  - [ ] 5.4 Document VMware snapshot procedures
    - Add pre-migration snapshot documentation
    - _Requirements: 2.2_

- [ ] 6. Documentation
  - [ ] 6.1 Create main README.md
    - Overview covering both EC2 and VMware
    - Prerequisites for each platform
    - Quick start guides
    - _Requirements: 10.1, 10.2, 10.5_

  - [ ] 6.2 Create terraform.tfvars.example files
    - EC2 example with instance IDs and volume IDs
    - VMware example with datacenter, cluster, and disk path
    - _Requirements: 10.1_

  - [ ] 6.3 Document rollback procedures
    - EC2 rollback with EBS snapshot restoration
    - VMware rollback with VM snapshot restoration
    - _Requirements: 9.1, 9.2, 9.3, 9.4_

- [ ] 7. Checkpoint - Infrastructure Complete
  - Ensure terraform init/validate passes for both examples
  - Review documentation is complete
  - Ask the user if questions arise

- [ ] 8. Ansible Migration Execution
  - [ ] 8.1 Create Ansible directory structure
    - Create `ansible/` directory with migrate.yml, verify.yml
    - Create `ansible/inventory/` with ec2.yml.example and vmware.yml.example
    - Create ansible.cfg and requirements.yml
    - _Requirements: 7.1, 7.2, 10.1, 10.2_

  - [ ] 8.2 Implement migration playbook
    - Add health check task with retries
    - Add migration API call task
    - Add error handling and result display
    - _Requirements: 7.3, 7.4, 7.5, 7.6_

  - [ ] 8.3 Implement verification playbook
    - Add gateway status verification
    - Add file share connectivity check
    - _Requirements: 8.1_

  - [ ] 8.4 Create inventory templates
    - EC2 template using AWS SSM connection plugin
    - VMware template using SSH connection
    - _Requirements: 7.7, 7.8, 10.3, 10.4_

- [ ] 9. Final Checkpoint
  - All files in place
  - Documentation complete for both EC2 and VMware
  - Terraform validate passes for both examples
  - Ansible playbooks syntax validated
  - Both modules backward compatible
  - Ask the user if questions arise

## Notes

- Tasks 1-2 modify existing modules (backward compatible changes)
- All new variables have defaults that preserve existing behavior
- Both EC2 and VMware migrations are fully automated via Terraform + Ansible
- Ansible playbooks are shared between EC2 and VMware
- EC2 uses SSM Session Manager as Ansible connection (no SSH needed)
- VMware uses SSH connection
- Module changes should be tested with existing examples before proceeding
