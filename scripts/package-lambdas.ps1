# Empaqueta Auth Service y Authorizer para AWS Lambda (Python 3.12)
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
if (-not $Root) { $Root = (Get-Location).Path }

$Build = Join-Path $Root "build"
$Out   = Join-Path $Root "dist"

Remove-Item -Recurse -Force $Build -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Build, $Out | Out-Null

function Install-Deps {
    param($ReqFile, $TargetDir)
    python -m pip install `
        --platform manylinux2014_x86_64 `
        --target $TargetDir `
        --implementation cp `
        --python-version 3.12 `
        --only-binary=:all: `
        --upgrade `
        -r $ReqFile
}

# ---------- Auth Service ----------
$AuthBuild = Join-Path $Build "auth_service"
New-Item -ItemType Directory -Force -Path $AuthBuild | Out-Null

$AuthReq = Join-Path $AuthBuild "requirements.pkg.txt"
@"
PyJWT>=2.8.0
bcrypt>=4.1.0
"@ | Set-Content $AuthReq -Encoding utf8

Write-Host "==> Instalando deps Auth Service (manylinux)..."
Install-Deps -ReqFile $AuthReq -TargetDir $AuthBuild

Copy-Item (Join-Path $Root "src\auth_service\handler.py")      $AuthBuild -Force
Copy-Item (Join-Path $Root "src\auth_service\auth_utils.py")   $AuthBuild -Force
Copy-Item (Join-Path $Root "src\auth_service\permissions.py")  $AuthBuild -Force
Copy-Item (Join-Path $Root "src\auth_service\repository.py")   $AuthBuild -Force
Copy-Item -Recurse (Join-Path $Root "src\shared") (Join-Path $AuthBuild "shared") -Force

$AuthZip = Join-Path $Out "auth_service.zip"
if (Test-Path $AuthZip) { Remove-Item $AuthZip -Force }
Compress-Archive -Path (Join-Path $AuthBuild "*") -DestinationPath $AuthZip -Force
Write-Host "OK: $AuthZip"

# ---------- Catalog Service ----------
$CatalogBuild = Join-Path $Build "catalog_service"
New-Item -ItemType Directory -Force -Path $CatalogBuild | Out-Null

$CatalogReq = Join-Path $CatalogBuild "requirements.pkg.txt"
@"
boto3>=1.34.0
"@ | Set-Content $CatalogReq -Encoding utf8

Write-Host "==> Instalando deps Catalog Service (manylinux)..."
Install-Deps -ReqFile $CatalogReq -TargetDir $CatalogBuild

Copy-Item (Join-Path $Root "src\catalog_service\handler.py")      $CatalogBuild -Force
Copy-Item (Join-Path $Root "src\catalog_service\permissions.py")  $CatalogBuild -Force
Copy-Item (Join-Path $Root "src\catalog_service\repository.py")   $CatalogBuild -Force
Copy-Item -Recurse (Join-Path $Root "src\shared") (Join-Path $CatalogBuild "shared") -Force

$CatalogZip = Join-Path $Out "catalog_service.zip"
if (Test-Path $CatalogZip) { Remove-Item $CatalogZip -Force }
Compress-Archive -Path (Join-Path $CatalogBuild "*") -DestinationPath $CatalogZip -Force
Write-Host "OK: $CatalogZip"

# ---------- Authorizer ----------
$AuthzBuild = Join-Path $Build "authorizer"
New-Item -ItemType Directory -Force -Path $AuthzBuild | Out-Null

$AuthzReq = Join-Path $AuthzBuild "requirements.pkg.txt"
@"
PyJWT>=2.8.0
"@ | Set-Content $AuthzReq -Encoding utf8

Write-Host "==> Instalando deps Authorizer (manylinux)..."
Install-Deps -ReqFile $AuthzReq -TargetDir $AuthzBuild

Copy-Item (Join-Path $Root "src\authorizer\handler.py") $AuthzBuild -Force

$AuthzZip = Join-Path $Out "authorizer.zip"
if (Test-Path $AuthzZip) { Remove-Item $AuthzZip -Force }
Compress-Archive -Path (Join-Path $AuthzBuild "*") -DestinationPath $AuthzZip -Force
Write-Host "OK: $AuthzZip"

Write-Host ""
Write-Host "Listo. Zips en: $Out"
Get-ChildItem $Out
