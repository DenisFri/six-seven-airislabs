output "bastion_public_ip" {
  description = "SSH entry point"
  value       = google_compute_instance.bastion.network_interface[0].access_config[0].nat_ip
}

output "bastion_private_ip" {
  description = "Bastion address inside the VPC (source of all traffic to the k3s node)"
  value       = google_compute_instance.bastion.network_interface[0].network_ip
}

output "k3s_private_ip" {
  description = "K3s node; reachable only through the bastion"
  value       = google_compute_instance.k3s.network_interface[0].network_ip
}