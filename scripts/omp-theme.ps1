# oh-my-posh 提示符主题选择器（omp 命令）
# 参考开源项目的做法：
#   poshpicker (jakemorgangit) —— 单键 n/p 导航 + 实时预览 + 保存应用
#   oh-my-theme (mikeisfree)   —— 浏览/搜索全部主题
# 用法：在 Tabby 里运行 omp：
#   n / ↓ 下一个      p / ↑ 上一个      Enter 应用      a 切换 全部/精选      q 退出
# 说明：本脚本在真实终端里【裸调用】oh-my-posh 渲染预览（不捕获输出），
#       所以能探测真实控制台宽度、右对齐正确（图标需 Nerd Font 字体）。
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
    $pkg = Get-AppxPackage -Name '*ohmyposh*' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pkg -and $pkg.InstallLocation) { $cands += (Join-Path $pkg.InstallLocation 'themes') }
    $cands += 'C:\Program Files\oh-my-posh\themes'
    $cands += (Join-Path $env:LOCALAPPDATA 'Programs\oh-my-posh\themes')
    if ($OmpExe) { $cands += (Join-Path (Split-Path $OmpExe -Parent) 'themes') }
    foreach ($c in $cands) { if ($c -and (Test-Path $c)) { return $c } }
    return $null
}

function Clear-PendingInput { try { $Host.UI.RawUI.FlushInputBuffer() } catch { } }

# 纯函数：把一次按键映射为动作（便于单测）。
# 返回 'next' | 'prev' | 'first' | 'last' | 'apply' | 'quit' | 'toggle' | 'none'
function Resolve-ThemeKey {
    param([System.ConsoleKey]$Key, [char]$KeyChar)
    if ($Key -eq [System.ConsoleKey]::Enter)  { return 'apply' }
    if ($Key -eq [System.ConsoleKey]::Escape) { return 'quit' }
    if ($Key -eq [System.ConsoleKey]::UpArrow -or $Key -eq [System.ConsoleKey]::LeftArrow)    { return 'prev' }
    if ($Key -eq [System.ConsoleKey]::DownArrow -or $Key -eq [System.ConsoleKey]::RightArrow) { return 'next' }
    if ($Key -eq [System.ConsoleKey]::Home) { return 'first' }
    if ($Key -eq [System.ConsoleKey]::End)  { return 'last' }
    $ch = ''
    if ([int]$KeyChar -ne 0) { $ch = ([string]$KeyChar).ToLowerInvariant() }
    if ($ch -eq 'n' -or $ch -eq 'j') { return 'next' }
    if ($ch -eq 'p' -or $ch -eq 'k') { return 'prev' }
    if ($ch -eq 'q') { return 'quit' }
    if ($ch -eq 'a') { return 'toggle' }
    return 'none'
}

$OmpExe    = Find-Omp
$ThemesDir = Find-ThemesDir
$Target    = Join-Path $env:USERPROFILE 'bin\oh-my-posh.omp.json'
$NameFile  = Join-Path $env:USERPROFILE 'bin\oh-my-posh.theme.txt'

if (-not $OmpExe)    { Write-Host '  未找到 oh-my-posh，请先: winget install JanDeDobbeleer.OhMyPosh' -ForegroundColor Red; exit 1 }
if (-not $ThemesDir) { Write-Host '  未找到 oh-my-posh 主题目录' -ForegroundColor Red; exit 1 }

# 精选炫酷主题（带中文说明）
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
    if ([string]::IsNullOrWhiteSpace($name)) { return $null }
    $f = Join-Path $ThemesDir ($name + '.omp.json')
    if (Test-Path $f) { return $f }
    return $null
}

function Get-CurrentTheme {
    if (Test-Path $NameFile) { $t = (Get-Content $NameFile -Raw).Trim(); if ($t) { return $t } }
    return ''
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

function Get-CuratedList {
    $l = @()
    foreach ($k in $Curated.Keys) { if (Get-ThemePath $k) { $l += $k } }
    return $l
}
function Get-AllList {
    return @(Get-ChildItem $ThemesDir -Filter *.omp.json -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object { $_.BaseName })
}

# 渲染一屏：标题 + 主题名/说明 + 真实预览（裸调用）+ 快捷键提示
function Show-ThemeScreen {
    param($List, [int]$Idx, [string]$Mode, [string]$Cur)
    try { Clear-Host } catch { }
    $n = [int]$List.Count
    if ($n -eq 0) { return }
    $name = [string]$List[$Idx]
    $desc = ''
    if ($Curated.Contains($name)) { $desc = [string]$Curated[$name] }
    $modeTxt = '精选 ' + $n
    if ($Mode -eq 'all') { $modeTxt = '全部 ' + $n }
    $star = ''
    if ($name -eq $Cur) { $star = '   *当前' }
    Write-Host ''
    Write-Host ('  ===== oh-my-posh 主题选择  [' + $modeTxt + ']  ' + ($Idx + 1) + '/' + $n + ' =====') -ForegroundColor Magenta
    Write-Host ('   ' + $name + '   ' + $desc + $star) -ForegroundColor White
    Write-Host ''
    $f = Get-ThemePath $name
    if ($OmpExe -and $f) { & $OmpExe print primary --config $f --shell pwsh }
    Write-Host ''
    Write-Host '  n/↓ 下一个    p/↑ 上一个    Enter 应用    a 全部/精选    q 退出' -ForegroundColor DarkGray
    Write-Host '  提示：图标需 Nerd Font 字体；此处即为真实终端效果。' -ForegroundColor DarkGray
}

$cur         = Get-CurrentTheme
$curatedList = Get-CuratedList
$allList     = Get-AllList
$mode = 'curated'
$list = $curatedList
if ($list.Count -eq 0) { $mode = 'all'; $list = $allList }
if ($list.Count -eq 0) { Write-Host '  未找到任何主题' -ForegroundColor Red; exit 1 }
$idx = 0
for ($i = 0; $i -lt $list.Count; $i++) { if ($list[$i] -eq $cur) { $idx = $i; break } }

$interactive = $false
try { $interactive = -not ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) } catch { $interactive = $false }

if ($interactive) {
    while ($true) {
        Show-ThemeScreen -List $list -Idx $idx -Mode $mode -Cur $cur
        $key = [Console]::ReadKey($true)
        $done = $false
        switch (Resolve-ThemeKey -Key $key.Key -KeyChar $key.KeyChar) {
            'apply' {
                Apply-Theme $list[$idx]
                $done = $true
            }
            'quit'  { $done = $true }
            'prev'  { $idx-- }
            'next'  { $idx++ }
            'first' { $idx = 0 }
            'last'  { $idx = $list.Count - 1 }
            'toggle' {
                if ($mode -eq 'all') { $mode = 'curated'; $list = $curatedList } else { $mode = 'all'; $list = $allList }
                if ($list.Count -eq 0) { $mode = 'all'; $list = $allList }
                $idx = 0
            }
        }
        if ($done) { break }
        if ($list.Count -gt 0) {
            if ($idx -lt 0) { $idx = $list.Count - 1 }
            if ($idx -ge $list.Count) { $idx = 0 }
        }
    }
} else {
    # 非交互（输出被重定向）：退化为输入编号
    Write-Host ''
    Write-Host '  ===== oh-my-posh 主题（非交互：输入编号）=====' -ForegroundColor Magenta
    $i = 0
    foreach ($nm in $list) { $i++; Write-Host ('   {0,3}) {1}' -f $i, $nm) }
    Write-Host ''
    Clear-PendingInput
    $sel = Read-Host '  选择编号（回车退出）'
    if ($sel -match '^\d+$') {
        $n = [int]$sel
        if ($n -ge 1 -and $n -le $list.Count) { Apply-Theme $list[$n - 1] }
    }
}
