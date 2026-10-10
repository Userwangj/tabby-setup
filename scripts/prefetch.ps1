<#
    prefetch.ps1 - 准备离线安装包
    ------------------------------------------------------------
    把安装所需的一切下载到本目录 cache\ 下，并写 manifest.json：
      Tabby 安装包 / JetBrainsMono Nerd Font / Node.js / PowerShell 7 /
      oh-my-posh / PowerShell 模块(PSReadLine,CompletionPredictor) / npm 插件
    在网好的机器上跑一次，之后把整个文件夹拷到目标机 -> install 即可离线秒装。
    用法:
      powershell -ExecutionPolicy Bypass -File prefetch.ps1
      powershell -ExecutionPolicy Bypass -File prefetch.ps1 -Only tabby,font
    可选项(-Only): tabby font node pwsh omp modules npm
#>
param(
    [string[]]$Only = @()
)
$ErrorActionPreference = 'Continue'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RootDir   = Split-Path -Parent $ScriptDir
$CacheDir  = Join-Path $RootDir 'cache'
$AssetsDir = Join-Path $RootDir 'assets'
. (Join-Path $ScriptDir 'cache-lib.ps1')

function Info($m) { Write-Host $m -ForegroundColor Cyan }
function Ok($m)   { Write-Host $m -ForegroundColor Green }
function Warn($m) { Write-Host $m -ForegroundColor Yellow }
function Want([string]$k) { return ($Only.Count -eq 0) -or ($Only -contains $k) }

New-Item -ItemType Directory -Path $CacheDir -Force | Out-Null
$manifest = Get-CacheManifest $CacheDir
$results = [ordered]@{}
$dlLog = Join-Path $CacheDir 'download.log'

Info '=================================================='
Info ' 准备离线安装包 (prefetch)'
Info (" 缓存目录: " + $CacheDir)
Info (" 进度日志: " + $dlLog)
Info '=================================================='

# --- Tabby ---
if (Want 'tabby') {
    Info ''
    Info '[Tabby] 查询最新版本...'
    $tag = Get-LatestGitHubTag 'Eugeny/tabby'
    $rel = $null
    if ($tag) {
        foreach ($api in @('https://api.github.com/repos/Eugeny/tabby/releases/latest', 'https://ghfast.top/https://api.github.com/repos/Eugeny/tabby/releases/latest')) {
            try { $rel = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = 'tabby-setup' } -UseBasicParsing -TimeoutSec 20; if ($rel) { break } } catch { }
        }
    }
    $asset = $null
    if ($rel) {
        $asset = $rel.assets | Where-Object { $_.name -match 'setup.*x64\.exe$' } | Select-Object -First 1
        if (-not $asset) { $asset = $rel.assets | Where-Object { $_.name -match 'x64.*setup\.exe$' } | Select-Object -First 1 }
    }
    if (-not $asset) { Warn '  未找到安装包资源/查询失败，跳过'; $results['Tabby'] = '失败' }
    else {
        $dst = Get-CachePath $CacheDir 'tabby'
        $ok = $false
        $urls = @("https://ghfast.top/$($asset.browser_download_url)", "https://gh-proxy.com/$($asset.browser_download_url)", $asset.browser_download_url)
        if (Get-FileFromMirrors -Urls $urls -OutFile $dst -MinBytes 40MB -ExpectedBytes $asset.size -TimeoutSec 900 -Activity "Tabby $tag" -LogFile $dlLog) { $ok = $true }
        if ($ok) { Set-ManifestEntry $CacheDir 'tabby' $tag $asset.name; Ok "  已准备 Tabby $tag"; $results['Tabby'] = $tag }
        else { Warn '  下载失败'; $results['Tabby'] = '失败' }
    }
}

# --- 字体 JetBrainsMono Nerd Font ---
if (Want 'font') {
    Info ''
    Info '[字体] 查询最新版本...'
    $tag = Get-LatestGitHubTag 'ryanoasis/nerd-fonts'
    $dst = Get-CachePath $CacheDir 'font'
    $urls = @(
        'https://ghfast.top/https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip',
        'https://gh-proxy.com/https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip',
        'https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip'
    )
    $ok = $false
    if (Get-FileFromMirrors -Urls $urls -OutFile $dst -MinBytes 25MB -TimeoutSec 600 -Activity 'JetBrainsMono NF' -LogFile $dlLog) { $ok = $true }
    if ($ok -and -not (Test-ZipFile $dst)) { Warn '  字体包校验失败（不完整）'; $ok = $false }
    $ver = if ($tag) { $tag } else { 'latest' }
    if ($ok) { Set-ManifestEntry $CacheDir 'font' $ver 'JetBrainsMono.zip'; Ok "  已准备 字体 $ver"; $results['字体'] = $ver }
    else { Warn '  下载失败'; $results['字体'] = '失败' }
}

# --- Node.js ---
if (Want 'node') {
    Info ''
    Info '[Node.js] 查询最新 LTS...'
    $ver = Get-LatestNodeLts
    if (-not $ver) { Warn '  查询失败，跳过'; $results['Node'] = '失败' }
    else {
        $dst = Get-CachePath $CacheDir 'node'
        $ok = $false
        $urls = @("https://registry.npmmirror.com/-/binary/node/$ver/node-$ver-win-x64.zip", "https://nodejs.org/dist/$ver/node-$ver-win-x64.zip")
        if (Get-FileFromMirrors -Urls $urls -OutFile $dst -MinBytes 10MB -TimeoutSec 600 -Activity "Node.js $ver" -LogFile $dlLog) { $ok = $true }
        if ($ok -and -not (Test-ZipFile $dst)) { Warn '  Node.js 包校验失败（不完整）'; $ok = $false }
        if ($ok) { Set-ManifestEntry $CacheDir 'node' $ver "node-$ver-win-x64.zip"; Ok "  已准备 Node.js $ver"; $results['Node'] = $ver }
        else { Warn '  下载失败'; $results['Node'] = '失败' }
    }
}

# --- PowerShell 7 ---
if (Want 'pwsh') {
    Info ''
    Info '[PowerShell 7] 查询最新版本...'
    $tag = Get-LatestGitHubTag 'PowerShell/PowerShell'
    if (-not $tag) { Warn '  查询失败，跳过'; $results['PowerShell'] = '失败' }
    else {
        $ver = $tag.TrimStart('v')
        $dst = Get-CachePath $CacheDir 'pwsh'
        $gh = "https://github.com/PowerShell/PowerShell/releases/download/v$ver/PowerShell-$ver.msixbundle"
        $ok = $false
        $purls = @("https://ghfast.top/$gh", "https://gh-proxy.com/$gh", $gh)
        if (Get-FileFromMirrors -Urls $purls -OutFile $dst -MinBytes 50MB -TimeoutSec 900 -Activity "PowerShell $ver" -LogFile $dlLog) { $ok = $true }
        if ($ok -and -not (Test-ZipFile $dst)) { Warn '  PowerShell MSIX 校验失败（不完整）'; $ok = $false }
        if ($ok) { Set-ManifestEntry $CacheDir 'pwsh' $ver "PowerShell-$ver.msixbundle"; Ok "  已准备 PowerShell $ver"; $results['PowerShell'] = $ver }
        else { Warn '  下载失败'; $results['PowerShell'] = '失败' }
    }
}

# --- oh-my-posh ---
if (Want 'omp') {
    Info ''
    Info '[oh-my-posh] 查询最新版本...'
    $tag = Get-LatestGitHubTag 'JanDeDobbeleer/oh-my-posh'
    $rel = $null
    if ($tag) {
        foreach ($api in @('https://api.github.com/repos/JanDeDobbeleer/oh-my-posh/releases/latest', 'https://ghfast.top/https://api.github.com/repos/JanDeDobbeleer/oh-my-posh/releases/latest')) {
            try { $rel = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = 'tabby-setup' } -UseBasicParsing -TimeoutSec 20; if ($rel) { break } } catch { }
        }
    }
    # v31+ 资源名：posh-windows-amd64.exe（便携 exe）+ themes.zip（主题）
    $assetExe = $null; $assetThemes = $null
    if ($rel) {
        $assetExe = $rel.assets | Where-Object { $_.name -match '^posh-windows-amd64\.exe$' } | Select-Object -First 1
        if (-not $assetExe) { $assetExe = $rel.assets | Where-Object { $_.name -match 'windows-amd64.*\.exe$' } | Select-Object -First 1 }
        $assetThemes = $rel.assets | Where-Object { $_.name -eq 'themes.zip' } | Select-Object -First 1
        # 兼容旧版命名（oh-my-posh-windows-amd64.zip）
        if (-not $assetExe) { $assetExe = $rel.assets | Where-Object { $_.name -match 'oh-my-posh-windows-amd64\.zip$' } | Select-Object -First 1 }
    }
    if (-not $assetExe) { Warn '  未找到资源/查询失败，跳过'; $results['oh-my-posh'] = '失败' }
    else {
        $dstExe = Get-CachePath $CacheDir 'omp'
        $ok = $false
        $exeUrls = @("https://ghfast.top/$($assetExe.browser_download_url)", "https://gh-proxy.com/$($assetExe.browser_download_url)", $assetExe.browser_download_url)
        if (Get-FileFromMirrors -Urls $exeUrls -OutFile $dstExe -MinBytes 5MB -ExpectedBytes $assetExe.size -TimeoutSec 600 -Activity "oh-my-posh $tag" -LogFile $dlLog) { $ok = $true }
        # 主题包（可选，供 omp 预览全部主题用）
        if ($assetThemes) {
            $dstTh = Get-CachePath $CacheDir 'ompthemes'
            $thUrls = @("https://ghfast.top/$($assetThemes.browser_download_url)", "https://gh-proxy.com/$($assetThemes.browser_download_url)", $assetThemes.browser_download_url)
            [void](Get-FileFromMirrors -Urls $thUrls -OutFile $dstTh -MinBytes 100KB -ExpectedBytes $assetThemes.size -TimeoutSec 300 -Activity 'oh-my-posh themes' -LogFile $dlLog)
        }
        if ($ok) { Set-ManifestEntry $CacheDir 'omp' $tag $assetExe.name; Ok "  已准备 oh-my-posh $tag"; $results['oh-my-posh'] = $tag }
        else { Warn '  下载失败'; $results['oh-my-posh'] = '失败' }
    }
}

# --- PowerShell 模块 ---
if (Want 'modules') {
    Info ''
    Info '[PS 模块] 下载 PSReadLine / CompletionPredictor ...'
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
        }
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
    } catch { }
    $dir = Join-Path $CacheDir 'modules'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    foreach ($mn in @('PSReadLine', 'CompletionPredictor')) {
        try {
            Save-Module -Name $mn -Path $dir -Force -ErrorAction Stop
            $v = Get-CachedModuleVersion $CacheDir $mn
            Ok "  已准备 $mn $v"; $results[$mn] = $v
        } catch { Warn ("  $mn 下载失败: " + $_.Exception.Message); $results[$mn] = '失败' }
    }
}

# --- npm 插件 ---
if (Want 'npm') {
    Info ''
    Info '[npm 插件] 安装到 cache 的 npm 目录 ...'
    $npmDir = Join-Path $CacheDir 'npm'
    New-Item -ItemType Directory -Path $npmDir -Force | Out-Null
    Copy-Item (Join-Path $AssetsDir 'plugins.package.json') (Join-Path $npmDir 'package.json') -Force
    if (Get-Command npm.cmd -ErrorAction SilentlyContinue) {
        Push-Location $npmDir
        try {
            $npmLog = Join-Path $env:TEMP 'tabby-npm-prefetch.log'
            Invoke-WithSpinner '正在下载 npm 插件...' 'npm 插件下载完成' {
                & npm.cmd install --no-audit --no-fund *> $npmLog
            }
            if (Test-Path (Join-Path $npmDir 'node_modules')) {
                Compress-TreeToZip -Source (Join-Path $npmDir 'node_modules') -ZipPath (Join-Path $npmDir 'node_modules.zip') -Activity '打包 npm 插件'
                Remove-Item (Join-Path $npmDir 'node_modules') -Recurse -Force -ErrorAction SilentlyContinue
                Ok '  已准备 npm 插件（已打包为 node_modules.zip，便于拷贝分发）'; $results['npm 插件'] = 'ok'
            }
            else {
                Warn '  npm install 未生成 node_modules'
                if (Test-Path $npmLog) { Get-Content $npmLog -Tail 10 -ErrorAction SilentlyContinue | ForEach-Object { Warn "    $_" } }
                $results['npm 插件'] = '失败'
            }
        } catch { Warn ("  npm install 失败: " + $_.Exception.Message); $results['npm 插件'] = '失败' }
        finally { Pop-Location }
    } else {
        Warn '  未找到 npm（请先安装 Node.js），跳过'; $results['npm 插件'] = '跳过'
    }
}

# --- 汇总 ---
Info ''
Info '=================================================='
Info ' 离线包准备结果'
Info '=================================================='
foreach ($k in $results.Keys) {
    $v = $results[$k]
    if ($v -eq '失败') { Warn ("  {0,-16} {1}" -f $k, $v) }
    elseif ($v -eq '跳过') { Warn ("  {0,-16} {1}" -f $k, $v) }
    else { Ok ("  {0,-16} {1}" -f $k, $v) }
}
Info ''
Info (" 全部缓存: " + $CacheDir)
Ok  ' 完成。把整个文件夹拷到目标机后运行 install.cmd 即可离线安装。'
