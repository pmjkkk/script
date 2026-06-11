# Scripts

Alpine Linux 运维脚本集，按语言和用途分类整理。

## 快速索引

| 脚本 | 用途 | 推荐场景 |
|------|------|----------|
| `Shell/realm.sh` | Realm 端口转发管理面板 | 端口映射 / 流量转发 |
| `Shell/proxy.sh` | Snell & AnyTLS 统一管理工具 | 代理服务端部署 |

## 目录结构

```
.
├── README.md
├── Shell/          # Shell 脚本（POSIX sh / ash）
│   ├── proxy.sh    Snell & AnyTLS 统一管理
│   └── realm.sh    Realm 端口转发管理面板
├── python/         # Python 脚本
└── tools/          # 独立工具与辅助程序
```

---

## Shell/realm.sh — Realm 端口转发管理面板

适用于 **Alpine Linux / OpenRC** 的 [Realm](https://github.com/zhboner/realm) 端口转发交互式管理面板（POSIX `sh`）。

**功能一览**

- 安装 / 升级 Realm（自动检测架构，从 GitHub 获取最新版本）
- 转发规则增删改查、备份还原
- 服务管理（启动/停止/重启/开机自启）
- 状态查看（版本、运行状态、端口监听检测）
- 日志跟踪（尾部输出、实时跟踪、清空）
- 一键卸载

**一键安装**

```sh
curl -fsSL https://raw.githubusercontent.com/pmjkkk/script/main/Shell/realm.sh -o realm.sh && chmod +x realm.sh && ./realm.sh
```

运行后按菜单提示输入 `0–6` 即可操作。

---

## Shell/proxy.sh — Snell & AnyTLS 统一管理工具

适用于 **Alpine Linux / OpenRC** 的一站式代理服务端管理脚本（`ash`），同时管理 [Snell](https://github.com/surge-networks/snell) 和 [AnyTLS](https://github.com/anytls/anytls-go) 两个服务。

**功能一览**

| 功能 | Snell | AnyTLS |
|------|-------|--------|
| 安装 / 升级 / 卸载 | ✅ | ✅ |
| 端口、PSK/密码、obfs/SNI 配置 | ✅ | ✅ |
| 服务管理（启动/停止/重启/自启） | ✅ | ✅ |
| 配置查看、重置、备份还原 | ✅ | ✅ |
| 日志跟踪 | ✅ | ✅ |

**一键安装**

```sh
curl -fsSL https://raw.githubusercontent.com/pmjkkk/script/main/Shell/proxy.sh -o proxy.sh && chmod +x proxy.sh && ./proxy.sh
```

运行后按菜单提示操作即可。

---

## 贡献指南

新脚本放入对应目录（`Shell/`、`python/`、`tools/`），并在本 README 的「快速索引」和对应章节中补充说明。
