# ENIConfig for VPC CNI custom networking
# One ENIConfig per intra subnet (40 total, 8 per AZ)
# ENIConfig name format: {az}-{per_az_index} (e.g. us-east-1a-0)
# VPC CNI uses k8s.amazonaws.com/eniConfig label to select the correct ENIConfig

resource "kubectl_manifest" "eniconfig" {
  for_each = local.eniconfig_map

  yaml_body = yamlencode({
    apiVersion = "crd.k8s.amazonaws.com/v1alpha1"
    kind       = "ENIConfig"
    metadata = {
      name = each.key
    }
    spec = {
      securityGroups = [module.eks.cluster_primary_security_group_id]
      subnet         = each.value.subnet_id
    }
  })

}
