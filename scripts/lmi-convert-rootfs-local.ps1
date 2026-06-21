param(
  [Parameter(Mandatory = $true)]
  [string]$RootfsTar,

  [string]$OutputImage = "",
  [string]$Size = "16G",
  [string]$Distro = "Ubuntu-26.04",
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Convert-ToWslPath([string]$Path) {
  $full = [System.IO.Path]::GetFullPath($Path)
  if ($full -match '^([A-Za-z]):\\(.*)$') {
    $drive = $Matches[1].ToLowerInvariant()
    $rest = $Matches[2].Replace('\', '/')
    return "/mnt/$drive/$rest"
  }

  throw "Only local drive paths like D:\path\file are supported: $Path"
}

function Convert-ToBashSingleQuoted([string]$Value) {
  return "'" + $Value.Replace("'", "'\''") + "'"
}

if (-not (Test-Path -LiteralPath $RootfsTar)) {
  throw "Rootfs tarball not found: $RootfsTar"
}

if ([string]::IsNullOrWhiteSpace($OutputImage)) {
  $name = [System.IO.Path]::GetFileName($RootfsTar)
  $name = $name -replace '\.tar\.xz$', ''
  $name = $name -replace '\.tar$', ''
  $OutputImage = Join-Path (Split-Path -Parent ([System.IO.Path]::GetFullPath($RootfsTar))) "$name.ext4.img"
}

$repo = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$script = Join-Path $repo "scripts\lmi-make-ext4-image.sh"
$wslTar = Convert-ToWslPath $RootfsTar
$wslOut = Convert-ToWslPath $OutputImage
$wslScript = Convert-ToWslPath $script
$command = "apt-get update && apt-get install -y e2fsprogs android-sdk-libsparse-utils rsync && " +
  "$(Convert-ToBashSingleQuoted $wslScript) $(Convert-ToBashSingleQuoted $wslTar) $(Convert-ToBashSingleQuoted $wslOut) $(Convert-ToBashSingleQuoted $Size)"

Write-Host "Converting rootfs tarball to ext4 image..."
Write-Host "Input : $RootfsTar"
Write-Host "Output: $OutputImage"
Write-Host "Size  : $Size"

if ($DryRun) {
  Write-Host "WSL input : $wslTar"
  Write-Host "WSL output: $wslOut"
  Write-Host "WSL script: $wslScript"
  Write-Host "Command   : $command"
  exit 0
}

wsl -d $Distro -u root -- bash -lc $command
