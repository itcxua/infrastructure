
# CI-01 Docker Services

This directory contains Docker-based services used by the CI-01 server to support CI/CD workflows.

Services are deployed using Docker or Docker Compose and are isolated from the host system as much as possible.

## Purpose

- Provide reproducible CI tooling
- Isolate build environments
- Avoid dependency pollution on the host OS
- Simplify upgrades and maintenance

## Typical Containers

Depending on the setup, this directory may include:
- CI runners (GitHub / GitLab)
- Build images
- Utility containers (linting, testing, packaging)
- Supporting services (artifact tools, helpers)

## Principles

- No secrets baked into images
- Configuration via environment variables
- Volumes used only where persistence is required
- Images should be versioned and documented

## Usage

Containers are started:
- Automatically via CI bootstrap scripts
- Or manually during maintenance/debug sessions

## Notes

This directory does not contain application runtime containers.
It is strictly limited to CI/CD and automation support services.
