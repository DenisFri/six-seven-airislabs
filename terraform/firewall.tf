# Ingress is denied by default; each rule opens exactly one door.

resource "google_compute_firewall" "admin_to_bastion" {
  name      = "six-seven-allow-admin-ssh-bastion"
  network   = google_compute_network.vpc.id
  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = [var.mngmt_cidr]
  target_tags   = ["bastion"]
}

resource "google_compute_firewall" "bastion_to_k3s" {
  name      = "six-seven-allow-bastion-to-k3s"
  network   = google_compute_network.vpc.id
  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["22", "6443"] # ssh + Kubernetes API for kubectl on the bastion
  }

  source_tags = ["bastion"]
  target_tags = ["k3s"]
}