# Scripts

A collection of scripts organized by language and purpose.

## Structure

```
.
├── README.md
├── python/         # Python scripts
├── bash/           # Bash / shell scripts
│   └── realm.sh    # Realm 端口转发管理面板
└── tools/          # Standalone tools and utilities
```

## Directories

- **python/** — Python scripts and utilities.
- **bash/** — Bash and other shell scripts.
- **tools/** — Standalone tools and helper utilities.

## Scripts

### bash/realm.sh — Realm 端口转发管理面板

适用于 **Alpine Linux / OpenRC** 的 [Realm](https://github.com/zhboner/realm) 端口转发交互式管理面板（POSIX `sh`）。

**功能**

- 安装 / 升级 Realm（自动检测架构，从 GitHub 获取最新版本；升级时若服务在运行会自动重启）
- 规则管理：添加 / 删除 / 重置 / 备份与还原转发规则（改动后若服务在运行会自动重启生效）
- 服务管理：启动 / 停止 / 重启，以及开机自启开关
- 状态查看：版本、运行状态、规则列表与端口监听检测
- 日志查看：尾部输出、清空、实时跟踪
- 一键卸载

**一键安装 / 运行**（需 root）

```sh
curl -fsSL https://raw.githubusercontent.com/pmjkkk/script/main/bash/realm.sh -o realm.sh && chmod +x realm.sh && ./realm.sh
```

按菜单提示选择 `0-6` 即可操作。

## Usage

Place new scripts in the directory that matches their language or purpose.
