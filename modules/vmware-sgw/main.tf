# target datacenter where the vm will be placed
data "vsphere_datacenter" "dc" {
  name = var.datacenter
}

# target datastore where the vm will be placed
data "vsphere_datastore" "datastore" {
  name          = var.datastore
  datacenter_id = data.vsphere_datacenter.dc.id
}

# target cluster root resource pool where the vm will be placed
data "vsphere_compute_cluster" "cluster" {
  name          = var.cluster
  datacenter_id = data.vsphere_datacenter.dc.id
}

# target host that will be used to deploy the ova on
data "vsphere_host" "host" {
  name          = var.host
  datacenter_id = data.vsphere_datacenter.dc.id
}

# vsphere port group that will be used for the Gateway
data "vsphere_network" "network" {
  name          = var.network
  datacenter_id = data.vsphere_datacenter.dc.id
}

# Read OVA properties to get correct guest_id, firmware, and disk layout for
# the selected deployment_option ("new-gateway" creates OS + cache disks,
# "migrate" creates OS disk only - cache disks are attached post-deploy).
data "vsphere_ovf_vm_template" "sgw" {
  name              = var.name
  resource_pool_id  = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id      = data.vsphere_datastore.datastore.id
  host_system_id    = data.vsphere_host.host.id
  local_ovf_path    = var.local_ovf_path
  remote_ovf_url    = var.local_ovf_path == null ? var.remote_ovf_url : null
  disk_provisioning = var.provisioning_type
  deployment_option = var.deployment_option
  ovf_network_map = {
    "VM Network" = data.vsphere_network.network.id
  }
}

locals {
  is_new_gateway = var.deployment_option == "new-gateway"
}

################################################################################
# vSphere VM - "new-gateway" deployment option
#
# Used for fresh Storage Gateway deployments. The OVA brings both the OS disk
# (80 GB, fixed by the OVF descriptor) and the cache disk (sized via the
# cache.size vApp property). prevent_destroy is enabled so a stray destroy
# does not wipe a production gateway.
################################################################################

resource "vsphere_virtual_machine" "vm" {
  count = local.is_new_gateway ? 1 : 0

  host_system_id             = data.vsphere_host.host.id
  resource_pool_id           = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id               = data.vsphere_datastore.datastore.id
  datacenter_id              = data.vsphere_datacenter.dc.id
  name                       = var.name
  num_cpus                   = var.cpus
  memory                     = var.memory
  guest_id                   = data.vsphere_ovf_vm_template.sgw.guest_id
  firmware                   = data.vsphere_ovf_vm_template.sgw.firmware
  wait_for_guest_net_timeout = 1
  sync_time_with_host        = true

  network_interface {
    network_id = data.vsphere_network.network.id
  }

  # Pass the cache disk size to the OVA via its "cache.size" vApp property
  # (uint32, gigabytes). The OVA itself sizes the cache disk during deploy.
  vapp {
    properties = {
      "cache.size" = tostring(var.cache_size)
    }
  }

  ovf_deploy {
    local_ovf_path    = var.local_ovf_path
    remote_ovf_url    = var.local_ovf_path == null ? var.remote_ovf_url : null
    disk_provisioning = var.provisioning_type
    deployment_option = var.deployment_option
    ovf_network_map   = data.vsphere_ovf_vm_template.sgw.ovf_network_map
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      host_system_id,
      annotation,
      vapp,
    ]
  }
}

################################################################################
# vSphere VM - "migrate" deployment option
#
# Used as the replacement VM in a method-1 Storage Gateway migration. The OVA
# brings only the OS disk; cache disks (and the old VM's root disk) are
# detached from the source VM and attached to this VM by the migration
# playbook. prevent_destroy is intentionally NOT set so the migration VM can
# be torn down and rebuilt cleanly during testing.
################################################################################

resource "vsphere_virtual_machine" "vm_migrate" {
  count = local.is_new_gateway ? 0 : 1

  host_system_id             = data.vsphere_host.host.id
  resource_pool_id           = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id               = data.vsphere_datastore.datastore.id
  datacenter_id              = data.vsphere_datacenter.dc.id
  name                       = var.name
  num_cpus                   = var.cpus
  memory                     = var.memory
  guest_id                   = data.vsphere_ovf_vm_template.sgw.guest_id
  firmware                   = data.vsphere_ovf_vm_template.sgw.firmware
  wait_for_guest_net_timeout = 1
  sync_time_with_host        = true

  network_interface {
    network_id = data.vsphere_network.network.id
  }

  ovf_deploy {
    local_ovf_path    = var.local_ovf_path
    remote_ovf_url    = var.local_ovf_path == null ? var.remote_ovf_url : null
    disk_provisioning = var.provisioning_type
    deployment_option = var.deployment_option
    ovf_network_map   = data.vsphere_ovf_vm_template.sgw.ovf_network_map
  }

  lifecycle {
    ignore_changes = [
      host_system_id,
      annotation,
      disk, # cache and old-root disks are attached out-of-band by the migration playbook
    ]
  }
}

# Look up the deployed VM to expose its guest IP address as a module output.
data "vsphere_virtual_machine" "aws_sg" {
  name          = var.name
  datacenter_id = data.vsphere_datacenter.dc.id
  depends_on = [
    vsphere_virtual_machine.vm,
    vsphere_virtual_machine.vm_migrate,
  ]
}
