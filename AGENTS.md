# modmailbot-docker

This repository builds and publishes the Dragory Modmail wrapper image. Read the current Dockerfile and `.github/workflows/publish.yml` before changing image behavior. Production definitions belong to the separate configurations repository.

Build for linux/amd64. The ignored upstream/ directory must be the upstream checkout selected by the publisher (the pinned patch revision for 3.11.0, an exact compatible stable tag for later versions) with package.json, package-lock.json, and .npmrc. Match MODMAIL_VERSION and UPSTREAM_REVISION build arguments to that checkout; follow the publisher for current image revision (`-rN`) and tag rules.

The runtime is Debian Trixie (glibc), non-root node, Tini, port 8890, Git, FFmpeg, and production dependencies. Keep compiler tooling in the build stage. Config and plugins mount read-only; attachments mount read-write.

Checks require PowerShell for the `.ps1` scripts; confirm it is installed before running them:
- `tests/repository-contract.ps1` statically asserts the Dockerfile, workflow, compose, and README contract and matches the current source, so a failure means real drift. If Git reports an ownership mismatch for a verified checkout, use a command-scoped safe.directory override rather than a global Git change.
- `tests/verify-image.ps1` runs against a built local image with explicit Image, Version, and Revision parameters. Review its temporary bind mounts before choosing the host invocation.

The existing .dockerignore uses an allowlist. Preserve it. Keep .env, config.ini, plugins/, attachments/, and upstream/ untracked. Image publication and production deployment are separate actions.
