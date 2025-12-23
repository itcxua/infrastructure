# CI-01 – CI/CD Core Server

`ci-01` is a dedicated CI/CD control node responsible for build orchestration, automation, and infrastructure-related workflows.

This server is intentionally isolated from application workloads.

## Responsibilities

- Hosting self-managed CI runners
- Executing build and test jobs
- Running automation tools (Terraform, Ansible)
- Acting as a control plane for infrastructure changes
- Building and publishing container images

## Typical Workloads

- CI pipeline execution
- Infrastructure provisioning (Terraform apply/plan)
- Configuration management (Ansible playbooks)
- Docker image builds
- Validation and linting jobs

## Design Principles

- No direct client-facing traffic
- No production application hosting
- Stateless where possible
- Reproducible setup via scripts

## Directory Structure

```

ci-01/
├── install_ci01.sh     # Bootstrap script for CI server
├── docker/             # Docker-based CI services
└── README.md

```

## Notes

- The server name follows the `<role>-<index>` convention
- All changes must be reproducible via code
- Manual changes on the server are discouraged


