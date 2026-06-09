# Scripts

一个按语言和用途整理的脚本集合。

## 目录结构

```
.
├── README.md
├── Shell/
│   ├── realm.sh    # Realm 端口转发管理面板
│   └── snell.sh    # Snell Server 管理工具
├── python/         # Python 脚本
└── tools/          # 独立工具与实用程序
```

## 分类说明

| 目录 | 说明 |
|------|------|
| `Shell/` | Shell 脚本 |
| `python/` | Python 脚本与工具 |
| `tools/` | 独立工具与辅助程序 |

---

## Shell/realm.sh — Realm 端口转发管理面板

适用于 **Alpine Linux / OpenRC** 的 [Realm](https://github.com/zhboner/realm) 端口转发交互式管理面板（POSIX `sh`）。

### 功能

- **安装 / 升级**：自动检测架构，从 GitHub 拉取最新版本；升级时若服务在运行会自动重启
- **规则管理**：添加 / 删除 / 重置 / 备份与还原转发规则（改动后自动重启生效）
- **服务管理**：启动 / 停止 / 重启，开机自启开关
- **状态查看**：版本、运行状态、规则列表与端口监听检测
- **日志管理**：尾部输出、清空、实时跟踪
- **一键卸载**

### 一键安装 / 运行（需 root）

```sh
curl -fsSL https://raw.githubusercontent.com/pmjkkk/script/main/Shell/realm.sh -o realm.sh && chmod +x realm.sh && ./realm.sh
```

按菜单提示选择 `0–6` 即可操作。

---

## Shell/snell.sh — Snell Server 管理工具

适用于 **Alpine Linux** 的 [Snell](https://github.com/surge-networks/snell) 代理服务端交互式管理工具（`ash`）。

### 功能

- **安装 / 升级**：自动探测最新版本，按架构下载对应二进制；升级保留配置，自动重启
- **配置管理**：交互式设置端口、PSK、obfs 等参数，支持一键重置
- **服务管理**：启动 / 停止 / 重启（OpenRC），以及开机自启开关
- **状态查看**：版本、运行状态、配置摘要（IP / 端口 / PSK / 地区）
- **日志管理**：尾部输出、实时跟踪、一键清空
- **一键卸载**：清理二进制、配置、服务文件及专用用户

### 一键安装 / 运行（需 root）

```sh
curl -fsSL https://raw.githubusercontent.com/pmjkkk/script/main/Shell/snell.sh -o snell.sh && chmod +x snell.sh && ./snell.sh
```

按菜单提示操作即可。

---

## 贡献

将新脚本放入与其语言或用途匹配的目录，并在本 README 中补充对应说明。
