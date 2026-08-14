$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$failures = [System.Collections.Generic.List[string]]::new()

function Read-RepoFile([string]$Path) {
  $fullPath = Join-Path $repo $Path
  if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
    $failures.Add("Missing file: $Path")
    return ""
  }

  return Get-Content -LiteralPath $fullPath -Raw
}

function Require-Match([string]$Path, [string]$Pattern, [string]$Message) {
  $content = Read-RepoFile $Path
  if ($content -notmatch $Pattern) {
    $failures.Add("${Path}: $Message")
  }
}

function Reject-Match([string]$Path, [string]$Pattern, [string]$Message) {
  $content = Read-RepoFile $Path
  if ($content -match $Pattern) {
    $failures.Add("${Path}: $Message")
  }
}

function Reject-Path([string]$Path, [string]$Message) {
  $tracked = @(& git -C $repo ls-files -- $Path) | Where-Object {
    Test-Path -LiteralPath (Join-Path $repo $_) -PathType Leaf
  }
  if ($tracked.Count -gt 0) {
    $failures.Add("${Path}: $Message")
  }
}

function Require-NormalizedSha256([string]$Path, [string]$Expected, [string]$Message) {
  $content = (Read-RepoFile $Path) -replace "`r`n", "`n"
  $sha256 = [Security.Cryptography.SHA256]::Create()

  try {
    $bytes = [Text.Encoding]::UTF8.GetBytes($content)
    $actual = ([BitConverter]::ToString($sha256.ComputeHash($bytes))).Replace("-", "").ToLowerInvariant()
  }
  finally {
    $sha256.Dispose()
  }

  if ($actual -ne $Expected) {
    $failures.Add("${Path}: $Message")
  }
}

function Reject-RepositoryMatch([string]$Pattern, [string]$Message) {
  $trackedFiles = & git -C $repo ls-files
  if ($LASTEXITCODE -ne 0) {
    $failures.Add("Could not enumerate tracked files")
    return
  }

  foreach ($path in $trackedFiles) {
    $fullPath = Join-Path $repo $path
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
      continue
    }

    $content = Get-Content -LiteralPath $fullPath -Raw
    if ($content -match $Pattern) {
      $failures.Add("${path}: $Message")
    }
  }
}

Require-Match ".gitignore" '(?m)^\.env$' "must ignore .env"
Require-Match ".gitignore" '(?m)^config\.ini$' "must ignore production config"
Require-Match ".gitignore" '(?m)^plugins/$' "must ignore mounted plugins"
Require-Match ".gitignore" '(?m)^attachments/$' "must ignore attachments"
Require-Match ".gitignore" '(?m)^upstream/$' "must ignore upstream source"
Require-Match ".dockerignore" '(?m)^\*\*$' "must exclude the repository by default"
Require-Match ".dockerignore" '(?m)^!upstream/\*\*$' "must include only upstream source"

Require-Match "compose.yaml" 'ghcr\.io/gtaodiscord/modmailbot:\$\{MODMAIL_IMAGE_TAG\}' "must use the configurable GHCR tag"
Require-Match "compose.yaml" 'restart:\s+unless-stopped' "must use the approved restart policy"
Require-Match "compose.yaml" '8890:8890' "must expose the upstream default port"
Require-Match "compose.yaml" '/app/config\.ini:ro' "must mount config read-only"
Require-Match "compose.yaml" '/app/plugins:ro' "must mount plugins read-only"
Require-Match "compose.yaml" '/app/attachments' "must persist attachments"
Require-Match "compose.yaml" 'external:\s+true' "must use the external network"
Require-Match "compose.yaml" 'name:\s+modmail' "must use the modmail network"

Require-NormalizedSha256 "config.example.ini" "917f4a91aaf8216b228c556e7fee07dbb4ada04cb9e2c3e73d2fc4df86a8b4da" "must match Dragory's v3.11.0 sample exactly"
Reject-Path "docs/superpowers" "private implementation notes must not be published"

Require-Match ".env.example" '(?m)^MODMAIL_IMAGE_TAG=3\.11\.0$' "must pin the initial image example"
Require-Match ".env.example" '(?m)^MM_TOKEN=$' "must leave the Discord token empty"
Require-Match ".env.example" '(?m)^MM_MYSQL_OPTIONS__PASSWORD=$' "must leave the database password empty"

Require-Match "Dockerfile" '(?m)^ARG NODE_VERSION=24$' "must default to the current Node major"
Require-Match "Dockerfile" 'FROM node:\$\{NODE_VERSION\}-alpine AS build' "must use an Alpine build stage"
Require-Match "Dockerfile" 'npm ci --omit=dev' "must use the upstream lockfile"
Require-Match "Dockerfile" 'apk add --no-cache tini git' "must install Tini and Git in the runtime"
Require-Match "Dockerfile" '(?m)^USER node$' "must run as non-root"
Require-Match "Dockerfile" 'ENTRYPOINT \["/sbin/tini", "--"\]' "must use Tini"
Require-Match "Dockerfile" 'CMD \["node", "src/index\.js"\]' "must start Modmail"
Require-Match "tests/verify-image.ps1" 'is-number@7\.0\.0' "must exercise generic runtime package installation"
Require-Match "tests/verify-image.ps1" 'git --version' "must verify runtime Git"

Require-Match ".github/workflows/publish.yml" 'cron:\s+"17 \*/6 \* \* \*"' "must check releases every six hours"
Require-Match ".github/workflows/publish.yml" '(?m)^  workflow_dispatch:\r?$' "must support manual dispatch"
Require-Match ".github/workflows/publish.yml" 'contents:\s+read' "must use read-only repository permission"
Require-Match ".github/workflows/publish.yml" 'packages:\s+write' "must allow GHCR publication"
Require-Match ".github/workflows/publish.yml" 'cancel-in-progress:\s+false' "must serialize publication"
Require-Match ".github/workflows/publish.yml" 'repos/Dragory/modmailbot/releases/latest' "must use the upstream stable release endpoint"
Require-Match ".github/workflows/publish.yml" 'docker manifest inspect' "must preserve existing exact tags"
Require-Match ".github/workflows/publish.yml" 'git clone --depth 1 --branch' "must check out the exact upstream tag"
Require-Match ".github/workflows/publish.yml" 'engines\.node' "must derive the upstream Node major"
Require-Match ".github/workflows/publish.yml" 'docker build --platform linux/amd64' "must build only AMD64"
Require-Match ".github/workflows/publish.yml" 'tests/verify-image\.ps1' "must verify before publication"
Require-Match ".github/workflows/publish.yml" 'docker push "\$image:\$version"' "must publish the immutable exact tag"
Require-Match ".github/workflows/publish.yml" 'docker push "\$image:\$minor"' "must publish the minor alias"
Require-Match ".github/workflows/publish.yml" 'docker push "\$image:\$major"' "must publish the major alias"
Require-Match ".github/workflows/publish.yml" 'docker push "\$image:latest"' "must publish latest"
Reject-Match ".github/workflows/publish.yml" '(?m)^\s*uses:' "must not depend on mutable third-party actions"
Reject-Match ".github/workflows/publish.yml" 'pull_request_target' "must not run privileged code from pull requests"

Require-Match "README.md" 'Immutable exact tags' "must explain exact tags"
Require-Match "README.md" 'Moving discovery tags' "must explain moving aliases"
Require-Match "README.md" 'public GitHub Container Registry package' "must document public GHCR visibility"
Require-Match "README.md" 'docker network create modmail' "must document network creation"
Require-Match "README.md" 'docker network connect --alias mariadb modmail YOUR_DATABASE_CONTAINER' "must document generic MariaDB network attachment"
Require-Match "README.md" 'container port `3306`' "must document the standard MariaDB container port"
Require-Match "README.md" 'UID and GID `1000`' "must document attachment ownership"
Require-Match "README.md" 'copied verbatim from Dragory' "must identify the generic upstream sample"
Require-Match "README.md" 'Keep deployment-specific values only in `config.ini`' "must separate private deployment configuration"
Require-Match "README.md" 'Back up MariaDB' "must require a database backup"
Require-Match "README.md" 'release notes' "must require upstream review"
Require-Match "README.md" 'Local and public CI verification' "must separate credential-free checks"
Require-Match "README.md" 'Live deployment acceptance' "must separate live checks"
Require-Match "README.md" 'Never commit `.env`' "must protect production secrets"
Reject-Match "README.md" '\b\d{17,19}\b' "must not contain production Discord identifiers"
Require-Match "LICENSE" 'Permission is hereby granted' "must include the MIT license grant"

$privateMarkers = @(
  ([string]::Concat("logs", ".", "gtao", "discord", ".com")),
  ([string]::Concat("gtao", "-modmail")),
  ([string]::Concat("GTA", " Online")),
  ([string]::Concat("Rock", "star")),
  ([string]::Concat("down", "detector")),
  ([string]::Concat("modmail", "-mariadb")),
  ([string]::Concat("Modmail", "MenuPlugin")),
  ([string]::Concat("modmail", "-afkmover")),
  ([string]::Concat("afk", "Mover.js")),
  ([string]::Concat("MMPlugins", "/LogSearch")),
  ([string]::Concat("AFK", "Move.")),
  ([string]::Concat("889", "1")),
  ([string]::Concat("330", "7"))
)

foreach ($marker in $privateMarkers) {
  Reject-RepositoryMatch ([Regex]::Escape($marker)) "must not contain deployment-specific examples"
}

Reject-RepositoryMatch '(?<!\d)\d{17,20}(?!\d)' "must not contain Discord snowflakes"

if ($failures.Count -gt 0) {
  $failures | ForEach-Object { [Console]::Error.WriteLine($_) }
  exit 1
}

Write-Output "Repository contract passed"
