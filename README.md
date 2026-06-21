# Scripts

Alpine Linux 运维脚本集。

## 索引

| 脚本 | 用途 |
|------|------|
| [`shell/realm.sh`](#shellrealmsh) | Realm 端口转发管理面板 |
| [`shell/proxy.sh`](#shellproxysh) | 多协议代理服务端管理（Snell / AnyTLS / Shadowsocks / Hysteria2） |

---

## shell/realm.sh

基于 [Realm](https://github.com/zhboner/realm) 的端口转发管理面板，适用于 Alpine Linux / OpenRC。

**功能**

- 安装 / 升级（自动检测架构，获取最新版本）
- 转发规则增删改查、备份 / 还原
- 服务管理（启动 / 停止 / 重启 / 开机自启）
- 状态查看（版本、运行状态、端口监听检测）
- 日志查看（尾部输出、实时跟踪、清空）
- 一键卸载

**安装**

```sh
curl -fsSL https://raw.githubusercontent.com/pmjkkk/script/main/shell/realm.sh -o realm.sh && chmod +x realm.sh && ./realm.sh
```

---

## shell/proxy.sh

[Snell](https://github.com/surge-networks/snell)、[AnyTLS](https://github.com/anytls/anytls-go)、[Shadowsocks](https://github.com/shadowsocks/shadowsocks-rust) 与 [Hysteria2](https://github.com/apernet/hysteria) 的一站式管理脚本，适用于 Alpine Linux / OpenRC。

**功能**

| | Snell | AnyTLS | Shadowsocks | Hysteria2 |
|---|:---:|:---:|:---:|:---:|
| 安装 / 更新 / 卸载 | ✅ | ✅ | ✅ | ✅ |
| 端口 / 密钥（密码）配置 | ✅ | ✅ | ✅ | ✅ |
| SNI 配置 | — | ✅ | — | ✅ |
| 服务管理（启动 / 停止 / 自启） | ✅ | ✅ | ✅ | ✅ |
| 配置备份 / 还原 | ✅ | ✅ | ✅ | ✅ |
| 安装后输出 Surge 节点 | ✅ | ✅ | ✅ | ✅ |

**实现说明**

- **Snell** — 闭源二进制，从官方 CDN 下载（自动探测最新版本）。
- **AnyTLS** — GitHub release 二进制 + SHA256 校验，自签证书（客户端需 `skip-cert-verify=true`）。
- **Shadowsocks** — 使用 Alpine 原生 `shadowsocks-rust` 包（apk），默认加密 `aes-256-gcm`，输出 Surge 节点与 SS URI。
- **Hysteria2** — GitHub release 二进制，自签 ECC 证书 + 伪装（masquerade proxy），客户端需 `skip-cert-verify=true`。

**安装**

```sh
curl -fsSL https://raw.githubusercontent.com/pmjkkk/script/main/shell/proxy.sh -o proxy.sh && chmod +x proxy.sh && ./proxy.sh
```
