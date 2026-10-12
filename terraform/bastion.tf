# Dedicated service account with no project roles: the bastion needs an identity,
# not GCP powers. (The default compute SA carries Editor, which is far too much.)

resource "google_service_account" "bastion" {
  account_id   = "six-seven-bastion"
  display_name = "Bastion VM"
}

resource "google_compute_instance" "bastion" {
  name         = "six-seven-bastion"
  machine_type = "e2-small"
  zone         = var.zone
  tags         = ["bastion"]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.private.id
    access_config {}
  }

  metadata = {
    ssh-keys = "${var.ssh_user}:${trimspace(file(pathexpand(var.ssh_public_key_path)))}"
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  service_account {
    email  = google_service_account.bastion.email
    scopes = ["https://www.googleapis.com/auth/logging.write", "https://www.googleapis.com/auth/monitoring.write"]
  }
}