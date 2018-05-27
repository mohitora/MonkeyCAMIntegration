#################################################################
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Licensed Materials - Property of IBM
#
# ©Copyright IBM Corp. 2017, 2018.
#
#################################################################

provider "aws" {
  version = "~> 1.2"
  region  = "${var.aws_region}"
}

variable "aws_region" {
  description = "AWS region to launch servers."
  default     = "us-east-1"
}

variable "vpc_name_tag" {
  description = "Name of the Virtual Private Cloud (VPC) this resource is going to be deployed into"
}

variable "subnet_cidr" {
  description = "Subnet cidr"
}

data "aws_vpc" "selected" {
  state = "available"

  filter {
    name   = "tag:Name"
    values = ["${var.vpc_name_tag}"]
  }
}

data "aws_subnet" "selected" {
  state      = "available"
  vpc_id     = "${data.aws_vpc.selected.id}"
  cidr_block = "${var.subnet_cidr}"
}

variable "public_ssh_key_name" {
  description = "Name of the public SSH key used to connect to the virtual guest"
}

variable "public_ssh_key" {
  description = "Public SSH key used to connect to the virtual guest"
}

#Variable : AWS image name
variable "aws_image" {
  type = "string"
  description = "Operating system image id / template that should be used when creating the virtual image"
  default = "ami-c998b6b2"
}



variable "vm_name_prefix" {
  description = "Prefix for vm names"
}

variable "vm_domain" {
  description = "Domain Name of virtual machine"
}

variable "sudo_user" {
  description = "Sudo User"
}

variable "sudo_password" {
  description = "Sudo Password"
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


#######################

resource "aws_key_pair" "orpheus_public_key" {
  key_name   = "${var.public_ssh_key_name}"
  public_key = "${var.public_ssh_key}"
}


##############################################################
# Create temp public key for ssh connection
##############################################################
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
}

resource "aws_key_pair" "temp_public_key" {
  key_name   = "${var.public_ssh_key_name}-temp"
  public_key = "${tls_private_key.ssh.public_key_openssh}"
}

##############################################################
# Create VMs
##############################################################

###########################################################################################################################################################
# Driver
#
resource "aws_instance" "driver" {
  count         = "1"
  tags { Name = "${var.vm_name_prefix}-driver.${var.vm_domain}" }
  instance_type = "m4.large"
  ami           = "${var.aws_image}"
  subnet_id     = "${data.aws_subnet.selected.id}"
  key_name      = "${aws_key_pair.temp_public_key.id}"
  root_block_device = { "volume_type" = "gp2", "volume_size" = "100", "delete_on_termination" = true }
  
  connection {
    user        = "ec2-user"
    private_key = "${tls_private_key.ssh.private_key_pem}"
    host        = "${self.public_ip}"
  }
  
   provisioner "file" {
    content = <<EOF
#!/bin/bash
LOGFILE="/var/log/addkey.log"
user_public_key=$1
if [ "$user_public_key" != "None" ] ; then
    echo "---start adding user_public_key----" | tee -a $LOGFILE 2>&1
    echo "$user_public_key" | tee -a $HOME/.ssh/authorized_keys          >> $LOGFILE 2>&1 || { echo "---Failed to add user_public_key---" | tee -a $LOGFILE; exit 1; }
    echo "---finish adding user_public_key----" | tee -a $LOGFILE 2>&1
fi
EOF

    destination = "/tmp/addkey.sh"
}

  provisioner "remote-exec" {
    inline = [
      "echo \"${var.vm_name_prefix}-driver.${var.vm_domain}\">/tmp/hostname",
      "sudo mv /tmp/hostname /etc/hostname",
      "sudo hostname \"${var.vm_name_prefix}-driver.${var.vm_domain}\"",
      "sudo chmod +x /tmp/addkey.sh; sudo bash /tmp/addkey.sh \"${var.public_ssh_key}\"",
      "sudo sed -i -e 's/# %wheel/%wheel/' -e 's/Defaults    requiretty/#Defaults    requiretty/' /etc/sudoers",
      "sudo useradd ${var.sudo_user}",
      "sudo echo ${var.sudo_password} | passwd ${var.sudo_user} --stdin",
      "sudo usermod ${var.sudo_user} -g wheel"
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
#sed -i 's/cloud_skip_prepare_nodes=0/cloud_skip_prepare_nodes=1/' global.properties

. ./setenv

utils/01_prepare_driver.sh

utils/01_prepare_all_nodes.sh

nohup ./01_master_install_hdp.sh &

EOF

    destination = "/tmp/installation.sh"

  }
  
}

###########################################################################################################################################################
# IDM
#
resource "aws_instance" "idm" {
  count         = "2"
  tags { Name = "${var.vm_name_prefix}-idm-${ count.index }.${var.vm_domain}" }
  instance_type = "m4.large"
  ami           = "${var.aws_image}"
  subnet_id     = "${data.aws_subnet.selected.id}"
  key_name      = "${aws_key_pair.temp_public_key.id}"
  root_block_device = { "volume_type" = "gp2", "volume_size" = "100", "delete_on_termination" = true }
  
  connection {
    user        = "ec2-user"
    private_key = "${tls_private_key.ssh.private_key_pem}"
    host        = "${self.public_ip}"
  }
  
   provisioner "file" {
    content = <<EOF
#!/bin/bash
LOGFILE="/var/log/addkey.log"
user_public_key=$1
if [ "$user_public_key" != "None" ] ; then
    echo "---start adding user_public_key----" | tee -a $LOGFILE 2>&1
    echo "$user_public_key" | tee -a $HOME/.ssh/authorized_keys          >> $LOGFILE 2>&1 || { echo "---Failed to add user_public_key---" | tee -a $LOGFILE; exit 1; }
    echo "---finish adding user_public_key----" | tee -a $LOGFILE 2>&1
fi
EOF

    destination = "/tmp/addkey.sh"
}

  provisioner "remote-exec" {
    inline = [
      "echo \"${var.vm_name_prefix}-idm-${ count.index }.${var.vm_domain}\">/tmp/hostname",
      "sudo mv /tmp/hostname /etc/hostname",
      "sudo hostname \"${var.vm_name_prefix}-idm-${ count.index }.${var.vm_domain}\"",
      "sudo chmod +x /tmp/addkey.sh; sudo bash /tmp/addkey.sh \"${var.public_ssh_key}\"",
      "sudo sed -i -e 's/# %wheel/%wheel/' -e 's/Defaults    requiretty/#Defaults    requiretty/' /etc/sudoers",
      "sudo useradd ${var.sudo_user}",
      "sudo echo ${var.sudo_password} | passwd ${var.sudo_user} --stdin",
      "sudo usermod ${var.sudo_user} -g wheel"
    ]
 }

  
}


###########################################################################################################################################################
# IS HTTP Front End
#
resource "aws_instance" "ishttp" {
  count         = "2"
  tags { Name = "${var.vm_name_prefix}-ishttp-${ count.index }.${var.vm_domain}" }
  instance_type = "m4.large"
  ami           = "${var.aws_image}"
  subnet_id     = "${data.aws_subnet.selected.id}"
  key_name      = "${aws_key_pair.temp_public_key.id}"
  root_block_device = { "volume_type" = "gp2", "volume_size" = "100", "delete_on_termination" = true }
  
  connection {
    user        = "ec2-user"
    private_key = "${tls_private_key.ssh.private_key_pem}"
    host        = "${self.public_ip}"
  }
  
   provisioner "file" {
    content = <<EOF
#!/bin/bash
LOGFILE="/var/log/addkey.log"
user_public_key=$1
if [ "$user_public_key" != "None" ] ; then
    echo "---start adding user_public_key----" | tee -a $LOGFILE 2>&1
    echo "$user_public_key" | tee -a $HOME/.ssh/authorized_keys          >> $LOGFILE 2>&1 || { echo "---Failed to add user_public_key---" | tee -a $LOGFILE; exit 1; }
    echo "---finish adding user_public_key----" | tee -a $LOGFILE 2>&1
fi
EOF

    destination = "/tmp/addkey.sh"
}

  provisioner "remote-exec" {
    inline = [
      "echo \"${var.vm_name_prefix}-ishttp-${ count.index }.${var.vm_domain}\">/tmp/hostname",
      "sudo mv /tmp/hostname /etc/hostname",
      "sudo hostname \"${var.vm_name_prefix}-ishttp-${ count.index }.${var.vm_domain}\"",
      "sudo chmod +x /tmp/addkey.sh; sudo bash /tmp/addkey.sh \"${var.public_ssh_key}\"",
      "sudo sed -i -e 's/# %wheel/%wheel/' -e 's/Defaults    requiretty/#Defaults    requiretty/' /etc/sudoers",
      "sudo useradd ${var.sudo_user}",
      "sudo echo ${var.sudo_password} | passwd ${var.sudo_user} --stdin",
      "sudo usermod ${var.sudo_user} -g wheel"
    ]
 }

  
}




###########################################################################################################################################################
# IS HTTP WAS-ND
#
resource "aws_instance" "iswasnd" {
  count         = "2"
  tags { Name = "${var.vm_name_prefix}-iswasnd-${ count.index }.${var.vm_domain}" }
  instance_type = "m4.large"
  ami           = "${var.aws_image}"
  subnet_id     = "${data.aws_subnet.selected.id}"
  key_name      = "${aws_key_pair.temp_public_key.id}"
  root_block_device = { "volume_type" = "gp2", "volume_size" = "100", "delete_on_termination" = true }
  
  connection {
    user        = "ec2-user"
    private_key = "${tls_private_key.ssh.private_key_pem}"
    host        = "${self.public_ip}"
  }
  
   provisioner "file" {
    content = <<EOF
#!/bin/bash
LOGFILE="/var/log/addkey.log"
user_public_key=$1
if [ "$user_public_key" != "None" ] ; then
    echo "---start adding user_public_key----" | tee -a $LOGFILE 2>&1
    echo "$user_public_key" | tee -a $HOME/.ssh/authorized_keys          >> $LOGFILE 2>&1 || { echo "---Failed to add user_public_key---" | tee -a $LOGFILE; exit 1; }
    echo "---finish adding user_public_key----" | tee -a $LOGFILE 2>&1
fi
EOF

    destination = "/tmp/addkey.sh"
}

  provisioner "remote-exec" {
    inline = [
      "echo \"${var.vm_name_prefix}-iswasnd-${ count.index }.${var.vm_domain}\">/tmp/hostname",
      "sudo mv /tmp/hostname /etc/hostname",
      "sudo hostname \"${var.vm_name_prefix}-iswasnd-${ count.index }.${var.vm_domain}\"",
      "sudo chmod +x /tmp/addkey.sh; sudo bash /tmp/addkey.sh \"${var.public_ssh_key}\"",
      "sudo sed -i -e 's/# %wheel/%wheel/' -e 's/Defaults    requiretty/#Defaults    requiretty/' /etc/sudoers",
      "sudo useradd ${var.sudo_user}",
      "sudo echo ${var.sudo_password} | passwd ${var.sudo_user} --stdin",
      "sudo usermod ${var.sudo_user} -g wheel"
    ]
 }

  
}



###########################################################################################################################################################
# IS HTTP DB2
#
resource "aws_instance" "isdb2" {
  count         = "2"
  tags { Name = "${var.vm_name_prefix}-isdb2-${ count.index }.${var.vm_domain}" }
  instance_type = "m4.large"
  ami           = "${var.aws_image}"
  subnet_id     = "${data.aws_subnet.selected.id}"
  key_name      = "${aws_key_pair.temp_public_key.id}"
  root_block_device = { "volume_type" = "gp2", "volume_size" = "100", "delete_on_termination" = true }
  
  connection {
    user        = "ec2-user"
    private_key = "${tls_private_key.ssh.private_key_pem}"
    host        = "${self.public_ip}"
  }
  
   provisioner "file" {
    content = <<EOF
#!/bin/bash
LOGFILE="/var/log/addkey.log"
user_public_key=$1
if [ "$user_public_key" != "None" ] ; then
    echo "---start adding user_public_key----" | tee -a $LOGFILE 2>&1
    echo "$user_public_key" | tee -a $HOME/.ssh/authorized_keys          >> $LOGFILE 2>&1 || { echo "---Failed to add user_public_key---" | tee -a $LOGFILE; exit 1; }
    echo "---finish adding user_public_key----" | tee -a $LOGFILE 2>&1
fi
EOF

    destination = "/tmp/addkey.sh"
}

  provisioner "remote-exec" {
    inline = [
      "echo \"${var.vm_name_prefix}-isdb2-${ count.index }.${var.vm_domain}\">/tmp/hostname",
      "sudo mv /tmp/hostname /etc/hostname",
      "sudo hostname \"${var.vm_name_prefix}-isdb2-${ count.index }.${var.vm_domain}\"",
      "sudo chmod +x /tmp/addkey.sh; sudo bash /tmp/addkey.sh \"${var.public_ssh_key}\"",
      "sudo sed -i -e 's/# %wheel/%wheel/' -e 's/Defaults    requiretty/#Defaults    requiretty/' /etc/sudoers",
      "sudo useradd ${var.sudo_user}",
      "sudo echo ${var.sudo_password} | passwd ${var.sudo_user} --stdin",
      "sudo usermod ${var.sudo_user} -g wheel"
    ]
 }

  
}






###########################################################################################################################################################
# IS DS
#
resource "aws_instance" "isds" {
  count         = "1"
  tags { Name = "${var.vm_name_prefix}-isds.${var.vm_domain}" }
  instance_type = "m4.large"
  ami           = "${var.aws_image}"
  subnet_id     = "${data.aws_subnet.selected.id}"
  key_name      = "${aws_key_pair.temp_public_key.id}"
  root_block_device = { "volume_type" = "gp2", "volume_size" = "100", "delete_on_termination" = true }
  
  connection {
    user        = "ec2-user"
    private_key = "${tls_private_key.ssh.private_key_pem}"
    host        = "${self.public_ip}"
  }
  
   provisioner "file" {
    content = <<EOF
#!/bin/bash
LOGFILE="/var/log/addkey.log"
user_public_key=$1
if [ "$user_public_key" != "None" ] ; then
    echo "---start adding user_public_key----" | tee -a $LOGFILE 2>&1
    echo "$user_public_key" | tee -a $HOME/.ssh/authorized_keys          >> $LOGFILE 2>&1 || { echo "---Failed to add user_public_key---" | tee -a $LOGFILE; exit 1; }
    echo "---finish adding user_public_key----" | tee -a $LOGFILE 2>&1
fi
EOF

    destination = "/tmp/addkey.sh"
}

  provisioner "remote-exec" {
    inline = [
      "echo \"${var.vm_name_prefix}-isds.${var.vm_domain}\">/tmp/hostname",
      "sudo mv /tmp/hostname /etc/hostname",
      "sudo hostname \"${var.vm_name_prefix}-isds.${var.vm_domain}\"",
      "sudo chmod +x /tmp/addkey.sh; sudo bash /tmp/addkey.sh \"${var.public_ssh_key}\"",
      "sudo sed -i -e 's/# %wheel/%wheel/' -e 's/Defaults    requiretty/#Defaults    requiretty/' /etc/sudoers",
      "sudo useradd ${var.sudo_user}",
      "sudo echo ${var.sudo_password} | passwd ${var.sudo_user} --stdin",
      "sudo usermod ${var.sudo_user} -g wheel"
    ]
 }

  
}




###########################################################################################################################################################
# HAProxy
#
resource "aws_instance" "haproxy" {
  count         = "1"
  tags { Name = "${var.vm_name_prefix}-haproxy.${var.vm_domain}" }
  instance_type = "m4.large"
  ami           = "${var.aws_image}"
  subnet_id     = "${data.aws_subnet.selected.id}"
  key_name      = "${aws_key_pair.temp_public_key.id}"
  root_block_device = { "volume_type" = "gp2", "volume_size" = "100", "delete_on_termination" = true }
  
  connection {
    user        = "ec2-user"
    private_key = "${tls_private_key.ssh.private_key_pem}"
    host        = "${self.public_ip}"
  }
  
   provisioner "file" {
    content = <<EOF
#!/bin/bash
LOGFILE="/var/log/addkey.log"
user_public_key=$1
if [ "$user_public_key" != "None" ] ; then
    echo "---start adding user_public_key----" | tee -a $LOGFILE 2>&1
    echo "$user_public_key" | tee -a $HOME/.ssh/authorized_keys          >> $LOGFILE 2>&1 || { echo "---Failed to add user_public_key---" | tee -a $LOGFILE; exit 1; }
    echo "---finish adding user_public_key----" | tee -a $LOGFILE 2>&1
fi
EOF

    destination = "/tmp/addkey.sh"
}

  provisioner "remote-exec" {
    inline = [
      "echo \"${var.vm_name_prefix}-haproxy.${var.vm_domain}\">/tmp/hostname",
      "sudo mv /tmp/hostname /etc/hostname",
      "sudo hostname \"${var.vm_name_prefix}-haproxy.${var.vm_domain}\"",
      "sudo chmod +x /tmp/addkey.sh; sudo bash /tmp/addkey.sh \"${var.public_ssh_key}\"",
      "sudo sed -i -e 's/# %wheel/%wheel/' -e 's/Defaults    requiretty/#Defaults    requiretty/' /etc/sudoers",
      "sudo useradd ${var.sudo_user}",
      "sudo echo ${var.sudo_password} | passwd ${var.sudo_user} --stdin",
      "sudo usermod ${var.sudo_user} -g wheel"
    ]
 }

  
}




###########################################################################################################################################################
# HDP Management Nodes
#
resource "aws_instance" "hdp-mgmtnodes" {
  count         = "4"
  tags { Name = "${var.vm_name_prefix}-mn-${ count.index }.${var.vm_domain}" }
  instance_type = "m4.4xlarge"
  ami           = "${var.aws_image}"
  subnet_id     = "${data.aws_subnet.selected.id}"
  key_name      = "${aws_key_pair.temp_public_key.id}"
  root_block_device = { "volume_type" = "gp2", "volume_size" = "100", "delete_on_termination" = true }  
  ebs_block_device = { "device_name" = "/dev/sdf", "volume_type" = "gp2", "volume_size" = "1000", "delete_on_termination" = true, "encrypted" = true }
  ebs_block_device = { "device_name" = "/dev/sdg", "volume_type" = "gp2", "volume_size" = "1000", "delete_on_termination" = true, "encrypted" = true }
  ebs_block_device = { "device_name" = "/dev/sdh", "volume_type" = "gp2", "volume_size" = "1000", "delete_on_termination" = true, "encrypted" = true }
  
  connection {
    user        = "ec2-user"
    private_key = "${tls_private_key.ssh.private_key_pem}"
    host        = "${self.public_ip}"
  }
  
   provisioner "file" {
    content = <<EOF
#!/bin/bash
LOGFILE="/var/log/addkey.log"
user_public_key=$1
if [ "$user_public_key" != "None" ] ; then
    echo "---start adding user_public_key----" | tee -a $LOGFILE 2>&1
    echo "$user_public_key" | tee -a $HOME/.ssh/authorized_keys          >> $LOGFILE 2>&1 || { echo "---Failed to add user_public_key---" | tee -a $LOGFILE; exit 1; }
    echo "---finish adding user_public_key----" | tee -a $LOGFILE 2>&1
fi
EOF

    destination = "/tmp/addkey.sh"
}

  provisioner "remote-exec" {
    inline = [
      "echo \"${var.vm_name_prefix}-mn-${ count.index }.${var.vm_domain}\">/tmp/hostname",
      "sudo mv /tmp/hostname /etc/hostname",
      "sudo hostname \"${var.vm_name_prefix}-mn-${ count.index }.${var.vm_domain}\"",
      "sudo chmod +x /tmp/addkey.sh; sudo bash /tmp/addkey.sh \"${var.public_ssh_key}\"",
      "sudo sed -i -e 's/# %wheel/%wheel/' -e 's/Defaults    requiretty/#Defaults    requiretty/' /etc/sudoers",
      "sudo useradd ${var.sudo_user}",
      "sudo echo ${var.sudo_password} | passwd ${var.sudo_user} --stdin",
      "sudo usermod ${var.sudo_user} -g wheel"
    ]
 }

  
}




###########################################################################################################################################################
# HDP Data Nodes
#
resource "aws_instance" "hdp-datanodes" {
  count         = "${var.num_datanodes}"
  tags { Name = "${var.vm_name_prefix}-dn-${ count.index }.${var.vm_domain}" }
  instance_type = "m4.16xlarge"
  ami           = "${var.aws_image}"
  subnet_id     = "${data.aws_subnet.selected.id}"
  key_name      = "${aws_key_pair.temp_public_key.id}"
  root_block_device = { "volume_type" = "gp2", "volume_size" = "100", "delete_on_termination" = true }  
  ebs_block_device = { "device_name" = "/dev/sdf", "volume_type" = "gp2", "volume_size" = "4000", "delete_on_termination" = true, "encrypted" = true }
  ebs_block_device = { "device_name" = "/dev/sdg", "volume_type" = "gp2", "volume_size" = "4000", "delete_on_termination" = true, "encrypted" = true }
  ebs_block_device = { "device_name" = "/dev/sdh", "volume_type" = "gp2", "volume_size" = "4000", "delete_on_termination" = true, "encrypted" = true }
  ebs_block_device = { "device_name" = "/dev/sdi", "volume_type" = "gp2", "volume_size" = "4000", "delete_on_termination" = true, "encrypted" = true }
  ebs_block_device = { "device_name" = "/dev/sdj", "volume_type" = "gp2", "volume_size" = "4000", "delete_on_termination" = true, "encrypted" = true }
  ebs_block_device = { "device_name" = "/dev/sdk", "volume_type" = "gp2", "volume_size" = "4000", "delete_on_termination" = true, "encrypted" = true }
  ebs_block_device = { "device_name" = "/dev/sdl", "volume_type" = "gp2", "volume_size" = "4000", "delete_on_termination" = true, "encrypted" = true }
  ebs_block_device = { "device_name" = "/dev/sdm", "volume_type" = "gp2", "volume_size" = "4000", "delete_on_termination" = true, "encrypted" = true }
  ebs_block_device = { "device_name" = "/dev/sdn", "volume_type" = "gp2", "volume_size" = "4000", "delete_on_termination" = true, "encrypted" = true }
  ebs_block_device = { "device_name" = "/dev/sdo", "volume_type" = "gp2", "volume_size" = "4000", "delete_on_termination" = true, "encrypted" = true }
  
  connection {
    user        = "ec2-user"
    private_key = "${tls_private_key.ssh.private_key_pem}"
    host        = "${self.public_ip}"
  }
  
   provisioner "file" {
    content = <<EOF
#!/bin/bash
LOGFILE="/var/log/addkey.log"
user_public_key=$1
if [ "$user_public_key" != "None" ] ; then
    echo "---start adding user_public_key----" | tee -a $LOGFILE 2>&1
    echo "$user_public_key" | tee -a $HOME/.ssh/authorized_keys          >> $LOGFILE 2>&1 || { echo "---Failed to add user_public_key---" | tee -a $LOGFILE; exit 1; }
    echo "---finish adding user_public_key----" | tee -a $LOGFILE 2>&1
fi
EOF

    destination = "/tmp/addkey.sh"
}

  provisioner "remote-exec" {
    inline = [
      "echo \"${var.vm_name_prefix}-dn-${ count.index }.${var.vm_domain}\">/tmp/hostname",
      "sudo mv /tmp/hostname /etc/hostname",
      "sudo hostname \"${var.vm_name_prefix}-dn-${ count.index }.${var.vm_domain}\"",
      "sudo chmod +x /tmp/addkey.sh; sudo bash /tmp/addkey.sh \"${var.public_ssh_key}\"",
      "sudo sed -i -e 's/# %wheel/%wheel/' -e 's/Defaults    requiretty/#Defaults    requiretty/' /etc/sudoers",
      "sudo useradd ${var.sudo_user}",
      "sudo echo ${var.sudo_password} | passwd ${var.sudo_user} --stdin",
      "sudo usermod ${var.sudo_user} -g wheel"
    ]
 }

  
}





###########################################################################################################################################################
# HDP BigSQL Head Node
#
resource "aws_instance" "hdp-bigsql" {
  count         = "1"
  tags { Name = "${var.vm_name_prefix}-bigsql-${ count.index }.${var.vm_domain}" }
  instance_type = "m4.16xlarge"
  ami           = "${var.aws_image}"
  subnet_id     = "${data.aws_subnet.selected.id}"
  key_name      = "${aws_key_pair.temp_public_key.id}"
  root_block_device = { "volume_type" = "gp2", "volume_size" = "100", "delete_on_termination" = true }  
  ebs_block_device = { "device_name" = "/dev/sdf", "volume_type" = "gp2", "volume_size" = "4000", "delete_on_termination" = true, "encrypted" = true }
  ebs_block_device = { "device_name" = "/dev/sdg", "volume_type" = "gp2", "volume_size" = "4000", "delete_on_termination" = true, "encrypted" = true }
  ebs_block_device = { "device_name" = "/dev/sdh", "volume_type" = "gp2", "volume_size" = "4000", "delete_on_termination" = true, "encrypted" = true }
  ebs_block_device = { "device_name" = "/dev/sdi", "volume_type" = "gp2", "volume_size" = "4000", "delete_on_termination" = true, "encrypted" = true }
  ebs_block_device = { "device_name" = "/dev/sdj", "volume_type" = "gp2", "volume_size" = "4000", "delete_on_termination" = true, "encrypted" = true }
  ebs_block_device = { "device_name" = "/dev/sdk", "volume_type" = "gp2", "volume_size" = "4000", "delete_on_termination" = true, "encrypted" = true }
  ebs_block_device = { "device_name" = "/dev/sdl", "volume_type" = "gp2", "volume_size" = "4000", "delete_on_termination" = true, "encrypted" = true }
  ebs_block_device = { "device_name" = "/dev/sdm", "volume_type" = "gp2", "volume_size" = "4000", "delete_on_termination" = true, "encrypted" = true }
  ebs_block_device = { "device_name" = "/dev/sdn", "volume_type" = "gp2", "volume_size" = "4000", "delete_on_termination" = true, "encrypted" = true }
  ebs_block_device = { "device_name" = "/dev/sdo", "volume_type" = "gp2", "volume_size" = "4000", "delete_on_termination" = true, "encrypted" = true }
  
  connection {
    user        = "ec2-user"
    private_key = "${tls_private_key.ssh.private_key_pem}"
    host        = "${self.public_ip}"
  }
  
   provisioner "file" {
    content = <<EOF
#!/bin/bash
LOGFILE="/var/log/addkey.log"
user_public_key=$1
if [ "$user_public_key" != "None" ] ; then
    echo "---start adding user_public_key----" | tee -a $LOGFILE 2>&1
    echo "$user_public_key" | tee -a $HOME/.ssh/authorized_keys          >> $LOGFILE 2>&1 || { echo "---Failed to add user_public_key---" | tee -a $LOGFILE; exit 1; }
    echo "---finish adding user_public_key----" | tee -a $LOGFILE 2>&1
fi
EOF

    destination = "/tmp/addkey.sh"
}

  provisioner "remote-exec" {
    inline = [
      "echo \"${var.vm_name_prefix}-bigsql-${ count.index }.${var.vm_domain}\">/tmp/hostname",
      "sudo mv /tmp/hostname /etc/hostname",
      "sudo hostname \"${var.vm_name_prefix}-bigsql-${ count.index }.${var.vm_domain}\"",
      "sudo chmod +x /tmp/addkey.sh; sudo bash /tmp/addkey.sh \"${var.public_ssh_key}\"",
      "sudo sed -i -e 's/# %wheel/%wheel/' -e 's/Defaults    requiretty/#Defaults    requiretty/' /etc/sudoers",
      "sudo useradd ${var.sudo_user}",
      "sudo echo ${var.sudo_password} | passwd ${var.sudo_user} --stdin",
      "sudo usermod ${var.sudo_user} -g wheel"
    ]
 }

  
}

