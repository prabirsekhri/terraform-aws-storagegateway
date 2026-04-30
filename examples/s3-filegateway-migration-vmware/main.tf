################################################################################
# S3 File Gateway Migration Example - VMware (Method 1)
# Migrates an existing VMware gateway to a new VM while preserving cache disks
# and Gateway ID. Follows AWS Method 1:
# https://docs.aws.amazon.com/filegateway/latest/files3/migrate-data.html
################################################################################

################################################################################
# Data Sources - Gather information about existing gateway and vSphere
################################################################################

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# vSphere infrastructure lookups
data "vsphere_datacenter" "dc" {
  name = var.datacenter
}

data "vsphere_datastore" "datastore" {
  name          = var.datastore
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_compute_cluster" "cluster" {
  name          = var.cluster
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_host" "host" {
  name          = var.host
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_network" "network" {
  name          = var.network
  datacenter_id = data.vsphere_datacenter.dc.id
}

# Look up the existing gateway VM to extract its configuration
data "vsphere_virtual_machine" "old_sgw" {
  name          = var.old_vm_name
  datacenter_id = data.vsphere_datacenter.dc.id
}

locals {
  new_vm_name = var.new_vm_name != null ? var.new_vm_name : "${var.old_vm_name}-new"

  # Use provided values or fall back to old VM configuration
  new_cpus   = var.cpus != null ? var.cpus : tostring(data.vsphere_virtual_machine.old_sgw.num_cpus)
  new_memory = var.memory != null ? var.memory : tostring(data.vsphere_virtual_machine.old_sgw.memory)

  # Extract disk info from old VM
  # disk 0 = OS disk, disk 1+ = cache disks
  old_vm_disks = data.vsphere_virtual_machine.old_sgw.disks
}

################################################################################
# Read OVA properties for the new gateway VM
################################################################################

data "vsphere_ovf_vm_template" "sgw" {
  name              = local.new_vm_name
  resource_pool_id  = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id      = data.vsphere_datastore.datastore.id
  host_system_id    = data.vsphere_host.host.id
  local_ovf_path    = var.local_ovf_path
  remote_ovf_url    = var.local_ovf_path == null ? var.remote_ovf_url : null
  disk_provisioning = var.provisioning_type
  ovf_network_map = {
    "VM Network" = data.vsphere_network.network.id
  }
}

################################################################################
# New Gateway VM - Deploy from OVA (no cache disk, migration will reuse old ones)
################################################################################

resource "vsphere_virtual_machine" "new_sgw" {
  host_system_id             = data.vsphere_host.host.id
  resource_pool_id           = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id               = data.vsphere_datastore.datastore.id
  datacenter_id              = data.vsphere_datacenter.dc.id
  name                       = local.new_vm_name
  num_cpus                   = local.new_cpus
  memory                     = local.new_memory
  guest_id                   = data.vsphere_ovf_vm_template.sgw.guest_id
  firmware                   = data.vsphere_ovf_vm_template.sgw.firmware
  wait_for_guest_net_timeout = 1
  sync_time_with_host        = true

  network_interface {
    network_id = data.vsphere_network.network.id
  }

  # OS disk only - no cache disk. Cache disks are migrated from the old VM.
  disk {
    label            = "os"
    unit_number      = 0
    size             = 80
    thin_provisioned = false
    eagerly_scrub    = false
  }

  ovf_deploy {
    local_ovf_path    = var.local_ovf_path != null ? var.local_ovf_path : null
    remote_ovf_url    = var.remote_ovf_url != null && var.local_ovf_path == null ? var.remote_ovf_url : null
    disk_provisioning = data.vsphere_ovf_vm_template.sgw.disk_provisioning
    ovf_network_map   = data.vsphere_ovf_vm_template.sgw.ovf_network_map
  }

  lifecycle {
    ignore_changes = [
      host_system_id,
      annotation,
      disk[0].io_share_count,
      disk[0].thin_provisioned,
    ]
  }
}

# Get the IP of the new VM after it boots
data "vsphere_virtual_machine" "new_sgw_info" {
  name          = local.new_vm_name
  datacenter_id = data.vsphere_datacenter.dc.id
  depends_on    = [vsphere_virtual_machine.new_sgw]
}
