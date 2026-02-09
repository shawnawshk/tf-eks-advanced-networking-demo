# EKS with VPC CNI Custom Networking

Terraform configuration for deploying an Amazon EKS cluster with VPC CNI custom networking using secondary CIDR blocks. This setup separates node IPs (primary CIDR) from pod IPs (secondary CIDRs) to maximize available IP addresses for pods.

## Architecture

```
VPC (10.8.0.0/16) — 5 AZs (us-east-1a, b, c, d, f — excluding e)
├── Primary CIDR: 10.8.0.0/16
│   ├── Private Subnets (5x /20) - Node IPs, EKS control plane
│   └── Public Subnets  (5x /20) - Load balancers, NAT gateways
└── Secondary CIDRs: 100.64.0.0/16 – 100.83.0.0/16 (20x /16)
    Each /16 split into 2x /17 subnets, round-robin across 5 AZs
    = 40 intra subnets total, 8 per AZ
```

### Subnet Distribution

20 secondary CIDRs produce 40 `/17` subnets (32,768 IPs each). Each `/16` is split into 2x `/17` and the two halves are placed in two consecutive AZs (round-robin across 5 AZs):

| Index | Subnet CIDR | Parent /16 | AZ |
|---|---|---|---|
| 0 | `100.64.0.0/17` | 100.64.0.0/16 | us-east-1a |
| 1 | `100.64.128.0/17` | 100.64.0.0/16 | us-east-1b |
| 2 | `100.65.0.0/17` | 100.65.0.0/16 | us-east-1c |
| 3 | `100.65.128.0/17` | 100.65.0.0/16 | us-east-1d |
| 4 | `100.66.0.0/17` | 100.66.0.0/16 | us-east-1f |
| 5 | `100.66.128.0/17` | 100.66.0.0/16 | us-east-1a |
| 6 | `100.67.0.0/17` | 100.67.0.0/16 | us-east-1b |
| 7 | `100.67.128.0/17` | 100.67.0.0/16 | us-east-1c |
| 8 | `100.68.0.0/17` | 100.68.0.0/16 | us-east-1d |
| 9 | `100.68.128.0/17` | 100.68.0.0/16 | us-east-1f |
| 10 | `100.69.0.0/17` | 100.69.0.0/16 | us-east-1a |
| 11 | `100.69.128.0/17` | 100.69.0.0/16 | us-east-1b |
| 12 | `100.70.0.0/17` | 100.70.0.0/16 | us-east-1c |
| 13 | `100.70.128.0/17` | 100.70.0.0/16 | us-east-1d |
| 14 | `100.71.0.0/17` | 100.71.0.0/16 | us-east-1f |
| 15 | `100.71.128.0/17` | 100.71.0.0/16 | us-east-1a |
| 16 | `100.72.0.0/17` | 100.72.0.0/16 | us-east-1b |
| 17 | `100.72.128.0/17` | 100.72.0.0/16 | us-east-1c |
| 18 | `100.73.0.0/17` | 100.73.0.0/16 | us-east-1d |
| 19 | `100.73.128.0/17` | 100.73.0.0/16 | us-east-1f |
| 20 | `100.74.0.0/17` | 100.74.0.0/16 | us-east-1a |
| 21 | `100.74.128.0/17` | 100.74.0.0/16 | us-east-1b |
| 22 | `100.75.0.0/17` | 100.75.0.0/16 | us-east-1c |
| 23 | `100.75.128.0/17` | 100.75.0.0/16 | us-east-1d |
| 24 | `100.76.0.0/17` | 100.76.0.0/16 | us-east-1f |
| 25 | `100.76.128.0/17` | 100.76.0.0/16 | us-east-1a |
| 26 | `100.77.0.0/17` | 100.77.0.0/16 | us-east-1b |
| 27 | `100.77.128.0/17` | 100.77.0.0/16 | us-east-1c |
| 28 | `100.78.0.0/17` | 100.78.0.0/16 | us-east-1d |
| 29 | `100.78.128.0/17` | 100.78.0.0/16 | us-east-1f |
| 30 | `100.79.0.0/17` | 100.79.0.0/16 | us-east-1a |
| 31 | `100.79.128.0/17` | 100.79.0.0/16 | us-east-1b |
| 32 | `100.80.0.0/17` | 100.80.0.0/16 | us-east-1c |
| 33 | `100.80.128.0/17` | 100.80.0.0/16 | us-east-1d |
| 34 | `100.81.0.0/17` | 100.81.0.0/16 | us-east-1f |
| 35 | `100.81.128.0/17` | 100.81.0.0/16 | us-east-1a |
| 36 | `100.82.0.0/17` | 100.82.0.0/16 | us-east-1b |
| 37 | `100.82.128.0/17` | 100.82.0.0/16 | us-east-1c |
| 38 | `100.83.0.0/17` | 100.83.0.0/16 | us-east-1d |
| 39 | `100.83.128.0/17` | 100.83.0.0/16 | us-east-1f |

### Per-AZ Summary

| AZ | Subnet Indices | /17 Subnets | IPs |
|---|---|---|---|
| us-east-1a | 0, 5, 10, 15, 20, 25, 30, 35 | 8 | 262,144 |
| us-east-1b | 1, 6, 11, 16, 21, 26, 31, 36 | 8 | 262,144 |
| us-east-1c | 2, 7, 12, 17, 22, 27, 32, 37 | 8 | 262,144 |
| us-east-1d | 3, 8, 13, 18, 23, 28, 33, 38 | 8 | 262,144 |
| us-east-1f | 4, 9, 14, 19, 24, 29, 34, 39 | 8 | 262,144 |
| **Total** | | **40 subnets** | **~1.31M** |

Each intra subnet gets its own ENIConfig (40 total). ENIConfig names follow the pattern `{az}-{per_az_index}` (e.g. `us-east-1a-0` through `us-east-1a-7`). All intra subnets are tagged with `kubernetes.io/role/pod: 1`.

### Resource Dependency Chain

The deployment order is critical for VPC CNI custom networking to work correctly:

```
VPC + Subnets
  → EKS Cluster + VPC CNI Addon (with custom networking enabled)
    → ENIConfig CRDs (40 total, one per intra subnet)
      → Managed Node Groups (nodes join with CNI already configured)
        → Addons (ALB Controller, EFS CSI, Karpenter, etc.)
```

Node groups are created as a **standalone module** (not inside `module.eks`) to enforce this ordering via `depends_on`. Without this, nodes would launch before ENIConfigs exist, causing the CNI to fail with `NetworkPluginNotReady`.

## Files

| File | Description |
|---|---|
| `main.tf` | Provider configuration, locals, AZ/subnet calculations |
| `vpc.tf` | VPC module with primary and secondary CIDRs |
| `eks.tf` | EKS cluster, addons (VPC CNI, CoreDNS, kube-proxy), Fargate profiles |
| `eniconfig.tf` | ENIConfig CRDs (40 total, one per intra subnet) for VPC CNI custom networking |
| `node_groups.tf` | Managed node group (separated from EKS module for dependency ordering) |
| `addons.tf` | EKS Blueprints addons (ALB Controller, EFS CSI, metrics-server) |
| `karpenter.tf` | Karpenter module, Helm release, EC2NodeClass, and per-AZ NodePools |
| `variables.tf` | Input variables |
| `outputs.tf` | Output values |

## VPC CNI Custom Networking

Custom networking is enabled via the VPC CNI addon configuration:

- `AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG = "true"` - Enables custom networking
- `ENI_CONFIG_LABEL_DEF = "k8s.amazonaws.com/eniConfig"` - Selects ENIConfig by a custom node label (set by Karpenter NodePools)
- `ENABLE_PREFIX_DELEGATION = "true"` - Assigns /28 prefixes instead of individual IPs for higher pod density

### ENIConfig Strategy

Instead of one ENIConfig per AZ, this setup creates **40 ENIConfigs** (one per intra subnet). Each ENIConfig is named `{az}-{index}` (e.g. `us-east-1a-0` through `us-east-1a-7`).

The VPC CNI uses `k8s.amazonaws.com/eniConfig` as the label selector (`ENI_CONFIG_LABEL_DEF`). Karpenter NodePools set this label on each node to `{az}-0`, directing the CNI to the correct ENIConfig for that AZ.

Flow:
1. Karpenter launches a node in a specific AZ with label `k8s.amazonaws.com/eniConfig: {az}-0`
2. VPC CNI reads the label and finds the matching ENIConfig
3. The ENIConfig specifies the security group and subnet for secondary ENIs
4. Pod IPs are assigned from that subnet using prefix delegation

## Karpenter

Karpenter runs on Fargate (via Fargate profiles) and manages Graviton-based node pools:

- **EC2NodeClass**: Uses `al2023@latest` AMI, targets private subnets tagged with `karpenter.sh/discovery`
- **NodePools**: For demo purposes, only **1 NodePool per AZ** (5 total) is created, each pinned to ENIConfig index `0` (e.g. `us-east-1a-0`). In a production deployment, you would create **multiple NodePools per AZ** (up to 8, matching the 8 ENIConfigs/subnets per AZ) to spread pods across all available subnets and fully utilize the ~262k pod IPs per AZ. Each NodePool would:
  - Be restricted to a single AZ via `topology.kubernetes.io/zone` requirement
  - Label nodes with `k8s.amazonaws.com/eniConfig: {az}-{index}` for VPC CNI ENIConfig selection (e.g. `us-east-1a-0` through `us-east-1a-7`)
  - Have its own vCPU limit (e.g. 30k / number-of-pools-per-AZ)
  - Use Graviton instances (m6g/m7g/m8g/r6g/r7g/r8g), on-demand, Nitro hypervisor
- **Authentication**: IRSA (Fargate does not support Pod Identity)

## Prerequisites

- Terraform >= 1.3
- AWS CLI configured with appropriate credentials
- `kubectl` installed
- `helm` installed

## Usage

```bash
terraform init
terraform plan -out=tfplan
terraform apply "tfplan"

# Update kubeconfig
aws eks update-kubeconfig --region us-east-1 --name eks-networking
```

## Variables

| Name | Description | Default |
|---|---|---|
| `region` | AWS region | `us-east-1` |
| `name` | Name prefix for resources | `eks-networking` |
| `vpc_cidr` | Primary VPC CIDR block | `10.8.0.0/16` |
| `secondary_cidrs` | Secondary CIDR blocks for pod networking | `["100.64.0.0/16", ..., "100.83.0.0/16"]` (20 blocks) |
| `tags` | Tags to apply to all resources | `{}` |

## Notes

- **us-east-1e**: Not available for EKS. Excluded from `local.azs` upfront — all resources (subnets, ENIConfigs, node groups) use only 5 AZs (a, b, c, d, f).
- **NAT Gateway**: One NAT gateway by default. Set `enable_nat_gateway` options in `vpc.tf` for one per AZ (higher availability, higher cost).
- **Secondary CIDRs**: 20 blocks from RFC 6598 `100.64.0.0/10` range (100.64–100.83). Each /16 produces 2x /17 subnets (~32k IPs each), totaling ~1.31M pod IPs across 5 AZs. Each subnet has a dedicated ENIConfig.
- **VPC CIDR Quota**: Associating 20 secondary CIDRs requires the VPC CIDR blocks quota to be raised above the default of 5. CIDRs from the 100.64.0.0/10 range have a separate higher limit.
