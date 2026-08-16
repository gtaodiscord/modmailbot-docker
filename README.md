# Dragory Modmail Docker

Minimal `linux/amd64` Debian/glibc image for [Dragory Modmail](https://github.com/Dragory/modmailbot), published as the public GitHub Container Registry package `ghcr.io/gtaodiscord/modmailbot`

GitHub Actions checks stable upstream releases every six hours, builds and verifies each missing release, and publishes it without modifying Modmail or updating a running deployment

## Image tags

- Immutable exact wrapper tags such as `3.11.0-r2` are the production-safe choice
- The `rN` suffix is the image-wrapper revision for the same upstream Modmail release
- Moving discovery tags such as `3.11`, `3`, and `latest` follow the newest approved wrapper for the latest stable upstream release
- Older immutable tags such as `3.11.0` remain untouched when the Docker wrapper changes

Pin production to an exact tag through `MODMAIL_IMAGE_TAG` in `.env`. Review the upstream release and back up the database before changing it

## Runtime

The image runs as the non-root `node` user under Tini on Debian slim with glibc. It keeps Git and NPM for Modmail's runtime plugin installer but contains no compiler, Python, Make, or development dependencies

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

Set `MM_TOKEN` in `.env`, then configure the required IDs and any optional settings in the private `config.ini`. Never commit `.env`, `config.ini`, mounted plugins, or attachments

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
docker compose config
docker compose pull
docker compose up -d
docker compose logs --tail=200 modmail
```

## Update production

1. Read the [upstream release notes](https://github.com/Dragory/modmailbot/releases)
2. Back up MariaDB using the deployment's existing backup procedure
3. Set `MODMAIL_IMAGE_TAG` to the reviewed immutable wrapper tag, for example `3.11.0-r2`
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
- Runtime Git availability and absence of build tools
- Plugin readability and attachment writability

Live deployment acceptance still requires private credentials and services:

- Resolve and connect to the configured database container
- Load the deployment's configured plugins
- Connect to Discord and open a test thread
- Upload an attachment and confirm persistence after recreation
- Open a generated log through the deployment's public URL
- Confirm database-backed history remains present

The public workflow never connects to Discord, MariaDB, a deployment host, or a reverse proxy

## Local image build

Place an exact tagged Dragory checkout in `upstream/`, derive its Node.js major from `package.json`, and build:

```bash
docker build --platform linux/amd64 \
  --build-arg NODE_VERSION=24 \
  --build-arg MODMAIL_VERSION=3.11.0 \
  --build-arg UPSTREAM_REVISION=REPLACE_WITH_UPSTREAM_COMMIT \
  --tag modmailbot-local:3.11.0-r2 \
  .
```

Run `tests/verify-image.ps1` with the same version and revision before publishing

## License

The container wrapper and automation use the MIT License. Dragory Modmail retains its upstream license and notices
