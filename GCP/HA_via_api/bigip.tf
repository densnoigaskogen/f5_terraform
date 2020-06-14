# BIG-IP

# Public IP for VIP
resource "google_compute_address" "vip1" {
  name = "${var.prefix}-vip1"
}

# Forwarding rule for Public IP
resource "google_compute_forwarding_rule" "vip1" {
  name       = "${var.prefix}-forwarding-rule"
  target     = google_compute_target_instance.f5vm.id
  ip_address = google_compute_address.vip1.address
  port_range = "1-65535"
}

resource "google_compute_target_instance" "f5vm" {
  name     = "${var.prefix}-ti"
  instance = google_compute_instance.f5vm02.id
}

# Setup Onboarding scripts
locals {
  vm_onboard = templatefile("${path.module}/onboard.tpl", {
    uname          = var.uname
    usecret        = var.usecret
    ksecret        = var.ksecret
    gcp_project_id = var.gcp_project_id
    DO_URL         = var.DO_URL
    AS3_URL        = var.AS3_URL
    TS_URL         = var.TS_URL
    CF_URL         = var.CF_URL
    onboard_log    = var.onboard_log
    DO_Document    = local.do_json
    AS3_Document   = ""
    TS_Document    = local.ts_json
    CFE_Document   = local.cfe_json
  })
  vm2_onboard = templatefile("${path.module}/onboard.tpl", {
    uname          = var.uname
    usecret        = var.usecret
    ksecret        = var.ksecret
    gcp_project_id = var.gcp_project_id
    DO_URL         = var.DO_URL
    AS3_URL        = var.AS3_URL
    TS_URL         = var.TS_URL
    CF_URL         = var.CF_URL
    onboard_log    = var.onboard_log
    DO_Document    = local.do2_json
    AS3_Document   = local.as3_json
    TS_Document    = local.ts_json
    CFE_Document   = local.cfe2_json
  })
  do_json = templatefile("${path.module}/do.json", {
    regKey         = var.license1
    host1          = "${var.prefix}-${var.host1_name}"
    host2          = "${var.prefix}-${var.host2_name}"
    local_host     = "${var.prefix}-${var.host1_name}"
    remote_host    = "${var.prefix}-${var.host2_name}"
    dns_server     = var.dns_server
    dns_suffix     = var.dns_suffix
    ntp_server     = var.ntp_server
    timezone       = var.timezone
    admin_username = var.uname
  })
  do2_json = templatefile("${path.module}/do.json", {
    regKey         = var.license2
    host1          = "${var.prefix}-${var.host1_name}"
    host2          = "${var.prefix}-${var.host2_name}"
    local_host     = "${var.prefix}-${var.host2_name}"
    remote_host    = "${var.prefix}-${var.host1_name}"
    dns_server     = var.dns_server
    dns_suffix     = var.dns_suffix
    ntp_server     = var.ntp_server
    timezone       = var.timezone
    admin_username = var.uname
  })
  as3_json = templatefile("${path.module}/as3.json", {
    gcp_region = var.gcp_region
    #publicvip  = "0.0.0.0"
    publicvip  = google_compute_address.vip1.address
    privatevip = var.alias_ip_range
  })
  ts_json = templatefile("${path.module}/ts.json", {
    gcp_project_id = var.gcp_project_id
    svc_acct       = var.svc_acct
    privateKeyId   = var.privateKeyId
  })
  cfe_json = templatefile("${path.module}/cfe.json", {
    f5_cloud_failover_label = var.f5_cloud_failover_label
    managed_route1          = var.managed_route1
    remote_selfip           = ""
  })
  cfe2_json = templatefile("${path.module}/cfe.json", {
    f5_cloud_failover_label = var.f5_cloud_failover_label
    managed_route1          = var.managed_route1
    remote_selfip           = google_compute_instance.f5vm01.network_interface.0.network_ip
  })
}

# Create F5 BIG-IP VMs
resource "google_compute_instance" "f5vm01" {
  name           = "${var.prefix}-${var.host1_name}"
  machine_type   = var.bigipMachineType
  zone           = var.gcp_zone
  can_ip_forward = true

  labels = {
    f5_cloud_failover_label = var.f5_cloud_failover_label
  }

  tags = ["appfw-${var.prefix}", "mgmtfw-${var.prefix}"]

  boot_disk {
    initialize_params {
      image = var.customImage != "" ? var.customImage : var.image_name
      size  = "128"
    }
  }

  network_interface {
    network    = var.extVpc
    subnetwork = var.extSubnet
    access_config {
    }
  }

  network_interface {
    network    = var.mgmtVpc
    subnetwork = var.mgmtSubnet
    access_config {
    }
  }

  metadata = {
    ssh-keys               = "${var.uname}:${var.gceSshPubKey}"
    block-project-ssh-keys = true
    startup-script         = var.customImage != "" ? var.customUserData : local.vm_onboard
  }

  service_account {
    email  = var.svc_acct
    scopes = ["cloud-platform"]
  }
}

resource "google_compute_instance" "f5vm02" {
  name           = "${var.prefix}-${var.host2_name}"
  machine_type   = var.bigipMachineType
  zone           = var.gcp_zone
  can_ip_forward = true

  labels = {
    f5_cloud_failover_label = var.f5_cloud_failover_label
  }

  tags = ["appfw-${var.prefix}", "mgmtfw-${var.prefix}"]

  boot_disk {
    initialize_params {
      image = var.customImage != "" ? var.customImage : var.image_name
      size  = "128"
    }
  }

  network_interface {
    network    = var.extVpc
    subnetwork = var.extSubnet
    access_config {
    }
    alias_ip_range {
      ip_cidr_range = var.alias_ip_range
    }
  }

  network_interface {
    network    = var.mgmtVpc
    subnetwork = var.mgmtSubnet
    access_config {
    }
  }

  metadata = {
    ssh-keys               = "${var.uname}:${var.gceSshPubKey}"
    block-project-ssh-keys = true
    startup-script         = var.customImage != "" ? var.customUserData : local.vm2_onboard
  }

  service_account {
    email  = var.svc_acct
    scopes = ["cloud-platform"]
  }
}

# # Troubleshooting - create local output files
# resource "local_file" "onboard_file" {
#   content  = local.vm_onboard
#   filename = "${path.module}/vm_onboard.tpl_data.json"
# }
