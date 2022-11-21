variable "name" {
  description = "The name of this deployment."
  type        = string
}

# AWS

## VPC

variable "region" {
  description = "The AWS region to create resources in."
  type        = string
  default     = "us-west-2"
}

variable "vpc_cidr" {
  description = "VPC CIDR block."
  type        = string
  default     = "10.0.0.0/16"

}

variable "private_subnets" {
  description = "List of private subnet CIDR blocks."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "public_subnets" {
  description = "List of public subnet CIDR blocks."
  type        = list(string)
  default     = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
}

## K8S

variable "k8s_version" {
  type        = string
  description = "Version of Kubernetes to deploy to EKS."
  default     = "1.22"
}

## IAM

variable "iam_path" {
  description = "The path under which IAM objecst are stored."
  type        = string
  default     = "/"
}

## S3

variable "s3_bucket_name" {
  description = "The name of an existing the S3 bucket to store snapshots in. The default is to create a new S3 bucket to store snapshots in."
  type        = string
  default     = ""
}

# Consul

variable "consul_chart_version" {
  description = "Version of the Helm chart used to install Consul."
  type        = string
  default     = "0.49.0"
}

variable "consul_datacenter" {
  description = "The name of the Consul datacenter."
  type        = string
  default     = "dc1"
}

variable "consul_image" {
  description = "The Consul version to deploy"
  type        = string
  default     = "hashicorp/consul-enterprise:1.13.3-ent"
}

variable "consul_license_path" {
  description = "The path to the Consul license file."
  type        = string
}

variable "consul_snapshot_interval" {
  description = "The interval as a go time.Duration string between snapshots."
  type        = string
  default     = "2m"
}

variable "consul_snapshot_retain" {
  description = "The number of snapshots to retain before deleting older snapshots."
  type        = number
  default     = 2
}
