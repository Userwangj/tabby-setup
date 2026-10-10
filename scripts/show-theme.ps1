<#
    tabbycolors - 直观查看当前 Tabby 主题是否生效
    ------------------------------------------------------------
    显示：主题名 / 终端背景色 / 16 色 ANSI 调色板
    这些颜色都来自 Tabby 的 terminal.colorScheme，
    换主题后本命令的输出颜色会立刻变化。
    用法（在 Tabby 里直接输入）：
        tabbycolors
#>
$e = [char]27
$cfg = Join-Path $env:APPDATA 'tabby\config.yaml'

$name = '(未知)'; $bg = ''; $fg = ''; $cursor = ''
try {
    $lines = [System.IO.File]::ReadAllLines($cfg, [Text.Encoding]::UTF8)
    $ci = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*colorScheme:') { $ci = $i; break } }
    if ($ci -ge 0) {
        for ($i = $ci + 1; $i -lt [Math]::Min($ci + 9, $lines.Count); $i++) {
            if ($lines[$i] -match 'name:\s*(.+)$')       { $name   = $Matches[1].Trim() }
            if ($lines[$i] -match 'background:\s*(.+)$') { $bg     = $Matches[1].Trim().Trim("'") }
            if ($lines[$i] -match 'foreground:\s*(.+)$') { $fg     = $Matches[1].Trim().Trim("'") }
            if ($lines[$i] -match 'cursor:\s*(.+)$')     { $cursor = $Matches[1].Trim().Trim("'") }
        }
    }
} catch { }

Write-Host ''
Write-Host '  ============================================' -ForegroundColor Cyan
Write-Host "   当前 Tabby 主题: $name" -ForegroundColor Cyan
Write-Host '  ============================================' -ForegroundColor Cyan
Write-Host "   终端背景 background = $bg"
Write-Host "   终端前景 foreground = $fg"
Write-Host "   光标 cursor         = $cursor"
Write-Host ''

# 背景色真彩块
if ($bg -match '#([0-9a-fA-F]{6})') {
    $r = [Convert]::ToInt32($Matches[1].Substring(0,2),16)
    $g = [Convert]::ToInt32($Matches[1].Substring(2,2),16)
    $b = [Convert]::ToInt32($Matches[1].Substring(4,2),16)
    Write-Host "   背景实测: $e[48;2;$r;$g;${b}m               $e[0m   (应和上面 background 一致)"
    Write-Host ''
}

$names = 'black','red','green','yellow','blue','magenta','cyan','white',
         'brightBlack','brightRed','brightGreen','brightYellow','brightBlue','brightMagenta','brightCyan','brightWhite'
Write-Host '   ANSI 16 色调色板（颜色 = 当前主题配色）:' -ForegroundColor Cyan
for ($i = 0; $i -lt 16; $i++) {
    Write-Host ("   {0,2} {1} " -f $i, $names[$i].PadRight(13)) -NoNewline
    Write-Host ("$e[48;5;${i}m        $e[0m  $e[38;5;${i}mThe quick brown fox 0123456789$e[0m")
}
Write-Host ''
Write-Host '   示例命令行: ' -NoNewline
Write-Host 'PS ' -ForegroundColor Green -NoNewline
Write-Host 'C:\project> ' -ForegroundColor Blue -NoNewline
Write-Host 'git status' -ForegroundColor White
Write-Host ''
Write-Host '   如果这些颜色是深紫底 + 霓虹青/粉，说明 Synthwave 已生效。' -ForegroundColor DarkGray
Write-Host '   标签栏活动标签底部还有一条发光条（那是 UI 的霓虹 CSS）。' -ForegroundColor DarkGray
Write-Host ''
