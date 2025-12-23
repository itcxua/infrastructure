
# CI Runners

This directory contains configuration and documentation for self-hosted CI runners used by different CI platforms.

Runners are responsible for executing CI jobs in controlled, isolated environments.

## Supported Platforms

- GitHub Actions (self-hosted runners)
- GitLab CI (shell / Docker executors)

## Responsibilities

- Execute build and test jobs
- Run infrastructure automation tasks
- Build container images
- Enforce controlled execution environments

## Design Guidelines

- Runners must be stateless where possible
- No long-lived credentials stored on runners
- Execution environments should be reproducible
- Runners must not expose inbound network services

## Typical Runner Types

- Docker-based runners (preferred)
- Shell runners (limited use cases only)

## Security Notes

- Runners should have the minimum required permissions
- Access to production resources must be restricted
- Logs should be retained according to policy

## Naming Convention

```

runner-<platform>-<index>

```

Examples:
- `runner-github-01`
- `runner-gitlab-01`
