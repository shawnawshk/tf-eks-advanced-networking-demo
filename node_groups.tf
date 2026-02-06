# Node groups created separately to ensure ENIConfig is applied first
# Dependency chain: EKS cluster -> ENIConfig -> Node Groups

module "eks_managed_node_group" {
  source  = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"
  version = "~> 20.31"

  name            = "ng-1"
  cluster_name    = module.eks.cluster_name
  cluster_version = module.eks.cluster_version

  subnet_ids                        = local.eks_private_subnet_ids
  cluster_primary_security_group_id = module.eks.cluster_primary_security_group_id
  cluster_service_cidr              = module.eks.cluster_service_cidr

  min_size       = 1
  max_size       = 2
  desired_size   = 2
  instance_types = ["m5.8xlarge"]

  block_device_mappings = {
    xvda = {
      device_name = "/dev/xvda"
      ebs = {
        volume_size           = 500
        volume_type           = "gp3"
        iops                  = 3000
        throughput            = 150
        delete_on_termination = true
      }
    }
  }

  tags = merge(local.tags, {
    "karpenter.sh/discovery" = local.name
  })

  # Ensure ENIConfigs exist before nodes join the cluster
  depends_on = [kubectl_manifest.eniconfig]
}
