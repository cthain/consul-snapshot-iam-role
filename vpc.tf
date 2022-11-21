data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
  state = "available"
}

data "aws_caller_identity" "current" {}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.14.2"

  name                       = var.name
  azs                        = data.aws_availability_zones.available.names
  cidr                       = var.vpc_cidr
  private_subnets            = var.private_subnets
  public_subnets             = var.public_subnets
  manage_default_route_table = true
  default_route_table_tags   = { DefaultRouteTable = true }
  enable_nat_gateway         = true
  single_nat_gateway         = true
  enable_dns_hostnames       = true
  enable_dns_support         = true
}

# Security Group for the HashiCups deployment.
# Note that this allows wide open ingress and egress from the public internet
# and is not suitable for production environments.
resource "aws_security_group" "this" {
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 0
    protocol  = "-1"
    to_port   = 0
    self      = true
  }

  egress {
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    protocol  = "-1"
    to_port   = 0
    self      = true
  }

}
