<#
    publish-cache.ps1 - 把本地 cache\ 打包发布到 GitHub Release
    ------------------------------------------------------------
    在“网好、已下好缓存的机器”上跑一次，把整份 cache\ 打成
    cache-bundle.zip 上传到本包仓库的 Release；目标机即可用
    install.cmd 选择从 GitHub 拉取完整缓存包（走镜像、可续传）。

    依赖：GitHub CLI (gh) 已登录（gh auth login）。

    用法:
      powershell -ExecutionPolicy Bypass -File scripts\publish-cache.ps1
      powershell -ExecutionPolicy Bypass -File scripts\publish-cache.ps1 -Tag cache-2026.10
      powershell -ExecutionPolicy Bypass -File scripts\publish-cache.ps1 -Repo user/fork -Tag v1
#>
param(
    [string]$Tag = '',
    [string]$Repo = '',
    [string]$Title = '',
    [string]$Notes = '',
    [switch]$Prerelease,
    [switch]$DryRun      # 只打包并打印信息，不上传（用于验证）
)
$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RootDir   = Split-Path -Parent $ScriptDir
$CacheDir  = Join-Path $RootDir 'cache'
. (Join-Path $ScriptDir 'cache-lib.ps1')

function Info($m) { Write-Host $m -ForegroundColor Cyan }
function Ok($m)   { Write-Host $m -ForegroundColor Green }
function Warn($m) { Write-Host $m -ForegroundColor Yellow }
function Fail($m) { Write-Host $m -ForegroundColor Red }

if (-not $Repo) { $Repo = Get-CacheReleaseRepo }
Info '=================================================='
Info ' 发布离线缓存包到 GitHub Release'
Info '=================================================='
Info (" 仓库: " + $Repo)

# --- 1. cache 检查 ---
if (-not (Test-Path $CacheDir)) { Fail "未找到 cache\：$CacheDir，请先运行 prefetch.cmd"; exit 1 }
$files = Get-ChildItem $CacheDir -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'download.log' }
if (-not $files -or @($files).Count -eq 0) { Fail 'cache\ 为空，请先运行 prefetch.cmd 下载离线包'; exit 1 }
$totalMB = ($files | Measure-Object Length -Sum).Sum / 1MB
Info (" 待发布: {0} 个文件, {1:N1} MB" -f @($files).Count, $totalMB)

# --- 2. tag ---
if (-not $Tag) { $Tag = 'cache-' + (Get-Date).ToString('yyyy.MM.dd') }
if (-not $Title) { $Title = 'Offline cache ' + $Tag }
Info (" Tag: " + $Tag)

# --- 3. 打包 ---
$tmpDir = Join-Path $env:TEMP ('tabby-cache-publish-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
$zip = Join-Path $tmpDir $script:CacheBundleName
Info ' 正在打包 cache\ ...'
Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
if (Test-Path $zip) { Remove-Item $zip -Force }
# includeBaseDirectory=false：cache\ 的内容直接位于 zip 根目录
[System.IO.Compression.ZipFile]::CreateFromDirectory($CacheDir, $zip, [System.IO.Compression.CompressionLevel]::Optimal, $false)
$zipMB = (Get-Item $zip).Length / 1MB
Info (" 打包完成: {0:N1} MB" -f $zipMB)
$sha = (Get-FileHash $zip -Algorithm SHA256).Hash
$shaFile = "$zip.sha256"
("$sha  " + $script:CacheBundleName) | Set-Content -Path $shaFile -Encoding ASCII
Info (" SHA256: " + $sha)

# --- DryRun：只验证打包，不上传 ---
if ($DryRun) {
    Ok ''
    Ok (" [DryRun] 打包成功: {0} ({1:N1} MB)" -f $zip, $zipMB)
    Ok (" [DryRun] 将发布到: https://github.com/{0}/releases/download/{1}/{2}" -f $Repo, $Tag, $script:CacheBundleName)
    Ok (" [DryRun] 未实际上传（去掉 -DryRun 才会发布）。")
    # 保留 zip 供检查
    exit 0
}

# --- 4. 定位 gh ---
$gh = (Get-Command gh -ErrorAction SilentlyContinue).Source
if (-not $gh) { $portable = Join-Path $env:LOCALAPPDATA 'Programs\gh\gh.exe'; if (Test-Path $portable) { $gh = $portable } }
if (-not $gh) { Fail '未找到 GitHub CLI (gh)。请先安装并执行 gh auth login。'; exit 1 }

# --- 5. 创建或覆盖上传 ---
# gh 会向 stderr 输出进度/提示；在 $ErrorActionPreference='Stop' 下原生命令的
# stderr 会被当成终止错误，故这里临时放宽为 Continue，用 $LASTEXITCODE 判定。
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$exists = $false
& $gh release view $Tag --repo $Repo 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { $exists = $true }

if ($exists) {
    Info (" Release {0} 已存在，上传/覆盖附件 ..." -f $Tag)
    & $gh release upload $Tag --repo $Repo $zip $shaFile --clobber
    $code = $LASTEXITCODE
} else {
    Info (" 创建 Release {0} 并上传附件 ..." -f $Tag)
    $ghArgs = @('release', 'create', $Tag, '--repo', $Repo, '--title', $Title)
    if ($Notes) { $ghArgs += @('--notes', $Notes) }
    else { $ghArgs += @('--notes', ("完整离线缓存包（{0:N1} MB）。SHA256: {1}" -f $zipMB, $sha)) }
    if ($Prerelease) { $ghArgs += '--prerelease' }
    $ghArgs += @($zip, $shaFile)
    & $gh @ghArgs
    $code = $LASTEXITCODE
}
$ErrorActionPreference = $prevEAP
if ($code -ne 0) { Fail '发布失败（gh 返回非 0）。'; exit 1 }

$url = "https://github.com/$Repo/releases/download/$Tag/$($script:CacheBundleName)"
Ok ''
Ok ' 发布完成!'
Ok (" 缓存包: " + $url)
Ok ' 目标机: install.cmd 选择 [b] 从 Release 拉取，或 install.ps1 -FromRelease'
Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
