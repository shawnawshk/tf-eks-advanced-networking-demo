module "eks_blueprints_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.0" #ensure to update this to the latest/desired version

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn
  # disable the Telemetry from AWS using CloudFormation
  observability_tag = null

  # Ensure node group is created before deploying addons that need compute
  depends_on = [module.eks]

  eks_addons = {
    metrics-server = { most_recent = true }
  }

  enable_aws_load_balancer_controller = true
  aws_load_balancer_controller = {
    chart_version = "1.14.1"
    set = [
      {
        name  = "vpcId" # explicitly set the vpcId, otherwise it may not able to retrieve the vpcId from the node
        value = module.vpc.vpc_id
      },
      {
        name  = "controllerConfig.featureGates.ALBGatewayAPI"
        value = "true"
      },
      {
        name  = "controllerConfig.featureGates.NLBGatewayAPI"
        value = "true"
      },
    ]
  }

  enable_aws_efs_csi_driver = true

  helm_releases = {
  }

  tags = merge(local.tags, {
    # NOTE - if creating multiple security groups with this module, only tag the
    # security group that Karpenter should utilize with the following tag
    # (i.e. - at most, only one security group should have this tag in your account)
    "Environment" = "dev"
  })
}
