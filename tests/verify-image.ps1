param(
  [Parameter(Mandatory = $true)]
  [string]$Image,

  [Parameter(Mandatory = $true)]
  [string]$Version,

  [Parameter(Mandatory = $true)]
  [string]$Revision
)

$ErrorActionPreference = "Stop"

function Invoke-Docker([string[]]$Arguments, [string]$Check) {
  $output = & docker @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "$Check failed with exit code $LASTEXITCODE"
  }

  return ($output | Out-String).Trim()
}

function Assert-Equal([string]$Actual, [string]$Expected, [string]$Check) {
  if ($Actual -ne $Expected) {
    throw "$Check failed: expected '$Expected', got '$Actual'"
  }

  Write-Output "PASS: $Check"
}

$packagedVersion = Invoke-Docker @(
  "run", "--rm", "--entrypoint", "node", $Image,
  "-p", "require('./package.json').version"
) "Packaged Modmail version"
Assert-Equal $packagedVersion $Version "Packaged Modmail version"

$inspectJson = Invoke-Docker @("image", "inspect", $Image) "Image metadata"
$inspect = @($inspectJson | ConvertFrom-Json)[0]
Assert-Equal $inspect.Config.User "node" "Runtime user"
Assert-Equal $inspect.Config.Labels.'org.opencontainers.image.version' $Version "OCI version label"
Assert-Equal $inspect.Config.Labels.'org.opencontainers.image.revision' $Revision "OCI revision label"

Invoke-Docker @(
  "run", "--rm", "--entrypoint", "sh", $Image,
  "-c", 'git --version >/dev/null'
) "Runtime Git" | Out-Null
Write-Output "PASS: Runtime Git"

Invoke-Docker @(
  "run", "--rm", "--entrypoint", "sh", $Image,
  "-c", 'for tool in python3 make g++ gcc; do ! command -v "$tool" >/dev/null 2>&1 || exit 1; done'
) "Runtime toolchain absence" | Out-Null
Write-Output "PASS: Runtime toolchain absence"

Invoke-Docker @(
  "run", "--rm", "--entrypoint", "node", $Image,
  "-e", "require.resolve('knex'); require.resolve('mysql2')"
) "Production dependencies" | Out-Null
Write-Output "PASS: Production dependencies"

Invoke-Docker @(
  "run", "--rm", "--entrypoint", "npm", $Image,
  "install", "--ignore-scripts", "--no-save", "is-number@7.0.0"
) "Runtime package installation" | Out-Null
Write-Output "PASS: Runtime package installation"

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "modmailbot-image-$([guid]::NewGuid().ToString('N'))"
$plugins = Join-Path $testRoot "plugins"
$attachments = Join-Path $testRoot "attachments"

try {
  New-Item -ItemType Directory -Path $plugins, $attachments -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $plugins "probe.js") -Value "module.exports = () => {};" -NoNewline

  if ($PSVersionTable.PSEdition -eq "Core" -and $IsLinux) {
    & chmod 0777 $attachments
    if ($LASTEXITCODE -ne 0) {
      throw "Could not prepare the attachment test directory"
    }
  }

  Invoke-Docker @(
    "run", "--rm",
    "--mount", "type=bind,src=$plugins,dst=/app/plugins,readonly",
    "--mount", "type=bind,src=$attachments,dst=/app/attachments",
    "--entrypoint", "sh", $Image,
    "-c", "test -r /app/plugins/probe.js && touch /app/attachments/probe"
  ) "Plugin and attachment mounts" | Out-Null
  Write-Output "PASS: Plugin and attachment mounts"
}
finally {
  if (Test-Path -LiteralPath $testRoot) {
    Remove-Item -LiteralPath $testRoot -Recurse -Force
  }
}

Write-Output "Image verification passed"
