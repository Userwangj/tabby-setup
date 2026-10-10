<#
    Tabby Neon 主题切换器（tabbytheme 命令）
    ------------------------------------------------------------
    列出 8 个霓虹配色方案，实时真彩色预览，选编号即应用到 Tabby
    （colorScheme + 霓虹发光 CSS），并自动重启 Tabby。
    只改配色 / 外观，不动字体 / 插件 / 其他配置。
    用法：
      在 Tabby 里直接运行   tabbytheme
      或 powershell -ExecutionPolicy Bypass -File switch-theme.ps1
#>

$ErrorActionPreference = 'Continue'
$Esc = [char]27

# ---- 显式选择：必须输入 Allowed 之一；回车/无效会重问，防止误触回车 ----
function Read-Choice {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][string[]]$Allowed,
        [string]$DefaultOnFail = '',
        [int]$MaxTries = 5
    )
    if ([string]::IsNullOrEmpty($DefaultOnFail)) { $DefaultOnFail = $Allowed[0] }
    try { $Host.UI.RawUI.FlushInputBuffer() } catch { }
    $allowedTxt = ($Allowed -join ' / ')
    for ($i = 0; $i -lt $MaxTries; $i++) {
        $ans = ''
        try { $ans = Read-Host $Prompt } catch { $ans = '' }
        $v = ([string]$ans).Trim().ToLowerInvariant()
        if ($Allowed -contains $v) { return $v }
        if ([string]::IsNullOrWhiteSpace($v)) {
            Write-Host ('   请直接输入 ' + $allowedTxt + '（不要直接回车）。') -ForegroundColor Yellow
        } else {
            Write-Host ('   无效输入，请输入 ' + $allowedTxt + '。') -ForegroundColor Yellow
        }
    }
    Write-Host ('   多次无效输入，默认按 ' + $DefaultOnFail + ' 处理。') -ForegroundColor Yellow
    return $DefaultOnFail
}

$cfg = Join-Path $env:APPDATA 'tabby\config.yaml'
$utf8 = New-Object System.Text.UTF8Encoding($false)

if (-not ('Win32.ConsoleVT' -as [type])) {
    try {
        Add-Type -Namespace Win32 -Name ConsoleVT -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr h, out uint m);
[DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr h, uint m);
'@
        $h = [Win32.ConsoleVT]::GetStdHandle(-11)
        $mode = 0
        if ([Win32.ConsoleVT]::GetConsoleMode($h, [ref]$mode)) { [void][Win32.ConsoleVT]::SetConsoleMode($h, $mode -bor 0x0004) }
    } catch { }
}

function Hex-ToRgb([string]$hex) {
    $h = $hex.TrimStart('#')
    return @([Convert]::ToInt32($h.Substring(0,2),16), [Convert]::ToInt32($h.Substring(2,2),16), [Convert]::ToInt32($h.Substring(4,2),16))
}
function Ansi-Fg([string]$hex) { $r = Hex-ToRgb $hex; return "$Esc[38;2;$($r[0]);$($r[1]);$($r[2])m" }
function Ansi-Bg([string]$hex) { $r = Hex-ToRgb $hex; return "$Esc[48;2;$($r[0]);$($r[1]);$($r[2])m" }

$Themes = @(
    @{ Name="Synthwave '84";   Fore='#ffffff'; Back='#262335'; Cursor='#ff7edb'; Colors=@('#262335','#fe4450','#72f1b8','#fede5d','#03edf9','#ff7edb','#03edf9','#ffffff','#495495','#fe4450','#72f1b8','#fede5d','#03edf9','#ff7edb','#03edf9','#ffffff') },
    @{ Name='Cyberpunk 2077';  Fore='#e8e8e8'; Back='#000000'; Cursor='#00f0ff'; Colors=@('#000000','#ff003c','#00ff9f','#fcee0a','#00f0ff','#ff00ff','#00f0ff','#d0d0d0','#505050','#ff003c','#00ff9f','#fcee0a','#00f0ff','#ff00ff','#00f0ff','#ffffff') },
    @{ Name='Neon Tokyo';      Fore='#e0e0ff'; Back='#0a0a12'; Cursor='#39ff14'; Colors=@('#0a0a12','#ff2a6d','#05ffa1','#f9f871','#b967ff','#ff71ce','#01cdfe','#e0e0ff','#3d3d5c','#ff2a6d','#05ffa1','#f9f871','#b967ff','#ff71ce','#01cdfe','#ffffff') },
    @{ Name='Aurora';          Fore='#d8e0e8'; Back='#0b0f14'; Cursor='#00ff9f'; Colors=@('#0b0f14','#ff5c8a','#00ff9f','#ffd93d','#00d9ff','#b388ff','#00ffc6','#d8e0e8','#2a3a4a','#ff5c8a','#00ff9f','#ffd93d','#00d9ff','#b388ff','#00ffc6','#ffffff') },
    @{ Name='Vaporwave';       Fore='#f8d7ff'; Back='#1a0b2e'; Cursor='#ff6ac1'; Colors=@('#1a0b2e','#ff6ac1','#72f1b8','#fede5d','#b967ff','#ff71ce','#01cdfe','#f8d7ff','#3d2b56','#ff6ac1','#72f1b8','#fede5d','#b967ff','#ff71ce','#01cdfe','#ffffff') },
    @{ Name='Matrix';          Fore='#00ff41'; Back='#000000'; Cursor='#00ff41'; Colors=@('#000000','#ff5555','#00ff41','#ccff00','#00ff41','#00cc33','#00ffcc','#b3ffb3','#003b00','#ff6666','#33ff66','#ddff33','#00ff41','#00cc33','#00ffcc','#e6ffe6') },
    @{ Name='Dracula';         Fore='#f8f8f2'; Back='#1e1f29'; Cursor='#bbbbbb'; Colors=@('#000000','#ff5555','#50fa7b','#f1fa8c','#bd93f9','#ff79c6','#8be9fd','#bbbbbb','#555555','#ff5555','#50fa7b','#f1fa8c','#bd93f9','#ff79c6','#8be9fd','#ffffff') },
    @{ Name='TokyoNight Storm'; Fore='#c0caf5'; Back='#24283b'; Cursor='#c0caf5'; Colors=@('#1d202f','#f7768e','#9ece6a','#e0af68','#7aa2f7','#bb9af7','#7dcfff','#a9b1d6','#414868','#f7768e','#9ece6a','#e0af68','#7aa2f7','#bb9af7','#7dcfff','#c0caf5') }
)

$NeonCss = @'
/* terminal scrollbar */
.xterm-viewport::-webkit-scrollbar { width: 9px; }
.xterm-viewport::-webkit-scrollbar-track { background: transparent; }
.xterm-viewport::-webkit-scrollbar-thumb { background: var(--theme-bg-more-2); border-radius: 5px; }
.xterm-viewport::-webkit-scrollbar-thumb:hover { background: var(--theme-primary); }

/* neon tab bar (high specificity to beat tabby default theme) */
app-root .main.content .tab-bar { border-bottom: 1px solid var(--theme-primary) !important; }
app-root .main.content .tab-bar > .tabs tab-header { border-radius: 9px 9px 0 0; transition: all .15s ease; }
app-root .main.content .tab-bar > .tabs tab-header:hover { background: var(--theme-bg-more) !important; }
app-root .main.content .tab-bar > .tabs tab-header.active {
  background: linear-gradient(180deg, var(--theme-bg-more), transparent) !important;
  box-shadow: inset 0 -2px 0 var(--theme-primary), 0 0 16px -4px var(--theme-primary) !important;
}
app-root .main.content .tab-bar > .tabs tab-header.active .current-tab-indicator {
  background: var(--theme-primary) !important;
  box-shadow: 0 0 8px var(--theme-primary), 0 0 20px var(--theme-primary) !important;
}
app-root .main.content .tab-bar .btn-tab-bar:hover { color: var(--theme-primary) !important; filter: drop-shadow(0 0 6px var(--theme-primary)); }
'@

function Show-ThemePreview($t) {
    $reset = "$Esc[0m"
    $bg = Ansi-Bg $t.Back
    $fg = Ansi-Fg $t.Fore
    $c = $t.Colors
    $parts = @(
        @{ t = ' user@host'; c = $t.Fore },
        @{ t = '  ~/project'; c = $c[4] },
        @{ t = '  (main)'; c = $c[2] },
        @{ t = '  ERROR'; c = $c[1] },
        @{ t = '  WARN'; c = $c[3] },
        @{ t = '  OK'; c = $c[2] },
        @{ t = '  src/'; c = $c[4] },
        @{ t = '  build.py'; c = $c[5] }
    )
    $plain = -join ($parts | ForEach-Object { $_.t })
    $ansi  = -join ($parts | ForEach-Object { (Ansi-Fg $_.c) + $_.t })
    $pad = 62 - $plain.Length
    if ($pad -lt 0) { $pad = 0 }
    $bar = (Ansi-Bg $c[4]) + (' ' * 5) + $reset + (Ansi-Bg $c[5]) + (' ' * 5) + $reset + (Ansi-Bg $c[6]) + (' ' * 5) + $reset
    Write-Host ("      " + $bg + $fg + $ansi + (' ' * $pad) + $reset + "  " + $bar)
}

function Stop-TabbySafe {
    Get-Process -Name Tabby -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    $n = 0
    while ((Get-Process -Name Tabby -ErrorAction SilentlyContinue) -and $n -lt 40) { Start-Sleep -Milliseconds 250; $n++ }
    Start-Sleep -Milliseconds 700
}

function Read-ConfigSafe($cfgPath) {
    $content = [System.IO.File]::ReadAllText($cfgPath, [Text.Encoding]::UTF8)
    if ($content -notmatch '(?m)^version:\s*\d') {
        $bak = Join-Path (Split-Path -Parent $cfgPath) 'config.yaml.backup'
        Write-Host '  config.yaml looks corrupt - trying backup...' -ForegroundColor Yellow
        if (Test-Path $bak) { $content = [System.IO.File]::ReadAllText($bak, [Text.Encoding]::UTF8) }
    }
    if ($content -notmatch '(?m)^version:\s*\d') { throw 'config.yaml is invalid and no usable backup exists.' }
    return $content
}

function Write-ConfigSafe($cfgPath, $content) {
    if ([string]::IsNullOrWhiteSpace($content) -or ($content -notmatch '(?m)^version:\s*\d')) {
        throw 'Generated config failed sanity check - NOT written (your config is untouched).'
    }
    $dir = Split-Path -Parent $cfgPath
    if (Test-Path $cfgPath) {
        $prev = [System.IO.File]::ReadAllText($cfgPath, [Text.Encoding]::UTF8)
        if ($prev -match '(?m)^version:\s*\d') {
            Copy-Item -LiteralPath $cfgPath -Destination (Join-Path $dir 'config.yaml.backup') -Force -ErrorAction SilentlyContinue
        }
    }
    # atomic write: temp file -> rename over the real config (never leaves a partial/zeroed file)
    $tmp = Join-Path $dir 'config.yaml.tmp'
    [System.IO.File]::WriteAllText($tmp, $content, (New-Object System.Text.UTF8Encoding($false)))
    if ((Get-Item -LiteralPath $tmp).Length -lt 200) { throw 'Temp config too small - NOT applied.' }
    Move-Item -LiteralPath $tmp -Destination $cfgPath -Force
}

function Apply-Theme($cfgPath, $theme, $css) {
    $content = Read-ConfigSafe $cfgPath
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("  colorScheme:`n")
    [void]$sb.Append("    name: $($theme.Name)`n")
    [void]$sb.Append("    foreground: '$($theme.Fore)'`n")
    [void]$sb.Append("    background: '$($theme.Back)'`n")
    [void]$sb.Append("    cursor: '$($theme.Cursor)'`n")
    [void]$sb.Append("    colors:`n")
    foreach ($c in $theme.Colors) { [void]$sb.Append("      - '$c'`n") }
    $csBlock = $sb.ToString()
    $rxCs = [regex]'(?s)  colorScheme:.*?(?=  lightColorScheme:)'
    $content = $rxCs.Replace($content, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $csBlock }, 1)

    $cssLines = $css -split "`r?`n"
    $cssBlock = "  css: |-`n" + (($cssLines | ForEach-Object { "    " + $_ }) -join "`n") + "`n"
    $rxCss = [regex]'(?ms)^  css:.*?(?=^\S)'
    $content = $rxCss.Replace($content, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $cssBlock }, 1)

    Write-ConfigSafe $cfgPath $content
}

Write-Host ''
Write-Host '  ========== Tabby NEON Themes ==========' -ForegroundColor Cyan
Write-Host ''
for ($i = 0; $i -lt $Themes.Count; $i++) {
    Write-Host ("    [{0}] {1}" -f ($i + 1), $Themes[$i].Name) -ForegroundColor White
    Show-ThemePreview $Themes[$i]
    Write-Host ''
}
Write-Host '    [0] Cancel (preview only, no change)' -ForegroundColor DarkGray
Write-Host ''

$allowed = @('0')
for ($i = 1; $i -le $Themes.Count; $i++) { $allowed += [string]$i }
$ans = Read-Choice -Prompt ("  Enter number to APPLY (1-$($Themes.Count), 0 = cancel)") -Allowed $allowed -DefaultOnFail '0'

if ($ans -match '^\s*\d+\s*$') {
    $n = [int]$ans.Trim()
    if ($n -ge 1 -and $n -le $Themes.Count) {
        $theme = $Themes[$n - 1]
        Stop-TabbySafe
        Apply-Theme $cfg $theme $NeonCss
        Write-Host ''
        Write-Host "  Applied: $($theme.Name)  (accent: $($theme.Colors[4]))" -ForegroundColor Green
        # auto-restart Tabby so the change is visible immediately
        $tabbyExe = @(
            (Join-Path $env:LOCALAPPDATA 'Programs\Tabby\Tabby.exe'),
            (Join-Path $env:LOCALAPPDATA 'Programs\tabby\Tabby.exe')
        ) | Where-Object { Test-Path $_ } | Select-Object -First 1
        if ($tabbyExe) {
            Start-Process $tabbyExe
            Write-Host '  Tabby restarted - open a NEW tab to see the new colors.' -ForegroundColor Green
        } else {
            Write-Host '  Restart Tabby manually to see the new color scheme + neon glow.' -ForegroundColor Green
        }
        Write-Host ''
        exit 0
    }
}
Write-Host ''
Write-Host '  No change made.' -ForegroundColor Yellow
Write-Host ''
