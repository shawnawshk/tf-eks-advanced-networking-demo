# ENIConfig for VPC CNI custom networking
# One ENIConfig per AZ, mapping to intra subnets (secondary CIDRs)
# ENIConfig name must match the AZ name since ENI_CONFIG_LABEL_DEF = "topology.kubernetes.io/zone"

resource "kubectl_manifest" "eniconfig" {
  for_each = zipmap(local.azs, module.vpc.intra_subnets)

  yaml_body = yamlencode({
    apiVersion = "crd.k8s.amazonaws.com/v1alpha1"
    kind       = "ENIConfig"
    metadata = {
      name = each.key
    }
    spec = {
      securityGroups = [module.eks.cluster_primary_security_group_id]
      subnet         = each.value
    }
  })

}
