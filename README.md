# Scripts

Alpine Linux 运维脚本集。

## 索引

| 脚本 | 用途 |
|------|------|
| [`Shell/realm.sh`](#shellrealmsh) | Realm 端口转发管理面板 |
| [`Shell/proxy.sh`](#shellproxysh) | Snell & AnyTLS 代理服务端管理 |

---

## Shell/realm.sh

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
curl -fsSL https://raw.githubusercontent.com/pmjkkk/script/main/Shell/realm.sh -o realm.sh && chmod +x realm.sh && ./realm.sh
```

---

## Shell/proxy.sh

[Snell](https://github.com/surge-networks/snell) 与 [AnyTLS](https://github.com/anytls/anytls-go) 的一站式管理脚本，适用于 Alpine Linux / OpenRC。

**功能**

| | Snell | AnyTLS |
|---|:---:|:---:|
| 安装 / 更新 / 卸载 | ✅ | ✅ |
| 端口 / 密钥配置 | ✅ | ✅ |
| SNI 配置 | — | ✅ |
| 服务管理（启动 / 停止 / 自启） | ✅ | ✅ |
| 配置备份 / 还原 | ✅ | ✅ |
| 安装后输出 Surge 节点 | ✅ | ✅ |

> **注意：** AnyTLS 使用自签证书，客户端需配置 `skip-cert-verify = true`。

**安装**

```sh
curl -fsSL https://raw.githubusercontent.com/pmjkkk/script/main/Shell/proxy.sh -o proxy.sh && chmod +x proxy.sh && ./proxy.sh
```
