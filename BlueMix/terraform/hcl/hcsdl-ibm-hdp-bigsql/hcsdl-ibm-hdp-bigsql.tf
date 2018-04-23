#################################################################
# Terraform template that will deploy Hybrid Secure Data Lake on IBM Cloud
#
#
# Julius Lerm, 9apr2018
#
# Version: 1.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Licensed Materials - Property of IBM
#
# ©Copyright IBM Corp. 2017.
#
#################################################################

#########################################################
# Define the ibmcloud provider
#########################################################
provider "ibm" {
}

#########################################################
# Define the variables
#########################################################
variable "datacenter" {
  description = "Softlayer datacenter where infrastructure resources will be deployed"
}

variable "vm_name_prefix" {
  description = "Prefix for vm names"
}

variable "vm_domain" {
  description = "Domain Name of virtual machine"
}

variable "public_ssh_key" {
  description = "Public SSH key used to connect to the virtual guest"
}

variable "sudo_user" {
  description = "Sudo User"
}

variable "sudo_password" {
  description = "Sudo Password"
}

variable "vlan_number" {
  description = "VLAN Number"
}

variable "vlan_router" {
  description = "VLAN router"
}

variable "time_server" {
  description = "time_server"
}

variable "vm_dns_servers" {
  type = "list"
  description = "vm_dns_servers"
}

variable "vm_dns_suffixes" {
  type = "list"
  description = "vm_dns_suffixes"
}

variable "monkey_mirror" {
  description = "monkey_mirror"
}

variable "cloud_install_tar_file_name" {
  description = "cloud_install_tar_file_name"
}

variable "public_nic_name" {
  description = "public_nic_name"
}

variable "cluster_name" {
  description = "cluster_name"
}

variable "mgmtnode_num_cpus" {
  description = "mgmtnode_num_cpus"
}

variable "mgmtnode_mem" {
  description = "mgmtnode_mem"
}

variable "mgmtnode_disks" {
  type = "list"
  description = "mgmtnode_disks"
}

variable "num_datanodes" {
  description = "num_datanodes"
}

variable "datanode_num_cpus" {
  description = "datanode_num_cpus"
}

variable "datanode_mem" {
  description = "datanode_mem"
}

variable "datanode_disks" {
  type = "list"
  description = "datanode_disks"
}

variable "dsengine_mem" {
  description = "dsengine_mem"
}

variable "dsengine_num_cpus" {
  description = "dsengine_num_cpus"
}

##############################################################
# Create public key in Devices>Manage>SSH Keys in SL console
##############################################################
resource "ibm_compute_ssh_key" "cam_public_key" {
  label      = "CAM Public Key"
  public_key = "${var.public_ssh_key}"
}

##############################################################
# Create temp public key for ssh connection
##############################################################
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
}

resource "ibm_compute_ssh_key" "temp_public_key" {
  label      = "Temp Public Key"
  public_key = "${tls_private_key.ssh.public_key_openssh}"
}

data "ibm_network_vlan" "cluster_vlan" {
    number = "${var.vlan_number}",
    router_hostname = "${var.vlan_router}"
}


##############################################################
# Create VMs
##############################################################

###########################################################################################################################################################
# Driver
resource "ibm_compute_vm_instance" "driver" {
  count                    = "1"
  hostname                 = "${var.vm_name_prefix}-drv"
  os_reference_code        = "REDHAT_7_64"
  domain                   = "${var.vm_domain}"
  datacenter               = "${var.datacenter}"
  private_vlan_id          = "${data.ibm_network_vlan.cluster_vlan.id}"
  network_speed            = 1000
  hourly_billing           = true
  private_network_only     = true
  cores                    = 4
  memory                   = 4096
  disks                    = [100]
  dedicated_acct_host_only = false
  local_disk               = false
  ssh_key_ids              = ["${ibm_compute_ssh_key.cam_public_key.id}", "${ibm_compute_ssh_key.temp_public_key.id}"]

  # Specify the ssh connection
  connection {
    user        = "root"
    private_key = "${tls_private_key.ssh.private_key_pem}"
    host        = "${self.ipv4_address_private}"
  }

  provisioner "remote-exec" {
    inline = [
    	"yum groupinstall \"Infrastructure Server\" -y",
      "sed -i -e 's/# %wheel/%wheel/' -e 's/Defaults    requiretty/#Defaults    requiretty/' /etc/sudoers",
      "useradd ${var.sudo_user}",
      "echo ${var.sudo_password} | passwd ${var.sudo_user} --stdin",
      "usermod ${var.sudo_user} -g wheel"
    ]
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

yum install -y ksh rsync expect unzip perl

perl -f cam_integration/01_gen_cam_install_properties.pl

sed -i 's/cloud_replace_rhel_repo=1/cloud_replace_rhel_repo=0/' global.properties
#sed -i 's/cloud_biginsights_bigsql_/#cloud_biginsights_bigsql_/' global.properties

. ./setenv

utils/01_prepare_driver.sh

utils/01_prepare_all_nodes.sh

nohup ./01_master_install_hdp.sh &

EOF

    destination = "/opt/installation.sh"

  }
}


###########################################################################################################################################################
# IDM
resource "ibm_compute_vm_instance" "idm" {
  count="2"
  hostname = "${var.vm_name_prefix}-idm-${ count.index }"
  os_reference_code        = "REDHAT_7_64"
  domain                   = "${var.vm_domain}"
  datacenter               = "${var.datacenter}"
  private_vlan_id          = "${data.ibm_network_vlan.cluster_vlan.id}"
  network_speed            = 1000
  hourly_billing           = true
  private_network_only     = true
  cores                    = 4
  memory                   = 4096
  disks                    = [100]
  dedicated_acct_host_only = false
  local_disk               = false
  ssh_key_ids              = ["${ibm_compute_ssh_key.cam_public_key.id}", "${ibm_compute_ssh_key.temp_public_key.id}"]

  # Specify the ssh connection
  connection {
    user        = "root"
    private_key = "${tls_private_key.ssh.private_key_pem}"
    host        = "${self.ipv4_address_private}"
  }

  provisioner "remote-exec" {
    inline = [
    	"yum groupinstall \"Infrastructure Server\" -y",
      "sed -i -e 's/# %wheel/%wheel/' -e 's/Defaults    requiretty/#Defaults    requiretty/' /etc/sudoers",
      "useradd ${var.sudo_user}",
      "echo ${var.sudo_password} | passwd ${var.sudo_user} --stdin",
      "usermod ${var.sudo_user} -g wheel"
    ]
  }
}



############################################################################################################################################################
# HAProxy
resource "ibm_compute_vm_instance" "haproxy" {
  count="1"
  hostname = "${var.vm_name_prefix}-haproxy-${ count.index }"
  os_reference_code        = "REDHAT_7_64"
  domain                   = "${var.vm_domain}"
  datacenter               = "${var.datacenter}"
  private_vlan_id          = "${data.ibm_network_vlan.cluster_vlan.id}"
  network_speed            = 1000
  hourly_billing           = true
  private_network_only     = true
  cores                    = 4
  memory                   = 4096
  disks                    = [100]
  dedicated_acct_host_only = false
  local_disk               = false
  ssh_key_ids              = ["${ibm_compute_ssh_key.cam_public_key.id}", "${ibm_compute_ssh_key.temp_public_key.id}"]

  # Specify the ssh connection
  connection {
    user        = "root"
    private_key = "${tls_private_key.ssh.private_key_pem}"
    host        = "${self.ipv4_address_private}"
  }

  provisioner "remote-exec" {
    inline = [
    	"yum groupinstall \"Infrastructure Server\" -y",
      "sed -i -e 's/# %wheel/%wheel/' -e 's/Defaults    requiretty/#Defaults    requiretty/' /etc/sudoers",
      "useradd ${var.sudo_user}",
      "echo ${var.sudo_password} | passwd ${var.sudo_user} --stdin",
      "usermod ${var.sudo_user} -g wheel"
    ]
  }
}


############################################################################################################################################################
# HDP MAnagement Nodes
resource "ibm_compute_vm_instance" "hdp-mgmtnodes" {
  count="4"
  hostname = "${var.vm_name_prefix}-mn-${ count.index }"
  os_reference_code        = "REDHAT_7_64"
  domain                   = "${var.vm_domain}"
  datacenter               = "${var.datacenter}"
  private_vlan_id          = "${data.ibm_network_vlan.cluster_vlan.id}"
  network_speed            = 1000
  hourly_billing           = true
  private_network_only     = true
  cores                    = "${var.mgmtnode_num_cpus}"
  memory                   = "${var.mgmtnode_mem}"
  disks                    = "${var.mgmtnode_disks}"
  dedicated_acct_host_only = false
  local_disk               = false
  ssh_key_ids              = ["${ibm_compute_ssh_key.cam_public_key.id}", "${ibm_compute_ssh_key.temp_public_key.id}"]

  # Specify the ssh connection
  connection {
    user        = "root"
    private_key = "${tls_private_key.ssh.private_key_pem}"
    host        = "${self.ipv4_address_private}"
  }

  provisioner "remote-exec" {
    inline = [
    	"yum groupinstall \"Infrastructure Server\" -y",
      "sed -i -e 's/# %wheel/%wheel/' -e 's/Defaults    requiretty/#Defaults    requiretty/' /etc/sudoers",
      "useradd ${var.sudo_user}",
      "echo ${var.sudo_password} | passwd ${var.sudo_user} --stdin",
      "usermod ${var.sudo_user} -g wheel"
    ]
  }
}


############################################################################################################################################################
# HDP Data Nodes
resource "ibm_compute_vm_instance" "hdp-datanodes" {
  count="${var.num_datanodes}"
  hostname = "${var.vm_name_prefix}-dn-${ count.index }"
  os_reference_code        = "REDHAT_7_64"
  domain                   = "${var.vm_domain}"
  datacenter               = "${var.datacenter}"
  private_vlan_id          = "${data.ibm_network_vlan.cluster_vlan.id}"
  network_speed            = 1000
  hourly_billing           = true
  private_network_only     = true
  cores                    = "${var.datanode_num_cpus}"
  memory                   = "${var.datanode_mem}"
  disks                    = "${var.datanode_disks}"
  dedicated_acct_host_only = false
  local_disk               = false
  ssh_key_ids              = ["${ibm_compute_ssh_key.cam_public_key.id}", "${ibm_compute_ssh_key.temp_public_key.id}"]

  # Specify the ssh connection
  connection {
    user        = "root"
    private_key = "${tls_private_key.ssh.private_key_pem}"
    host        = "${self.ipv4_address_private}"
  }

  provisioner "remote-exec" {
    inline = [
    	"yum groupinstall \"Infrastructure Server\" -y",
      "sed -i -e 's/# %wheel/%wheel/' -e 's/Defaults    requiretty/#Defaults    requiretty/' /etc/sudoers",
      "useradd ${var.sudo_user}",
      "echo ${var.sudo_password} | passwd ${var.sudo_user} --stdin",
      "usermod ${var.sudo_user} -g wheel"
    ]
  }
}


############################################################################################################################################################
# Start Install
resource "null_resource" "start_install" {

  depends_on = [ 
  	"ibm_compute_vm_instance.driver",  
  	"ibm_compute_vm_instance.idm",  
  	"ibm_compute_vm_instance.ishttp",  
  	"ibm_compute_vm_instance.iswasnd",  
  	"ibm_compute_vm_instance.isdb2",  
  	"ibm_compute_vm_instance.isds",  
  	"ibm_compute_vm_instance.haproxy",  
  	"ibm_compute_vm_instance.hdp-mgmtnodes",
  	"ibm_compute_vm_instance.hdp-datanodes"
  ]
  
  connection {
    host     = "${ibm_compute_vm_instance.driver.0.ipv4_address_private}"
    type     = "ssh"
    user     = "root"
    private_key = "${tls_private_key.ssh.private_key_pem}"
  }

  provisioner "remote-exec" {
    inline = [
    
      "echo  export cam_sudo_user=${var.sudo_user} >> /opt/monkey_cam_vars.txt",
      "echo  export cam_sudo_password=${var.sudo_password} >> /opt/monkey_cam_vars.txt",
      
      "echo  export cam_private_ips=${join(",",ibm_compute_vm_instance.driver.*.ipv4_address_private)} >> /opt/monkey_cam_vars.txt",
      "echo  export cam_private_subnets=${join(",",ibm_compute_vm_instance.driver.*.private_subnet)} >> /opt/monkey_cam_vars.txt",

      "echo  export cam_vm_domain=${var.vm_domain} >> /opt/monkey_cam_vars.txt",      
      "echo  export cam_vm_dns_servers=${join(",",var.vm_dns_servers)} >> /opt/monkey_cam_vars.txt",
      "echo  export cam_vm_dns_suffixes=${join(",",var.vm_dns_suffixes)} >> /opt/monkey_cam_vars.txt",

      "echo  export cam_time_server=${var.time_server} >> /opt/monkey_cam_vars.txt",
      
      "echo  export cam_public_nic_name=${var.public_nic_name} >> /opt/monkey_cam_vars.txt",
      "echo  export cam_cluster_name=${var.cluster_name} >> /opt/monkey_cam_vars.txt",
      "echo  export cloud_install_tar_file_name=${var.cloud_install_tar_file_name} >> /opt/monkey_cam_vars.txt",
      
      # Hardcode the list of data devices here...
      # It must be updated if the data node template is modified.
      # This list must match the naming format, for the data node template definition.
      
      # For the SL VMs used so far, /dev/xvdb is defined as swap. Removing it for now...
      #"echo  export cam_cloud_biginsights_data_devices=/disk1@/dev/xvdb,/disk2@/dev/xvdc,/disk3@/dev/xvdd,/disk4@/dev/xvde,/disk5@/dev/xvdf,/disk6@/dev/xvdg,/disk7@/dev/xvdh,/disk8@/dev/xvdi,/disk9@/dev/xvdj,/disk10@/dev/xvdk,/disk11@/dev/xvdl,/disk12@/dev/xvdm,/disk13@/dev/xvdn >> /opt/monkey_cam_vars.txt",
      "echo  export cam_cloud_biginsights_data_devices=/disk2@/dev/xvdc,/disk3@/dev/xvdd,/disk4@/dev/xvde,/disk5@/dev/xvdf,/disk6@/dev/xvdg,/disk7@/dev/xvdh,/disk8@/dev/xvdi,/disk9@/dev/xvdj,/disk10@/dev/xvdk,/disk11@/dev/xvdl,/disk12@/dev/xvdm,/disk13@/dev/xvdn >> /opt/monkey_cam_vars.txt",
      
      "echo  export cam_monkeymirror=${var.monkey_mirror} >> /opt/monkey_cam_vars.txt",
    
      "echo  export cam_driver_ip=${join(",",ibm_compute_vm_instance.driver.*.ipv4_address_private)} >> /opt/monkey_cam_vars.txt",
      "echo  export cam_driver_name=${join(",",ibm_compute_vm_instance.driver.*.hostname)} >> /opt/monkey_cam_vars.txt",
    
      "echo  export cam_idm_ip=${join(",",ibm_compute_vm_instance.idm.*.ipv4_address_private)} >> /opt/monkey_cam_vars.txt",
      "echo  export cam_idm_name=${join(",",ibm_compute_vm_instance.idm.*.hostname)} >> /opt/monkey_cam_vars.txt",
    
      "echo  export cam_haproxy_ip=${join(",",ibm_compute_vm_instance.haproxy.*.ipv4_address_private)} >> /opt/monkey_cam_vars.txt",
      "echo  export cam_haproxy_name=${join(",",ibm_compute_vm_instance.haproxy.*.hostname)} >> /opt/monkey_cam_vars.txt",
    
      "echo  export cam_hdp_mgmtnodes_ip=${join(",",ibm_compute_vm_instance.hdp-mgmtnodes.*.ipv4_address_private)} >> /opt/monkey_cam_vars.txt",
      "echo  export cam_hdp_mgmtnodes_name=${join(",",ibm_compute_vm_instance.hdp-mgmtnodes.*.hostname)} >> /opt/monkey_cam_vars.txt",
      
      "echo  export cam_hdp_datanodes_ip=${join(",",ibm_compute_vm_instance.hdp-datanodes.*.ipv4_address_private)} >> /opt/monkey_cam_vars.txt",
      "echo  export cam_hdp_datanodes_name=${join(",",ibm_compute_vm_instance.hdp-datanodes.*.hostname)} >> /opt/monkey_cam_vars.txt",
    
      "chmod 755 /opt/installation.sh",
      "nohup /opt/installation.sh &",
      "sleep 60"
    ]
  }
}
