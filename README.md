# Scripts

Alpine Linux 运维脚本集。

## 索引

| 脚本 | 用途 |
|------|------|
| [`shell/realm.sh`](#shellrealmsh) | Realm 端口转发管理面板 |
| [`shell/proxy.sh`](#shellproxysh) | 多协议代理服务端管理 |

---

## shell/realm.sh

基于 [Realm](https://github.com/zhboner/realm) 的端口转发管理面板，适用于 Alpine Linux / OpenRC。

**功能**：安装/升级、转发规则增删改查、服务管理、状态查看、日志、一键卸载。

```sh
curl -fsSL https://raw.githubusercontent.com/pmjkkk/script/main/shell/realm.sh | ash
```

---

## shell/proxy.sh

六协议代理服务端管理脚本，适用于 Alpine Linux / OpenRC。

| 协议 | 实现 | SNI/证书 | 输出节点 |
|---|---|---|---|
| [Snell](https://github.com/surge-networks/snell) | 官方 CDN 二进制，自动探测最新版 | — | Surge |
| [Shadowsocks](https://github.com/shadowsocks/shadowsocks-rust) | Alpine apk（shadowsocks-rust） | — | Surge / SS URI |
| [Hysteria2](https://github.com/apernet/hysteria) | GitHub release 二进制 | 自签 ECC 证书 | Surge |
| [Trojan](https://github.com/p4gefau1t/trojan-go) | GitHub release 二进制 | 自签 ECC 证书 | Surge |
| [SOCKS5](https://www.inet.no/dante/) | Alpine apk（dante-server） | — | socks5:// URI |
| [AnyTLS](https://github.com/anytls/anytls-go) | GitHub release 二进制 + SHA256 校验 | 自签证书 | Surge |

**功能**：安装/配置/更新/卸载、随机端口、自动生成密钥、公网 IP 与地区检测、Surge 节点输出、服务开机自启。

> Shadowsocks 加密：`2022-blake3-aes-128-gcm`（需 base64 格式密钥）  
> 自签证书协议（Hysteria2 / Trojan / AnyTLS）客户端需配置 `skip-cert-verify = true`

```sh
curl -fsSL https://raw.githubusercontent.com/pmjkkk/script/main/shell/proxy.sh | ash
```
