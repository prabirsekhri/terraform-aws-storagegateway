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

- [ ] 3. Create Migration Example Structure
  - [ ] 3.1 Create base file structure
    - Create `examples/ec2-sgw-al2023-migration/` directory
    - Create `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`
    - _Requirements: 3.1, 3.2_

  - [ ] 3.2 Implement pre-flight validation
    - Add data source for old instance
    - Add `terraform_data` resource with preconditions
    - Validate instance state is "stopped"
    - Add variable validations for resource ID formats
    - _Requirements: 1.1, 1.2, 1.3, 1.4_

  - [ ] 3.3 Implement EBS snapshot backup
    - Add `aws_ebs_snapshot` resource with for_each
    - Implement conditional creation based on `create_snapshots` variable
    - Add appropriate tagging
    - _Requirements: 2.1, 2.2, 2.3_

  - [ ] 3.4 Implement instance provisioning using ec2-sgw module
    - Call ec2-sgw module with migration settings
    - Set create_cache_volume=false, create_eip=false
    - Implement instance type upgrade mapping
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8_

  - [ ] 3.5 Implement cache volume attachment
    - Add `aws_volume_attachment` resources with for_each
    - Generate sequential device names
    - _Requirements: 4.1, 4.2, 4.3, 4.4_

- [ ] 4. Documentation and Examples
  - [ ] 4.1 Create README.md with usage instructions
    - Document prerequisites
    - Add usage examples
    - Document input variables and outputs
    - _Requirements: 6.2, 6.3_

  - [ ] 4.2 Create terraform.tfvars.example
    - Provide example values for all required variables
    - Include comments explaining each variable
    - _Requirements: 6.3_

  - [ ] 4.3 Document rollback procedures
    - Add rollback section to README
    - Include snapshot restoration steps
    - _Requirements: 7.1, 7.2, 7.3_

- [ ] 5. Checkpoint - Core Infrastructure Complete
  - Ensure terraform init/validate passes
  - Review outputs provide clear next steps
  - Ask the user if questions arise

- [ ] 6. SSM Migration Execution
  - [ ] 6.1 Create SSM document for migration
    - Create `ssm.tf` with `aws_ssm_document` resource
    - Define migration command with health check and curl
    - Add configurable timeout
    - _Requirements: 5.1, 5.2, 5.3, 5.5_

  - [ ] 6.2 Implement SSM association/execution
    - Add `aws_ssm_association` to trigger migration
    - Ensure proper dependency on volume attachment
    - _Requirements: 5.1, 5.4_

  - [ ] 6.3 Create optional IAM resources
    - Create `iam.tf` with conditional IAM role
    - Add SSM managed policy attachment
    - Create instance profile
    - _Requirements: 8.1, 8.2, 8.3_

- [ ] 7. Final Checkpoint
  - All files in place
  - Documentation complete
  - Terraform validate passes
  - ec2-sgw module backward compatible
  - Ask the user if questions arise

## Notes

- Task 1 modifies the existing ec2-sgw module (backward compatible changes)
- All new variables have defaults that preserve existing behavior
- SSM Run Command is used for migration execution
- IAM role creation is optional - users can provide existing instance profile
- ec2-sgw module changes should be tested with existing examples before proceeding
