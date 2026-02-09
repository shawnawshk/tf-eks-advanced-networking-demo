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

  # Exclude AZ IDs that don't support EKS control plane
  exclude_zone_ids = var.eks_unsupported_az_ids
}

locals {
  azs = data.aws_availability_zones.available.names

  # Primary CIDR subnets (10.8.0.0/16) - one /20 per AZ
  primary_private_subnets = [for i in range(length(local.azs)) : cidrsubnet(var.vpc_cidr, 4, i)]
  public_subnets          = [for i in range(length(local.azs)) : cidrsubnet(var.vpc_cidr, 4, i + length(local.azs))]

  # Secondary CIDR subnets - 2 AZs per secondary CIDR, one /17 per AZ
  secondary_private_subnets = flatten([
    for cidr in var.secondary_cidrs : [
      cidrsubnet(cidr, 1, 0),
      cidrsubnet(cidr, 1, 1),
    ]
  ])

  # All private subnets: primary first, then secondary
  private_subnets = concat(local.primary_private_subnets, local.secondary_private_subnets)

  # EKS control plane uses only primary CIDR subnets
  eks_private_subnet_ids = slice(module.vpc.private_subnets, 0, length(local.primary_private_subnets))

  # Secondary CIDR subnet IDs (for selective tagging)
  secondary_subnet_ids = slice(
    module.vpc.private_subnets,
    length(local.primary_private_subnets),
    length(local.private_subnets)
  )
}
