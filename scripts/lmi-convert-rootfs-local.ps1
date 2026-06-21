param(
  [Parameter(Mandatory = $true)]
  [string]$RootfsTar,

  [string]$OutputImage = "",
  [string]$Size = "16G",
  [string]$Distro = "Ubuntu-26.04"
)

$ErrorActionPreference = "Stop"

function Convert-ToWslPath([string]$Path) {
  $full = [System.IO.Path]::GetFullPath($Path)
  return (wsl -d $Distro -- wslpath -a $full).Trim()
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

wsl -d $Distro -u root -- bash -lc $command
