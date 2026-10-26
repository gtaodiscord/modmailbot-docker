# Dragory Modmail Docker

Minimal `linux/amd64` Debian/glibc image for [Dragory Modmail](https://github.com/Dragory/modmailbot), published as the public GitHub Container Registry package `ghcr.io/gtaodiscord/modmailbot`

GitHub Actions checks stable upstream releases every six hours, builds and verifies each missing release, and publishes it without updating a running deployment

This README describes the checked-out wrapper and workflows. The publisher currently specifies revision `5`; this is not evidence that an image has been published or either GTAO instance uses it.

## Prerequisites

For a standalone installation, use Docker Engine with the Compose plugin on an AMD64 host, a configured Discord bot, a reachable database when using MariaDB, and a private configuration file. The bundled Compose file is a generic example, not the GTAO deployment definition. Before changing image behavior, inspect `Dockerfile`, `.github/workflows/publish.yml`, and the verification scripts below.

## Image tags

- Immutable exact tags such as `3.11.0-r5` are the production-safe choice
- The `rN` suffix is the image-wrapper revision for the same upstream Modmail release
- Moving discovery tags such as `3.11`, `3`, and `latest` follow the newest approved wrapper for the latest stable upstream release
- Older immutable tags such as `3.11.0` remain untouched when the Docker wrapper changes

Pin production to an exact tag through `MODMAIL_IMAGE_TAG` in `.env`. Review the upstream release and back up the database before changing it

`3.11.0-r5` retains the upstream revision containing the attachment and recovery fixes and adds Discord timestamps to `!logs`. Dates include the year and render in each viewer's timezone and locale using Discord's `f` style

The Docker build applies a small compatibility fix only when the exact legacy date-formatting block is present. Already-fixed or refactored upstream code is left unchanged, so this fix adds no ancestry requirement or merge conflict to future upstream releases. If upstream changes that block differently, localized dates need to be checked again. Future stable releases still build their exact tag only after the publisher confirms the existing attachment/recovery revision remains in their history

The OCI revision label identifies the upstream base commit; the image-wrapper revision identifies this build-time adjustment. The upstream checkout itself remains unchanged

## GTAO production deployments

The main Modmail and Appeals deployment definitions reference this image family; inspect their current pinned tags and runtime separately. Their Compose definitions, MariaDB services, persistent mounts, plugin configuration, and Komodo deployment settings are maintained centrally in [gtaodiscord/configurations](https://github.com/gtaodiscord/configurations):

- [Main Modmail](https://github.com/gtaodiscord/configurations/tree/main/gtao_modmail)
- [Appeals](https://github.com/gtaodiscord/configurations/tree/main/gtao_appeals)

Those deployments add the GTAO [Plugin Loader](https://github.com/gtaodiscord/ModmailPluginLoader) and managed Menu, Reply Suggest, and Authentication plugins. This repository publishes the base Modmail image only; image publication does not deploy or restart either production instance

## Runtime

The image runs as the non-root `node` user under Tini on Debian slim with glibc. It keeps Git, NPM, FFmpeg, and FFprobe for Modmail's runtime plugin installer and media handling but contains no compiler, Python, Make, or development dependencies

| Host path | Container path | Access |
| --- | --- | --- |
| `./config.ini` | `/app/config.ini` | Read-only |
| `./plugins` | `/app/plugins` | Read-only |
| `./attachments` | `/app/attachments` | Read-write |

The Compose file exposes Dragory's default port `8890` and joins an existing external Docker network named `modmail`

## Configure

```bash
cp .env.example .env
cp config.example.ini config.ini
mkdir -p plugins attachments
```

`config.example.ini` is copied verbatim from Dragory's v3.11.0 sample. Keep deployment-specific values only in `config.ini`, which Git ignores

The example `.env` retains the initial `3.11.0` tag. Explicitly select the reviewed exact wrapper tag before starting. Set `MM_TOKEN` in `.env`, then configure the required IDs and any optional settings in the private `config.ini`. Never commit `.env`, `config.ini`, mounted plugins, or attachments

For an external MariaDB container, add the settings documented in [Dragory's configuration reference](https://github.com/Dragory/modmailbot/blob/master/docs/configuration.md) to the private `config.ini`. Use the database container's Docker DNS alias and container port `3306`, not a host-published port. The password can remain in `.env` as `MM_MYSQL_OPTIONS__PASSWORD`

Place local plugin files in `./plugins` and reference their `/app/plugins/...` paths only from the private configuration

## Network

Create the external network once:

```bash
docker network create modmail
```

Connect the existing database container using a generic DNS alias:

```bash
docker network connect --alias mariadb modmail YOUR_DATABASE_CONTAINER
```

Set `mysqlOptions.host = mariadb` in the private configuration. Inspect existing network membership before connecting a container again

## Attachment permissions

The image user has UID and GID `1000`. Grant that identity access only to the attachment directory when the host requires it:

```bash
sudo chown -R 1000:1000 ./attachments
```

Do not recursively change the full application directory or database storage

## Start

```bash
docker compose config --quiet
docker compose pull
docker compose up -d
docker compose logs --tail=200 modmail
```

`config --quiet` validates Compose without printing resolved secrets. Successful startup logs alone do not prove end-user delivery; complete the live acceptance checks below.

## Update a standalone installation

1. Read the [upstream release notes](https://github.com/Dragory/modmailbot/releases)
2. Back up MariaDB using the deployment's existing backup procedure
3. Set `MODMAIL_IMAGE_TAG` to the reviewed immutable wrapper tag, for example `3.11.0-r5`
4. Pull and recreate only Modmail
5. Run the live acceptance checks

```bash
docker compose pull modmail
docker compose up -d modmail
docker compose logs --tail=200 modmail
```

Upstream Modmail controls database migrations and runs them before the bot starts. Do not assume an application rollback is safe after a migration

## Verification boundaries

Local and public CI verification covers:

- Exact packaged Modmail version and upstream revision
- Compatible Node.js major version
- Debian/glibc runtime identity
- Non-root runtime identity
- Production dependencies and runtime NPM installation
- Runtime Git, FFmpeg, and FFprobe availability and absence of build tools
- Plugin readability and attachment writability
- Renderable `!logs` timestamps in Unix seconds for the 3.11.0 compatibility build

Live deployment acceptance still requires private credentials and services:

- Resolve and connect to the configured database container
- Load the deployment's configured plugins
- Connect to Discord and open a test thread
- Upload an attachment and confirm persistence after recreation
- Open a generated log through the deployment's public URL
- Confirm database-backed history remains present

The public workflow never connects to Discord, MariaDB, a deployment host, or a reverse proxy

## Local image build

Use Docker and Git for builds. PowerShell 7 is needed for the verification scripts (CI provides it, Ubuntu may not). Place the publisher-selected Dragory checkout in ignored `upstream/`, including `package.json`, `package-lock.json`, and `.npmrc`.

To reproduce the current publisher's `3.11.0-r5` source, use upstream commit `536317c964e2c174ca13e35c7a872f560a554e47`, not the unpatched `v3.11.0` tag. For later versions, the publisher requires an exact stable tag containing that commit. Derive the Node.js major from the checkout's `package.json` and set `UPSTREAM_REVISION` to its actual `git rev-parse HEAD` output. The Dockerfile records these arguments but does not verify them.

Example build after preparing and checking the source:

```bash
docker build --platform linux/amd64 \
  --build-arg NODE_VERSION=24 \
  --build-arg MODMAIL_VERSION=3.11.0 \
  --build-arg UPSTREAM_REVISION=REPLACE_WITH_UPSTREAM_COMMIT \
  --tag modmailbot-local:3.11.0-r5 \
  .
```

Run the static repository contract from this directory with PowerShell 7:

```powershell
./tests/repository-contract.ps1
```

For a built local image:

```powershell
./tests/verify-image.ps1 -Image modmailbot-local:3.11.0-r5 -Version 3.11.0 -Revision REPLACE_WITH_UPSTREAM_COMMIT
```

The image verifier starts disposable containers, creates temporary bind mounts, and downloads a small npm package to test runtime installation. It needs Docker and registry access, but does not start Modmail or contact Discord or a database. Review those effects before running it.

The pull-request image workflow builds the latest stable upstream tag directly; it does not use the publisher's patched-source selection. Its success alone does not verify the `3.11.0-r5` source. The scheduled publisher skips builds for an existing exact image tag and refreshes moving aliases.

## Troubleshooting

- External network not found: inspect Docker networks and create `modmail` only for a new standalone installation.
- Database connection failure: confirm network membership, DNS alias, private credentials, and container port `3306`.
- Attachment permission denied: inspect the attachment directory's ownership and write permissions for UID/GID 1000 before changing them.
- Plugin initialization failure: inspect Modmail logs, plugin paths, and configuration. The generic read-only plugin mount may not fit plugins that write managed releases; use the deployment repository's mount contract for PluginLoader.
- Startup or migration failure after an update: preserve logs and the database backup. Diagnose the failure before restarting repeatedly or rolling back.

Keep resolved Compose output and logs private when they contain tokens, credentials, or message content.

## License

The container wrapper and automation use the MIT License. Dragory Modmail retains its upstream license and notices
