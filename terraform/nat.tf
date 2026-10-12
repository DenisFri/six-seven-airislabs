# By default - OFF. 
# The K3s VM has no public IP. Cloud NAT gives it outbound-only internet

resource "google_compute_router" "router" {
  name    = "six-seven-router"
  count   = var.enable_nat ? 1 : 0
  network = google_compute_network.vpc.id
  region  = var.region
}

resource "google_compute_router_nat" "nat" {
  name                               = "six-seven-nat"
  count                              = var.enable_nat ? 1 : 0
  router                             = google_compute_router.router[0].name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}
