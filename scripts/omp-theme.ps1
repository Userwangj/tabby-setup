# oh-my-posh 炫酷主题选择器（omp 命令）
# 用法：在 Tabby 里直接运行 omp，选择编号即可在真彩色下预览并应用
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}

function Find-Omp {
    $cands = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\oh-my-posh.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\oh-my-posh\oh-my-posh.exe'),
        (Join-Path $env:ProgramFiles 'oh-my-posh\bin\oh-my-posh.exe'),
        'C:\Program Files\oh-my-posh\bin\oh-my-posh.exe'
    )
    foreach ($c in $cands) { if ($c -and (Test-Path $c)) { return $c } }
    $cmd = Get-Command 'oh-my-posh.exe' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Find-ThemesDir {
    $cands = @()
    # Store 版：用 Get-AppxPackage（直接列举 WindowsApps 会被拒绝访问）
    $pkg = Get-AppxPackage -Name '*ohmyposh*' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pkg -and $pkg.InstallLocation) { $cands += (Join-Path $pkg.InstallLocation 'themes') }
    # winget / 手动安装
    $cands += 'C:\Program Files\oh-my-posh\themes'
    $cands += (Join-Path $env:LOCALAPPDATA 'Programs\oh-my-posh\themes')
    # exe 同目录
    if ($OmpExe) { $cands += (Join-Path (Split-Path $OmpExe -Parent) 'themes') }
    foreach ($c in $cands) { if ($c -and (Test-Path $c)) { return $c } }
    return $null
}

$OmpExe    = Find-Omp
$ThemesDir = Find-ThemesDir
$Target    = Join-Path $env:USERPROFILE 'bin\oh-my-posh.omp.json'
$NameFile  = Join-Path $env:USERPROFILE 'bin\oh-my-posh.theme.txt'

if (-not $OmpExe)    { Write-Host '  未找到 oh-my-posh，请先: winget install JanDeDobbeleer.OhMyPosh' -ForegroundColor Red; exit 1 }
if (-not $ThemesDir) { Write-Host '  未找到 oh-my-posh 主题目录' -ForegroundColor Red; exit 1 }

# 精选炫酷主题
$Curated = [ordered]@{
    'atomic'                = '现代两行 · 图标+git · 简约炫'
    'jandedobbeleer'        = '经典彩色分段 · 默认风'
    'powerlevel10k_rainbow' = '彩虹分段 · 最炫'
    'paradox'               = '粗体 Powerline · 硬核'
    'aliens'                = '太空异形风'
    'montys'                = '清爽多彩 · 圆角'
    'smoothie'              = '柔和渐变'
    'velvet'                = '紫罗兰丝绒'
    'blueish'               = '冰蓝冷色'
    '1_shell'               = 'Windows 磁贴风'
    'tonybaloney'           = '企鹅橙 · 活泼'
    'M365Princess'          = '微软公主风'
    'clean-detailed'        = '干净细致'
    'darkblood'             = '暗血红'
    'craver'                = '暗色分段'
    'nu4a'                  = '极简图标'
}

function Get-ThemePath([string]$name) {
    $f = Join-Path $ThemesDir ($name + '.omp.json')
    if (Test-Path $f) { return $f }
    return $null
}

function Get-CurrentTheme {
    if (Test-Path $NameFile) { return (Get-Content $NameFile -Raw).Trim() }
    return ''
}

function Show-Preview([string]$name) {
    $f = Get-ThemePath $name
    if (-not $f) { Write-Host ('  主题不存在: ' + $name) -ForegroundColor Red; return }
    Write-Host ''
    Write-Host ('  ── 预览: ' + $name + ' ──') -ForegroundColor DarkGray
    Write-Host ''
    & $OmpExe print primary --config $f --shell pwsh
    Write-Host ''
}

function Apply-Theme([string]$name) {
    $f = Get-ThemePath $name
    if (-not $f) { Write-Host ('  主题不存在: ' + $name) -ForegroundColor Red; return }
    $bin = Split-Path $Target -Parent
    if (-not (Test-Path $bin)) { New-Item -ItemType Directory -Path $bin -Force | Out-Null }
    Copy-Item $f $Target -Force
    Set-Content -Path $NameFile -Value $name -Encoding ASCII
    Write-Host ''
    Write-Host ('  已应用: ' + $name + '  ->  ' + $Target) -ForegroundColor Green
    Write-Host '  开一个新标签页即可看到新提示符（profile 在 PowerShell 启动时加载）' -ForegroundColor Green
    Write-Host ''
}

$cur = Get-CurrentTheme

while ($true) {
    Write-Host ''
    Write-Host '  ========== oh-my-posh 炫酷主题 ==========' -ForegroundColor Magenta
    $i = 0
    $map = @()
    foreach ($k in $Curated.Keys) {
        $i++
        $map += $k
        $star = ''
        if ($k -eq $cur) { $star = '   *当前' }
        Write-Host ('   {0,2}) {1,-22} {2}{3}' -f $i, $k, $Curated[$k], $star)
    }
    Write-Host ''
    Write-Host '    L) 列出全部主题并预览    Q) 退出' -ForegroundColor DarkGray
    Write-Host ''
    $sel = Read-Host '  选择编号'
    if ([string]::IsNullOrWhiteSpace($sel)) { continue }
    if ($sel -match '^(q|Q)$') { break }

    if ($sel -match '^(l|L)$') {
        Write-Host ''
        $all = Get-ChildItem $ThemesDir -Filter *.omp.json | Sort-Object Name | ForEach-Object { $_.BaseName }
        Write-Host ('  全部 ' + $all.Count + ' 个主题:') -ForegroundColor DarkGray
        Write-Host ('   ' + ($all -join ', ')) -ForegroundColor DarkGray
        Write-Host ''
        $nm = Read-Host '  输入主题名预览 (回车返回)'
        if (-not [string]::IsNullOrWhiteSpace($nm)) {
            $nm = $nm.Trim()
            if (-not (Get-ThemePath $nm)) { Write-Host ('  主题不存在: ' + $nm) -ForegroundColor Red; continue }
            Show-Preview $nm
            $yn = Read-Host ('  应用 ' + $nm + ' ? (y/N)')
            if ($yn -match '^(y|Y)') { Apply-Theme $nm; $cur = $nm }
        }
        continue
    }

    if ($sel -match '^\d+$') {
        $n = [int]$sel
        if ($n -ge 1 -and $n -le $map.Count) {
            $name = $map[$n - 1]
            if (-not (Get-ThemePath $name)) { Write-Host ('  主题不存在: ' + $name) -ForegroundColor Red; continue }
            Show-Preview $name
            $yn = Read-Host ('  应用 ' + $name + ' ? (y/N)')
            if ($yn -match '^(y|Y)') { Apply-Theme $name; $cur = $name }
        }
    }
}
