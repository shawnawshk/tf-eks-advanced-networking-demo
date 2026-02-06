terraform {
  required_version = ">= 1.3"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.34"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.9"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14"
    }
  }
}


provider "aws" {
  region = var.region
}

provider "aws" {
  alias  = "ecr"
  region = "us-east-1"
}


provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
  load_config_file       = false
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      # This requires the awscli to be installed locally where Terraform is executed
      args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}



data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.ecr
}

data "aws_availability_zones" "available" {
  # Do not include local zones
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}
locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 6)

  # Primary CIDR subnets (10.8.0.0/16) - 6x /20
  private_subnets = [for i in range(6) : cidrsubnet(var.vpc_cidr, 4, i)]
  public_subnets  = [for i in range(6) : cidrsubnet(var.vpc_cidr, 4, i + 6)]

  # Secondary CIDR subnets - 2 AZs per secondary CIDR, one /17 per AZ
  # 100.64.0.0/16 -> AZ a,b | 100.65.0.0/16 -> AZ c,d | 100.66.0.0/16 -> AZ e,f
  intra_subnets = flatten([
    for cidr in var.secondary_cidrs : [
      cidrsubnet(cidr, 1, 0),
      cidrsubnet(cidr, 1, 1),
    ]
  ])

  # EKS control plane does not support us-east-1e
  eks_private_subnet_ids = [
    for i, subnet in module.vpc.private_subnets : subnet
    if local.azs[i] != "us-east-1e"
  ]
}

