# Architecture

This document explains the infrastructure created by this project and how all the pieces fit together.

## Overview

This project provisions a complete cloud infrastructure on **Oracle Cloud Infrastructure (OCI)** using Terraform/OpenTofu. Everything runs within OCI's **Always Free Tier** — meaning the entire setup costs **$0/month**, forever, with no credit card charges.

## What Gets Created

```
┌─────────────────────────────────────────────────────────┐
│                    OCI Tenancy                          │
│                                                         │
│  ┌───────────────────────────────────────────────────┐  │
│  │              VCN (10.0.0.0/16)                    │  │
│  │                                                   │  │
│  │  ┌─────────────────────────────────────────────┐  │  │
│  │  │       Public Subnet (10.0.0.0/24)           │  │  │
│  │  │                                             │  │  │
│  │  │  ┌───────────────┐  ┌──────────────────┐   │  │  │
│  │  │  │ ARM Instance  │  │ Micro Instance 1 │   │  │  │
│  │  │  │ (A1.Flex)     │  │ (E2.1.Micro)     │   │  │  │
│  │  │  │               │  │                  │   │  │  │
│  │  │  │ 4 OCPU        │  │ 1 OCPU           │   │  │  │
│  │  │  │ 24 GB RAM     │  │ 1 GB RAM         │   │  │  │
│  │  │  │ 50 GB Disk    │  │ 50 GB Disk       │   │  │  │
│  │  │  │ Ubuntu 24.04  │  │ Ubuntu 24.04     │   │  │  │
│  │  │  │ (aarch64)     │  │ (amd64)          │   │  │  │
│  │  │  │ Public IP     │  │ Public IP        │   │  │  │
│  │  │  └───────────────┘  │ Tailscale        │   │  │  │
│  │  │                     └──────────────────┘   │  │  │
│  │  │                     ┌──────────────────┐   │  │  │
│  │  │                     │ Micro Instance 2 │   │  │  │
│  │  │                     │ (E2.1.Micro)     │   │  │  │
│  │  │                     │                  │   │  │  │
│  │  │                     │ 1 OCPU           │   │  │  │
│  │  │                     │ 1 GB RAM         │   │  │  │
│  │  │                     │ 50 GB Disk       │   │  │  │
│  │  │                     │ Ubuntu 24.04     │   │  │  │
│  │  │                     │ (amd64)          │   │  │  │
│  │  │                     │ Public IP        │   │  │  │
│  │  │                     │ Tailscale        │   │  │  │
│  │  │                     └──────────────────┘   │  │  │
│  │  └─────────────────────────────────────────────┘  │  │
│  │                                                   │  │
│  │  ┌──────────────┐  ┌──────────────────────────┐   │  │
│  │  │   Internet   │  │     Route Table          │   │  │
│  │  │   Gateway    │◄─┤  0.0.0.0/0 → IGW        │   │  │
│  │  └──────┬───────┘  └──────────────────────────┘   │  │
│  │         │                                         │  │
│  │  ┌──────┴───────────────────────────────────────┐ │  │
│  │  │           Security List                      │ │  │
│  │  │  IN:  SSH (22) from your IP only             │ │  │
│  │  │  IN:  All traffic within VCN                 │ │  │
│  │  │  OUT: All traffic to internet                │ │  │
│  │  └──────────────────────────────────────────────┘ │  │
│  └───────────────────────────────────────────────────┘  │
│                                                         │
│  ┌───────────────────────────────────────────────────┐  │
│  │  Object Storage (S3-compatible)                   │  │
│  │  └── Terraform state file (tf.tfstate)            │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

## Components Explained

### Virtual Cloud Network (VCN)

The VCN is a software-defined private network inside OCI. Think of it as your own isolated section of the Oracle cloud. It uses CIDR block `10.0.0.0/16`, giving you 65,536 possible IP addresses.

**Created in:** `vcn.tf`

### Public Subnet

A subdivision of the VCN (`10.0.0.0/24` — 256 addresses). All instances live here and get public IP addresses for direct internet access.

**Created in:** `vcn.tf`

### Internet Gateway

The gateway that connects your VCN to the public internet. Without it, nothing inside the VCN can reach the outside world (or be reached from it).

**Created in:** `vcn.tf`

### Route Table

Tells traffic where to go. The single rule says: "anything destined for `0.0.0.0/0` (i.e., the internet) should go through the Internet Gateway."

**Created in:** `vcn.tf`

### Security List (Firewall)

Controls what traffic is allowed in and out:

| Direction | Rule | Why |
|-----------|------|-----|
| **Inbound** | SSH (port 22) from your IP only | So only you can SSH into instances |
| **Inbound** | All traffic within VCN (10.0.0.0/16) | So instances can talk to each other |
| **Outbound** | All traffic to anywhere | So instances can reach the internet |

**Created in:** `vcn.tf`

### ARM Instance (VM.Standard.A1.Flex)

The most powerful free instance. Uses an Ampere A1 ARM processor (aarch64 architecture).

| Spec | Value |
|------|-------|
| CPU | 4 OCPUs (ARM) |
| RAM | 24 GB |
| Disk | 50 GB boot volume |
| OS | Ubuntu 24.04 (aarch64) |
| Network | Public IP, SSH access |

This is great for running Docker containers, web servers, databases, or anything that benefits from more resources. The ARM architecture means you need ARM-compatible software (most things work fine).

**Created in:** `instance.tf`

### Micro Instances (VM.Standard.E2.1.Micro) × 2

Two small AMD instances, ideal for lightweight tasks.

| Spec | Value |
|------|-------|
| CPU | 1 OCPU (AMD x86_64) |
| RAM | 1 GB |
| Disk | 50 GB boot volume each |
| OS | Ubuntu 24.04 (amd64) |
| Network | Public IP, SSH access |
| Extra | Tailscale auto-installed |

These instances automatically install Tailscale on first boot via cloud-init, joining your Tailnet for private mesh networking.

**Created in:** `instance.tf`

### Remote State Backend

Terraform state is stored remotely in an OCI Object Storage bucket using the S3-compatible API. This means:

- State is not stored locally (safe for teams)
- State survives if your machine dies
- You can run Terraform from any machine

**Created in:** `backend.tf`

## How It All Connects

1. **Terraform reads** `variables.tf` and `terraform.tfvars` to get your configuration.
2. **Provider authenticates** with OCI using your API key (`provider.tf`).
3. **VCN is created** as an isolated network, along with the subnet, gateway, route table, and firewall rules (`vcn.tf`).
4. **Image IDs are looked up** dynamically — Terraform finds the latest Ubuntu 24.04 images for each shape (`instance.tf`).
5. **Instances are launched** in the subnet with public IPs. Micro instances run a cloud-init script to install Tailscale (`instance.tf`).
6. **State is saved** to OCI Object Storage over the S3-compatible API (`backend.tf`).
7. **Outputs** show you the public IPs of all instances (`output.tf`).

## Data Flow

```
You (SSH) ──► Internet ──► Internet Gateway ──► Security List ──► Instance
                                                    │
                                                    ├── Port 22 allowed (your IP only)
                                                    └── All other inbound blocked

Instance ──► Security List ──► Internet Gateway ──► Internet (all outbound allowed)

Instance ──► VCN internal ──► Instance (all VCN traffic allowed)
```

## Availability Domains

OCI regions have one or more Availability Domains (ADs) — physically separate data centers. This project:

- Queries all ADs in your region (`availability-domains.tf`)
- Places the ARM instance in AD index 1 (falls back to 0 if only one exists)
- Places micro instances in AD index 0

This is configurable in `locals.tf`.

## Tags

All resources are tagged with:

| Tag | Value |
|-----|-------|
| `Project` | Your project name |
| `ManagedBy` | `Terraform` |
| `Environment` | `production` |
| `CreatedAt` | Timestamp of creation |

These help you identify and filter resources in the OCI console.
