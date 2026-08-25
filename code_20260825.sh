# 删除损坏脚本
rm -f build-proot.ps1

# 写入干净无特殊符号版本
cat > build-proot.ps1 <<'EOF'
<#
.SYNOPSIS
    Build PRoot and proot-loader for Android
.DESCRIPTION
    Build PRoot from Termux source using Docker.
    Produces libproot.so, libproot-loader.so, libproot-loader32.so, libtalloc.so.2
#>
Param(
    [ValidateSet('arm64', 'arm32', 'x86_64', 'all')]
    [string]$Arch = 'all',
    [ValidateSet('incremental', 'rebuild', 'clean')]
    [string]$Mode = 'incremental',
    [string]$OutputPath = '',
    [string]$AndroidProjectRoot = '',
    [switch]$CopyToJniLibs,
    [switch]$CopyToAssets,
    [switch]$ResetSource,
    [ValidateSet('shared', 'static')]
    [string]$TallocLink = 'shared'
)
$ErrorActionPreference = 'Stop'

function Write-Info($msg) { Write-Host "[i] $msg" -ForegroundColor Cyan }
function Write-Success($msg) { Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "[!] $msg" -ForegroundColor Yellow }
function Write-Err($msg) { Write-Host "[x] $msg" -ForegroundColor Red }

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path $scriptRoot

if (-not $OutputPath -or [string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $scriptRoot 'output'
}
New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null
$outputBase = (Resolve-Path $OutputPath).Path
$SourceVolumeName = "proot-builder-source"

function Test-Docker {
    try {
        $null = docker version 2>&1
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}

function Test-BuildxMultiArch {
    $info = docker buildx inspect 2>$null
    return $info -match 'linux/arm64'
}

function Ensure-Buildx {
    if (-not (Test-BuildxMultiArch)) {
        Write-Info "Configuring Docker buildx multi-arch support..."
        docker buildx create --name proot-builder-multiarch --use 2>$null | Out-Null
        docker buildx inspect --bootstrap 2>$null | Out-Null
    }
}

$ImageBaseName = "proot-builder"
function Get-ImageName($arch) { return "${ImageBaseName}:${arch}" }
function Get-ContainerName($arch) { return "proot-builder-build-${arch}" }

function Test-ImageExists($arch) {
    $imageName = Get-ImageName $arch
    $exists = docker images -q $imageName 2>$null
    return [bool]$exists
}
function Test-ContainerExists($arch) {
    $containerName = Get-ContainerName $arch
    $exists = docker ps -aq --filter "name=^${containerName}$" 2>$null
    return [bool]$exists
}
function Remove-ExistingContainer($arch) {
    $containerName = Get-ContainerName $arch
    if (Test-ContainerExists $arch) {
        Write-Info "Removing existing container: $containerName"
        docker rm -f $containerName 2>$null | Out-Null
    }
}
function Remove-ExistingImage($arch) {
    $imageName = Get-ImageName $arch
    if (Test-ImageExists $arch) {
        Write-Info "Removing existing image: $imageName"
        docker rmi -f $imageName 2>$null | Out-Null
    }
}
function Test-VolumeExists($volumeName) {
    $exists = docker volume ls -q --filter "name=^${volumeName}$" 2>$null
    return [bool]$exists
}
function Remove-SourceVolume {
    if (Test-VolumeExists $SourceVolumeName) {
        Write-Info "Removing source volume: $SourceVolumeName"
        docker volume rm -f $SourceVolumeName 2>$null | Out-Null
    }
}

function Build-Image($arch) {
    $imageName = Get-ImageName $arch
    $platform = 'linux/amd64'
    $dockerfile = Join-Path $scriptRoot "Dockerfile"
    $targetArch = switch ($arch) {
        'arm64' { 'aarch64' }
        'arm32' { 'armv7a' }
        'x86_64' { 'x86_64' }
    }
    Write-Info "DEBUG input arch=[$arch], mapped targetArch=[$targetArch]"
    Write-Info "Building image: $imageName (target: $targetArch)"
    Write-Info "  Platform: $platform"
    $buildArgs = @(
        'build','--progress','plain','--platform',$platform,
        '--build-arg',"TARGET_ARCH=$targetArch",
        '-t',$imageName,'-f',$dockerfile,$scriptRoot
    )
    & docker @buildArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Image build failed: $imageName"
        return $false
    }
    Write-Success "Image built: $imageName"
    return $true
}

function Ensure-SourceVolume {
    if (-not (Test-VolumeExists $SourceVolumeName)) {
        Write-Info "Creating source volume: $SourceVolumeName"
        docker volume create $SourceVolumeName | Out-Null
    } else {
        Write-Info "Using existing source volume: $SourceVolumeName"
    }
}

function Build-PRoot($arch, $outputDir) {
    $imageName = Get-ImageName $arch
    $containerName = Get-ContainerName $arch
    $targetArch = switch ($arch) {
        'arm64' { 'aarch64' }
        'arm32' { 'armv7a' }
        'x86_64' { 'x86_64' }
    }
    Write-Info "DEBUG PRoot input arch=[$arch], mapped targetArch=[$targetArch]"
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
    Ensure-SourceVolume
    Remove-ExistingContainer $arch
    Write-Info "Building PRoot ($arch)..."
    $scriptsPath = (Resolve-Path $scriptRoot).Path
    $dockerArgs = @(
        'run','--name',$containerName,
        '-v',"${SourceVolumeName}:/build/src",
        '-v',"${scriptsPath}:/build/scripts:ro",
        '-v',"${outputDir}:/output",
        '-e',"TARGET_ARCH=$targetArch",
        '-e',"TALLOC_LINK=$TallocLink",
        $imageName
    )
    $process = Start-Process -FilePath docker -ArgumentList $dockerArgs -NoNewWindow -Wait -PassThru
    $buildExitCode = $process.ExitCode
    if (Test-ContainerExists $arch) { docker rm $containerName 2>$null | Out-Null }
    if ($buildExitCode -ne 0) { Write-Err "Build failed!"; return $false }
    $requiredFiles = @('libproot.so')
    $missing = @()
    foreach($f in $requiredFiles){
        if(-not (Test-Path (Join-Path $outputDir $f))){ $missing += $f }
    }
    if($missing.Count -gt 0){ Write-Err "Missing files: $($missing -join ', ')"; return $false }
    Write-Success "Build completed: $outputDir"
    return $true
}

function Build-Architecture($arch) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor White
    Write-Info "Start build: $arch"
    Write-Host "========================================" -ForegroundColor White
    $outputDir = Join-Path $outputBase $arch
    switch ($Mode) {
        'clean' {
            Remove-ExistingContainer $arch
            Remove-ExistingImage $arch
            Remove-SourceVolume
        }
        'rebuild' { Remove-ExistingContainer $arch }
    }
    if ($ResetSource) { Remove-SourceVolume }
    $needBuild = -not (Test-ImageExists $arch)
    if ($Mode -eq 'rebuild' -or $Mode -eq 'clean') { $needBuild = $true }
    if ($needBuild) {
        if (-not (Build-Image $arch)) { return $false }
    } else {
        Write-Info "Reusing existing image: $(Get-ImageName $arch)"
    }
    if (-not (Build-PRoot $arch $outputDir)) { return $false }
    return $true
}

# main
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Android PRoot Builder" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Docker)) {
    Write-Err "Docker is not running."
    exit 1
}
Write-Info "Output dir: $outputBase"
Write-Info "Build mode: $Mode"

$archList = switch ($Arch) {
    'all' { @('arm64','arm32','x86_64') }
    default { @($Arch) }
}
$allSuccess = $true
foreach($a in $archList){
    if(-not (Build-Architecture $a)){ $allSuccess = $false }
}

if ($allSuccess -and $CopyToJniLibs) {
    Write-Host ""; Write-Info "Copying to jniLibs..."
    if (-not $AndroidProjectRoot -or [string]::IsNullOrWhiteSpace($AndroidProjectRoot)) {
        Write-Err "-AndroidProjectRoot required"; exit 1
    }
    $jniLibsBase = Join-Path (Resolve-Path $AndroidProjectRoot).Path 'app\src\main\jniLibs'
    foreach($a in $archList){
        $srcDir = Join-Path $outputBase $a
        $dstDir = switch($a){
            'arm64'  { Join-Path $jniLibsBase 'arm64-v8a' }
            'arm32'  { Join-Path $jniLibsBase 'armeabi-v7a' }
            'x86_64' { Join-Path $jniLibsBase 'x86_64' }
        }
        New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
        $files = @('libproot.so','libproot-loader.so')
        if($a -eq 'arm64'){ $files += 'libproot-loader32.so' }
        foreach($fn in $files){
            $sf = Join-Path $srcDir $fn
            if(Test-Path $sf){
                Copy-Item -Force $sf $dstDir
                Write-Success "Copied: $dstDir\$fn"
            }
        }
    }
}

if ($allSuccess -and $CopyToAssets) {
    Write-Host ""; Write-Info "Copying libtalloc.so.2 to assets..."
    if (-not $AndroidProjectRoot -or [string]::IsNullOrWhiteSpace($AndroidProjectRoot)) {
        Write-Err "-AndroidProjectRoot required"; exit 1
    }
    if($TallocLink -eq 'static'){ Write-Warn "static link, libtalloc.so.2 not needed" }
    foreach($a in $archList){
        $srcFile = Join-Path $outputBase "$a\libtalloc.so.2"
        $abi = switch($a){
            'arm64'  { 'arm64-v8a' }
            'arm32'  { 'armeabi-v7a' }
            'x86_64' { 'x86_64' }
        }
        $flavor = switch($a){
            'arm64' { 'arm64' }
            'arm32' { 'arm32' }
            'x86_64' { 'x86_64' }
        }
        $dstDir = Join-Path (Resolve-Path $AndroidProjectRoot).Path "app\src\$flavor\assets\proot\$abi"
        if(Test-Path $srcFile){
            New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
            Copy-Item -Force $srcFile $dstDir
            Write-Success "Copied: $dstDir\libtalloc.so.2"
        }
    }
}

Write-Host ""
if ($allSuccess) {
    Write-Success "Build completed!"
    Write-Host ""
    Write-Info "Artifacts:"
    foreach($a in $archList){
        $d = Join-Path $outputBase $a
        if(Test-Path $d){
            Write-Host "  $a/" -ForegroundColor White
            Get-ChildItem $d -Filter "*.so*" | ForEach-Object {
                $sz = [math]::Round($_.Length / 1KB,2)
                Write-Host "    - $($_.Name) ($sz KB)" -ForegroundColor Gray
            }
        }
    }
} else {
    Write-Err "Build failed."
    exit 1
}
EOF

# 清理旧错误镜像
docker rmi -f proot-builder:armeabi-v7a 2>/dev/null

# 运行全架构编译
pwsh build-proot.ps1 -Arch all
