# Tabby 终端配置同步包

本目录是一套**可移植的 Tabby 终端配置**。换新设备时，双击 `install.cmd` 即可自动还原全部个性化设置（主题、字体、插件、快速命令），无需手动重配。

---

## 一、文件清单

### 目录结构

```
tabby-setup\
├── install.cmd          ← 双击 → 安装
├── uninstall.cmd        ← 双击 → 卸载（彻底还原）
├── README.md            ← 本说明文档
├── cache\               ← 离线安装包（prefetch 生成；整体只有 ~50 个文件）
├── scripts\             ← 所有脚本（平时不用管）
└── assets\              ← 配置模板 / 依赖清单
```

### 入口（用户只需用这两个）

| 文件 | 说明 |
|------|------|
| `install.cmd` | **双击安装**。无参数即全自动：自动探测网络/离线包，只有检测到上游更新或需要选主题时才停下询问 |
| `uninstall.cmd` | **双击卸载**。还原个性化设置 + 卸载 Tabby；oh-my-posh 与 PowerShell 7 会**询问**是否卸载；Node.js **保留**。见下文「十一、卸载」 |

### `scripts\`（脚本，平时不用管）

| 文件 | 说明 |
|------|------|
| `install.ps1` | 一键同步安装主程序（优先使用离线包） |
| `uninstall.ps1` | **一键卸载主程序**：撤销 install 的全部改动；默认连程序一起卸载 |
| `cache-lib.ps1` | 共享库：实时进度条下载 / manifest / 版本比较 / 上游版本探测 / 来源决策 |
| `prefetch.cmd` / `prefetch.ps1` | **离线包准备**：把 Tabby/字体/Node/PS7/oh-my-posh/模块/插件全下到 `cache\`（双击 `prefetch.cmd`） |
| `verify.cmd` / `verify.ps1` | 进度显示自检（演示跑马灯 + 下载进度条 + 解压进度条） |
| `pack.cmd` / `pack.ps1` | **分发打包**：把整个 `tabby-setup\` 压成单个 `tabby-setup-portable.zip`（双击 `pack.cmd`） |
| `progress.cmd` / `progress.ps1` | 查看离线包已下载内容（可选） |
| `tabbyhelp.cmd` / `tabbyhelp.txt` | `tabbyhelp` 命令：功能清单（GBK，安装时注入真实路径） |
| `tabbycolors.cmd` / `show-theme.ps1` | `tabbycolors` 命令：显示当前主题名 + 16 色调色板 + 背景色 |
| `tabbytheme.cmd` / `switch-theme.ps1` | `tabbytheme` 命令：切换 Tabby **终端配色**（8 霓虹主题 + 霓虹发光 CSS + 自动重启） |
| `omp.cmd` / `omp-theme.ps1` | `omp` 命令：切换 oh-my-posh **提示符主题**（16 精选 + 全部 122，真彩色预览） |
| `Microsoft.PowerShell_profile.ps1` | PowerShell profile 模板：启动时加载 oh-my-posh 提示符 |

### `assets\`（配置模板 / 依赖清单）

| 文件 | 说明 |
|------|------|
| `config.yaml` | Tabby 完整配置备份（主题/字体/终端/快速命令） |
| `oh-my-posh.omp.json` | oh-my-posh **提示符**主题（默认 **atomic**，内置炫酷主题，可直接换） |
| `plugins.package.json` | 8 个插件的 npm 依赖清单 |

### `cache\`（离线安装包）

| 说明 |
|------|
| 由 `prefetch` 生成。除 npm 插件树外都是大压缩包；npm 插件树已打包为单个 `cache\npm\node_modules.zip`，因此整个目录只有 ~50 个文件，复制/拷贝极快 |

---

## 二、前置要求

| 依赖 | 说明 | 检查命令 |
|------|------|----------|
| Windows 10/11 | 已在本机验证 Win11 (build 26200) | — |
| winget | 优先用来自动安装 Tabby 与 Node.js（不可用时脚本会自动回退） | `winget --version` |
| Node.js / npm | 用于安装插件；脚本检测不到时会自动安装 | `node --version` / `npm.cmd --version` |
| 网络 | 下载 Tabby、Node.js、字体与 PowerShell 7；GitHub 慢时脚本会自动用镜像 | — |
| PowerShell 7 | 提供命令名级智能补全；脚本自动安装（免管理员） | `pwsh -v` |

---

## 二·五、离线安装包（强烈推荐）

> **痛点**：上面的组件大多托管在 GitHub，国内直连下载经常很慢甚至卡死。
>
> **方案**：在**网络好的机器**上先跑一次 `prefetch.cmd`，把所有安装包下好放进本目录 `cache\`；之后**整个文件夹**（含 `cache\`）拷到任意新设备，运行 `install.cmd` 即**离线秒装**，完全不用碰 GitHub。若没有 `cache\`，`install.cmd` 也会**自动在线下载**（镜像优先）并在**同一个窗口实时显示进度**——全程一键，只有「版本选择 / 主题选择」这类需要你决定的地方才会停下来询问。

### 1. 准备离线包（网好时执行一次）

```powershell
# 双击 scripts\prefetch.cmd，或：
powershell -ExecutionPolicy Bypass -File .\scripts\prefetch.ps1
# 只准备其中几项（可选项：tabby font node pwsh omp modules npm）
powershell -ExecutionPolicy Bypass -File .\scripts\prefetch.ps1 -Only tabby,font,pwsh
```

下载时在主窗口显示**实时刷新的进度条**（填充块 + 百分比 + 已下载/总 MB + 实时速度 + ETA 剩余时间），完成后会写出 `cache\manifest.json`，记录每一项的版本。

覆盖内容：

| 组件 | 缓存文件 |
|------|----------|
| Tabby 安装包 | `cache\tabby-setup.exe` |
| JetBrainsMono Nerd Font | `cache\JetBrainsMono.zip` |
| Node.js (LTS) | `cache\node-win-x64.zip` |
| PowerShell 7 (MSIX) | `cache\PowerShell.msixbundle` |
| oh-my-posh (便携版) | `cache\oh-my-posh.exe` + `cache\oh-my-posh-themes.zip` |
| PSReadLine / CompletionPredictor | `cache\modules\<名称>\` |
| 8 个 npm 插件 | `cache\npm\node_modules.zip` |

### 2. 在新设备安装（离线）

```powershell
# 双击 install.cmd，或：
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

### 3. 版本检测与选择（自动）

安装开始时，脚本会读取 `cache\manifest.json`，并向上游查询最新版本，列出对照表：

```
  ========== 离线包版本检查 ==========
  组件                 已准备          最新            状态
  Tabby               1.0.207        1.0.210         ^ 有更新
  JetBrainsMono NF    3.4.0          3.4.0           最新
  PowerShell 7        7.6.6          7.6.6           最新
  oh-my-posh          26.11.0        26.11.0         最新
  Node.js             v22.11.0       v22.12.0        ^ 有更新

  [!] 从 GitHub 直连下载可能很慢（每项可能数分钟）
   [1] * 全部使用已准备版本（推荐：离线、秒装）
   [2]   全部在线下载最新版本（慢）
   [3]   逐个选择
```

**默认（直接回车）= 用已准备的离线版本**，快且稳；想尝鲜可手动选最新（会提示从 GitHub 下载较慢）。

### 4. 安装脚本开关（**平时都不用加**）

> 直接双击 `install.cmd`（或运行 `install.ps1` 不带任何参数）即可：脚本会自动探测网络/离线包，**只有检测到上游有新版本时才停下询问**。下面的开关只是按需覆盖默认行为的高级选项。

| 开关 | 作用 |
|------|------|
| （无） | **推荐**：全自动。有离线包且无更新→静默用；有更新→询问（默认已准备）；无网络→提示并直接用离线包默认安装；无离线包→有网则自动在线下载 |
| `-Offline` | 强制**只用离线包，绝不联网**（无缓存的组件跳过） |
| `-Online` | 强制总是从线上拉最新版 |
| `-Yes` | 遇到「有更新」也不询问，自动选默认（已准备版本），适合批处理 |
| `-Ours` | 检测到已有 pwsh / oh-my-posh 时，直接安装**本程序的版本**（会覆盖本机同名程序的配置） |

> **已装 pwsh / oh-my-posh 时会询问（重要）**：安装时脚本会检测本机是否已安装 PowerShell 7 与 oh-my-posh；若已安装，会停下让你选：
> ```
>   检测到本机已安装 oh-my-posh：C:\...\oh-my-posh.exe
>     [1] 保留本机现有版本（不安装本程序版本，且完全不改动它的配置）   ← 默认
>     [2] 安装本程序的版本  <-- 注意：会覆盖本机相同程序的配置
> ```
> 选 `[1]`（直接回车）→ 不装本程序的二进制，**也不写入会改变它配置的内容**（不部署本包 omp 主题/选择器、不改 PowerShell profile、跳过 CompletionPredictor/PSReadLine）。选 `[2]` 才安装并配置。
> `-Yes`/批处理下默认 `[1]`（保留）；想强制用本程序版本用 `-Ours`。

```powershell
# 平时：直接双击 install.cmd 即可，无需参数
# 纯离线、不询问
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1 -Offline -Yes
# 全部拉最新
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1 -Online -Yes
# 已有 pwsh/omp 也强制用本程序版本
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1 -Ours
```

> 即使没有先准备离线包，`install.ps1` 也能照常在线安装（镜像优先，进度实时显示）；并且**在线下载下来的文件会自动存入 `cache\`，下次即可离线**。

---

> **全自动**：Tabby、Node.js(LTS)、字体、8 个插件、tabbyhelp 命令——脚本会全部自动完成。
>
> **回退机制（winget 不可用时）**：
> - **Tabby**：winget → 失败则从 GitHub Releases 下载 `tabby-*-setup-x64.exe` 并静默安装（`/S`）
> - **Node.js**：winget → 失败则从 nodejs.org 下载免管理员 zip 版，解压到 `%LOCALAPPDATA%\Programs\nodejs` 并加入 PATH
> - **字体**：GitHub 官方源 → 失败则用国内镜像（`ghfast.top` / `gh-proxy.com`）
> - **PowerShell 7**：winget（限时 5 分钟）→ 超时/失败则用 `ghfast.top` 镜像下载 `.msixbundle`，`Add-AppxPackage` 用户级安装（免管理员）

---

## 三、一键同步安装（推荐）

```powershell
# 在本目录下执行（会先自动关闭 Tabby）
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1
```

脚本执行流程：
0. **全自动决策（无需任何参数）**：自动探测网络与离线包，且**只在检测到上游有新版本时**才询问（默认用已准备版本）
   - 无网络 → 提示「未检测到网络，使用离线包默认安装」，直接装
   - 有网络 + 无更新 → 静默使用离线包
   - 有网络 + 有更新 → 才弹出 1/2/3 选择（默认 `[1]` 用已准备版本）
   - 完全没有离线包 → 有网则自动在线下载；无网则提示并停止
1. **关闭 Tabby**（配置在退出时会被回写，必须先关）
2. 安装 **Tabby**（优先离线包 → 直连下载 → winget）
3. 复制 `assets\config.yaml` 到 `%APPDATA%\tabby\config.yaml`
4. **选择配色主题**（8 个主题，带 ANSI 真彩色实时预览）
5. 安装 **JetBrainsMono Nerd Font**（优先离线包，用户级，免管理员）
6. 安装 **PowerShell 7 (pwsh)** + `CompletionPredictor`（优先离线包）；把 Tabby 默认 shell 切到 `local:powershell-core`
7. 部署 **oh-my-posh** 提示符（优先离线便携版 → winget；主题 + profile；配 `omp` 命令）
8. 安装 **Node.js**（优先离线包）+ **8 个插件**（优先离线 npm 树）
9. 创建 `tabbyhelp` / `tabbycolors` / `tabbytheme` 命令（`%USERPROFILE%\bin` + PATH）
10. 启动 Tabby

> 全程**一键自动**，只有「版本选择 / 主题选择」会让你输入。
> - **下载**（Tabby / 字体 / Node.js / PowerShell 7 / oh-my-posh）在主窗口显示**实时进度条**（填充块 + 百分比 + 已下载/总 MB + 速度 + ETA）；在线下载还会**自动存入 `cache\`**，下次即可离线。

> [!NOTE]
> 进度条填充字符会按当前控制台编码自动适配：UTF-8 终端用 `█`/`░`；GBK/GB2312 控制台（`░` 不受支持）自动改用 `█`/`-`，避免出现 `?`。
> - **本地加载**（字体解压、Node 解压、oh-my-posh 主题解压、离线 npm 插件复制）显示**确定性进度条**（按文件数/项数推进到 100%）；**外部安装**（Tabby 静默安装、PowerShell 7 MSIX、CompletionPredictor、在线 npm）显示**跑马灯进度条**，全程都有可视化反馈，不再是转圈或静默等待。
> - **性能/分发**：离线 npm 插件树有 1.7 万+ 小文件，直接拷整目录会很慢。现在 `prefetch` 会把它打包成**单个 `cache\npm\node_modules.zip`**（215 MB → 53.6 MB），整个 `tabby-setup\` 因此只剩 ~50 个文件，随便拷贝都很快；安装时用 `tar.exe` 一次性解压（带进度条），并用签名文件跳过重复解压。
> - **单文件分发**：双击 `scripts\pack.cmd` 生成一个 `tabby-setup-portable.zip`（约 714 MB），把**这一个文件**拷给对方，解压后运行 `install.cmd` 即可。
> - **本地复制依旧快**：若 `cache` 里仍是展开的 `node_modules` 目录（旧格式），脚本会自动改用 `robocopy /MT:16` 多线程复制（实测 54s → 7.5s）。

### 配色主题选择（霓虹 / 炫酷风格）

安装时脚本会列出 **8 个炫酷主题**，每个都用 ANSI 真彩色渲染出实际样例（含配色色块），输入编号即可选择：

| # | 主题 | 风格 |
|---|------|------|
| 1 | Synthwave '84 | 合成波：霓虹粉 / 紫 / 青 |
| 2 | Cyberpunk 2077 | 赛博朋克：霓虹黄 / 青 / 红 |
| 3 | Neon Tokyo | 霓虹东京：紫 / 粉 / 青 |
| 4 | Aurora | 极光：绿 / 蓝 / 紫 |
| 5 | Vaporwave | 蒸汽波：粉 / 紫 |
| 6 | Matrix | 矩阵：全息绿 |
| 7 | Dracula | 经典紫（非霓虹） |
| 8 | TokyoNight Storm | 现代柔和（默认） |

**同时应用霓虹发光 UI 增强**（写入 `appearance.css`，随主题联动）：
- 活动标签：霓虹发光边框 + 渐变背景
- 标签栏、按钮 hover 的霓虹强调光效
- 关键：配色里的 **`colors[4]` 会成为整个 UI 的强调色**——Tabby 的 `Follow the color scheme` 主题会自动用它渲染标签栏、高亮、开关等，所以换霓虹配色 = 整个界面变炫

**非交互安装**可指定主题，跳过选择：
```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\install.ps1 -Theme "Cyberpunk 2077"
```
> 主题影响 `terminal.colorScheme` + `appearance.css`；亮色模式仍用 TokyoNight Day。

#### 如何确认主题已生效

主题写入配置后，**必须完全退出并重开 Tabby** 才会加载（配置只在启动时读一次）。生效后：

- **最直接**：在 Tabby 里输入 `tabbycolors` —— 会显示当前主题名、背景色和 16 色调色板，颜色随主题变化。
- **看界面**：终端背景变成主题底色；活动标签底部出现霓虹发光条；标签栏 / 按钮 hover 变强调色。
- **看设置**：`设置 → 外观 → 配色方案` 里显示所选主题名。
- **看配置**：`%APPDATA%\tabby\config.yaml` 的 `terminal.colorScheme.name` 与 `appearance.css` 里的 `current-tab-indicator`。

#### 提示符美化（oh-my-posh）

终端里 `PS C:\Users>` 默认是**纯文本**（只显示终端前景色）。安装脚本会额外用 **oh-my-posh** 把提示符换成彩色分段（图标 / git 分支 / 路径 / 执行时间）：

- 安装时自动 `winget install JanDeDobbeleer.OhMyPosh`
- 默认主题 **`atomic`**（现代两行、圆角 Powerline、图标 + git + 右侧时钟）部署到 `%USERPROFILE%\bin\oh-my-posh.omp.json`
- PowerShell profile 部署到 `Documents\WindowsPowerShell\` 与 `Documents\PowerShell\`；若已有自定义 profile，则**追加**一个代码块而不覆盖
- **打开新的 Tabby 标签页 / 重开 Tabby** 即可看到新提示符（profile 在 PowerShell 启动时加载）

##### 换主题：`omp` 选择器

在 Tabby 里运行 `omp`，会列出精选的炫酷主题，并**在真实终端里用真彩色渲染预览**，输入编号回车即可应用：

```
   1) atomic                现代两行 · 图标+git · 简约炫  *当前
   2) jandedobbeleer        经典彩色分段 · 默认风
   3) powerlevel10k_rainbow 彩虹分段 · 最炫
   4) paradox               粗体 Powerline · 硬核
   5) aliens                太空异形风
   ...
   L) 列出全部主题并预览    Q) 退出
```

- `L` 可列出内置的**全部主题**（122 个），输入名字即可预览
- 应用后会写入 `%USERPROFILE%\bin\oh-my-posh.omp.json`，并在 `oh-my-posh.theme.txt` 记录当前主题名（`omp` 里显示 `*当前`）
- 重开标签页生效

内置主题位于 oh-my-posh 安装目录的 `themes\` 下（Store 版为 `C:\Program Files\WindowsApps\ohmyposh.cli_*\themes`）。也可以手动把任意 `.omp.json` 覆盖到 `%USERPROFILE%\bin\oh-my-posh.omp.json`。

##### 两类「主题」别搞混

| 命令 | 换的是 | 影响范围 |
|---|---|---|
| `tabbytheme` | Tabby **终端配色**（colorScheme + 霓虹发光 CSS） | 标签栏发光、终端背景、ANSI 16 色 |
| `omp` | oh-my-posh **命令提示符** | 提示符样式（开新标签加载） |

两者**互不影响**，可分别设置。安装包里 `install.ps1` 的配色选择与 `tabbytheme` 用的是同一套主题。

#### 智能补全（灰字内联预测）

默认 shell 是 **PowerShell 7 (pwsh)**，profile 已启用 **PSReadLine 预测性智能提示 + `CompletionPredictor`**：输入前缀即用灰字提示命令/参数（**即使从未用过**），按 `→` / `End` 采纳（类似 fish / cmd+Clink）。

- `install.ps1` 会自动：装 **PowerShell 7** → 把 Tabby 默认 shell 设为 `local:powershell-core` → 装 **CompletionPredictor**（CurrentUser 级，免管理员）
- 验证：在 pwsh 新标签输入 `(Get-PSReadLineOption).PredictionSource`，应返回 `HistoryAndPlugin`
- 改"菜单式"列表（非内联灰字）：`Set-PSReadLineOption -PredictionViewStyle ListView`
- 回退：若 PowerShell 7 不可用，则留在 **Windows PowerShell 5.1**，`install.ps1` 会把自带 PSReadLine 2.0 升级到 2.4+，预测来自**历史记录**（用过一次的命令即可被提示）
- 手动（pwsh）：`pwsh -Command 'Install-Module CompletionPredictor -Scope CurrentUser -Force'`

---

## 四、手动安装步骤（脚本失效时照做）

### 1. 安装 Tabby
```powershell
winget install --id Eugeny.Tabby --accept-package-agreements --accept-source-agreements
```

### 2. 部署配置
关闭 Tabby，然后把 `assets\config.yaml` 复制到：
```
%APPDATA%\tabby\config.yaml
```
（即 `C:\Users\<用户名>\AppData\Roaming\tabby\config.yaml`）

### 3. 安装字体 JetBrainsMono Nerd Font
1. 下载字体包（任选其一）：
   - 官方：`https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip`
   - 镜像：`https://ghfast.top/https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip`
2. 解压，取 `JetBrainsMonoNerdFontMono-*.ttf`（**Mono** 版本，严格等宽）
3. 复制到 `%LOCALAPPDATA%\Microsoft\Windows\Fonts`
4. 注册到用户字体（免管理员）：
```powershell
$reg = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
$fontDir = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
foreach ($s in 'Regular','Bold','Italic','BoldItalic','Medium','MediumItalic','Light','LightItalic','SemiBold','SemiBoldItalic') {
    $f = "JetBrainsMonoNerdFontMono-$s.ttf"
    New-ItemProperty -Path $reg -Name "JetBrainsMono Nerd Font Mono $s (TrueType)" `
        -Value (Join-Path $fontDir $f) -PropertyType String -Force | Out-Null
}
```

### 4. 安装插件
```powershell
$pluginDir = "$env:APPDATA\tabby\plugins"
New-Item -ItemType Directory -Path $pluginDir -Force | Out-Null
Copy-Item .\assets\plugins.package.json (Join-Path $pluginDir 'package.json') -Force
Set-Location $pluginDir
npm.cmd install --no-audit --no-fund
```
> Tabby 内部就是用 npm 的 Arborist 引擎安装插件到该目录，此方式与官方 UI 安装完全一致。

---

## 五、配置改动明细（`config.yaml`）

### 外观 / 界面
| 项 | 值 | 作用 |
|----|----|------|
| `appearance.theme` | Follow the color scheme | UI 跟随终端配色 |
| `appearance.frame` | thin | 细边框 |
| `appearance.tabsLocation` | top | 标签在顶部 |
| `appearance.flexTabs` | true | 标签宽度自适应 |
| `appearance.opacity` | 0.95 | 轻微透明 |
| `appearance.vibrancy` | true | 亚克力毛玻璃（Win11） |
| `appearance.vibrancyType` | blur | 模糊类型 |
| `appearance.colorSchemeMode` | dark | 深色模式 |
| `appearance.css` | 自定义 | 美化终端滚动条 |
| `enableWelcomeTab` | false | 关闭欢迎页（启动更快） |
| `enableAnalytics` | false | 关闭遥测 |
| `recoverTabs` | false | 关闭标签恢复，避免启动时重复打印上次终端内容（含 Clink 横幅与 "History restored"） |
| `hacks.disableVibrancyWhileDragging` | true | 拖拽时不卡顿 |

### 终端
| 项 | 值 | 作用 |
|----|----|------|
| `terminal.font` | JetBrainsMono NFM | Nerd Font |
| `terminal.profile` | local:powershell | 新标签默认用 PowerShell（Tabby 默认本是 cmd+Clink） |
| `terminal.fontSize` | 15 | 字号 |
| `terminal.ligatures` | true | 连字 |
| `terminal.cursor` / `cursorBlink` | block / true | 块状闪烁光标 |
| `terminal.scrollbackLines` | 100000 | 回滚缓冲 |
| `terminal.copyOnSelect` | true | 选中即复制 |
| `terminal.rightClick` | clipboard | 右键粘贴 |
| `terminal.linePadding` | 1 | 行间距（日志更易读） |
| `terminal.colorScheme` | TokyoNight Storm | 深色配色 |
| `terminal.lightColorScheme` | TokyoNight Day | 亮色配色 |

---

## 六、插件清单（8 个）

安装位置：`%APPDATA%\tabby\plugins\node_modules`

| 插件 | 版本 | 用途 |
|------|------|------|
| tabby-clickable-links | 4.2.0 | URL / IP / 文件路径可点击 |
| tabby-save-output | 3.1.0 | 终端输出保存到文件（日志） |
| tabby-quick-cmds | 1.2.3 | 快速命令管理器 |
| tabby-highlight | 3.0.0 | 关键字高亮（文本/正则/JS） |
| tabby-serial-timestamp | 1.0.3 | 串口会话时间戳 |
| tabby-terminal-charset | 2.0.2 | 切换字符编码（GBK 等） |
| tabby-trzsz | 1.0.7 | `trz`/`tsz` 文件传输 |
| tabby-search-in-browser | 0.0.1 | 选中文本用浏览器搜索 |

---

## 七、快速命令（`config.yaml` 的 `qc` 节）

按 **PowerShell** 语法预设，共 4 组：

| 分组 | 命令 |
|------|------|
| **ADB & 设备** | 查看连接设备 / 重启 ADB 服务 / 设备型号与版本 / 屏幕截图 |
| **日志 logcat** | 实时日志 / 清空日志缓冲 / 日志保存到文件 / 日志过滤关键字 |
| **Git** | 查看状态 / 拉取更新 / 最近提交 / 全部暂存 |
| **帮助** | 显示功能清单（`tabbyhelp`） |

---

## 八、使用方法

| 操作 | 快捷键 |
|------|--------|
| 打开快速命令菜单 | `Alt + Q` |
| 打开设置 | `Ctrl + ,` |
| 放大 / 缩小 / 重置字号 | `Ctrl + =` / `Ctrl + -` / `Ctrl + 0` |
| 新建 / 关闭标签 | `Ctrl + Shift + T` / `Ctrl + Shift + W` |
| 分屏 右 / 下 | `Ctrl + Shift + S` / `Ctrl + Shift + D` |
| 切换标签 | `Ctrl + Tab` |

- **clickable-links**：`Ctrl + 点击` 打开链接/路径
- **save-output**：标签右键或工具栏按钮选择保存文件
- **highlight**：设置 → Highlight 添加关键字规则
- **charset**：SSH/串口标签右键切换编码（如 `gbk`）
- **trzsz**：SSH 会话中运行 `trz` / `tsz` 传输文件
- **quick-cmds**：设置 → Quick commands 可视化增删改
- **tabbyhelp**：在任意 Tabby 终端输入 `tabbyhelp`，列出全部已配置功能与用法
- **tabbycolors**：查看当前 Tabby 配色是否生效（主题名 + 16 色调色板）
- **tabbytheme**：随时切换 Tabby 终端配色（8 个霓虹主题，真彩色预览，自动重启）
- **omp**：切换 oh-my-posh 提示符主题（16 精选 + 全部 122）

---

## 十、`tabbyhelp` 命令

在任意 Tabby 终端输入 `tabbyhelp`，即可打印全部已配置功能与用法。

- 实现：`%USERPROFILE%\bin\tabbyhelp.cmd` 用 `type` 直接输出同目录 `tabbyhelp.txt`（GBK 编码）。
  - 清单分隔线使用 `*` 号。
  - 内容涵盖：外观/终端、**提示符 oh-my-posh（`omp` 用法）**、8 个插件、快速命令、快捷键、`tabbyhelp`/`tabbycolors`/`tabbytheme`/`omp` 工具箱。
  - 「配置同步包」路径为**动态注入**：`scripts\tabbyhelp.txt` 内用占位符 `@TABBY_SETUP_DIR@`，`install.ps1` 部署时替换为**本机实际路径**，所以每台设备显示的路径都准确。
- 该目录已加入用户 PATH；若新终端找不到，重开终端或确认 `%USERPROFILE%\bin` 在 PATH 中
- 也可在 Tabby 快速命令菜单（`Alt+Q`）→ **帮助 → 显示功能清单**
- 更新清单：直接编辑 `scripts\tabbyhelp.txt`（保持 **GBK 编码**），或同步本目录后重跑 `install.ps1`

---

## 九、维护与迁移

- **备份配置**：Tabby 关闭时复制 `%APPDATA%\tabby\config.yaml` 覆盖 `assets\config.yaml`。
- **更新插件清单**：复制 `%APPDATA%\tabby\plugins\package.json` 覆盖 `assets\plugins.package.json`。
- **迁移到新设备**：
  1. **推荐**先在网好的机器跑 `prefetch.cmd` 备好 `cache\`
  2. 通过 Git / U 盘 / 网盘把**整个目录（含 `cache\`）**带过去
  3. 运行 `install.ps1`（有 `cache\` 即离线秒装）
- **注意**：Tabby 会在退出时把内存配置回写 `config.yaml`，因此**改配置前先关闭 Tabby**。

## 十、安全与恢复（重要）

改配置最大的风险是写到一半被打断，留下**全零/半截的 `config.yaml`**，导致 Tabby 启动即崩。脚本已做如下防护：

- **原子写入**：先写 `config.yaml.tmp`，校验通过后再原子改名覆盖 `config.yaml`，绝不会留下半截文件。
- **写前备份**：每次写入前，把上一份可用配置复制为 `config.yaml.backup`（Tabby 官方也会从这里自动恢复）。
- **内容校验**：新配置缺少 `version:` 或过小直接中止，**不动**你的原配置。
- **读前自愈**：若读取到的 `config.yaml` 已损坏，自动改用 `config.yaml.backup`。
- **安全停进程**：停止 Tabby 后轮询等待进程真正退出，再动配置文件。

### 万一 Tabby 还是打不开

1. 关闭 Tabby。
2. 删除（或改名）`%APPDATA%\tabby\config.yaml`。
3. 把 `%APPDATA%\tabby\config.yaml.backup` 复制一份改名为 `config.yaml`。
4. 重新启动 Tabby。

或直接重跑 `install.cmd`（它会重新部署一份已知可用的 `config.yaml` 模板）。

---

## 十一、卸载（`uninstall.cmd`）

双击 `uninstall.cmd`，或在 `scripts\` 下运行 `uninstall.ps1`。运行前会先列出**将要移除的清单**，确认后执行。

**默认行为**：还原个性化设置 + 卸载 **Tabby**；oh-my-posh、PowerShell 7 **询问**；Node.js **保留**。

| 类别 | 内容 |
|------|------|
| 提示符 | 两个 PowerShell profile 中的 oh-my-posh / PSReadLine 块（只删本包写入的部分，保留你原有内容） |
| 命令 | `%USERPROFILE%\bin` 里的 `tabbyhelp` / `tabbycolors` / `tabbytheme` / `omp` 等 10 个文件（目录空了才删目录并移出 PATH） |
| 模块 | `CompletionPredictor` |
| 字体 | JetBrainsMono Nerd Font Mono（10 个样式 + 注册表项 + 文件） |
| 插件 | Tabby 的 `node_modules` / `package.json` 等 |
| 配置 | `config.yaml`（**先备份**为 `config.yaml.uninstalled-bak` 再移除，Tabby 下次启动生成默认配置） |
| 程序 | **Tabby**（卸载）；**oh-my-posh**、**PowerShell 7**（询问，见下） |

**保留**：**Node.js / npm** —— 本机由 `nvm4w` 管理，非本包安装。

### oh-my-posh / PowerShell 7 的处理（安装时记录）

- `install.ps1` 会在安装前检测本机是否**已存在** oh-my-posh 与 PowerShell 7，并把结果写入
  `%LOCALAPPDATA%\tabby-setup\install-state.json`。
- 卸载时若检测到它们，会**询问**是否卸载：
  - 本包安装的 → 默认 `Y`（卸载）
  - 安装前本机已有 / 来源未知 → 默认 `N`（保留）
- 非交互（`-Yes`）时按上述默认自动决定。
- 若选择卸载 **PowerShell 7**，卸载脚本会把 Tabby 默认 shell 从 `local:powershell-core` **回退为** `local:powershell`（系统自带 5.1），保证新标签页仍能打开。

> **PowerShell 7 vs 系统自带 5.1**：两者并存、互不覆盖。7 更快、支持新语法、默认 UTF-8、补全体验更好；但它被别的终端/脚本共用，删除前请确认没有别的地方依赖 `pwsh`。

### 可选参数

| 参数 | 作用 |
|------|------|
| `-Yes` | 不再询问，直接执行（oh-my-posh / pwsh 按记录默认） |
| `-KeepApps` | 只还原个性化设置，**不**卸载任何程序（含 Tabby） |
| `-UninstallOmp` | 一并卸载 oh-my-posh |
| `-KeepOmp` | 强制保留 oh-my-posh |
| `-UninstallPwsh` | 一并卸载 PowerShell 7 |
| `-KeepPwsh` | 强制保留 PowerShell 7 |
| `-KeepFont` | 保留字体 |
| `-KeepConfig` | 保留 Tabby 配置 |
| `-DryRun` | 只看卸载计划，不改动任何东西 |

> ⚠️ 字体（JetBrainsMono Nerd Font Mono）你若在 VS Code / Windows Terminal 也在用，删除后会回退成别的字体；想保留加 `-KeepFont`。
>
> 卸载后 PATH 的变更需**新开终端**才生效。
