output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "eks_cluster_id" {
  value = module.eks.cluster_id
}

output "update_kubeconfig_cmd" {
  value = "aws eks --region ${var.region} update-kubeconfig --name ${module.eks.cluster_id}"
}

output "consul_http_token" {
  value = random_uuid.bootstrap_token.result
}

output "consul_ca_cert" {
  value     = tls_self_signed_cert.ca.cert_pem
  sensitive = true
}

output "region" {
  value = var.region
}
