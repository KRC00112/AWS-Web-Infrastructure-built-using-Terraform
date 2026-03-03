# AWS Web Infrastructure built using Terraform

This project provisions a simple but production-ready AWS web infrastructure: a VPC with public/private subnets, an Application Load Balancer, and a fleet of EC2 instances behind it. Terraform state is stored remotely in S3 and locked via DynamoDB using the CloudPosse `tfstate-backend` module.

---

## What This Provisions

- **Remote State Backend** — S3 bucket + DynamoDB table for state locking (via CloudPosse `tfstate-backend`)
- **VPC** — `10.0.0.0/16` CIDR with 3 public and 3 private subnets across 3 AZs, with NAT gateways per AZ
- **Security Groups** — HTTP (port 80) and SSH (port 22) ingress open to `0.0.0.0/0`
- **Application Load Balancer** — Public-facing ALB forwarding HTTP traffic to EC2 instances
- **EC2 Instances** — 3x `t3.micro` instances running Amazon Linux 2023 (EKS-optimized AMI), placed in private subnets
- **SSH Key Pair** — Imported from a local `infra-key.pub` file

---

## Prerequisites

- Terraform `>= 1.1`
- AWS CLI configured with appropriate credentials
- An SSH key pair generated locally (see [Usage](#usage))

---

## Usage

### 1. Generate the SSH key pair

```bash
ssh-keygen -t rsa -f infra-key
```

This produces `infra-key` (private) and `infra-key.pub` (public). The `.pub` file is referenced by Terraform and is safe to commit. **Never commit the private key (`infra-key`).**

### 2. Bootstrap the remote state (one-time)

The CloudPosse backend module must be bootstrapped before the S3 backend can be used. Follow these steps in order:

```bash
# Step 1 — Download providers and modules
terraform init

# Step 2 — Create the S3 bucket and DynamoDB table (state is still local at this point)
terraform apply -auto-approve

# Step 3 — Migrate local state into the newly created S3 backend
terraform init -force-copy
```

After Step 3, Terraform will read/write state from S3 and use DynamoDB for locking on every subsequent run.

### 3. Deploy infrastructure

```bash
terraform plan
terraform apply
```

### 4. Configure region (optional)

The default region is `ap-south-1`. Override it at apply time:

```bash
terraform apply -var="region=us-east-1"
```

---

## Outputs

| Name | Description |
|------|-------------|
| `vpc_Id` | ID of the provisioned VPC |
| `subnet_Id` | Public subnet IDs |
| `route_table_Ids` | Database route table IDs |
| `security_groups_id_http` | HTTP security group ID |
| `security_groups_id_ssh` | SSH security group ID |
| `aws_ami` | AMI ID used for EC2 instances |
| `aws_instance` | List of EC2 instance IDs |

---

## ⚠️ Important Gotchas

### 1. Region must support 3 AZs and the required AMI

The VPC and EC2 instances are spread across 3 Availability Zones, so the target region must have at least 3 AZs. The EC2 instances also use an Amazon Linux 2023 EKS-optimized AMI (`amazon-eks-node-al2023-*`). Verify this AMI is available in the target region before deploying. Most major regions support it, but some newer or smaller regions (e.g. `ap-south-2`) may not.

---

### 2. The `infra-key` EC2 key pair name is hardcoded

The key pair resource uses a fixed name:

```hcl
resource "aws_key_pair" "myKey" {
  key_name   = "infra-key"
  public_key = file("infra-key.pub")
}
```

**This will cause a conflict if:**
- Someone else has already created a key pair named `infra-key` in the same AWS account and region
- This is deployed to multiple environments (e.g. `dev` and `prod`) within the same account

If a `KeyPair already exists` error appears, either delete the conflicting key pair from the AWS console/CLI, or rename the key in `main.tf` to something unique (e.g. `infra-key-dev-2138`) and regenerate the local key files to match.

---

### 3. Destroying the CloudPosse backend. DO THIS CAREFULLY!

The S3 bucket has `force_destroy = false`, which means Terraform **will refuse to delete it** while it contains state files. To tear down the entire infrastructure including the backend, the CloudPosse destruction procedure must be followed in order. Skipping steps will leave orphaned cloud resources and a lost state file:

```bash
# Step 1 — In main.tf, update the backend module arguments:
#   terraform_backend_config_file_path = ""
#   force_destroy                      = true

# Step 2 — Apply just the backend module to action those changes
terraform apply -target module.terraform_state_backend -auto-approve

# Step 3 — Migrate state back to local before the bucket is deleted
terraform init -force-copy

# Step 4 — Now it's safe to destroy everything
terraform destroy
```

> **Never run `terraform destroy` directly without first migrating state back to local.** Doing so will delete the S3 bucket mid-destroy, causing Terraform to lose the state file and leaving untracked cloud resources behind.

---

## Security Notes

- SSH ingress is currently open to `0.0.0.0/0`. Rstrict this to a known IP range.
- EC2 instances live in **private** subnets and are not directly reachable from the internet; SSH access requires a bastion host or AWS SSM Session Manager

---

## File Structure

```
.
├── main.tf          # Core infrastructure resources
├── outputs.tf       # Output values
├── terraform.tf     # Provider and version requirements
├── variables.tf     # Input variables
├── backend.tf       # Auto-generated by CloudPosse module on first apply
├── infra-key        # SSH private key — DO NOT COMMIT (add to .gitignore)
└── infra-key.pub    # SSH public key — safe to commit
```
