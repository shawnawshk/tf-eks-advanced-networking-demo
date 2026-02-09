# MNG removed - Karpenter handles all node provisioning.
# Karpenter runs on Fargate, so no bootstrap nodes are needed.
# Karpenter NodePools already set the k8s.amazonaws.com/eniConfig label per-AZ,
# which avoids the custom networking label issue with MNG nodes.
