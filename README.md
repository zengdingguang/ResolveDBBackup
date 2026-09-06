<div align="center">

<img src="docs/images/app-icon.png" alt="水螅 Resolve Backup" width="128" height="128">

# 水螅 Resolve Backup

### 达芬奇 DaVinci Resolve 数据库自动备份工具

**macOS 菜单栏 App · 双架构支持（Apple Silicon + Intel）**

[![macOS](https://img.shields.io/badge/macOS-14.0+-000000?style=flat-square&logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9-FA7343?style=flat-square&logo=swift)](https://swift.org/)
[![Release](https://img.shields.io/github/v/release/zengdingguang/ResolveDBBackup?style=flat-square)](https://github.com/zengdingguang/ResolveDBBackup/releases)
[![License](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)](LICENSE)

[下载安装包](https://github.com/zengdingguang/ResolveDBBackup/releases/latest) · [使用教程](#使用教程) · [功能特性](#功能特性)

</div>

---

## 为什么叫"水螅"？

水螅通过**出芽生殖**产生新的芽体，芽体与母体的基因完全相同——这正是数据库备份的本质：**完整克隆母体，确保数据永不丢失**。

---

## 功能特性

### 三种数据库类型，全面覆盖

| 类型 | 说明 | 扫描方式 |
|---|---|---|
| 🖥️ **本地磁盘库** | 达芬奇本地项目库（Resolve Projects） | 自动扫描官方默认目录 + 自定义路径 |
| 🔗 **本机共享库** | 本机 PostgreSQL 网络数据库（127.0.0.1） | 自动扫描本机 PostgreSQL 实例 |
| 🌐 **局域网共享库** | 局域网内其他电脑的达芬奇数据库 | 自动扫描整个 /24 网段 + 手动指定 IP |

### 智能自动扫描

- **一键自动扫描**：同时发现本机磁盘库 + 本机共享库，无需手动配置
- **局域网全网段扫描**：自动发现局域网内所有运行中的 PostgreSQL 数据库
- **手动添加**：支持手动输入主机、端口、数据库名、用户名、密码
- **默认凭据自动填充**：达芬奇默认密码 `DaVinci` 自动填入，可修改

### 全局备份机制

- **间隔分钟**：自定义备份间隔（默认 10 分钟）
- **三级保留策略**（类 Time Machine）：
  - 最近 **24 小时内**：全部保留
  - 超过 **24 小时**：每天保留 1 份（当天最后一份）
  - 超过 **1 个月**：每月保留 1 份（当月最后一份）
- **全局统一备份路径**：所有数据库备份统一管理，按数据库名分文件夹

### 安全可靠

- **Keychain 存储密码**：数据库密码存在 macOS 钥匙串，不落盘到配置文件
- **pg_dump 自定义格式**：`--blobs` 含大对象，`pg_restore` 一键还原
- **失败系统通知**：备份失败时右上角弹出 macOS 系统通知
- **单库失败不阻断**：某个数据库备份失败不影响其他数据库
- **配置自动备份**：配置 JSON 实时同步到备份根目录，换机/恢复无忧

### 定时调度

- **用户级 LaunchAgent**（SMAppService）：无需 root，开机自启
- **菜单栏常驻**：一键立即备份全部、查看状态、打开管理面板
- **双击即开**：App 运行中再次双击自动弹出主界面

---

## 系统要求

- **macOS 14.0 (Sonoma)** 或更高版本
- **Apple Silicon** (M1 / M2 / M3 / M4) 或 **Intel** 处理器（双架构通用）
- 达芬奇 DaVinci Resolve（数据库由达芬奇创建，本工具负责备份）

---

## 安装方法

### 方式一：直接下载（推荐）

1. 前往 [Releases 页面](https://github.com/zengdingguang/ResolveDBBackup/releases/latest)
2. 下载 `水螅ResolveBackup-v1.7.6-macOS.zip`
3. 解压后将 `水螅ResolveBackup.app` 拖到「应用程序」文件夹
4. 双击打开（首次打开可能需要右键 → 打开）

### 方式二：自行编译

```bash
git clone https://github.com/zengdingguang/ResolveDBBackup.git
cd ResolveDBBackup
swift build
.build/debug/ResolveDBBackup
```

---

## 使用教程

### 第一步：扫描数据库

1. 打开 App，进入「连接」页面
2. 点击 **「自动扫描数据库」**——同时发现本机磁盘库 + 本机共享库
3. 如需备份局域网其他电脑的数据库，点击 **「扫描局域网数据库」**
4. 勾选要备份的数据库，点击「添加所选」

### 第二步：配置备份任务

1. 进入「备份任务」页面
2. 设置**全局备份位置**（建议选择外接硬盘，确保数据安全）
3. 设置**备份间隔**（分钟，默认 10 分钟）
4. 点击「保存设置」
5. 为每个数据库启用备份任务（开关打开）

### 第三步：开始备份

- 点击「立即备份全部」手动触发一次备份
- 之后 App 会按设定的间隔自动备份
- 菜单栏图标可随时查看备份状态、触发立即备份

### 第四步：还原数据库

备份文件为 pg_dump 自定义格式（`.backup`），使用 `pg_restore` 还原：

```bash
pg_restore --host=127.0.0.1 --port=5432 --username=postgres \
  --dbname=目标数据库名 --no-password 备份文件.backup
```

---

## 备份输出结构

```
备份根目录/
├── 数据库名1/
│   ├── 数据库名1_2026_09_06_10_00.backup
│   ├── 数据库名1_2026_09_06_10_10.backup
│   └── ...
├── 数据库名2/
│   └── ...
└── ResolveDBBackup-config.json  （配置自动备份）
```

---

## 常见问题

**Q：为什么需要输入电脑密码？**
A：首次访问钥匙串中的数据库密码时，macOS 会要求授权。点击「始终允许」后后续不再提示。

**Q：备份文件存在哪里？**
A：默认在 `~/DaVinci Database Auto Backup/`，可在设置中自定义，**强烈建议选择外接硬盘**。

**Q：支持哪些达芬奇版本？**
A：支持所有使用 PostgreSQL 网络数据库的达芬奇版本，以及本地磁盘库。

**Q：会备份项目文件 (.drp) 吗？**
A：项目数据包含在 PostgreSQL 数据库中，pg_dump 会完整转储。

---

## 免责声明

本软件按"现状"提供，不提供任何明示或暗示的担保。使用者应自行验证备份数据的完整性与可恢复性。因使用本软件造成的任何数据损失，作者不承担责任。

**重要**：备份完成后，请定期使用 `pg_restore --list` 校验备份文件，并在测试环境中验证还原流程。

---

## 作者

**调色师 zengdingguang（曾定光）**

- 职业：电影视频广告调色师
- 反馈邮箱：[402481025@qq.com](mailto:402481025@qq.com)

如果这个软件对你有帮助，欢迎请作者喝杯咖啡 ☕

<div align="center">
<img src="docs/images/donation-qr.png" alt="打赏二维码" width="180">
<p>别等数据库炸了才想起我。扫码赏点，让我有电继续给你站岗。</p>
</div>

---

## 许可证

[MIT License](LICENSE)

---

<div align="center">

**水螅 Resolve Backup** · 让你的达芬奇数据库永远有备份

[⬇️ 下载最新版](https://github.com/zengdingguang/ResolveDBBackup/releases/latest) · [⭐ 点个 Star](https://github.com/zengdingguang/ResolveDBBackup) · [🐛 反馈问题](https://github.com/zengdingguang/ResolveDBBackup/issues)

</div>
