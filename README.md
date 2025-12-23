# Infrastructure

This repository contains the core DevOps infrastructure used for provisioning, configuration, and operation of cloud environments.

It serves as a single source of truth for infrastructure-as-code, CI/CD automation, and system bootstrap processes across development, staging, and production environments.

## Scope

The repository covers:
- CI/CD infrastructure (build servers, runners, automation)
- Infrastructure provisioning (Terraform)
- Configuration management (Ansible)
- Server bootstrap and security hardening
- Environment separation (dev / staging / production)

## Technology Stack

- Cloud provider: Hetzner (primary)
- Infrastructure as Code: Terraform
- Configuration management: Ansible
- Containerization: Docker
- CI/CD: GitHub Actions / GitLab CI (self-hosted runners)
- OS: Linux (Ubuntu), Windows (selected internal workloads)

## Repository Structure

```

infrastructure/
├── ci/                 # CI/CD servers, runners, build infrastructure
├── terraform/          # Infrastructure provisioning
├── ansible/            # Configuration management
├── scripts/            # Utility and bootstrap scripts
├── docs/               # Architecture and platform documentation
└── .env.example        # Environment variables template

```

## Environments

Infrastructure is organized by isolated environments:
- `dev` – development and testing
- `staging` – pre-production validation
- `prod` – production workloads

## Security Notes

- Secrets and tokens must never be committed to this repository
- Use environment variables or external secret managers
- `.env.example` is provided as a reference only

## Ownership

This repository is maintained by the DevOps / Platform team and is used for internal and client project infrastructure.
