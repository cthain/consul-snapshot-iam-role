
locals {
  s3_bucket_name   = var.s3_bucket_name != "" ? var.s3_bucket_name : "${var.name}-consul-snapshots"
  create_s3_bucket = var.s3_bucket_name == ""

  consul_snapshot_config = <<EOF
{
  "snapshot_agent": {
    "snapshot": {
      "interval": "${var.consul_snapshot_interval}",
      "retain": ${var.consul_snapshot_retain}
    },
    "aws_storage": {
      "s3_region": "${var.region}",
      "s3_bucket": "${local.s3_bucket_name}"
    }
  }
}
EOF
}

# EKS
module "eks" {
  source                          = "registry.terraform.io/terraform-aws-modules/eks/aws"
  version                         = "18.26.6"
  cluster_name                    = var.name
  cluster_version                 = var.k8s_version
  subnet_ids                      = concat(module.vpc.private_subnets, module.vpc.public_subnets)
  vpc_id                          = module.vpc.vpc_id
  enable_irsa                     = false
  eks_managed_node_group_defaults = {}
  create_cluster_security_group   = false
  cluster_security_group_id       = aws_security_group.this.id
  eks_managed_node_groups = {
    default_group = {
      min_size               = 3
      max_size               = 3
      desired_size           = 3
      labels                 = {}
      vpc_security_group_ids = [aws_security_group.this.id]

      instance_types = ["m5.large"]
      metadata_options = {
        http_endpoint               = "enabled"
        http_tokens                 = "optional"
        http_put_response_hop_limit = 2
        instance_metadata_tags      = "disabled"
      }
    }
  }
}

# S3
resource "aws_s3_bucket" "consul_snapshots" {
  count  = local.create_s3_bucket ? 1 : 0
  bucket = local.s3_bucket_name
}

# Secure install

## ACLs - bootstrap token
resource "random_uuid" "bootstrap_token" {}

## Gossip encryption - gossip key
resource "random_id" "gossip_key" {
  byte_length = 32
}

## TLS

### private key
resource "tls_private_key" "ca" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P384"
}

### CA cert
resource "tls_self_signed_cert" "ca" {
  private_key_pem = tls_private_key.ca.private_key_pem

  subject {
    common_name  = "Consul Agent CA"
    organization = "HashiCorp Inc."
  }

  // 5 years.
  validity_period_hours = 43800

  is_ca_certificate  = true
  set_subject_key_id = true

  allowed_uses = [
    "digital_signature",
    "cert_signing",
    "crl_signing",
  ]
}

resource "kubernetes_secret" "consul_secrets" {
  metadata {
    name = var.name
  }
  data = {
    license             = file(var.consul_license_path)
    caKey               = tls_private_key.ca.private_key_pem
    caCert              = tls_self_signed_cert.ca.cert_pem
    gossipEncryptionKey = random_id.gossip_key.b64_std
    bootstrapToken      = random_uuid.bootstrap_token.result
    ssaConfig           = local.consul_snapshot_config
  }
  type = "Opaque"
}

resource "local_file" "consul_values_yaml" {
  filename        = "values.yaml"
  file_permission = "0644"
  content = templatefile("values.yaml.tftpl", {
    datacenter   = var.consul_datacenter
    consul_image = var.consul_image
    secret_name  = var.name
  })
}
