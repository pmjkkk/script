# Scripts

> Alpine Linux 运维脚本集 · 开箱即用的交互式终端管理面板

<p align="center">
  <img src="https://img.shields.io/badge/Alpine-3.x-0D597F?logo=alpinelinux&logoColor=white" alt="Alpine">
  <img src="https://img.shields.io/badge/init-OpenRC-4B8BBE" alt="OpenRC">
  <img src="https://img.shields.io/badge/arch-x86__64%20%7C%20aarch64-555" alt="Arch">
  <img src="https://img.shields.io/badge/shell-ash%2FPOSIX-89E051?logo=gnu-bash&logoColor=white" alt="Shell">
</p>

| 脚本 | 说明 |
|------|------|
| [**`shell/proxy.sh`**](#-shellproxysh) | 多协议代理服务端管理 · 六协议一键部署 |
| [**`shell/realm.sh`**](#-shellrealmsh) | Realm 端口转发管理面板 |

---

## 🚀 shell/proxy.sh

六协议代理服务端一站式管理脚本，适用于 **Alpine Linux / OpenRC**。

```sh
curl -fsSL https://raw.githubusercontent.com/pmjkkk/script/main/shell/proxy.sh -o proxy.sh && chmod +x proxy.sh && ./proxy.sh
```

### 支持协议

| # | 协议 | 部署方式 | 传输 | 证书 |
|:---:|------|----------|:----:|:----:|
| 1 | [Snell](https://github.com/surge-networks/snell) | 官方 CDN 二进制（自动探测最新版） | TCP | — |
| 2 | [Shadowsocks](https://github.com/shadowsocks/shadowsocks-rust) | apk · shadowsocks-rust | TCP/UDP | — |
| 3 | [Hysteria2](https://github.com/apernet/hysteria) | GitHub release | UDP | 自签 ECC · 脚本生成 |
| 4 | [Trojan](https://github.com/p4gefau1t/trojan-go) | GitHub release | TCP | 自签 ECC · 脚本生成 |
| 5 | [SOCKS5](https://www.inet.no/dante/) | apk · dante-server | TCP | — |
| 6 | [AnyTLS](https://github.com/anytls/anytls-go) | GitHub release（SHA256 校验） | TCP | 自签 · 程序内置 |

> 安装后均输出 **Surge 节点**，公网 IP 与地区自动检测。
>
> **证书说明**：Hysteria2 / Trojan 由脚本用 OpenSSL 预生成 ECC 证书落盘；AnyTLS 由服务端进程启动时自动生成（不落盘）。三者客户端均需 `skip-cert-verify = true`。

### 功能特性

- **🎯 交互式安装** — 端口 / 密码 / PSK / SNI / 用户名逐项询问，回车即用随机默认值
- **🔄 完整生命周期** — 安装 / 配置 / 更新 / 卸载，配置变更自动备份回滚
- **📦 开箱即用** — 自动装依赖、随机可用端口、生成密钥、自签证书、注册开机自启
- **🧹 干净卸载** — 二进制 / 配置 / 证书 / 系统用户全部清除，零残留

### 界面预览

```text
  ╭─── 代理服务管理  Alpine Linux · OpenRC
  ──────────────────────────────────────────────
    [1]  Snell        ● 运行中  v5.0.1
    [2]  Shadowsocks  ● 运行中  v1.24.0
    [3]  Hysteria2    ● 运行中  v2.9.2
    [4]  Trojan       ○ 未安装
    [5]  SOCKS5       ○ 未安装
    [6]  AnyTLS       ● 运行中  v0.0.12
    [0]  退出
  ──────────────────────────────────────────────
   ❯ 请选择 [0-6]
```

### 注意事项

| 项 | 说明 |
|----|------|
| Shadowsocks 加密 | 固定 `2022-blake3-aes-128-gcm`，密码为 16 字节 base64（自动生成） |
| 自签证书协议 | Hysteria2 / Trojan / AnyTLS 客户端需设 `skip-cert-verify = true` |
| Snell 依赖 | 需 `gcompat` + `musl-obstack`（glibc 兼容层），脚本自动处理 |
| SNI 默认值 | `addons.mozilla.org` |

> ✅ 已在 Alpine 3.23 / x86_64 真机验证六协议安装、运行、卸载全流程。

---

## 🔀 shell/realm.sh

基于 [Realm](https://github.com/zhboner/realm) 的端口转发管理面板，适用于 Alpine Linux / OpenRC。

```sh
curl -fsSL https://raw.githubusercontent.com/pmjkkk/script/main/shell/realm.sh -o realm.sh && chmod +x realm.sh && ./realm.sh
```

**功能**：安装 / 升级（自动检测架构与最新版）· 转发规则增删改查 · 服务管理 · 状态查看 · 日志查看 · 一键卸载。

---

<p align="center"><sub>仅供学习与合法用途 · 请遵守所在地法律法规</sub></p>
