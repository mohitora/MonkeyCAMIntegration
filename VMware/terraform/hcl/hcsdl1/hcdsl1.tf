
##############################################################
# Keys - CAMC (public/private) & optional User Key (public)
##############################################################
variable "allow_unverified_ssl" {
  description = "Communication with vsphere server with self signed certificate"
  default = "true"
}

##############################################################
# Define the vsphere provider
##############################################################
provider "vsphere" {
  allow_unverified_ssl = "${var.allow_unverified_ssl}"
  version = "~> 1.3"
}

provider "camc" {
  version = "~> 0.1"
}

##############################################################
# Define pattern variables
##############################################################
##############################################################
# Vsphere data for provider
##############################################################
data "vsphere_datacenter" "vm_datacenter" {
  name = "${var.vm_datacenter}"
}
data "vsphere_datastore" "vm_datastore" {
  name = "${var.vm_root_disk_datastore}"
  datacenter_id = "${data.vsphere_datacenter.vm_datacenter.id}"
}
data "vsphere_resource_pool" "vm_resource_pool" {
  name = "${var.vm_resource_pool}"
  datacenter_id = "${data.vsphere_datacenter.vm_datacenter.id}"
}
data "vsphere_network" "vm_network" {
  name = "${var.vm_network_interface_label}"
  datacenter_id = "${data.vsphere_datacenter.vm_datacenter.id}"
}

data "vsphere_virtual_machine" "vm_template" {
  name = "${var.vm-image}"
  datacenter_id = "${data.vsphere_datacenter.vm_datacenter.id}"
}

##### Image Parameters variables #####

#Variable : vm-name
variable "vm-name" {
  type = "string"
  description = "Generated"
  default = "hcsdl"
}



#########################################################
##### Resource : vm
#########################################################
variable "ssh_user" {
  description = "The user for ssh connection, which is default in template"
  default     = "root"
}

variable "ssh_user_password" {
  description = "The user password for ssh connection, which is default in template"
}

variable "num_vms" {
  description = "Number of VMs to create"
}


variable "vm_folder" {
  description = "Target vSphere folder for virtual machine"
}

variable "vm_datacenter" {
  description = "Target vSphere datacenter for virtual machine creation"
}

variable "vm_domain" {
  description = "Domain Name of virtual machine"
}

variable "vm_number_of_vcpu" {
  description = "Number of virtual CPU for the virtual machine, which is required to be a positive Integer"
  default = "1"
}

variable "vm_memory" {
  description = "Memory assigned to the virtual machine in megabytes. This value is required to be an increment of 1024"
  default = "1024"
}

variable "vm_cluster" {
  description = "Target vSphere cluster to host the virtual machine"
}

variable "vm_resource_pool" {
  description = "Target vSphere Resource Pool to host the virtual machine"
}

variable "vm_dns_suffixes" {
  type = "list"
  description = "Name resolution suffixes for the virtual network adapter"
}

variable "vm_dns_servers" {
  type = "list"
  description = "DNS servers for the virtual network adapter"
}

variable "vm_network_interface_label" {
  description = "vSphere port group or network label for virtual machine's vNIC"
}

variable "vm_ipv4_gateway" {
  description = "IPv4 gateway for vNIC configuration"
}

variable "vm_start_ipv4_address" {
  description = "Start IPv4 address for vNIC configuration"
}

variable "vm_ipv4_prefix_length" {
  description = "IPv4 prefix length for vNIC configuration. The value must be a number between 8 and 32"
}

variable "vm_adapter_type" {
  description = "Network adapter type for vNIC Configuration"
  default = "vmxnet3"
}

variable "vm_root_disk_datastore" {
  description = "Data store or storage cluster name for target virtual machine's disks"
}

variable "vm_root_disk_type" {
  type = "string"
  description = "Type of template disk volume"
  default = "eager_zeroed"
}

variable "vm_root_disk_controller_type" {
  type = "string"
  description = "Type of template disk controller"
  default = "scsi"
}

variable "vm_root_disk_keep_on_remove" {
  type = "string"
  description = "Delete template disk volume when the virtual machine is deleted"
  default = "false"
}

variable "vm_root_disk_size" {
  description = "Size of template disk volume. Should be equal to template's disk size"
  default = "25"
}

variable "vm_datanode_disk_size" {
  description = "Datanode Data Disk Size"
  default = "100"
}

variable "vm-image" {
  description = "Operating system image id / template that should be used when creating the virtual image"
}

########
# Isolate IP address components:
locals {
  vm_ipv4_address_elements = "${split(".",var.vm_start_ipv4_address)}"
  vm_ipv4_address_base = "${format("%s.%s.%s",local.vm_ipv4_address_elements[0],local.vm_ipv4_address_elements[1],local.vm_ipv4_address_elements[2])}"
  vm_ipv4_address_start= "${local.vm_ipv4_address_elements[3] + 5}"
}


# vsphere vm
resource "vsphere_virtual_machine" "datanodes" {
	count  = "${var.num_vms}"
  name = "${var.vm-name}-${ count.index }"
  folder = "${var.vm_folder}"
  num_cpus = "${var.vm_number_of_vcpu}"
  memory = "${var.vm_memory}"
  resource_pool_id = "${data.vsphere_resource_pool.vm_resource_pool.id}"
  datastore_id = "${data.vsphere_datastore.vm_datastore.id}"
  guest_id = "${data.vsphere_virtual_machine.vm_template.guest_id}"
  clone {
    template_uuid = "${data.vsphere_virtual_machine.vm_template.id}"
    customize {
      linux_options {
        domain = "${var.vm_domain}"
        host_name = "${var.vm-name}-${ count.index }"
      }
      network_interface {
        ipv4_address = "${local.vm_ipv4_address_base }.${local.vm_ipv4_address_start + count.index}"
        ipv4_netmask = "${ var.vm_ipv4_prefix_length }"
      }
    ipv4_gateway = "${var.vm_ipv4_gateway}"
    dns_suffix_list = "${var.vm_dns_suffixes}"
    dns_server_list = "${var.vm_dns_servers}"
    }
  }

  network_interface {
    network_id = "${data.vsphere_network.vm_network.id}"
    adapter_type = "${var.vm_adapter_type}"
  }

  disk {
    label = "${var.vm-name}0.vmdk"
    size = "${var.vm_root_disk_size}"
    keep_on_remove = "${var.vm_root_disk_keep_on_remove}"
    datastore_id = "${data.vsphere_datastore.vm_datastore.id}"
  }
  
  disk {
    label = "${var.vm-name}1.vmdk"
    size = "${var.vm_datanode_disk_size}"
    keep_on_remove = "${var.vm_root_disk_keep_on_remove}"
    datastore_id = "${data.vsphere_datastore.vm_datastore.id}"
    unit_number = "1"
  }
  
  disk {
    label = "${var.vm-name}2.vmdk"
    size = "${var.vm_datanode_disk_size}"
    keep_on_remove = "${var.vm_root_disk_keep_on_remove}"
    datastore_id = "${data.vsphere_datastore.vm_datastore.id}"
    unit_number = "2"
  }
  
  disk {
    label = "${var.vm-name}3.vmdk"
    size = "${var.vm_datanode_disk_size}"
    keep_on_remove = "${var.vm_root_disk_keep_on_remove}"
    datastore_id = "${data.vsphere_datastore.vm_datastore.id}"
    unit_number = "3"
  }
  
  disk {
    label = "${var.vm-name}4.vmdk"
    size = "${var.vm_datanode_disk_size}"
    keep_on_remove = "${var.vm_root_disk_keep_on_remove}"
    datastore_id = "${data.vsphere_datastore.vm_datastore.id}"
    unit_number = "4"
  }

  connection {
    type = "ssh"
    user     = "${var.ssh_user}"
    password = "${var.ssh_user_password}"
  }

}

#########################################################
# Output
#########################################################
output "ip_addresses" {
  depends_on = [ "vsphere_virtual_machine.datanodes" ]
  value = "${join(",", vsphere_virtual_machine.datanodes.*.clone.0.customize.0.network_interface.0.ipv4_address)}"
}


resource "null_resource" "cluster" {

  depends_on = [ "vsphere_virtual_machine.datanodes" ]

  # Bootstrap script can run on any instance of the cluster
  # So we just choose the first in this case
  connection {
    host     = "${vsphere_virtual_machine.datanodes.0.clone.0.customize.0.network_interface.0.ipv4_address}"
    type     = "ssh"
    user     = "root"
    password = "${var.ssh_user_password}"
  }

  provisioner "remote-exec" {
    # Bootstrap script called with private_ip of each node in the clutser
    inline = [
      "echo  ${join(",",vsphere_virtual_machine.datanodes.*.clone.0.customize.0.network_interface.0.ipv4_address)} >> /tmp/out.log",
      "echo  ${join(",",vsphere_virtual_machine.datanodes.*.name)} >> /tmp/out.log"
    ]
  }
}
