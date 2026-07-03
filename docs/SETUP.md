# Setup Guide

A step-by-step walkthrough to go from zero to a fully running infrastructure.

> **Cost: $0.** Everything in this project runs on Oracle Cloud's Always Free Tier. See [PREREQUISITES.md](PREREQUISITES.md) for details.

## Step 1: Clone and Prepare

```bash
git clone <this-repo>
cd <this-repo>
```

## Step 2: Create Your `IaC/terraform.tfvars`

Copy the example file and fill in your real values:

```bash
cp IaC/terraform.tfvars.example IaC/terraform.tfvars
```

Edit `IaC/terraform.tfvars`:

```hcl
tenancy_ocid = "ocid1.tenancy.oc1..aaaaaaaayour-actual-tenancy-ocid"
user_ocid    = "ocid1.user.oc1..aaaaaaaayour-actual-user-ocid"
fingerprint  = "your:api:key:fingerprint"
region       = "us-ashburn-1"  # your home region

vcn_cidr_block      = "10.0.0.0/16"
public_subnet_cidr  = "10.0.0.0/24"
private_subnet_cidr = "10.0.1.0/24"
nat_subnet_cidr     = "10.0.2.0/24"

vcn_dns_label = "myvcn"
project       = "myproject"

ssh_authorized_keys = "ssh-ed25519 AAAA... your-email@example.com"
user_ip_address     = "YOUR.PUBLIC.IP/32"
```

> **Where to find these values:** See the [Prerequisites](PREREQUISITES.md#2-upload-the-public-key-to-oci) doc.

## Step 3: Set Sensitive Environment Variables

These should **not** go in `IaC/terraform.tfvars` (they'd be committed to git):

```bash
# Your OCI API private key (base64-encoded)
# macOS:
export TF_VAR_OCA_PRIVATE_KEY="$(base64 < ~/.oci/oci-api-key.pem)"
# Linux:
export TF_VAR_OCA_PRIVATE_KEY="$(base64 -w0 < ~/.oci/oci-api-key.pem)"

# Tailscale auth key (optional — remove if not using Tailscale)
export TF_VAR_TAILSCALE_AUTH_KEY="tskey-auth-xxxxx"

# S3 backend credentials (for remote state)
export AWS_ACCESS_KEY_ID="your-s3-access-key"
export AWS_SECRET_ACCESS_KEY="your-s3-secret-key"
```

## Step 4: Configure the Backend

Edit `IaC/backend.tf` and replace the placeholder values:

```hcl
terraform {
  backend "s3" {
    bucket = "your-bucket-name"
    region = "your-region"
    key    = "IaC/tf.tfstate"
    # ... keep the other settings as-is ...
    endpoints = {
      s3 = "https://your-namespace.compat.objectstorage.your-region.oraclecloud.com"
    }
  }
}
```

> **Alternative: Local backend.** If you don't want remote state, replace the entire `IaC/backend.tf` with:
> ```hcl
> terraform {
>   backend "local" {}
> }
> ```
> This stores state in a local `IaC/terraform.tfstate` file. Fine for personal use, but don't commit it to git.

## Step 5: Initialize

```bash
tofu -chdir=IaC init
```

This downloads the OCI provider plugin and initializes the backend. You should see:

```
Terraform has been successfully initialized!
```

## Step 6: Preview Changes

```bash
tofu -chdir=IaC plan
```

This shows what Terraform will create without actually doing anything. Review the output carefully. You should see resources like:

- `oci_core_vcn.vcn`
- `oci_core_internet_gateway.igw`
- `oci_core_subnet.public`
- `oci_core_route_table.public_route_table`
- `oci_core_security_list.public_security_list`
- `oci_core_instance.arm_instance`
- `oci_core_instance.micro_instances["micro1"]`
- `oci_core_instance.micro_instances["micro2"]`

## Step 7: Apply

```bash
tofu -chdir=IaC apply
```

Type `yes` when prompted. Terraform will create all resources. This typically takes 2-5 minutes.

When done, you'll see the outputs:

```
arm_instance_public_ip = "xxx.xxx.xxx.xxx"
micro1_public_ip = "xxx.xxx.xxx.xxx"
micro2_public_ip = "xxx.xxx.xxx.xxx"
```

## Step 8: Connect

SSH into any instance:

```bash
# ARM instance
ssh ubuntu@<arm_instance_public_ip>

# Micro instances
ssh ubuntu@<micro1_public_ip>
ssh ubuntu@<micro2_public_ip>
```

> The default username for Ubuntu images on OCI is `ubuntu`.

## Managing the Infrastructure

### See current state

```bash
tofu -chdir=IaC show
```

### Update after changing variables

```bash
tofu -chdir=IaC plan    # preview
tofu -chdir=IaC apply   # apply
```

### Tear everything down

```bash
tofu -chdir=IaC destroy
```

Type `yes` to confirm. This deletes all resources.

## Troubleshooting

### "Out of capacity" error for ARM instance

The A1.Flex shape is popular and OCI may not have capacity in your availability domain. Try:

1. Change the availability domain index in `IaC/instance.tf` (switch between 0 and 1).
2. Try at a different time (early morning tends to have more capacity).
3. Reduce the shape config (e.g., 2 OCPUs, 12 GB RAM) and try again.

### "Not authorized" errors

- Verify your `tenancy_ocid`, `user_ocid`, and `fingerprint` are correct.
- Make sure the API key is uploaded to the correct user in OCI.
- Check that `TF_VAR_OCA_PRIVATE_KEY` is set and base64-encoded correctly.

### SSH connection refused

- Verify `user_ip_address` in `IaC/terraform.tfvars` matches your current public IP.
- Check that the instance has finished booting (allow 2-3 minutes after apply).
- Confirm you're using the correct SSH key.

### Backend initialization fails

- Verify `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` are set.
- Check that the Object Storage bucket exists.
- Verify the S3 endpoint URL uses the correct namespace and region.

### Tailscale not connecting on micro instances

- The auth key might have expired — generate a new one and redeploy.
- Check cloud-init logs on the instance: `sudo cat /var/log/cloud-init-output.log`
