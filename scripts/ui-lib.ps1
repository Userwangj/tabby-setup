# ============================================================
#  ui-lib.ps1 - 安装横幅 / 分步进度 / 结果汇总
#  由 install.ps1 / prefetch.ps1 / uninstall.ps1 共用。
#  依赖 cache-lib.ps1：Get-ConWidth / Get-DisplayWidth / Test-CharRenderable
#  约定：文案用中文；颜色 青=进行中/标题 绿=成功 黄=警告/跳过 红=失败 灰=次要；
#        不支持彩色/图标时（GBK、重定向、TABBY_SETUP_NO_UI=1）自动降级为纯文本。
# ============================================================

# ---- 终端能力探测：决定是否启用真彩色 / Unicode 图标 ----
$script:UiE     = [char]27
$script:UiColor = $true
$script:UiUni   = $true
try {
    if ([Console]::IsOutputRedirected) {
        $script:UiColor = $false
        $script:UiUni   = $false
    } else {
        if (-not (Test-CharRenderable ([char]0x2588))) { $script:UiUni = $false }  # 实心块
        if (-not (Test-CharRenderable ([char]0x2500))) { $script:UiUni = $false }  # 制表线
        if (-not (Test-CharRenderable ([char]0x2714))) { $script:UiUni = $false }  # 对勾
    }
} catch { $script:UiColor = $false; $script:UiUni = $false }
if ($env:TABBY_SETUP_NO_UI -eq '1') { $script:UiColor = $false; $script:UiUni = $false }

# 霓虹配色（TokyoNight 系），与安装主题同一色系
$script:UiPalette = @{
    brand  = '#7aa2f7'; accent = '#bb9af7'; ok   = '#9ece6a'; warn = '#e0af68'
    err    = '#f7768e'; dim    = '#565f89'; info = '#7dcfff'; text = '#c0caf5'
}
# 真彩色不可用时的 ConsoleColor 回退
$script:UiFallback = @{
    brand='Cyan'; accent='Magenta'; ok='Green'; warn='Yellow'
    err='Red'; dim='DarkGray'; info='Cyan'; text='Gray'
}

# ---- 开启控制台 VT（真彩色/ANSI）----
function Enable-UiConsole {
    if (-not ('Win32.ConsoleVT' -as [type])) {
        try {
            Add-Type -Namespace Win32 -Name ConsoleVT -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr h, out uint m);
[DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr h, uint m);
'@
        } catch { return }
    }
    try {
        $h = [Win32.ConsoleVT]::GetStdHandle(-11)
        $mode = 0
        if ([Win32.ConsoleVT]::GetConsoleMode($h, [ref]$mode)) { [void][Win32.ConsoleVT]::SetConsoleMode($h, $mode -bor 0x0004) }
    } catch { }
}

# ---- 颜色工具 ----
function Ui-Fg([string]$Hex) {
    if (-not $script:UiColor -or -not $Hex) { return '' }
    $h = ([string]$Hex).TrimStart('#')
    if ($h.Length -ne 6) { return '' }
    try {
        $r = [Convert]::ToInt32($h.Substring(0,2),16)
        $g = [Convert]::ToInt32($h.Substring(2,2),16)
        $b = [Convert]::ToInt32($h.Substring(4,2),16)
        return "$script:UiE[38;2;$r;$g;${b}m"
    } catch { return '' }
}
function Ui-Reset { if ($script:UiColor) { return "$script:UiE[0m" } return '' }
function Resolve-UiHex([string]$Color) {
    if ($script:UiPalette.ContainsKey($Color)) { return $script:UiPalette[$Color] }
    return $Color
}
# 统一彩色输出：$Color 可为调色板名(brand/ok/...)或 #RRGGBB
function Write-UiColor {
    param([string]$Text, [string]$Color = 'text', [switch]$NoNewline)
    $hex = Resolve-UiHex $Color
    if ($script:UiColor -and $hex -match '^#') {
        $s = (Ui-Fg $hex) + $Text + (Ui-Reset)
        if ($NoNewline) { Write-Host $s -NoNewline } else { Write-Host $s }
    } else {
        $c = 'Gray'
        if ($script:UiFallback.ContainsKey($Color)) { $c = $script:UiFallback[$Color] }
        if ($NoNewline) { Write-Host $Text -ForegroundColor $c -NoNewline } else { Write-Host $Text -ForegroundColor $c }
    }
}

# ---- 图标（Unicode），不支持时用 ASCII 文本 ----
function Ui-Icon([string]$Name) {
    $u = $script:UiUni
    switch ($Name) {
        'ok'      { if ($u) { return [string][char]0x2714 } else { return '[+]' } }  # 对勾
        'run'     { if ($u) { return [string][char]0x25B6 } else { return '>'   } }  # 三角
        'skip'    { if ($u) { return [string][char]0x25CB } else { return '[-]' } }  # 空心圆
        'fail'    { if ($u) { return [string][char]0x2718 } else { return '[x]' } }  # 叉
        'pending' { if ($u) { return [string][char]0x00B7 } else { return '.'   } }
        'clock'   { if ($u) { return [string][char]0x231B } else { return '~'   } }
    }
    return ''
}

# ---- 宽度 / 重复字符串工具 ----
function Get-UiLineWidth {
    $w = 80
    try { $w = Get-ConWidth } catch { }
    if ($w -lt 44) { $w = 44 }
    if ($w -gt 96) { $w = 96 }
    return $w
}
function Ui-Repeat([string]$Ch, [int]$N) {
    if ($N -lt 0) { $N = 0 }
    if (-not $script:UiUni) {
        switch ($Ch) {
            ([string][char]0x2500) { return ('-' * $N) }
            ([string][char]0x2550) { return ('=' * $N) }
            ([string][char]0x2588) { return ('#' * $N) }
        }
    }
    return ($Ch * $N)
}
function Ui-ProgressBar([int]$Done, [int]$Total, [int]$Width = 12) {
    if ($Total -le 0) { $Total = 1 }
    if ($Done -lt 0) { $Done = 0 }
    if ($Done -gt $Total) { $Done = $Total }
    $fullCh  = if ($script:UiUni) { [string][char]0x2588 } else { '#' }
    $emptyCh = if ($script:UiUni) { [string][char]0x2591 } else { '-' }
    $fill = [int][Math]::Round($Done / [double]$Total * $Width)
    if ($fill -gt $Width) { $fill = $Width }
    return (($fullCh * $fill) + ($emptyCh * ($Width - $fill)))
}
function Ui-PadRight([string]$Text, [int]$Width) {
    $pad = $Width - (Get-DisplayWidth $Text)
    if ($pad -lt 0) { $pad = 0 }
    return ($Text + (' ' * $pad))
}
function Set-UiTitle([string]$Text) {
    try { [Console]::Title = "Tabby 安装器 · $Text" } catch { }
}

# ============================================================
#  Logo 横幅
# ============================================================
function Show-UiBanner {
    param([string]$Subtitle = '终端配置同步 · 一键安装')
    Enable-UiConsole
    $w = Get-UiLineWidth
    Write-Host ''
    Write-UiColor ('  ' + (Ui-Repeat ([string][char]0x2500) ($w - 4))) 'dim'
    if ($script:UiUni) {
        $art = @(
            '  ████████╗ █████╗ ██████╗ ██████╗ ██╗   ██╗',
            '  ╚══██╔══╝██╔══██╗██╔══██╗██╔══██╗╚██╗ ██╔╝',
            '     ██║   ███████║██████╔╝██████╔╝ ╚████╔╝ ',
            '     ██║   ██╔══██║██╔══██╗██╔══██╗  ╚██╔╝  ',
            '     ██║   ██║  ██║██████╔╝██████╔╝   ██║   ',
            '     ╚═╝   ╚═╝  ╚═╝╚═════╝ ╚═════╝    ╚═╝   '
        )
    } else {
        $art = @(
            '   _____ _   ___ ___  __   __',
            '  |_   _/_\ | _ ) _ ) \ \ / /',
            '    | |/ _ \| _ \ _ \  \ V / ',
            '    |_/_/ \_\___/___/   |_|  '
        )
    }
    $grad = @('brand','info','accent','accent','info','brand')
    for ($i = 0; $i -lt $art.Count; $i++) { Write-UiColor $art[$i] $grad[$i % $grad.Count] }
    Write-UiColor ('  ' + $Subtitle) 'text'
    Write-UiColor ('  ' + (Ui-Repeat ([string][char]0x2500) ($w - 4))) 'dim'
    Write-Host ''
}

# ============================================================
#  步骤计划 / 进度看板
# ============================================================
$script:UiPlan  = New-Object System.Collections.ArrayList
$script:UiStart = Get-Date

# $Steps: @( @{ Index = 1; Title = 'xxx' }, ... )
function New-UiPlan {
    param([object[]]$Steps)
    $script:UiPlan = New-Object System.Collections.ArrayList
    foreach ($s in $Steps) {
        [void]$script:UiPlan.Add([pscustomobject]@{
            Index = [int]$s.Index; Title = [string]$s.Title; State = 'pending'; Note = ''
        })
    }
    $script:UiStart = Get-Date
}
function Get-UiStep([int]$Index) {
    foreach ($r in $script:UiPlan) { if ($r.Index -eq $Index) { return $r } }
    return $null
}
# 绘制步骤头（分隔线 + 进度条 + 标题），并把窗口标题更新为当前进度
function Start-UiStep {
    param([int]$Index, [string]$Title = '')
    $total = $script:UiPlan.Count
    if ($total -le 0) { $total = 9 }
    $rec = Get-UiStep $Index
    if ($rec) { $rec.State = 'running'; if ($Title) { $rec.Title = $Title } }
    else { $rec = [pscustomobject]@{ Index=$Index; Title=$Title; State='running'; Note='' } }
    $w = Get-UiLineWidth
    Write-Host ''
    Write-UiColor ('  ' + (Ui-Repeat ([string][char]0x2500) ($w - 4))) 'dim'
    $left  = '  ' + (Ui-Icon 'run') + ' 第 ' + $Index + '/' + $total + ' 步 · ' + $rec.Title
    $pct   = [int][Math]::Round(($Index - 1) / [double]$total * 100)
    $right = '[' + (Ui-ProgressBar ($Index - 1) $total 12) + '] ' + $pct + '%'
    $pad = $w - 2 - (Get-DisplayWidth $left) - (Get-DisplayWidth $right)
    if ($pad -lt 1) { $pad = 1 }
    Write-UiColor ($left + (' ' * $pad) + $right) 'brand'
    Set-UiTitle ('第 ' + $Index + '/' + $total + ' 步 · ' + $rec.Title)
}
function Set-UiStepState {
    param([int]$Index, [string]$State, [string]$Note = '')
    $rec = Get-UiStep $Index
    if ($rec) { $rec.State = $State; $rec.Note = $Note }
}
function Write-UiStepResult {
    param([string]$State, [string]$Note = '')
    switch ($State) {
        'done' { $icon = Ui-Icon 'ok';      $txt = '完成';   $col = 'ok'   }
        'skip' { $icon = Ui-Icon 'skip';    $txt = '已跳过'; $col = 'warn' }
        'fail' { $icon = Ui-Icon 'fail';    $txt = '失败';   $col = 'err'  }
        default { $icon = Ui-Icon 'pending'; $txt = '待处理'; $col = 'dim' }
    }
    $msg = '     ' + $icon + ' ' + $txt
    if ($Note) { $msg += ' · ' + $Note }
    Write-UiColor $msg $col
}
function Complete-UiStep { param([int]$Index, [string]$Note = '') Set-UiStepState $Index 'done' $Note; Write-UiStepResult 'done' $Note }
function Skip-UiStep     { param([int]$Index, [string]$Note = '') Set-UiStepState $Index 'skip' $Note; Write-UiStepResult 'skip' $Note }
function Fail-UiStep     { param([int]$Index, [string]$Note = '') Set-UiStepState $Index 'fail' $Note; Write-UiStepResult 'fail' $Note }

function Format-UiDuration([timespan]$Span) {
    if ($Span.TotalSeconds -lt 60) { return ('{0:N0} 秒' -f $Span.TotalSeconds) }
    return ('{0:N0} 分 {1:N0} 秒' -f [Math]::Floor($Span.TotalMinutes), $Span.Seconds)
}

# ============================================================
#  结果汇总看板（圆角边框 + 逐行状态）
# ============================================================
function Show-UiSummary {
    param([string]$Title = '安装结果汇总')
    if ($script:UiPlan.Count -eq 0) { return }
    $w = Get-UiLineWidth
    $inner = $w - 6
    if ($inner -lt 30) { $inner = 30 }

    $u = $script:UiUni
    $tl = if ($u) { [string][char]0x2554 } else { '+' }
    $tr = if ($u) { [string][char]0x2557 } else { '+' }
    $bl = if ($u) { [string][char]0x255A } else { '+' }
    $br = if ($u) { [string][char]0x255D } else { '+' }
    $ml = if ($u) { [string][char]0x2560 } else { '+' }
    $mr = if ($u) { [string][char]0x2563 } else { '+' }
    $hz = if ($u) { [string][char]0x2550 } else { '=' }
    $vt = if ($u) { [string][char]0x2551 } else { '|' }
    $hrule = ($hz * $inner)

    Write-Host ''
    Write-UiColor ('  ' + $tl + $hrule + $tr) 'brand'
    Write-UiColor ('  ' + $vt + (Ui-PadRight ('  ' + $Title) $inner) + $vt) 'brand'
    Write-UiColor ('  ' + $ml + $hrule + $mr) 'brand'

    $total = $script:UiPlan.Count
    foreach ($r in $script:UiPlan) {
        switch ($r.State) {
            'done' { $icon = Ui-Icon 'ok';      $col = 'ok';   $st = '完成'   }
            'skip' { $icon = Ui-Icon 'skip';    $col = 'warn'; $st = '已跳过' }
            'fail' { $icon = Ui-Icon 'fail';    $col = 'err';  $st = '失败'   }
            'running' { $icon = Ui-Icon 'run';  $col = 'info'; $st = '进行中' }
            default { $icon = Ui-Icon 'pending'; $col = 'dim'; $st = '未执行' }
        }
        if ($r.Note) { $st = $st + ' · ' + $r.Note }
        $left  = ' ' + $icon + ' ' + $r.Index + '/' + $total + '  ' + $r.Title
        $pad   = $inner - (Get-DisplayWidth $left) - (Get-DisplayWidth $st) - 1
        if ($pad -lt 1) { $pad = 1 }
        $row = $left + (' ' * $pad) + $st + ' '
        Write-UiColor ('  ' + $vt + $row + $vt) $col
    }
    Write-UiColor ('  ' + $bl + $hrule + $br) 'brand'

    $elapsed = (Get-Date) - $script:UiStart
    Write-UiColor ('  ' + (Ui-Icon 'clock') + ' 总用时 ' + (Format-UiDuration $elapsed)) 'dim'
    Write-Host ''
}
