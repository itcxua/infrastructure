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

