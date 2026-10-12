# 修改记录（CHANGELOG）

本文件记录 `tabby-setup` 的每次改动。日期格式：`YYYY-MM-DD`。

---

## 2026-10-12 — 安装界面优化

### 新增

- `scripts/ui-lib.ps1`：安装横幅、分步进度、结果汇总（供 install / prefetch / uninstall 共用）。
- `CONVENTIONS.md`：文案与显示约定。
- `CHANGELOG.md`：本文件。

### 变更

- `scripts/install.ps1`：安装时显示横幅、9 步进度与结果行，结束时给出汇总；控制台真彩色初始化复用 `ui-lib.ps1`。
- `scripts/prefetch.ps1`：显示横幅，缓存目录与组件范围改用统一配色。
- `scripts/uninstall.ps1`：显示横幅、9 步卸载进度与汇总。
- `README.md`：补充界面说明。

### 兼容性

- 兼容 PowerShell 5.1；原有功能、参数、命令交互不变，仅改输出表现。
- GBK 控制台或输出被重定向时自动降级为纯 ASCII。
- 环境变量 `TABBY_SETUP_NO_UI=1` 可关闭彩色与图标。
