# Prerequisites

Everything in this project runs on Oracle Cloud's **Always Free Tier**. You will not be charged anything — not now, not ever (as long as you stay within the free limits).

## Oracle Cloud Always Free Tier

Oracle offers one of the most generous free tiers of any cloud provider. Here's what you get **permanently free**:

### Compute (what this project uses)

| Resource | Free Allocation | What This Project Uses |
|----------|----------------|----------------------|
| **ARM Instances (A1.Flex)** | 4 OCPUs + 24 GB RAM total | 1 instance: 4 OCPUs, 24 GB RAM |
| **Micro Instances (E2.1.Micro)** | 2 instances | 2 instances: 1 OCPU, 1 GB RAM each |
| **Boot Volumes** | 200 GB total | 150 GB (50 GB × 3 instances) |

### Networking (what this project uses)

| Resource | Free Allocation |
|----------|----------------|
| **VCN** | Up to 2 VCNs |
| **Public IPs** | Included with instances |
| **Outbound Data** | 10 TB/month |
| **Internet Gateway** | Included |
| **Route Tables / Security Lists** | Included |

### Storage (for Terraform state)

| Resource | Free Allocation |
|----------|----------------|
| **Object Storage** | 10 GB (Standard), 10 GB (Infrequent Access) |
| **Object Storage API Requests** | 50,000/month |

> **Bottom line:** This entire infrastructure fits within the Always Free Tier with room to spare. You still have 50 GB of boot volume quota left and all the networking headroom you need.

### Sign up

1. Go to [cloud.oracle.com](https://cloud.oracle.com) and click **Sign Up**.
2. You'll need a valid email, phone number, and a credit/debit card (for identity verification only — you will **not** be charged).
3. Choose your **Home Region** carefully — this cannot be changed later and determines where your Always Free resources live. Pick the region closest to you.
4. Once your account is active, you'll have access to the Always Free tier immediately.

> **Important:** Oracle gives you $300 in free credits for 30 days. After those credits expire or the 30 days pass, your account converts to "Always Free" and **only Always Free resources remain running**. Paid resources are terminated. The infrastructure in this project is all Always Free, so it will keep running.

## Required Software

### OpenTofu or Terraform

This project uses infrastructure-as-code. You need one of these:

**OpenTofu (recommended — open source)**
```bash
# macOS
brew install opentofu

# Linux (snap)
snap install --classic opentofu

# Or download from https://opentofu.org/docs/intro/install/
```

**Terraform**
```bash
# macOS
brew install terraform

# Linux
# See https://developer.hashicorp.com/terraform/install
```

Both work identically with this project. The docs use `tofu` commands, but you can substitute `terraform` anywhere.

### OCI CLI (optional but helpful)

The OCI CLI isn't required to run this project, but it's useful for debugging and manual operations.

```bash
# macOS / Linux
bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)"
```

## OCI API Key Setup

Terraform authenticates with OCI using an API signing key. You need to create one.

### 1. Generate an API Key Pair

```bash
# Create the .oci directory
mkdir -p ~/.oci

# Generate a 2048-bit RSA private key
openssl genrsa -out ~/.oci/oci-api-key.pem 2048

# Set proper permissions
chmod 600 ~/.oci/oci-api-key.pem

# Generate the public key
openssl rsa -pubout -in ~/.oci/oci-api-key.pem -out ~/.oci/oci-api-key-public.pem
```

### 2. Upload the Public Key to OCI

1. Log in to the [OCI Console](https://cloud.oracle.com).
2. Click your **profile icon** (top-right) → **My Profile** (or **User Settings**).
3. Under **Resources**, click **API Keys** → **Add API Key**.
4. Choose **Paste Public Key** and paste the contents of `~/.oci/oci-api-key-public.pem`.
5. Click **Add**.
6. OCI will show you a **Configuration File Preview** — save these values! You'll need:
   - `tenancy` (this is your `tenancy_ocid`)
   - `user` (this is your `user_ocid`)
   - `fingerprint`
   - `region`

### 3. Prepare the Private Key for Terraform

This project expects the private key as a base64-encoded environment variable:

```bash
# macOS
export TF_VAR_OCA_PRIVATE_KEY="$(base64 < ~/.oci/oci-api-key.pem)"

# Linux
export TF_VAR_OCA_PRIVATE_KEY="$(base64 -w0 < ~/.oci/oci-api-key.pem)"
```

## Object Storage Bucket (for Remote State)

Terraform state is stored remotely in an OCI Object Storage bucket via the S3-compatible API.

### Create the Bucket

1. In the OCI Console, go to **Storage** → **Buckets**.
2. Click **Create Bucket**.
3. Give it a name (e.g., `tofu-backend`).
4. Leave defaults (Standard storage tier) and click **Create**.

### Get S3 Compatibility Credentials

1. Click your **profile icon** → **My Profile**.
2. Under **Resources**, click **Customer Secret Keys** → **Generate Secret Key**.
3. Give it a name and click **Generate**.
4. **Save the secret key immediately** — it won't be shown again.
5. Note the **Access Key** that appears in the list.

### Find Your Namespace

1. In the OCI Console, click your **profile icon** → **Tenancy: <your-tenancy>**.
2. Find the **Object Storage Namespace** — it's a random string like `axzfe5abcdef`.

Your S3 endpoint will be:
```
https://<namespace>.compat.objectstorage.<region>.oraclecloud.com
```

Update `IaC/backend.tf` with your bucket name, region, and endpoint.

## SSH Key

You need an SSH key pair to access your instances.

```bash
# Generate a new key if you don't have one
ssh-keygen -t ed25519 -C "your-email@example.com"
```

The public key (contents of `~/.ssh/id_ed25519.pub`) goes into `IaC/terraform.tfvars` as `ssh_authorized_keys`.

## Tailscale Auth Key (Optional)

The micro instances auto-install [Tailscale](https://tailscale.com/) for private mesh networking. If you want this feature:

1. Go to [Tailscale Admin Console](https://login.tailscale.com/admin/settings/keys).
2. Generate an **Auth Key** (reusable, with your preferred tags).
3. Set it as an environment variable:
   ```bash
   export TF_VAR_TAILSCALE_AUTH_KEY="tskey-auth-xxxxx"
   ```

If you don't use Tailscale, you can remove the Tailscale-related `user_data` block from `IaC/instance.tf` and the `TAILSCALE_AUTH_KEY` variable from `IaC/variables.tf`.

## Your Public IP Address

The security list restricts SSH access to a single IP address. Find yours:

```bash
curl -s ifconfig.me
```

Use this IP with `/32` suffix in `IaC/terraform.tfvars`:
```
user_ip_address = "YOUR.IP.HERE/32"
```

> **Tip:** If your IP changes frequently (e.g., residential ISP), you'll need to update this value and run `tofu -chdir=IaC apply` again, or consider using Tailscale SSH instead which bypasses the security list entirely.

## Summary Checklist

- [ ] Oracle Cloud account created (Always Free)
- [ ] Home region selected
- [ ] OpenTofu or Terraform installed
- [ ] API key pair generated and public key uploaded to OCI
- [ ] Noted down: `tenancy_ocid`, `user_ocid`, `fingerprint`, `region`
- [ ] Object Storage bucket created for Terraform state
- [ ] S3 compatibility credentials generated (access key + secret key)
- [ ] Object Storage namespace noted
- [ ] SSH key pair ready
- [ ] Tailscale auth key generated (optional)
- [ ] Your public IP address noted
