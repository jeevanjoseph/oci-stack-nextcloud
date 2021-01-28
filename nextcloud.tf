
data "template_file" "nextcloud-docker-compose" {
  template = file("${path.module}/scripts/nextcloud.yaml")

  vars = {
    public_key_openssh  = tls_private_key.public_private_key_pair.public_key_openssh,
    mysql_root_password = var.mysql_root_password,
    wp_schema           = var.wp_schema,
    wp_db_user          = var.wp_db_user,
    wp_db_password      = var.wp_db_password,
    wp_site_url         = oci_core_public_ip.Nextcloud_public_ip.ip_address,
    wp_admin_user          = var.wp_admin_user,
    wp_admin_password      = var.wp_admin_password
  }
}


resource "oci_core_instance" "Nextcloud" {
  availability_domain = local.availability_domain_name
  compartment_id      = var.compartment_ocid
  display_name        = "Nextcloud"
  shape               = var.node_shape

  create_vnic_details {
    subnet_id        = oci_core_subnet.public.id
    display_name     = "primaryvnic"
    assign_public_ip = false
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.InstanceImageOCID.images[0].id
  }

  metadata = {
    ssh_authorized_keys = var.generate_public_ssh_key ? tls_private_key.public_private_key_pair.public_key_openssh : var.public_ssh_key
    user_data           = base64encode(templatefile("./scripts/setup-docker.yaml",{}))
  }

}

data "oci_core_vnic_attachments" "Nextcloud_vnics" {
  compartment_id      = var.compartment_ocid
  availability_domain = local.availability_domain_name
  instance_id         = oci_core_instance.Nextcloud.id
}

data "oci_core_vnic" "Nextcloud_vnic1" {
  vnic_id = data.oci_core_vnic_attachments.Nextcloud_vnics.vnic_attachments[0]["vnic_id"]
}

data "oci_core_private_ips" "Nextcloud_private_ips1" {
  vnic_id = data.oci_core_vnic.Nextcloud_vnic1.id
}

resource "oci_core_public_ip" "Nextcloud_public_ip" {
  compartment_id = var.compartment_ocid
  display_name   = "Nextcloud_public_ip"
  lifetime       = "RESERVED"
  private_ip_id  = data.oci_core_private_ips.Nextcloud_private_ips1.private_ips[0]["id"]
}

resource "null_resource" "Nextcloud_provisioner" {
  depends_on = [oci_core_instance.Nextcloud, oci_core_public_ip.Nextcloud_public_ip]

  provisioner "file" {
    content     = data.template_file.nextcloud-docker-compose.rendered
    destination = "/home/opc/nextcloud.yaml"

    connection {
      type        = "ssh"
      host        = oci_core_public_ip.Nextcloud_public_ip.ip_address
      agent       = false
      timeout     = "5m"
      user        = "opc"
      private_key = tls_private_key.public_private_key_pair.private_key_pem

    }
  }

  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      host        = oci_core_public_ip.Nextcloud_public_ip.ip_address
      agent       = false
      timeout     = "5m"
      user        = "opc"
      private_key = tls_private_key.public_private_key_pair.private_key_pem

    }

    inline = [
      "while [ ! -f /tmp/cloud-init-complete ]; do sleep 2; done",
      "docker-compose -f /home/opc/nextcloud.yaml up -d"
    ]

  }
}



locals {
  availability_domain_name = var.availability_domain_name != null ? var.availability_domain_name : data.oci_identity_availability_domains.ADs.availability_domains[0].name
}
