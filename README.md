# EKS Advanced Networking Demo

Terraform configurations demonstrating two approaches to Amazon EKS pod networking with secondary CIDR blocks. Both solve the same problem -- separating node IPs from pod IPs to maximize available IP addresses -- but differ in complexity and operational overhead.

## Use Cases

### 1. [Multi-CIDR Custom Networking](./multi-cidr-custom-networking/)

The traditional approach using **ENIConfig CRDs** to map each Availability Zone to a specific secondary CIDR subnet for pod IPs.

- **How it works**: VPC CNI custom networking is enabled (`AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true`) and an ENIConfig resource is created per AZ. Each ENIConfig tells the CNI which secondary subnet to use for pod ENIs. When a node launches, the CNI reads the node's AZ label, finds the matching ENIConfig, and assigns pod IPs from the corresponding secondary CIDR subnet.
- **Secondary CIDRs**: RFC 6598 space (`100.64.0.0/16`, `100.65.0.0/16`, `100.66.0.0/16`)
- **Key detail**: Node groups must be created _after_ ENIConfig CRDs exist, requiring careful dependency ordering (`depends_on`). Nodes that launch before ENIConfigs are in place will fail with `NetworkPluginNotReady`.
- **Pod subnets**: Intra subnets (no NAT route) -- pods are isolated from direct internet routing.

### 2. [Enhanced Subnet Discovery with Tags](./enhanced-subnet-discovery-with-tags/)

A simpler, more modern approach that eliminates ENIConfig CRDs entirely. The VPC CNI **auto-discovers** pod subnets using the `kubernetes.io/role/cni: 1` tag.

- **How it works**: VPC CNI subnet discovery is enabled (`ENABLE_SUBNET_DISCOVERY=true`). The CNI finds subnets tagged with `kubernetes.io/role/cni: 1` in the node's AZ and uses them for pod networking automatically -- no CRDs, no per-AZ mapping.
- **Secondary CIDRs**: RFC 1918 space (`10.1.0.0/16`, `10.2.0.0/16`, `10.3.0.0/16`)
- **Key detail**: No special dependency ordering needed for node groups. Tag the subnets and the CNI handles the rest.
- **Pod subnets**: Regular private subnets (routable via NAT) -- pods can reach the internet through NAT gateways.

## Comparison

| | Multi-CIDR Custom Networking | Enhanced Subnet Discovery |
|---|---|---|
| ENIConfig CRDs | 1 per AZ (required) | Not needed |
| CNI config | `CUSTOM_NETWORK_CFG` + `ENI_CONFIG_LABEL_DEF` | `ENABLE_SUBNET_DISCOVERY` |
| Subnet selection | Explicit per-AZ mapping in CRD | Tag-based auto-discovery |
| Dependency ordering | Node groups depend on ENIConfig | No special dependency |
| Pod subnet routing | Intra (non-routable) | Private (routable via NAT) |

## Common Across Both

- EKS v1.35 with Fargate profiles for Karpenter and CoreDNS
- Prefix delegation enabled (`ENABLE_PREFIX_DELEGATION=true`) for higher pod density
- Karpenter managing Graviton instance pools (m6g/m7g/m8g/r6g/r7g/r8g)
- Addons: VPC CNI, CoreDNS, kube-proxy (IPVS), AWS Load Balancer Controller, EFS CSI Driver, metrics-server

## Prerequisites

- Terraform >= 1.3
- AWS CLI configured with appropriate credentials
- `kubectl` and `helm` installed

## Usage

```bash
cd multi-cidr-custom-networking   # or enhanced-subnet-discovery-with-tags
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```
