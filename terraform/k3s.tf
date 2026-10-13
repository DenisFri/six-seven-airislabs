# Same pattern as the bastion host, but for the k3s cluster. (No public IP)
# Bigger machine type for the k3s server, since it will be running k3s + CNPG operator + two Postgres pods ( >=4 GB )

resource "google_service_account" "k3s" {
  account_id   = "six-seven-k3s"
  display_name = "K3s VM"
}

resource "google_compute_instance" "k3s" {
  name         = "six-seven-k3s"
  machine_type = "e2-standard-2"
  zone         = var.zone
  tags         = ["k3s"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 20
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.private.id
    # No access_config: no public IP. 
    # In only through the bastion. Out only through NAT.
  }

  metadata = {
    ssh-keys               = "${var.ssh_user}:${trimspace(file(pathexpand(var.ssh_public_key_path)))}"
    block-project-ssh-keys = "true"
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  service_account {
    email  = google_service_account.k3s.email
    scopes = ["https://www.googleapis.com/auth/logging.write", "https://www.googleapis.com/auth/monitoring.write"]
  }
}