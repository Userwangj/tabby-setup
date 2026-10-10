<#
    Tabby Terminal - One-click Setup / Sync Script
    ------------------------------------------------------------
    Prefers a pre-downloaded offline cache (cache\): a device with no/slow
    GitHub access can then install fully offline (run prefetch.cmd first).
      0. Auto-detect (no flags needed): no network -> use prepared pack;
         network + no updates -> silently use pack; network + updates -> ask
         (default = prepared); no pack -> online download (or stop if offline)
      1. Tabby terminal   (cache -> direct download -> winget)
      2. config.yaml      (font / terminal / quick commands)
      3. Neon color theme  (interactive picker with live ANSI preview
                            + neon-glow CSS enhancement)
      4. JetBrainsMono Nerd Font (cache/online; user-level, no admin)
      5. PowerShell 7 (pwsh) + CompletionPredictor (cache -> winget ->
         mirrored MSIX); Tabby default shell ->
         local:powershell-core (falls back to Windows PowerShell)
      6. oh-my-posh prompt (cache -> winget -> portable exe; theme +
                            PowerShell profile; "omp" to switch themes)
      7. Node.js if needed (cache -> winget -> nodejs.org zip)
         then 8 npm plugins (cache -> npm install)
      8. tabbyhelp / tabbycolors / tabbytheme commands
      9. Start Tabby
    Usage:
      powershell -ExecutionPolicy Bypass -File install.ps1
      powershell -ExecutionPolicy Bypass -File install.ps1 -Theme "Cyberpunk 2077"
      powershell -ExecutionPolicy Bypass -File install.ps1 -Offline        # cache only, never network
      powershell -ExecutionPolicy Bypass -File install.ps1 -Online         # always latest
      powershell -ExecutionPolicy Bypass -File install.ps1 -Yes            # never ask (auto default)
      powershell -ExecutionPolicy Bypass -File install.ps1 -Ours           # 已有 pwsh/omp 时直接用本程序版本
    Note: 若本机已安装 PowerShell 7 / oh-my-posh，安装时会询问：
          [1] 保留本机版本（默认，完全不改动它的配置）
          [2] 安装本程序版本（会覆盖本机相同程序的配置）
    Prepare the offline cache first with:  prefetch.cmd
    Theme names: Synthwave '84, Cyberpunk 2077, Neon Tokyo, Aurora,
                 Vaporwave, Matrix, Dracula, TokyoNight Storm
#>

param(
    [string]$Theme = '',  # preset theme name; empty = interactive picker
    [switch]$Offline,     # 只用离线包，绝不联网下载
    [switch]$Online,      # 总是在线下载最新版
    [switch]$Yes,         # 全部接受默认（完全不交互）
    [switch]$Ours         # 检测到已有 pwsh/oh-my-posh 时，直接用本程序的版本（覆盖）
)

$ErrorActionPreference = 'Continue'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$RootDir   = Split-Path -Parent $ScriptDir
$CacheDir  = Join-Path $RootDir 'cache'
$AssetsDir = Join-Path $RootDir 'assets'
$TabbyDir  = Join-Path $env:APPDATA 'tabby'
$PluginDir = Join-Path $TabbyDir 'plugins'
$BinDir    = Join-Path $env:USERPROFILE 'bin'
$Esc = [char]27

function Info($m) { Write-Host $m -ForegroundColor Cyan }
function Ok($m)   { Write-Host $m -ForegroundColor Green }
function Warn($m) { Write-Host $m -ForegroundColor Yellow }

# 检测到本机已有 pwsh/oh-my-posh 时询问：用本程序的版本（覆盖）还是保留本机版本（完全不碰）
# 返回 'ours' 或 'keep'（默认 keep）
function Select-ExistingAction([string]$Name, [string]$Path) {
    Write-Host ''
    Warn  "  检测到本机已安装 $Name：$Path"
    Write-Host '    [1] 保留本机现有版本（不安装本程序版本，且完全不改动它的配置）' -ForegroundColor White
    Write-Host '    [2] 安装本程序的版本  <-- 注意：会覆盖本机相同程序的配置' -ForegroundColor White
    $ans = ''
    try { $ans = Read-Host '  选择 [1/2]（默认 1）' } catch { $ans = '' }
    if ($ans -match '^\s*2\s*$') { return 'ours' }
    return 'keep'
}

# ---- 离线包共享库（进度下载 / manifest / 版本检查）----
. (Join-Path $ScriptDir 'cache-lib.ps1')

# ---- 运行模式: ask(默认) / cache(-Offline) / online(-Online) ----
$RunMode = 'ask'
if ($Offline) { $RunMode = 'cache' }
if ($Online)  { $RunMode = 'online' }
$AutoYes = [bool]$Yes

function Find-Tabby {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Tabby\Tabby.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\tabby\Tabby.exe'),
        'C:\Program Files\Tabby\Tabby.exe',
        'C:\Program Files (x86)\Tabby\Tabby.exe'
    )
    foreach ($p in $candidates) { if (Test-Path $p) { return $p } }
    return $null
}

function Update-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
}

# ---- ANSI true-color helpers (for theme preview) ----
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

# ---- Neon theme presets (colors[4] becomes the UI accent color) ----
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

# ---- Neon-glow UI enhancement (uses theme CSS variables, adapts to any theme) ----
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

function Select-Theme {
    Write-Host ''
    Write-Host '  ========== Choose a NEON color theme ==========' -ForegroundColor Cyan
    Write-Host ''
    for ($i = 0; $i -lt $Themes.Count; $i++) {
        Write-Host ("    [{0}] {1}" -f ($i + 1), $Themes[$i].Name) -ForegroundColor White
        Show-ThemePreview $Themes[$i]
        Write-Host ''
    }
    $ans = ''
    try { $ans = Read-Host '  Enter number 1-8 (Enter = default 8: TokyoNight Storm)' } catch { $ans = '' }
    $idx = $Themes.Count - 1   # default last (TokyoNight Storm)
    if ($ans -match '^\s*\d+\s*$') {
        $n = [int]$ans.Trim()
        if ($n -ge 1 -and $n -le $Themes.Count) { $idx = $n - 1 }
    }
    return $Themes[$idx]
}

function Stop-TabbySafe {
    Get-Process -Name Tabby -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    $n = 0
    while ((Get-Process -Name Tabby -ErrorAction SilentlyContinue) -and $n -lt 40) { Start-Sleep -Milliseconds 250; $n++ }
    Start-Sleep -Milliseconds 700   # let Tabby finish any pending config write
}

function Read-ConfigSafe($cfgPath) {
    $content = [System.IO.File]::ReadAllText($cfgPath, [Text.Encoding]::UTF8)
    if ($content -notmatch '(?m)^version:\s*\d') {
        $bak = Join-Path (Split-Path -Parent $cfgPath) 'config.yaml.backup'
        Warn "       config.yaml looks corrupt - trying $bak"
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
    # keep a recovery copy of the previous good config (Tabby auto-recovers from config.yaml.backup)
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

    # --- replace terminal.colorScheme block ---
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

    # --- replace appearance.css block ---
    $cssLines = $css -split "`r?`n"
    $cssBlock = "  css: |-`n" + (($cssLines | ForEach-Object { "    " + $_ }) -join "`n") + "`n"
    $rxCss = [regex]'(?ms)^  css:.*?(?=^\S)'
    $content = $rxCss.Replace($content, [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $cssBlock }, 1)

    Write-ConfigSafe $cfgPath $content
}

Info '=================================================='
Info ' Tabby Terminal Setup / Sync'
Info '=================================================='

# --- 0. Stop Tabby (config is overwritten on exit) ---
Stop-TabbySafe

$winget = Get-Command winget -ErrorAction SilentlyContinue

# ---- 离线包 / 版本检查（默认用已准备版本；有更新时让用户选）----
$manifest = Get-CacheManifest $CacheDir
$pref = Invoke-VersionCheck -CacheDir $CacheDir -Manifest $manifest -Mode $RunMode -Yes $AutoYes
if ($pref -and $pref.ContainsKey('__cancel')) { Warn '安装已结束（见上方提示）。'; exit 0 }
if ($RunMode -eq 'cache' -and -not (Test-Path $CacheDir)) { Warn '  [离线模式] 未发现 cache\，需要下载的组件将被跳过。请先运行 prefetch.cmd。' }

# --- 1/9. Install Tabby if missing (cache -> direct download -> winget) ---
Info '[1/9] Tabby terminal'
$tabbyExe = Find-Tabby
if ($tabbyExe) {
    Ok '       Tabby already installed - skip'
} else {
    $src = Resolve-Source -Key 'tabby' -CacheDir $CacheDir -Preference $pref -Mode $RunMode
    $setup = $null
    if ($src -eq 'cache') {
        $setup = Get-CachePath $CacheDir 'tabby'
        Ok '       使用离线包安装'
    } elseif ($src -eq 'online') {
        try {
            $rel = $null
            foreach ($api in @('https://api.github.com/repos/Eugeny/tabby/releases/latest', 'https://ghfast.top/https://api.github.com/repos/Eugeny/tabby/releases/latest')) {
                try { $rel = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = 'tabby-setup' } -UseBasicParsing -TimeoutSec 20; if ($rel) { break } } catch { }
            }
            $asset = $null
            if ($rel) {
                $asset = $rel.assets | Where-Object { $_.name -match 'setup.*x64\.exe$' } | Select-Object -First 1
                if (-not $asset) { $asset = $rel.assets | Where-Object { $_.name -match 'x64.*setup\.exe$' } | Select-Object -First 1 }
            }
            if ($asset) {
                $out = Get-CachePath $CacheDir 'tabby'
                foreach ($u in @("https://ghfast.top/$($asset.browser_download_url)", "https://gh-proxy.com/$($asset.browser_download_url)", $asset.browser_download_url)) {
                    Warn "       Downloading: $u"
                    if (Get-FileWithProgress -Url $u -OutFile $out -MinBytes 40MB -ExpectedBytes $asset.size -TimeoutSec 600 -Activity 'Tabby') { break }
                }
                if ((Test-Path $out) -and ((Get-Item $out).Length -gt 40MB)) {
                    Set-ManifestEntry $CacheDir 'tabby' ([string]$rel.tag_name) $asset.name
                    $setup = $out
                }
            }
        } catch { Warn "       Download failed: $_" }
        if (-not $setup -and $winget) {
            Warn '       直接下载失败 - 改用 winget...'
            winget install --id Eugeny.Tabby --accept-package-agreements --accept-source-agreements
            Start-Sleep -Seconds 3
            $tabbyExe = Find-Tabby
        }
    } else {
        Warn '       Tabby 已跳过（无离线包/用户选择跳过）'
    }
    if ($setup -and (Test-Path $setup)) {
        Invoke-WithSpinner '正在静默安装 Tabby...' 'Tabby 安装完成' {
            Start-Process -FilePath $setup -ArgumentList '/S' -Wait
            Start-Sleep -Seconds 5
        }
        $tabbyExe = Find-Tabby
    }
    if ($tabbyExe) { Ok "       Tabby ready: $tabbyExe" }
    elseif ($src -ne 'skip') { Warn '       Tabby could not be installed. Install manually: https://tabby.sh' }
}

# --- 2/7. Deploy config.yaml ---
Info '[2/9] Deploying config.yaml...'
New-Item -ItemType Directory -Path $TabbyDir -Force | Out-Null
Copy-Item (Join-Path $AssetsDir 'config.yaml') (Join-Path $TabbyDir 'config.yaml') -Force
Ok '       config.yaml deployed'

# --- 3/7. Neon theme selection (with live preview) ---
Info '[3/9] Neon color theme'
$chosen = $null
if ($Theme) { $chosen = $Themes | Where-Object { $_.Name -eq $Theme } | Select-Object -First 1 }
if (-not $chosen) { $chosen = Select-Theme }
Apply-Theme (Join-Path $TabbyDir 'config.yaml') $chosen $NeonCss
Ok "       Theme applied: $($chosen.Name)  (accent: $($chosen.Colors[4]))"

# --- 4/7. Install JetBrainsMono Nerd Font (user-level) ---
Info '[4/9] Installing JetBrainsMono Nerd Font...'
$fontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
$regPath = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
New-Item -ItemType Directory -Path $fontDir -Force | Out-Null
if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }

$installedFonts = (Get-ItemProperty $regPath -ErrorAction SilentlyContinue).PSObject.Properties.Name
if ($installedFonts -match 'JetBrainsMono Nerd Font Mono') {
    Ok '       Font already installed - skip'
} else {
    $src = Resolve-Source -Key 'font' -CacheDir $CacheDir -Preference $pref -Mode $RunMode
    $zip = $null
    if ($src -eq 'cache') {
        $zip = Get-CachePath $CacheDir 'font'
        Ok '       使用离线包'
    } elseif ($src -eq 'online') {
        $tmp = Join-Path $env:TEMP 'tabby-setup-font'
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        $tmpZip = Join-Path $tmp 'JetBrainsMono.zip'
        $urls = @(
            'https://ghfast.top/https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip',
            'https://gh-proxy.com/https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip',
            'https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip'
        )
        foreach ($u in $urls) {
            Warn "       Downloading: $u"
            if (Get-FileWithProgress -Url $u -OutFile $tmpZip -MinBytes 25MB -TimeoutSec 300 -Activity 'JetBrainsMono NF') { break }
        }
        if ((Test-Path $tmpZip) -and ((Get-Item $tmpZip).Length -gt 25MB) -and (Test-ZipFile $tmpZip)) {
            Copy-Item $tmpZip (Get-CachePath $CacheDir 'font') -Force -ErrorAction SilentlyContinue
            $tag = Get-LatestGitHubTag 'ryanoasis/nerd-fonts'; if (-not $tag) { $tag = 'latest' }
            Set-ManifestEntry $CacheDir 'font' $tag 'JetBrainsMono.zip'
            $zip = $tmpZip
        } elseif (Test-Path $tmpZip) {
            Warn '       字体包不完整，已丢弃'
            Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue
        }
    } else {
        Warn '       字体已跳过（无离线包/用户选择跳过）'
    }
    if ($zip -and (Test-Path $zip) -and (Test-ZipFile $zip)) {
        $ext = Join-Path $env:TEMP 'tabby-setup-font-extract'
        Expand-ZipWithProgress -ZipPath $zip -Destination $ext -Activity '解压字体'
        $styles = @('Regular','Bold','Italic','BoldItalic','Medium','MediumItalic','Light','LightItalic','SemiBold','SemiBoldItalic')
        $n = 0
        foreach ($s in $styles) {
            $ttf = Join-Path $ext "JetBrainsMonoNerdFontMono-$s.ttf"
            if (Test-Path $ttf) {
                $dst = Join-Path $fontDir "JetBrainsMonoNerdFontMono-$s.ttf"
                Copy-Item $ttf $dst -Force
                New-ItemProperty -Path $regPath -Name "JetBrainsMono Nerd Font Mono $s (TrueType)" -Value $dst -PropertyType String -Force | Out-Null
                $n++
            }
        }
        Ok "       Installed $n font files"
    } elseif ($src -ne 'skip') {
        Warn '       Font install failed - install JetBrainsMono Nerd Font manually later.'
    }
}

# --- 5/9. Ensure PowerShell 7 (pwsh) + CompletionPredictor, switch Tabby default shell ---
Info '[5/9] Ensuring PowerShell 7 (pwsh) for modern completion...'
function Find-Pwsh {
    $c = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
    if ($c) { return $c }
    return @("$env:ProgramFiles\PowerShell\7\pwsh.exe", "$env:LOCALAPPDATA\Microsoft\WindowsApps\pwsh.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
}
$pwshExe = Find-Pwsh
# 记录“安装前 PowerShell 7 是否已存在”，供 uninstall.ps1 判断是否为【本包安装】
$pwshPreexisting = [bool]$pwshExe
$pwshPrePath     = [string]$pwshExe
# 已有 → 询问：安装本程序版本（覆盖）还是保留本机版本（完全不碰）
$installOwnPwsh = $false
if ($pwshExe) {
    if ($Ours) { $installOwnPwsh = $true }
    elseif (-not $AutoYes) { $installOwnPwsh = ((Select-ExistingAction 'PowerShell 7' $pwshExe) -eq 'ours') }
}
$useOwnPwsh = (-not $pwshPreexisting) -or $installOwnPwsh
if (-not $pwshExe -or $installOwnPwsh) {
    $src = Resolve-Source -Key 'pwsh' -CacheDir $CacheDir -Preference $pref -Mode $RunMode
    $msix = $null
    if ($src -eq 'cache') {
        $msix = Get-CachePath $CacheDir 'pwsh'
        Ok '       使用离线包（MSIX）'
    } elseif ($src -eq 'online') {
        # 在线：先试 winget（限时），失败再用镜像 MSIX
        if ($winget) {
            Warn '       Installing PowerShell 7 via winget (max 5 min)...'
            try {
                $wp = Start-Process -FilePath 'winget' -ArgumentList 'install','--id','Microsoft.PowerShell','--accept-package-agreements','--accept-source-agreements','--silent' -PassThru -NoNewWindow
                if (-not $wp.WaitForExit(300000)) {
                    Warn '       winget timed out - killing it, will use mirror...'
                    Get-Process -Name winget -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                }
            } catch { Warn "       winget failed: $_" }
            Update-Path
            $pwshExe = Find-Pwsh
        }
        if (-not $pwshExe) {
            try {
                $tag = Get-LatestGitHubTag 'PowerShell/PowerShell'
                if (-not $tag) { $tag = 'v7.6.6' }   # last-resort pin
                $ver = ([string]$tag).TrimStart('v')
                $out = Get-CachePath $CacheDir 'pwsh'
                $gh = "https://github.com/PowerShell/PowerShell/releases/download/v$ver/PowerShell-$ver.msixbundle"
                foreach ($u in @("https://ghfast.top/$gh", "https://gh-proxy.com/$gh", $gh)) {
                    Warn "       Downloading: $u"
                    if (Get-FileWithProgress -Url $u -OutFile $out -MinBytes 50MB -TimeoutSec 900 -Activity 'Downloading PowerShell 7') { break }
                }
                if ((Test-Path $out) -and ((Get-Item $out).Length -gt 50MB)) {
                    Set-ManifestEntry $CacheDir 'pwsh' $ver "PowerShell-$ver.msixbundle"
                    $msix = $out
                } else { Warn '       MSIX download failed' }
            } catch { Warn "       MSIX download failed: $_" }
        }
    } else {
        Warn '       PowerShell 7 已跳过（无离线包/用户选择跳过）'
    }
    if ($msix -and (Test-Path $msix)) {
        try {
            Invoke-WithSpinner '正在安装 PowerShell 7 (MSIX)...' 'PowerShell 7 安装完成' {
                Add-AppxPackage -Path $msix -ErrorAction Stop
                Start-Sleep -Seconds 3
            }
            Update-Path
            $pwshExe = Find-Pwsh
        } catch { Warn "       MSIX install failed: $_" }
    }
}
if ($pwshExe) {
    Ok "       PowerShell 7 ready: $pwshExe"
    # switch Tabby default shell to PowerShell Core (profile id: local:powershell-core)
    $cfgPath = Join-Path $TabbyDir 'config.yaml'
    $cfgText = [System.IO.File]::ReadAllText($cfgPath, [Text.Encoding]::UTF8)
    if ($cfgText -match '(?m)^(\s*profile:\s*)local:powershell\s*$') {
        $cfgText = [regex]::Replace($cfgText, '(?m)^(\s*profile:\s*)local:powershell\s*$', '${1}local:powershell-core', 1)
        Write-ConfigSafe $cfgPath $cfgText
        Ok '       Tabby default shell -> PowerShell 7 (local:powershell-core)'
    }
    if ($useOwnPwsh) {
        # CompletionPredictor: 优先离线缓存，否则从 PSGallery 安装
        try {
            $cachedCp = Get-CachedModuleVersion $CacheDir 'CompletionPredictor'
            $cpDir = Join-Path $env:USERPROFILE 'Documents\PowerShell\Modules'
            New-Item -ItemType Directory -Path $cpDir -Force | Out-Null
            if ($cachedCp) {
                Copy-Item (Join-Path $CacheDir 'modules\CompletionPredictor') $cpDir -Recurse -Force
                Ok "       CompletionPredictor $cachedCp (离线包)"
            } else {
                $cnt = & $pwshExe -NoProfile -Command "($env:PSModulePath -split ';' | ForEach-Object { Join-Path `$_ 'CompletionPredictor' } | Where-Object { Test-Path `$_ } | Measure-Object).Count" 2>$null
                if ([int]$cnt -lt 1) {
                    Warn '       Installing CompletionPredictor (pwsh)...'
                    Invoke-WithSpinner '正在安装 CompletionPredictor...' 'CompletionPredictor 安装完成' {
                        & $pwshExe -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; try { Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue } catch {}; Install-Module CompletionPredictor -Scope CurrentUser -Force -AllowClobber"
                    }
                }
                Ok '       CompletionPredictor ready'
            }
        } catch { Warn '       CompletionPredictor install failed - predictions fall back to history' }
    } else {
        Warn '       保留本机 PowerShell 7：未改动它的配置（跳过 CompletionPredictor）'
    }
} else {
    Warn '       PowerShell 7 unavailable - staying on Windows PowerShell 5.1'
}

# --- 6/9. oh-my-posh prompt (install + deploy theme + profile) ---
Info '[6/9] Setting up oh-my-posh prompt...'
$omp = $null
$ompCmd = Get-Command oh-my-posh -ErrorAction SilentlyContinue
if ($ompCmd) { $omp = $ompCmd.Source }
if (-not $omp) {
    $ompAlias = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\oh-my-posh.exe'
    if (Test-Path $ompAlias) { $omp = $ompAlias }
}
# 便携版目录（离线包解压到这里）
$ompPortableDir = Join-Path $env:LOCALAPPDATA 'Programs\oh-my-posh'
if (-not $omp -and (Test-Path (Join-Path $ompPortableDir 'oh-my-posh.exe'))) {
    $omp = Join-Path $ompPortableDir 'oh-my-posh.exe'
}
# 记录“安装前 oh-my-posh 是否已存在”，供 uninstall.ps1 判断是否为【本包安装】
$ompPreexisting = [bool]$omp
$ompPrePath     = [string]$omp
# 已有 → 询问：安装本程序版本（覆盖）还是保留本机版本（完全不碰）
$installOwnOmp = $false
if ($omp) {
    if ($Ours) { $installOwnOmp = $true }
    elseif (-not $AutoYes) { $installOwnOmp = ((Select-ExistingAction 'oh-my-posh' $omp) -eq 'ours') }
}
$useOwnOmp = (-not $ompPreexisting) -or $installOwnOmp
if (-not $omp -or $installOwnOmp) {
    $src = Resolve-Source -Key 'omp' -CacheDir $CacheDir -Preference $pref -Mode $RunMode
    if ($src -eq 'cache' -or $src -eq 'online') {
        $ompExeCache = Get-CachePath $CacheDir 'omp'
        $ompThemesCache = Get-CachePath $CacheDir 'ompthemes'
        if ($src -eq 'online') {
            # 在线：先试 winget（若用户选了“本程序版本”则跳过 winget，直接部署便携版），失败再下便携 zip
            if ($winget -and -not $installOwnOmp) {
                Warn '       Installing oh-my-posh via winget...'
                winget install --id JanDeDobbeleer.OhMyPosh --accept-package-agreements --accept-source-agreements --silent
                Start-Sleep -Seconds 2
                Update-Path
                $ompCmd = Get-Command oh-my-posh -ErrorAction SilentlyContinue
                if ($ompCmd) { $omp = $ompCmd.Source }
            }
            if (-not $omp -or $installOwnOmp) {
                try {
                    $rel = $null
                    foreach ($api in @('https://api.github.com/repos/JanDeDobbeleer/oh-my-posh/releases/latest', 'https://ghfast.top/https://api.github.com/repos/JanDeDobbeleer/oh-my-posh/releases/latest')) {
                        try { $rel = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = 'tabby-setup' } -UseBasicParsing -TimeoutSec 20; if ($rel) { break } } catch { }
                    }
                    $assetExe = $null; $assetThemes = $null
                    if ($rel) {
                        $assetExe = $rel.assets | Where-Object { $_.name -match '^posh-windows-amd64\.exe$' } | Select-Object -First 1
                        if (-not $assetExe) { $assetExe = $rel.assets | Where-Object { $_.name -match 'windows-amd64.*\.exe$' } | Select-Object -First 1 }
                        $assetThemes = $rel.assets | Where-Object { $_.name -eq 'themes.zip' } | Select-Object -First 1
                    }
                    if ($assetExe) {
                        foreach ($u in @("https://ghfast.top/$($assetExe.browser_download_url)", "https://gh-proxy.com/$($assetExe.browser_download_url)", $assetExe.browser_download_url)) {
                            Warn "       Downloading: $u"
                            if (Get-FileWithProgress -Url $u -OutFile $ompExeCache -MinBytes 5MB -ExpectedBytes $assetExe.size -TimeoutSec 600 -Activity 'oh-my-posh') { break }
                        }
                        if ((Test-Path $ompExeCache) -and ((Get-Item $ompExeCache).Length -gt 1MB)) {
                            Set-ManifestEntry $CacheDir 'omp' ([string]$rel.tag_name) $assetExe.name
                        }
                        if ($assetThemes) {
                            foreach ($u in @("https://ghfast.top/$($assetThemes.browser_download_url)", "https://gh-proxy.com/$($assetThemes.browser_download_url)", $assetThemes.browser_download_url)) {
                                if (Get-FileWithProgress -Url $u -OutFile $ompThemesCache -MinBytes 100KB -ExpectedBytes $assetThemes.size -TimeoutSec 300 -Activity 'oh-my-posh themes') { break }
                            }
                        }
                    }
                } catch { Warn "       oh-my-posh download failed: $_" }
            }
        }
        # 安装便携版：exe 复制到便携目录 + themes.zip 解压出主题
        if ($useOwnOmp -and (Test-Path $ompExeCache) -and ((Get-Item $ompExeCache).Length -gt 1MB)) {
            Invoke-WithSpinner '正在部署 oh-my-posh 便携版...' 'oh-my-posh 部署完成' {
                New-Item -ItemType Directory -Path $ompPortableDir -Force | Out-Null
                Copy-Item $ompExeCache (Join-Path $ompPortableDir 'oh-my-posh.exe') -Force
            }
            if ((Test-Path $ompThemesCache) -and ((Get-Item $ompThemesCache).Length -gt 10KB)) {
                $ext = Join-Path $env:TEMP 'omp-themes-extract'
                Expand-ZipWithProgress -ZipPath $ompThemesCache -Destination $ext -Activity '解压 omp 主题'
                $thDir = Join-Path $ompPortableDir 'themes'
                New-Item -ItemType Directory -Path $thDir -Force | Out-Null
                Get-ChildItem $ext -File -Recurse -Filter *.omp.json | ForEach-Object { Copy-Item $_.FullName $thDir -Force }
            }
            $up = [Environment]::GetEnvironmentVariable('Path', 'User')
            $parts = $up -split ';' | Where-Object { $_ -and ($_.TrimEnd('\') -ne $ompPortableDir.TrimEnd('\')) }
            if ($installOwnOmp) {
                # 前置便携目录，确保优先于 winget 别名（真正用本程序版本）
                [Environment]::SetEnvironmentVariable('Path', $ompPortableDir + ';' + ($parts -join ';'), 'User')
            } elseif (($up -split ';') -notcontains $ompPortableDir) {
                [Environment]::SetEnvironmentVariable('Path', $up.TrimEnd(';') + ';' + $ompPortableDir, 'User')
            }
            Update-Path
            $omp = Join-Path $ompPortableDir 'oh-my-posh.exe'
            if ($src -eq 'cache') { Ok '       使用离线包（便携版）' }
        }
    }
}
New-Item -ItemType Directory -Path $BinDir -Force | Out-Null

# 只有“使用本程序版本”时才部署本包的 omp 主题/主题选择器（否则完全不碰本机 omp 配置）
if ($useOwnOmp) {
    Copy-Item (Join-Path $AssetsDir 'oh-my-posh.omp.json') (Join-Path $BinDir 'oh-my-posh.omp.json') -Force
    # deploy the oh-my-posh theme picker (omp command) + remember default theme name
    foreach ($hf in @('omp.cmd', 'omp-theme.ps1')) {
        if (Test-Path (Join-Path $ScriptDir $hf)) {
            Copy-Item (Join-Path $ScriptDir $hf) (Join-Path $BinDir $hf) -Force
        }
    }
    $themeNameFile = Join-Path $BinDir 'oh-my-posh.theme.txt'
    if (-not (Test-Path $themeNameFile)) { Set-Content -Path $themeNameFile -Value 'atomic' -Encoding ASCII }
} else {
    Warn '       保留本机 oh-my-posh：未改动它的配置（不部署本包主题/选择器）'
}

# PowerShell profile：只写入本包“确实要用”的块，并保留你原有的内容（仅剥离本包旧块）
if ($useOwnOmp -or $useOwnPwsh) {
    $templateText = [System.IO.File]::ReadAllText((Join-Path $ScriptDir 'Microsoft.PowerShell_profile.ps1'), [Text.Encoding]::UTF8)
    $ompBlock = ''; $prlBlock = ''
    if ($templateText -match '(?s)(# ==== oh-my-posh prompt.*?# ==== end oh-my-posh ====)') { $ompBlock = $Matches[1] }
    if ($templateText -match '(?s)(# ==== PSReadLine.*?# ==== end PSReadLine ====)')       { $prlBlock = $Matches[1] }
    $desiredList = @()
    if ($useOwnOmp)  { $desiredList += $ompBlock }
    if ($useOwnPwsh) { $desiredList += $prlBlock }
    $desiredText = ($desiredList -join "`r`n")
    $utf8bom = New-Object System.Text.UTF8Encoding($true)
    foreach ($pp in @(
        (Join-Path $env:USERPROFILE 'Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1'),
        (Join-Path $env:USERPROFILE 'Documents\PowerShell\Microsoft.PowerShell_profile.ps1')
    )) {
        New-Item -ItemType Directory -Path (Split-Path $pp) -Force | Out-Null
        $exists = Test-Path $pp
        $existing = if ($exists) { ([System.IO.File]::ReadAllText($pp, [Text.Encoding]::UTF8)) -replace "^\uFEFF", '' } else { '' }
        # 剥离本包旧块（不影响用户自己的内容）
        $stripped = [regex]::Replace($existing, '(?s)\r?\n?# ==== oh-my-posh prompt.*?# ==== end oh-my-posh ====\s*', "`r`n")
        $stripped = [regex]::Replace($stripped, '(?s)\r?\n?# ==== PSReadLine.*?# ==== end PSReadLine ====\s*', "`r`n")
        $stripped = $stripped.TrimEnd()
        $newContent = if ([string]::IsNullOrWhiteSpace($stripped)) { $desiredText } else { $stripped + "`r`n" + $desiredText }
        [System.IO.File]::WriteAllText($pp, ($newContent.TrimEnd() + "`r`n"), $utf8bom)
        Ok "       profile updated: $pp"
    }
} else {
    Warn '       保留本机 pwsh 与 oh-my-posh：未改动 PowerShell profile'
}

if ($useOwnOmp) { Ok '       oh-my-posh prompt deployed - run "omp" to browse cool themes (default: atomic)' }
elseif ($omp)   { Warn '       保留本机 oh-my-posh（未部署本包提示符配置）' }
else            { Warn '       oh-my-posh not installed - prompt NOT enabled. Install it then re-run.' }

# ensure modern PSReadLine (predictive completion needs >= 2.1; Windows PowerShell 5.1 ships 2.0)
if ($useOwnPwsh) {
    $prlBest = Get-Module PSReadLine -ListAvailable -ErrorAction SilentlyContinue | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $prlBest -or $prlBest.Version -lt [version]'2.1.0') {
        $cachedPrl = Get-CachedModuleVersion $CacheDir 'PSReadLine'
        $wpModDir = Join-Path $env:USERPROFILE 'Documents\WindowsPowerShell\Modules'
        if ($cachedPrl) {
            New-Item -ItemType Directory -Path $wpModDir -Force | Out-Null
            Copy-Item (Join-Path $CacheDir 'modules\PSReadLine') $wpModDir -Recurse -Force
            Ok "       PSReadLine $cachedPrl (离线包) - predictive completion ready"
        } else {
            Warn '       Upgrading PSReadLine for predictive completion (grey inline suggestions)...'
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
                    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser -ErrorAction Stop | Out-Null
                }
                Install-Module PSReadLine -Scope CurrentUser -Force -AllowClobber -SkipPublisherCheck -ErrorAction Stop
                Ok '       PSReadLine upgraded - predictive completion ready'
            } catch {
                Warn '       PSReadLine upgrade failed - run: Install-Module PSReadLine -Scope CurrentUser -Force'
            }
        }
    } else {
        Ok "       PSReadLine $($prlBest.Version) present - predictive completion ready"
    }
} else {
    Warn '       保留本机 PowerShell 7：未改动它的配置（跳过 PSReadLine 升级）'
}

# --- 7/9. Ensure Node.js/npm, then install plugins (cache -> winget -> nodejs.org) ---
Info '[7/9] Installing npm plugins...'
Update-Path
if (-not (Get-Command npm.cmd -ErrorAction SilentlyContinue)) {
    $src = Resolve-Source -Key 'node' -CacheDir $CacheDir -Preference $pref -Mode $RunMode
    $nodeZip = $null
    if ($src -eq 'cache') {
        $nodeZip = Get-CachePath $CacheDir 'node'
        Ok '       使用离线包安装 Node.js'
    } elseif ($src -eq 'online') {
        if ($winget) {
            Warn '       Node.js/npm not found - installing Node.js LTS via winget...'
            winget install --id OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements
            Update-Path
        }
        if (-not (Get-Command npm.cmd -ErrorAction SilentlyContinue)) {
            try {
                $ver = Get-LatestNodeLts
                if (-not $ver) { $ver = 'v22.11.0' }
                $out = Get-CachePath $CacheDir 'node'
                $ok = $false
                foreach ($u in @("https://registry.npmmirror.com/-/binary/node/$ver/node-$ver-win-x64.zip", "https://nodejs.org/dist/$ver/node-$ver-win-x64.zip")) {
                    Warn "       Downloading: $u"
                    if (Get-FileWithProgress -Url $u -OutFile $out -MinBytes 10MB -TimeoutSec 600 -Activity 'Node.js') { $ok = $true; break }
                }
                if ($ok) {
                    Set-ManifestEntry $CacheDir 'node' $ver "node-$ver-win-x64.zip"
                    $nodeZip = $out
                }
            } catch { Warn "       Node.js download failed: $_" }
        }
    } else {
        Warn '       Node.js 已跳过（无离线包/用户选择跳过）'
    }
    if ($nodeZip -and (Test-Path $nodeZip)) {
        $extract = Join-Path $env:TEMP 'nodejs-extract'
        Expand-ZipWithProgress -ZipPath $nodeZip -Destination $extract -Activity '解压 Node.js'
        $inner = Get-ChildItem $extract -Directory | Select-Object -First 1
        $nodeDir = Join-Path $env:LOCALAPPDATA 'Programs\nodejs'
        if (Test-Path $nodeDir) { Remove-Item $nodeDir -Recurse -Force }
        Move-Item $inner.FullName $nodeDir
        $up = [Environment]::GetEnvironmentVariable('Path', 'User')
        if (($up -split ';') -notcontains $nodeDir) {
            [Environment]::SetEnvironmentVariable('Path', $up.TrimEnd(';') + ';' + $nodeDir, 'User')
        }
        Update-Path
        Ok "       Node.js installed to $nodeDir"
    }
}
New-Item -ItemType Directory -Path $PluginDir -Force | Out-Null
Copy-Item (Join-Path $AssetsDir 'plugins.package.json') (Join-Path $PluginDir 'package.json') -Force
# 优先使用离线 npm 插件（支持 node_modules 目录 或 node_modules.zip 单文件）
$npmCacheDir  = Join-Path $CacheDir 'npm'
$npmTree      = Join-Path $npmCacheDir 'node_modules'
$npmZip       = Join-Path $npmCacheDir 'node_modules.zip'
$installedTree = Join-Path $PluginDir 'node_modules'
$sigFile      = Join-Path $PluginDir '.tabby-setup-npm.sig'
$offlineSig   = ''
if (Test-Path $npmZip) {
    $zi = Get-Item $npmZip
    $offlineSig = 'zip:' + $zi.Length + ':' + $zi.LastWriteTimeUtc.Ticks
} elseif (Test-Path $npmTree) {
    $offlineSig = 'tree:' + (Get-Item $npmTree).LastWriteTimeUtc.Ticks
}
$curSig = ''
if (Test-Path $sigFile) { try { $curSig = (Get-Content -LiteralPath $sigFile -Raw -ErrorAction SilentlyContinue).Trim() } catch { } }
$hasOffline = (Test-Path $npmTree) -or (Test-Path $npmZip)
if ($hasOffline) {
    if ((Test-Path $installedTree) -and $offlineSig -and ($curSig -eq $offlineSig)) {
        Ok '       Plugins already installed (离线包，跳过)'
    } elseif (Test-Path $npmTree) {
        Copy-TreeWithProgress -Source $npmTree -Destination $PluginDir -Activity '复制 npm 插件'
        Set-Content -LiteralPath $sigFile -Value $offlineSig -Encoding ASCII -ErrorAction SilentlyContinue
        Ok '       Plugins installed (离线包)'
    } else {
        Expand-ZipFast -ZipPath $npmZip -Destination $PluginDir -Activity '解压 npm 插件' -NoClear
        Set-Content -LiteralPath $sigFile -Value $offlineSig -Encoding ASCII -ErrorAction SilentlyContinue
        Ok '       Plugins installed (离线包)'
    }
    if (Test-Path (Join-Path $npmCacheDir 'package-lock.json')) {
        Copy-Item (Join-Path $npmCacheDir 'package-lock.json') $PluginDir -Force
    }
} elseif (Get-Command npm.cmd -ErrorAction SilentlyContinue) {
    Push-Location $PluginDir
    try {
        $npmLog = Join-Path $env:TEMP 'tabby-npm-install.log'
        Invoke-WithSpinner '正在安装 npm 插件...' 'npm 插件安装完成' {
            & npm.cmd install --no-audit --no-fund *> $npmLog
        }
        if (Test-Path (Join-Path $PluginDir 'node_modules')) {
            Ok '       Plugins installed'
            # 顺便存入离线缓存（打包成单个 zip，便于拷贝分发），下次即可离线
            New-Item -ItemType Directory -Path $npmCacheDir -Force | Out-Null
            Compress-TreeToZip -Source (Join-Path $PluginDir 'node_modules') -ZipPath $npmZip -Activity '缓存 npm 插件'
            Remove-Item $npmTree -Recurse -Force -ErrorAction SilentlyContinue
            Copy-Item (Join-Path $PluginDir 'package.json') $npmCacheDir -Force -ErrorAction SilentlyContinue
            if (Test-Path (Join-Path $PluginDir 'package-lock.json')) { Copy-Item (Join-Path $PluginDir 'package-lock.json') $npmCacheDir -Force -ErrorAction SilentlyContinue }
        } else {
            Warn '       npm install failed - tail of log:'
            if (Test-Path $npmLog) { Get-Content $npmLog -Tail 15 -ErrorAction SilentlyContinue | ForEach-Object { Warn "       $_" } }
        }
    } catch {
        Warn "       npm install failed: $_"
    } finally {
        Pop-Location
    }
} else {
    Warn '       Node.js/npm unavailable - plugins NOT installed. Install Node.js then re-run.'
}

# --- 8/9. Create 'tabbyhelp' + 'tabbycolors' + 'tabbytheme' commands ---
Info '[8/9] Creating tabbyhelp + tabbycolors + tabbytheme commands...'
$binDir = Join-Path $env:USERPROFILE 'bin'
New-Item -ItemType Directory -Path $binDir -Force | Out-Null
Copy-Item (Join-Path $ScriptDir 'tabbyhelp.cmd') (Join-Path $binDir 'tabbyhelp.cmd') -Force
Copy-Item (Join-Path $ScriptDir 'tabbycolors.cmd') (Join-Path $binDir 'tabbycolors.cmd') -Force
Copy-Item (Join-Path $ScriptDir 'show-theme.ps1') (Join-Path $binDir 'show-theme.ps1') -Force
Copy-Item (Join-Path $ScriptDir 'tabbytheme.cmd') (Join-Path $binDir 'tabbytheme.cmd') -Force
Copy-Item (Join-Path $ScriptDir 'switch-theme.ps1') (Join-Path $binDir 'switch-theme.ps1') -Force
$gbk = [System.Text.Encoding]::GetEncoding(936)
$helpTxt = [System.IO.File]::ReadAllText((Join-Path $ScriptDir 'tabbyhelp.txt'), $gbk)
$helpTxt = $helpTxt.Replace('@TABBY_SETUP_DIR@', $RootDir)
[System.IO.File]::WriteAllText((Join-Path $binDir 'tabbyhelp.txt'), $helpTxt, $gbk)
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (($userPath -split ';') -notcontains $binDir) {
    [Environment]::SetEnvironmentVariable('Path', $userPath.TrimEnd(';') + ';' + $binDir, 'User')
    Ok "       tabbyhelp + tabbycolors + tabbytheme created; $binDir added to PATH (open a new terminal to use)"
} else {
    Ok '       tabbyhelp + tabbycolors + tabbytheme created; PATH already contains bin'
}

# --- 9/9. Start Tabby ---
Info '[9/9] Starting Tabby...'

# --- 记录安装状态：供 uninstall.ps1 判断哪些程序是本包安装的 ---
try {
    $stateDir = Join-Path $env:LOCALAPPDATA 'tabby-setup'
    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
    $state = [ordered]@{
        installedAt    = (Get-Date).ToString('o')
        ompPreexisting = [bool]$ompPreexisting
        ompPrePath     = [string]$ompPrePath
        ompPath        = [string]$omp
        ompInstalledByUs = [bool]((-not $ompPreexisting) -or $installOwnOmp)
        pwshPreexisting = [bool]$pwshPreexisting
        pwshPrePath     = [string]$pwshPrePath
        pwshPath        = [string]$pwshExe
        pwshInstalledByUs = [bool]((-not $pwshPreexisting) -or $installOwnPwsh)
        tabbyExe       = [string]$tabbyExe
    }
    ($state | ConvertTo-Json -Depth 4) | Set-Content -Path (Join-Path $stateDir 'install-state.json') -Encoding UTF8
} catch { }

if ($tabbyExe) { Start-Process $tabbyExe } else { Warn '       Tabby exe not found - start it manually' }
Ok '=================================================='
Ok ' Done! Tabby is configured.'
Ok '=================================================='
