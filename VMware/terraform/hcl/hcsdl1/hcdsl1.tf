
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

variable "monkey_mirror" {
  description = "Monkey Mirror IP or Hostname"
}

variable "num_datanodes" {
  description = "Number of HDP Datanodes to create"
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


variable "time_server" {
  description = "Hostname or IPv4 for time server"
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

variable "vm_mgmtnode_disk_size" {
  description = "Management Node Data Disk Size"
  default = "20"
}

variable "vm-image" {
  description = "Operating system image id / template that should be used when creating the virtual image"
}

variable "public_nic_name" {
  description = "Name of the public network interface"
  default = "ens192"
}

variable "cluster_name" {
  description = "HDP Cluster Name"
  default = "MYCLUSTER"
}

variable "cloud_install_tar_file_name" {
  description = "Name of the tar file downloaded from the mirror, which contains the Cloud Installer code."
  default = "cloud_install.tar"
}

########
# Isolate IP address components:
locals {
  vm_ipv4_address_elements = "${split(".",var.vm_start_ipv4_address)}"
  vm_ipv4_address_base = "${format("%s.%s.%s",local.vm_ipv4_address_elements[0],local.vm_ipv4_address_elements[1],local.vm_ipv4_address_elements[2])}"
  vm_ipv4_address_start= "${local.vm_ipv4_address_elements[3] + 5}"
  vm_dns_domain="${join(",",var.vm_dns_suffixes)}"
}

###########################################################################################################################################################

# Driver 
resource "vsphere_virtual_machine" "driver" {
  name = "${var.vm-name}drv"
  folder = "${var.vm_folder}"
  num_cpus = "4"
  memory = "4096"
  resource_pool_id = "${data.vsphere_resource_pool.vm_resource_pool.id}"
  datastore_id = "${data.vsphere_datastore.vm_datastore.id}"
  guest_id = "${data.vsphere_virtual_machine.vm_template.guest_id}"
  clone {
    template_uuid = "${data.vsphere_virtual_machine.vm_template.id}"
    customize {
      linux_options {
        domain = "${var.vm_domain}"
        host_name = "${var.vm-name}drv"
      }
      network_interface {
        ipv4_address = "${local.vm_ipv4_address_base }.${local.vm_ipv4_address_start + count.index }"
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

  connection {
    type = "ssh"
    user     = "${var.ssh_user}"
    password = "${var.ssh_user_password}"
  }



  provisioner "file" {
    content = <<EOF
#!/bin/sh

set -x 

mkdir -p /opt/cloud_install; 

cd /opt/cloud_install;

. /opt/monkey_cam_vars.txt;

wget http://$cam_monkeymirror/cloud_install/$cloud_install_tar_file_name

tar xf ./$cloud_install_tar_file_name

yum install -y ksh rsync expect unzip

perl -f cam_integration/01_gen_cam_install_properties.pl

. ./setenv

utils/01_prepare_driver.sh


. $MASTER_INSTALLER_HOME/utils/00_globalFunctions.sh
nodeList=`echo $cloud_hostpasswords|awk -v RS="," -v FS=":" '{s=sprintf("%s %s",s,$1);}END{print s}'`
for hostName in `echo $nodeList|sed 's/,/ /g'`
do
  if [ "$hostName" != "" ]
	then
    hostPwd=`get_root_password $hostName`
		ssh.exp $hostName $hostPwd "echo \`hostname\`.\`hostname -d\`>/etc/hostname;"
	fi
done

utils/01_prepare_all_nodes.sh

$MASTER_INSTALLER_HOME/01_master_install_hdp.sh

EOF

    destination = "/opt/installation.sh"

  }
  
}



###########################################################################################################################################################

# IDM
resource "vsphere_virtual_machine" "idm" {
  count="2"
  name = "${var.vm-name}idm${ count.index }"
  folder = "${var.vm_folder}"
  num_cpus = "4"
  memory = "4096"
  resource_pool_id = "${data.vsphere_resource_pool.vm_resource_pool.id}"
  datastore_id = "${data.vsphere_datastore.vm_datastore.id}"
  guest_id = "${data.vsphere_virtual_machine.vm_template.guest_id}"
  clone {
    template_uuid = "${data.vsphere_virtual_machine.vm_template.id}"
    customize {
      linux_options {
        domain = "${var.vm_domain}"
        host_name = "${var.vm-name}idm${ count.index }"
      }
      network_interface {
        ipv4_address = "${local.vm_ipv4_address_base }.${local.vm_ipv4_address_start + count.index + 1}"
        ipv4_netmask = "${ var.vm_ipv4_prefix_length }"
      }
    ipv4_gateway = "${var.vm_ipv4_gateway}"
    dns_suffix_list = "${var.vm_dns_suffixes}"
    dns_server_list = [ "127.0.0.1" , "10.0.80.11" , "10.0.80.12" ]
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

  connection {
    type = "ssh"
    user     = "${var.ssh_user}"
    password = "${var.ssh_user_password}"
  }

}


############################################################################################################################################################


# IS HTTP Front-end
resource "vsphere_virtual_machine" "ishttp" {
  count="2"
  name = "${var.vm-name}ishttp${ count.index }"
  folder = "${var.vm_folder}"
  num_cpus = "4"
  memory = "4096"
  resource_pool_id = "${data.vsphere_resource_pool.vm_resource_pool.id}"
  datastore_id = "${data.vsphere_datastore.vm_datastore.id}"
  guest_id = "${data.vsphere_virtual_machine.vm_template.guest_id}"
  clone {
    template_uuid = "${data.vsphere_virtual_machine.vm_template.id}"
    customize {
      linux_options {
        domain = "${var.vm_domain}"
        host_name = "${var.vm-name}ishttp${ count.index }"
      }
      network_interface {
        ipv4_address = "${local.vm_ipv4_address_base }.${local.vm_ipv4_address_start + 4 + count.index}"
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

  connection {
    type = "ssh"
    user     = "${var.ssh_user}"
    password = "${var.ssh_user_password}"
  }

}



# IS WAS-ND
resource "vsphere_virtual_machine" "iswasnd" {
  count="3"
  name = "${var.vm-name}iswasnd${ count.index }"
  folder = "${var.vm_folder}"
  num_cpus = "4"
  memory = "8192"
  resource_pool_id = "${data.vsphere_resource_pool.vm_resource_pool.id}"
  datastore_id = "${data.vsphere_datastore.vm_datastore.id}"
  guest_id = "${data.vsphere_virtual_machine.vm_template.guest_id}"
  clone {
    template_uuid = "${data.vsphere_virtual_machine.vm_template.id}"
    customize {
      linux_options {
        domain = "${var.vm_domain}"
        host_name = "${var.vm-name}iswasnd${ count.index }"
      }
      network_interface {
        ipv4_address = "${local.vm_ipv4_address_base }.${local.vm_ipv4_address_start + 6 + count.index }"
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

  connection {
    type = "ssh"
    user     = "${var.ssh_user}"
    password = "${var.ssh_user_password}"
  }

}


# IS DB2
resource "vsphere_virtual_machine" "isdb2" {
  count="2"
  name = "${var.vm-name}isdb2${ count.index }"
  folder = "${var.vm_folder}"
  num_cpus = "4"
  memory = "8192"
  resource_pool_id = "${data.vsphere_resource_pool.vm_resource_pool.id}"
  datastore_id = "${data.vsphere_datastore.vm_datastore.id}"
  guest_id = "${data.vsphere_virtual_machine.vm_template.guest_id}"
  clone {
    template_uuid = "${data.vsphere_virtual_machine.vm_template.id}"
    customize {
      linux_options {
        domain = "${var.vm_domain}"
        host_name = "${var.vm-name}isdb2${ count.index }"
      }
      network_interface {
        ipv4_address = "${local.vm_ipv4_address_base }.${local.vm_ipv4_address_start + 9 + count.index }"
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

  connection {
    type = "ssh"
    user     = "${var.ssh_user}"
    password = "${var.ssh_user_password}"
  }

}




# IS Engine
resource "vsphere_virtual_machine" "isds" {
  name = "${var.vm-name}isds"
  folder = "${var.vm_folder}"
  num_cpus = "4"
  memory = "8192"
  resource_pool_id = "${data.vsphere_resource_pool.vm_resource_pool.id}"
  datastore_id = "${data.vsphere_datastore.vm_datastore.id}"
  guest_id = "${data.vsphere_virtual_machine.vm_template.guest_id}"
  clone {
    template_uuid = "${data.vsphere_virtual_machine.vm_template.id}"
    customize {
      linux_options {
        domain = "${var.vm_domain}"
        host_name = "${var.vm-name}isds"
      }
      network_interface {
        ipv4_address = "${local.vm_ipv4_address_base }.${local.vm_ipv4_address_start + 11 }"
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

  connection {
    type = "ssh"
    user     = "${var.ssh_user}"
    password = "${var.ssh_user_password}"
  }

}









###########################################################################################################################################################

# HAProxy
resource "vsphere_virtual_machine" "haproxy" {
  count="2"
  name = "${var.vm-name}haproxy${ count.index }"
  folder = "${var.vm_folder}"
  num_cpus = "4"
  memory = "4096"
  resource_pool_id = "${data.vsphere_resource_pool.vm_resource_pool.id}"
  datastore_id = "${data.vsphere_datastore.vm_datastore.id}"
  guest_id = "${data.vsphere_virtual_machine.vm_template.guest_id}"
  clone {
    template_uuid = "${data.vsphere_virtual_machine.vm_template.id}"
    customize {
      linux_options {
        domain = "${var.vm_domain}"
        host_name = "${var.vm-name}haproxy${ count.index }"
      }
      network_interface {
        ipv4_address = "${local.vm_ipv4_address_base }.${local.vm_ipv4_address_start + 13 + count.index }"
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

  connection {
    type = "ssh"
    user     = "${var.ssh_user}"
    password = "${var.ssh_user_password}"
  }

}


############################################################################################################################################################

# HDP Management
resource "vsphere_virtual_machine" "hdp-mgmtnodes" {
	count  = "4"
  name = "${var.vm-name}mn${ count.index }"
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
        host_name = "${var.vm-name}mn${ count.index }"
      }
      network_interface {
        ipv4_address = "${local.vm_ipv4_address_base }.${local.vm_ipv4_address_start + count.index + 15 }"
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
    size = "${var.vm_mgmtnode_disk_size}"
    keep_on_remove = "${var.vm_root_disk_keep_on_remove}"
    datastore_id = "${data.vsphere_datastore.vm_datastore.id}"
    unit_number = "1"
  }
  
  disk {
    label = "${var.vm-name}2.vmdk"
    size = "${var.vm_mgmtnode_disk_size}"
    keep_on_remove = "${var.vm_root_disk_keep_on_remove}"
    datastore_id = "${data.vsphere_datastore.vm_datastore.id}"
    unit_number = "2"
  }
  
  disk {
    label = "${var.vm-name}3.vmdk"
    size = "${var.vm_mgmtnode_disk_size}"
    keep_on_remove = "${var.vm_root_disk_keep_on_remove}"
    datastore_id = "${data.vsphere_datastore.vm_datastore.id}"
    unit_number = "3"
  }
  
  connection {
    type = "ssh"
    user     = "${var.ssh_user}"
    password = "${var.ssh_user_password}"
  }

}


# HDP Datanodes
resource "vsphere_virtual_machine" "hdp-datanodes" {
	count  = "${var.num_datanodes}"
  name = "${var.vm-name}dn${ count.index }"
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
        host_name = "${var.vm-name}dn${ count.index }"
      }
      network_interface {
        ipv4_address = "${local.vm_ipv4_address_base }.${local.vm_ipv4_address_start + count.index + 19}"
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

  
  disk {
    label = "${var.vm-name}5.vmdk"
    size = "${var.vm_datanode_disk_size}"
    keep_on_remove = "${var.vm_root_disk_keep_on_remove}"
    datastore_id = "${data.vsphere_datastore.vm_datastore.id}"
    unit_number = "5"
  }
  
  disk {
    label = "${var.vm-name}6.vmdk"
    size = "${var.vm_datanode_disk_size}"
    keep_on_remove = "${var.vm_root_disk_keep_on_remove}"
    datastore_id = "${data.vsphere_datastore.vm_datastore.id}"
    unit_number = "6"
  }

  connection {
    type = "ssh"
    user     = "${var.ssh_user}"
    password = "${var.ssh_user_password}"
  }

}


resource "null_resource" "start_install" {

  depends_on = [ 
  	"vsphere_virtual_machine.driver",  
  	"vsphere_virtual_machine.idm",  
  	"vsphere_virtual_machine.ishttp",  
  	"vsphere_virtual_machine.iswasnd",  
  	"vsphere_virtual_machine.isdb2",  
  	"vsphere_virtual_machine.isds",  
  	"vsphere_virtual_machine.haproxy",  
  	"vsphere_virtual_machine.hdp-mgmtnodes",
  	"vsphere_virtual_machine.hdp-datanodes"
  ]

  # Bootstrap script can run on any instance of the cluster
  # So we just choose the first in this case
  connection {
    host     = "${vsphere_virtual_machine.driver.0.clone.0.customize.0.network_interface.0.ipv4_address}"
    type     = "ssh"
    user     = "root"
    password = "${var.ssh_user_password}"
  }

  provisioner "remote-exec" {
    # Bootstrap script called with private_ip of each node in the clutser
    inline = [
    
      "echo  export cam_ssh_user=${var.ssh_user} >> /opt/monkey_cam_vars.txt",
      "echo  export cam_ssh_user_password=${var.ssh_user_password} >> /opt/monkey_cam_vars.txt",
      
      "echo  export cam_vm_domain=${var.vm_domain} >> /opt/monkey_cam_vars.txt",      
      "echo  export cam_vm_dns_servers=${join(",",var.vm_dns_servers)} >> /opt/monkey_cam_vars.txt",
      "echo  export cam_vm_dns_suffixes=${join(",",var.vm_dns_suffixes)} >> /opt/monkey_cam_vars.txt",
      "echo  export cam_vm_ipv4_prefix_length=${var.vm_ipv4_prefix_length} >> /opt/monkey_cam_vars.txt",
      
      "echo  export cam_time_server=${var.time_server} >> /opt/monkey_cam_vars.txt",
      
      "echo  export cam_public_nic_name=${var.public_nic_name} >> /opt/monkey_cam_vars.txt",
      "echo  export cam_cluster_name=${var.cluster_name} >> /opt/monkey_cam_vars.txt",
      "echo  export cloud_install_tar_file_name=${var.cloud_install_tar_file_name} >> /opt/monkey_cam_vars.txt",
      
      # Hardcode the list of data devices here...
      # It must be updated if the data node template is modified.
      # This list must match the number of disks and naming format, for the data node template definition.
      "echo  export cam_cloud_biginsights_data_devices=/disk1@/dev/sdb,/disk2@/dev/sdc,/disk3@/dev/sdd,/disk4@/dev/sde,/disk5@/dev/sdf,/disk6@/dev/sdg,/disk7@/dev/sdh,/disk8@/dev/sdi,/disk9@/dev/sdj,/disk10@/dev/sdk,/disk11@/dev/sdl,/disk12@/dev/sdm,/disk13@/dev/sdn >> /opt/monkey_cam_vars.txt",
      
      "echo  export cam_monkeymirror=${var.monkey_mirror} >> /opt/monkey_cam_vars.txt",
    
      "echo  export cam_driver_ip=${join(",",vsphere_virtual_machine.driver.*.clone.0.customize.0.network_interface.0.ipv4_address)} >> /opt/monkey_cam_vars.txt",
      "echo  export cam_driver_name=${join(",",vsphere_virtual_machine.driver.*.name)} >> /opt/monkey_cam_vars.txt",
    
      "echo  export cam_idm_ip=${join(",",vsphere_virtual_machine.idm.*.clone.0.customize.0.network_interface.0.ipv4_address)} >> /opt/monkey_cam_vars.txt",
      "echo  export cam_idm_name=${join(",",vsphere_virtual_machine.idm.*.name)} >> /opt/monkey_cam_vars.txt",
    
      "echo  export cam_ishttp_ip=${join(",",vsphere_virtual_machine.ishttp.*.clone.0.customize.0.network_interface.0.ipv4_address)} >> /opt/monkey_cam_vars.txt",
      "echo  export cam_ishttp_name=${join(",",vsphere_virtual_machine.ishttp.*.name)} >> /opt/monkey_cam_vars.txt",
    
      "echo  export cam_iswasnd_ip=${join(",",vsphere_virtual_machine.iswasnd.*.clone.0.customize.0.network_interface.0.ipv4_address)} >> /opt/monkey_cam_vars.txt",
      "echo  export cam_iswasnd_name=${join(",",vsphere_virtual_machine.iswasnd.*.name)} >> /opt/monkey_cam_vars.txt",
    
      "echo  export cam_isdb2_ip=${join(",",vsphere_virtual_machine.isdb2.*.clone.0.customize.0.network_interface.0.ipv4_address)} >> /opt/monkey_cam_vars.txt",
      "echo  export cam_isdb2_name=${join(",",vsphere_virtual_machine.isdb2.*.name)} >> /opt/monkey_cam_vars.txt",
    
      "echo  export cam_isds_ip=${join(",",vsphere_virtual_machine.isds.*.clone.0.customize.0.network_interface.0.ipv4_address)} >> /opt/monkey_cam_vars.txt",
      "echo  export cam_isds_name=${join(",",vsphere_virtual_machine.isds.*.name)} >> /opt/monkey_cam_vars.txt",
    
      "echo  export cam_haproxy_ip=${join(",",vsphere_virtual_machine.haproxy.*.clone.0.customize.0.network_interface.0.ipv4_address)} >> /opt/monkey_cam_vars.txt",
      "echo  export cam_haproxy_name=${join(",",vsphere_virtual_machine.haproxy.*.name)} >> /opt/monkey_cam_vars.txt",
    
      "echo  export cam_hdp_mgmtnodes_ip=${join(",",vsphere_virtual_machine.hdp-mgmtnodes.*.clone.0.customize.0.network_interface.0.ipv4_address)} >> /opt/monkey_cam_vars.txt",
      "echo  export cam_hdp_mgmtnodes_name=${join(",",vsphere_virtual_machine.hdp-mgmtnodes.*.name)} >> /opt/monkey_cam_vars.txt",
      
      "echo  export cam_hdp_datanodes_ip=${join(",",vsphere_virtual_machine.hdp-datanodes.*.clone.0.customize.0.network_interface.0.ipv4_address)} >> /opt/monkey_cam_vars.txt",
      "echo  export cam_hdp_datanodes_name=${join(",",vsphere_virtual_machine.hdp-datanodes.*.name)} >> /opt/monkey_cam_vars.txt",
      
      
      "chmod 755 /opt/installation.sh; nohup /opt/installation.sh &; sleep 10;"
    ]
  }
}
