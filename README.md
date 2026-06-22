# Scripts

Alpine Linux 运维脚本集，开箱即用的交互式管理面板。

## 索引

| 脚本 | 用途 |
|------|------|
| [`shell/proxy.sh`](#shellproxysh) | 多协议代理服务端管理（六协议） |
| [`shell/realm.sh`](#shellrealmsh) | Realm 端口转发管理面板 |

---

## shell/proxy.sh

六协议代理服务端一站式管理脚本，适用于 **Alpine Linux / OpenRC**。

### 支持协议

| 协议 | 部署方式 | 传输 | 证书 | 节点格式 |
|---|---|---|:---:|---|
| [Snell](https://github.com/surge-networks/snell) | 官方 CDN 二进制（自动探测最新版） | TCP | — | Surge |
| [Shadowsocks](https://github.com/shadowsocks/shadowsocks-rust) | Alpine apk · shadowsocks-rust | TCP/UDP | — | Surge |
| [Hysteria2](https://github.com/apernet/hysteria) | GitHub release 二进制 | UDP | 自签 ECC | Surge |
| [Trojan](https://github.com/p4gefau1t/trojan-go) | GitHub release 二进制 | TCP | 自签 ECC | Surge |
| [SOCKS5](https://www.inet.no/dante/) | Alpine apk · dante-server | TCP | — | Surge |
| [AnyTLS](https://github.com/anytls/anytls-go) | GitHub release 二进制（SHA256 校验） | TCP | 自签 | Surge |

### 功能

- **交互式安装** — 端口 / 密码 / PSK / SNI / 用户名逐项询问，**回车即用随机默认值**（SNI 默认 `addons.mozilla.org`）
- **完整生命周期** — 安装 / 配置 / 更新 / 卸载，配置变更自动备份回滚
- **开箱即用** — 自动安装依赖、随机可用端口、生成密钥、自签证书、注册 OpenRC 开机自启
- **节点输出** — 安装后直接打印 Surge 节点，公网 IP 与地区自动检测
- **干净卸载** — 二进制 / 配置 / 证书 / 系统用户（含认证用户）全部清除，无残留

### 安装

```sh
curl -fsSL https://raw.githubusercontent.com/pmjkkk/script/main/shell/proxy.sh -o proxy.sh && chmod +x proxy.sh && ./proxy.sh
```

### 说明

- **Shadowsocks** 加密固定 `2022-blake3-aes-128-gcm`，密码为 16 字节 base64（脚本自动生成）。
- **自签证书协议**（Hysteria2 / Trojan / AnyTLS）客户端需设 `skip-cert-verify = true`。
- **Snell** 依赖 `gcompat` + `musl-obstack`（glibc 兼容层），脚本自动处理。
- 已在 Alpine 3.23 / x86_64 真机验证六协议安装、运行、卸载全流程。

---

## shell/realm.sh

基于 [Realm](https://github.com/zhboner/realm) 的端口转发管理面板，适用于 Alpine Linux / OpenRC。

**功能**：安装 / 升级（自动检测架构与最新版）、转发规则增删改查、服务管理、状态查看、日志查看、一键卸载。

```sh
curl -fsSL https://raw.githubusercontent.com/pmjkkk/script/main/shell/realm.sh -o realm.sh && chmod +x realm.sh && ./realm.sh
```
