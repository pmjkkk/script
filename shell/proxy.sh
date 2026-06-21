#!/bin/ash
# shellcheck disable=SC2059  # ANSI 颜色变量出现在 printf 格式串中，属故意为之
#=============================================================================
# proxy.sh  ·  Snell & AnyTLS 管理工具  ·  Alpine Linux 专用
#=============================================================================

# ── Snell ───────────────────────────────────────────────────────────────────
readonly SNELL_BIN="/usr/local/bin/snell-server"
readonly SNELL_BIN_BAK="${SNELL_BIN}.bak"
readonly SNELL_CONF="/etc/snell/snell-server.conf"
readonly SNELL_CONF_BAK="${SNELL_CONF}.bak"
readonly SNELL_INFO="/etc/snell/config.txt"
readonly SNELL_INIT="/etc/init.d/snell"
readonly SNELL_USER="snell"
SNELL_VERSION="v5.0.1"

# ── AnyTLS ──────────────────────────────────────────────────────────────────
readonly AT_BIN="/usr/local/bin/anytls-server"
readonly AT_BIN_BAK="${AT_BIN}.bak"
readonly AT_CONF="/etc/anytls/anytls.conf"
readonly AT_CONF_BAK="${AT_CONF}.bak"
readonly AT_INFO="/etc/anytls/config.txt"
readonly AT_INIT="/etc/init.d/anytls"
readonly AT_USER="anytls"
readonly AT_API="https://api.github.com/repos/anytls/anytls-go/releases"
readonly AT_DEFAULT_SNI="addons.mozilla.org"
AT_VERSION="v0.0.12"

# ── Shadowsocks (shadowsocks-rust，apk) ──────────────────────────────────────
readonly SS_BIN="/usr/bin/ssserver"
readonly SS_CONF="/etc/shadowsocks/config.json"
readonly SS_CONF_BAK="${SS_CONF}.bak"
readonly SS_INFO="/etc/shadowsocks/config.txt"
readonly SS_INIT="/etc/init.d/shadowsocks"
readonly SS_USER="ss"
readonly SS_METHOD="aes-256-gcm"

# ── Hysteria2 ────────────────────────────────────────────────────────────────
readonly HY_BIN="/usr/local/bin/hysteria"
readonly HY_BIN_BAK="${HY_BIN}.bak"
readonly HY_DIR="/etc/hysteria"
readonly HY_CONF="${HY_DIR}/config.yaml"
readonly HY_CONF_BAK="${HY_CONF}.bak"
readonly HY_CERT="${HY_DIR}/server.crt"
readonly HY_KEY="${HY_DIR}/server.key"
readonly HY_INFO="${HY_DIR}/config.txt"
readonly HY_INIT="/etc/init.d/hysteria"
readonly HY_USER="hysteria"
readonly HY_API="https://api.github.com/repos/apernet/hysteria/releases"
readonly HY_DEFAULT_SNI="bing.com"
HY_VERSION="v2.9.2"

# ── ANSI ────────────────────────────────────────────────────────────────────
R='\033[0;31m' G='\033[0;32m' Y='\033[0;33m' C='\033[0;36m'
B='\033[1m'    D='\033[2m'    W='\033[1;37m' Z='\033[0m'

###############################################################################
# §1  输出 & 交互
###############################################################################

die()  { printf "\n${R}✗ %s${Z}\n" "$*"; exit 1; }
ok()   { printf "${G}✓ %s${Z}\n" "$*"; }
warn() { printf "${Y}⚠ %s${Z}\n" "$*"; }
info() { printf "${C}! %s${Z}\n" "$*"; }
hr()   { printf "${D}  ──────────────────────────────────────────${Z}\n"; }

# confirm  $1=提示  $2=默认 y|n（默认 n）
confirm() {
    local msg="$1" def="${2:-n}" ans hint
    [ "$def" = "y" ] && hint="${B}Y${Z}/n" || hint="y/${B}N${Z}"
    printf "${Y}  %s${Z} [%b]: " "$msg" "$hint"
    read -r ans
    [ -z "$ans" ] && ans="$def"
    [ "$ans" = "y" ] || [ "$ans" = "Y" ]
}

# ask  $1=提示  $2=默认值 → 结果写入 $REPLY
ask() {
    local msg="$1" def="$2"
    if [ -n "$def" ]; then
        printf "${C}  %s${Z}  ${D}[%s]${Z}: " "$msg" "$def"
    else
        printf "${C}  %s${Z}: " "$msg"
    fi
    read -r REPLY
    [ -z "$REPLY" ] && REPLY="$def"
}

_st=0; _st_n=0
steps_init() { _st_n="$1"; _st=0; }
step() { _st=$((_st+1)); printf "${C}[%d/%d]${Z} %s\n" "$_st" "$_st_n" "$1"; }

###############################################################################
# §2  通用工具
###############################################################################

check_root()   { [ "$(id -u)" = "0" ] || die "请以 root 权限运行此脚本"; }
check_alpine() { [ -f /etc/alpine-release ] || die "此脚本仅支持 Alpine Linux"; }

# 随机密钥（24 位字母数字）
gen_secret() { tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 24; }

# 架构检测  $1=go → Go 命名(arm64)；否则 GNU 命名(aarch64)
_arch() {
    case "$(uname -m)" in
        aarch64)      [ "$1" = "go" ] && echo "arm64" || echo "aarch64" ;;
        x86_64|amd64) echo "amd64" ;;
        *) die "不支持的系统架构: $(uname -m)（仅支持 x86_64 / aarch64）" ;;
    esac
}

# 安装缺失依赖  $@=包名列表
ensure_pkgs() {
    local missing="" p
    for p in "$@"; do
        apk info -e "$p" > /dev/null 2>&1 || missing="$missing $p"
    done
    [ -z "$missing" ] && return 0
    info "安装缺失依赖:${missing}"
    apk update -q || die "apk update 失败"
    # shellcheck disable=SC2086
    apk add -q $missing || die "apk add 失败"
    ok "依赖安装完成"
}

# 公网 IP → PUB_IP / PUB_COUNTRY
fetch_public_ip() {
    local raw
    raw=$(curl -s --connect-timeout 5 --max-time 10 \
        "https://www.cloudflare.com/cdn-cgi/trace" \
        | grep '^ip=' | sed 's/^ip=//' | tr -d '[:space:]')
    [ -z "$raw" ] && raw=$(curl -s --connect-timeout 5 --max-time 10 \
        "https://api.ipify.org" | tr -d '[:space:]')
    PUB_IP="${raw:-未知}"
    if [ "$PUB_IP" != "未知" ]; then
        PUB_COUNTRY=$(curl -s --connect-timeout 5 --max-time 10 \
            "https://ipinfo.io/${PUB_IP}/country" | tr -d '[:space:]')
        [ -z "$PUB_COUNTRY" ] && PUB_COUNTRY="未知"
    else
        PUB_COUNTRY="未知"
    fi
}

# 随机可用端口（带冲突检测）
gen_port() {
    local port seed attempts=0
    while [ $attempts -lt 20 ]; do
        seed=$(od -An -N4 -tu4 /dev/urandom | tr -d ' \n')
        port=$(awk -v s="$seed" 'BEGIN{srand(s+0); print int(rand()*35000)+30000}')
        _port_in_use "$port" || { echo "$port"; return 0; }
        attempts=$((attempts + 1))
    done
    die "无法找到可用端口，请手动指定"
}

_port_in_use() {
    if   command -v ss      > /dev/null 2>&1; then
        ss -tlnp 2>/dev/null | grep -qE ":${1}( |$)"
    elif command -v netstat > /dev/null 2>&1; then
        netstat -tlnp 2>/dev/null | grep -qE ":${1}( |$)"
    else
        return 1
    fi
}

# 服务就绪等待（点动画），10s 超时；$1=服务名
_wait_for_service() {
    local svc="$1" i=0
    printf "${C}  等待服务启动${Z}"
    while [ $i -lt 10 ]; do
        rc-service "$svc" status > /dev/null 2>&1 && { printf " ${G}就绪${Z}\n"; return 0; }
        printf "."; sleep 1; i=$((i+1))
    done
    printf " ${Y}超时${Z}\n"; return 1
}

# 服务控制  $1=动作(start/stop/enable/disable)  $2=服务名
svc() {
    case "$1" in
        start|stop) rc-service "$2" "$1"        > /dev/null 2>&1 || true ;;
        enable)     rc-update  add "$2" default > /dev/null 2>&1 || true ;;
        disable)    rc-update  del "$2"         > /dev/null 2>&1 || true ;;
    esac
}

# 删除系统用户（含 home 目录，带安全守卫）
_del_user() {
    id "$1" > /dev/null 2>&1 || return 0
    local home
    home=$(getent passwd "$1" 2>/dev/null | cut -d: -f6)
    deluser "$1" > /dev/null 2>&1 || true
    [ -n "$home" ] && [ "$home" != "/" ] && [ -d "$home" ] && rm -rf "$home"
}

# 从 GitHub API JSON 提取指定 asset 的 SHA256  $1=json  $2=asset 名
_extract_sha256() {
    echo "$1" | awk -v name="$2" '
        index($0, name) { f=1 }
        f && index($0, "digest") {
            gsub(/.*sha256:/, ""); gsub(/".*/, ""); print; exit
        }'
}

# 备份→解压→失败回滚  $1=zip  $2=bin  $3=bak  $4=zip内文件名  $5=服务名
_extract_with_rollback() {
    local zip="$1" bin="$2" bak="$3" member="$4" name="$5"
    [ -f "$bin" ] && cp "$bin" "$bak"
    if ! unzip -oq "$zip" "$member" -d /usr/local/bin; then
        rm -f "$zip"
        if [ -f "$bak" ]; then mv "$bak" "$bin"; warn "解压失败，已回滚至旧版本"; fi
        die "解压 ${name} 失败"
    fi
    rm -f "$zip" "$bak"
    chmod +x "$bin"
}

###############################################################################
# §3  Snell
###############################################################################

snell_is_installed() { [ -f "$SNELL_BIN" ]; }
snell_is_running()   { [ -f "$SNELL_INIT" ] && rc-service snell status > /dev/null 2>&1; }

snell_get_version() {
    snell_is_installed || { echo "未安装"; return; }
    "$SNELL_BIN" -version 2>&1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' || echo "未知"
}

snell_read_conf() {
    [ -f "$SNELL_CONF" ] || return 1
    CONF_PORT=$(grep '^listen' "$SNELL_CONF" | sed 's/.*://')
    CONF_PSK=$(grep  '^psk'    "$SNELL_CONF" | sed 's/.*= //')
}

snell_write_conf() {
    mkdir -p /etc/snell || return 1
    printf '[snell-server]\nlisten = ::0:%s\npsk = %s\nipv6 = true\n' \
        "$1" "$2" > "$SNELL_CONF" || return 1
}

snell_write_info() {
    printf '%s = snell, %s, %s, psk = %s, version = 5, reuse = true\n' \
        "$4" "$3" "$1" "$2" > "$SNELL_INFO"
}

snell_write_init() {
    cat > "$SNELL_INIT" << 'EOF'
#!/sbin/openrc-run
name="snell"
description="Snell Proxy Service"
command="/usr/local/bin/snell-server"
command_args="-c /etc/snell/snell-server.conf"
command_user="snell"
supervisor="supervise-daemon"
EOF
    chmod +x "$SNELL_INIT"
}

snell_show_summary() {
    # $1=port $2=psk $3=ip $4=country
    printf "\n"
    _box "Snell" "配置摘要"
    hr
    printf "    ${D}地区${Z}  %s\n" "$4"
    printf "    ${D}IP  ${Z}  %s\n" "$3"
    printf "    ${D}端口${Z}  %s\n" "$1"
    printf "    ${D}PSK ${Z}  %s\n" "$2"
    hr
    printf "  ${D}Surge 节点:${Z}\n"
    printf "  ${C}%s = snell, %s, %s, psk = %s, version = 5, reuse = true${Z}\n" \
        "$4" "$3" "$1" "$2"
    hr; printf "\n"
}

# Snell 闭源无 API，对下载 URL 发 HEAD 探测
_snell_url() {
    printf "https://dl.nssurge.com/snell/snell-server-%s-linux-%s.zip" "$1" "$(_arch)"
}

_snell_probe() {
    curl -sf --head --connect-timeout 4 --max-time 6 "$(_snell_url "$1")" > /dev/null 2>&1
}

# 从当前版本向后探测 patch（遇 404 即停），再试 minor+1.0
snell_fetch_latest() {
    local maj min pat best cand p
    maj=$(echo "$SNELL_VERSION" | grep -oE '[0-9]+' | sed -n '1p')
    min=$(echo "$SNELL_VERSION" | grep -oE '[0-9]+' | sed -n '2p')
    pat=$(echo "$SNELL_VERSION" | grep -oE '[0-9]+' | sed -n '3p')
    if [ -z "$maj" ] || [ -z "$min" ] || [ -z "$pat" ]; then
        warn "版本号解析失败，跳过探测"; echo "$SNELL_VERSION"; return
    fi
    best="$SNELL_VERSION"
    p=$((pat + 1))
    while [ $p -le $((pat + 10)) ]; do
        cand="v${maj}.${min}.${p}"
        if _snell_probe "$cand"; then best="$cand"; p=$((p+1)); else break; fi
    done
    cand="v${maj}.$((min + 1)).0"
    _snell_probe "$cand" && best="$cand"
    echo "$best"
}

snell_download() {
    local ver="${1:-$SNELL_VERSION}" zip="/tmp/snell-$$.zip"
    info "下载 Snell ${ver} ..."
    wget -q "$(_snell_url "$ver")" -O "$zip" || { rm -f "$zip"; die "下载失败，请检查网络"; }
    _extract_with_rollback "$zip" "$SNELL_BIN" "$SNELL_BIN_BAK" snell-server Snell
    upx -d "$SNELL_BIN" > /dev/null 2>&1 || true
    ok "Snell ${ver} 部署完成"
}

###############################################################################
# §4  AnyTLS
###############################################################################

at_is_installed() { [ -f "$AT_BIN" ]; }
at_is_running()   { [ -f "$AT_INIT" ] && rc-service anytls status > /dev/null 2>&1; }

at_get_version() {
    at_is_installed || { echo "未安装"; return; }
    local ver
    ver=$("$AT_BIN" -version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
    [ -n "$ver" ] && echo "v${ver}" || echo "未知"
}

at_read_conf() {
    [ -f "$AT_CONF" ] || return 1
    CONF_PORT=$(grep '^PORT='     "$AT_CONF" | sed 's/^PORT=//')
    CONF_PASS=$(grep '^PASSWORD=' "$AT_CONF" | sed 's/^PASSWORD=//')
    CONF_SNI=$(grep  '^SNI='      "$AT_CONF" | sed 's/^SNI=//')
    [ -z "$CONF_SNI" ] && CONF_SNI="$AT_DEFAULT_SNI"
}

at_write_conf() {
    mkdir -p /etc/anytls || return 1
    printf 'PORT=%s\nPASSWORD=%s\nSNI=%s\n' "$1" "$2" "$3" > "$AT_CONF" || return 1
}

at_write_info() {
    printf 'anytls://%s@%s:%s?sni=%s\n' "$2" "$3" "$1" "$4" > "$AT_INFO"
}

at_write_init() {
    cat > "$AT_INIT" << 'EOF'
#!/sbin/openrc-run
name="anytls"
description="AnyTLS Proxy Service"
command="/usr/local/bin/anytls-server"
command_user="anytls"
supervisor="supervise-daemon"

start_pre() {
    . /etc/anytls/anytls.conf
    command_args="-l [::]:${PORT} -p ${PASSWORD}"
}
EOF
    chmod +x "$AT_INIT"
}

at_show_summary() {
    # $1=port $2=pass $3=ip $4=country $5=sni
    printf "\n"
    _box "AnyTLS" "配置摘要"
    hr
    printf "    ${D}地区${Z}  %s\n" "$4"
    printf "    ${D}IP  ${Z}  %s\n" "$3"
    printf "    ${D}端口${Z}  %s\n" "$1"
    printf "    ${D}密码${Z}  %s\n" "$2"
    printf "    ${D}SNI ${Z}  %s\n" "$5"
    hr
    printf "  ${D}Surge 节点:${Z}\n"
    printf "  ${C}%s = anytls, %s, %s, password=%s, reuse=true, skip-cert-verify=true, sni=%s${Z}\n" \
        "$4" "$3" "$1" "$2" "$5"
    hr; printf "\n"
}

_at_url()   { printf "https://github.com/anytls/anytls-go/releases/download/%s/anytls_%s_linux_%s.zip" "$1" "${1#v}" "$(_arch go)"; }
_at_asset() { printf "anytls_%s_linux_%s.zip" "${1#v}" "$(_arch go)"; }

# 单次请求 /latest → AT_LATEST_VER / AT_LATEST_SHA256
at_fetch_latest() {
    local json
    json=$(curl -sf --connect-timeout 5 --max-time 10 "${AT_API}/latest")
    if [ -z "$json" ]; then
        warn "无法访问 GitHub API，回退到内置版本 ${AT_VERSION}"
        AT_LATEST_VER="$AT_VERSION"; AT_LATEST_SHA256=""; return
    fi
    AT_LATEST_VER=$(echo "$json" | grep '"tag_name"' | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+')
    [ -z "$AT_LATEST_VER" ] && { warn "无法解析最新版本"; AT_LATEST_VER="$AT_VERSION"; }
    AT_LATEST_SHA256=$(_extract_sha256 "$json" "$(_at_asset "$AT_LATEST_VER")")
}

at_download() {
    # $1=版本  $2=SHA256（可选，为空则单独查询）
    local ver="${1:-$AT_VERSION}" sha="${2:-}" zip="/tmp/anytls-$$.zip" actual
    info "下载 AnyTLS ${ver} ..."
    wget -q "$(_at_url "$ver")" -O "$zip" || { rm -f "$zip"; die "下载失败，请检查网络"; }
    if [ -z "$sha" ]; then
        local json
        json=$(curl -sf --connect-timeout 5 --max-time 10 "${AT_API}/tags/${ver}")
        sha=$(_extract_sha256 "$json" "$(_at_asset "$ver")")
    fi
    if [ -n "$sha" ]; then
        actual=$(sha256sum "$zip" | awk '{print $1}')
        [ "$actual" != "$sha" ] && { rm -f "$zip"; die "SHA256 校验失败\n  期望: ${sha}\n  实际: ${actual}"; }
        ok "SHA256 校验通过"
    else
        warn "无法获取 SHA256，跳过完整性验证"
    fi
    _extract_with_rollback "$zip" "$AT_BIN" "$AT_BIN_BAK" anytls-server AnyTLS
    ok "AnyTLS ${ver} 部署完成"
}

###############################################################################
# §4b  Shadowsocks (shadowsocks-rust)
###############################################################################

ss_is_installed() { [ -f "$SS_BIN" ] && [ -f "$SS_CONF" ]; }
ss_is_running()   { [ -f "$SS_INIT" ] && rc-service shadowsocks status > /dev/null 2>&1; }

ss_get_version() {
    [ -f "$SS_BIN" ] || { echo "未安装"; return; }
    "$SS_BIN" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 \
        | sed 's/^/v/' || echo "未知"
}

ss_read_conf() {
    [ -f "$SS_CONF" ] || return 1
    CONF_PORT=$(grep '"server_port"' "$SS_CONF" | grep -oE '[0-9]+')
    CONF_PASS=$(grep '"password"'    "$SS_CONF" | sed 's/.*: *"//; s/".*//')
    CONF_METHOD=$(grep '"method"'    "$SS_CONF" | sed 's/.*: *"//; s/".*//')
    [ -z "$CONF_METHOD" ] && CONF_METHOD="$SS_METHOD"
    return 0
}

ss_write_conf() {
    # $1=port $2=password $3=method
    mkdir -p /etc/shadowsocks || return 1
    cat > "$SS_CONF" << EOF
{
    "server": "::",
    "server_port": $1,
    "password": "$2",
    "method": "$3",
    "mode": "tcp_and_udp",
    "fast_open": false
}
EOF
}

ss_write_info() {
    # $1=port $2=pass $3=ip $4=country $5=method
    printf '%s = ss, %s, %s, encrypt-method=%s, password=%s, udp-relay=true\n' \
        "$4" "$3" "$1" "$5" "$2" > "$SS_INFO"
}

ss_write_init() {
    cat > "$SS_INIT" << 'EOF'
#!/sbin/openrc-run
name="shadowsocks"
description="Shadowsocks-rust Server"
command="/usr/bin/ssserver"
command_args="-c /etc/shadowsocks/config.json"
command_user="ss"
supervisor="supervise-daemon"
EOF
    chmod +x "$SS_INIT"
}

ss_show_summary() {
    # $1=port $2=pass $3=ip $4=country $5=method
    local uri b64
    b64=$(printf '%s:%s' "$5" "$2" | base64 | tr -d '\n')
    uri="ss://${b64}@${3}:${1}#${4}"
    printf "\n"
    _box "Shadowsocks" "配置摘要"
    hr
    printf "    ${D}地区${Z}  %s\n" "$4"
    printf "    ${D}IP  ${Z}  %s\n" "$3"
    printf "    ${D}端口${Z}  %s\n" "$1"
    printf "    ${D}密码${Z}  %s\n" "$2"
    printf "    ${D}加密${Z}  %s\n" "$5"
    hr
    printf "  ${D}Surge 节点:${Z}\n"
    printf "  ${C}%s = ss, %s, %s, encrypt-method=%s, password=%s, udp-relay=true${Z}\n" \
        "$4" "$3" "$1" "$5" "$2"
    printf "  ${D}SS URI:${Z}\n"
    printf "  ${C}%s${Z}\n" "$uri"
    hr; printf "\n"
}

###############################################################################
# §4c  Hysteria2
###############################################################################

hy_is_installed() { [ -f "$HY_BIN" ]; }
hy_is_running()   { [ -f "$HY_INIT" ] && rc-service hysteria status > /dev/null 2>&1; }

hy_get_version() {
    hy_is_installed || { echo "未安装"; return; }
    "$HY_BIN" version 2>&1 | grep -iE '^version' | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' \
        | head -1 | sed 's/^v*/v/' || echo "未知"
}

hy_read_conf() {
    [ -f "$HY_CONF" ] || return 1
    CONF_PORT=$(grep '^listen:' "$HY_CONF" | grep -oE '[0-9]+')
    CONF_PASS=$(grep -A1 '^auth:' "$HY_CONF" | grep 'password:' | sed 's/.*password: *//')
    CONF_SNI=$(grep '^# sni:' "$HY_CONF" | sed 's/^# sni: *//')
    [ -z "$CONF_SNI" ] && CONF_SNI="$HY_DEFAULT_SNI"
    return 0
}

hy_write_conf() {
    # $1=port $2=password $3=sni
    mkdir -p "$HY_DIR" || return 1
    cat > "$HY_CONF" << EOF
# sni: $3
listen: :$1

tls:
  cert: $HY_CERT
  key: $HY_KEY

auth:
  type: password
  password: $2

masquerade:
  type: proxy
  proxy:
    url: https://$3
    rewriteHost: true
EOF
}

hy_write_info() {
    # $1=port $2=pass $3=ip $4=country $5=sni
    printf '%s = hysteria2, %s, %s, password=%s, sni=%s, skip-cert-verify=true, download-bandwidth=200, upload-bandwidth=50\n' \
        "$4" "$3" "$1" "$2" "$5" > "$HY_INFO"
}

hy_write_init() {
    cat > "$HY_INIT" << 'EOF'
#!/sbin/openrc-run
name="hysteria"
description="Hysteria2 Proxy Server"
command="/usr/local/bin/hysteria"
command_args="server -c /etc/hysteria/config.yaml"
command_user="hysteria"
supervisor="supervise-daemon"
EOF
    chmod +x "$HY_INIT"
}

# 生成自签证书（10 年）→ HY_CERT / HY_KEY
hy_gen_cert() {
    local cn="${1:-$HY_DEFAULT_SNI}"
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
        -keyout "$HY_KEY" -out "$HY_CERT" -days 3650 -nodes \
        -subj "/CN=${cn}" -addext "subjectAltName=DNS:${cn}" > /dev/null 2>&1 \
        || die "自签证书生成失败"
    chmod 600 "$HY_KEY"
}

hy_show_summary() {
    # $1=port $2=pass $3=ip $4=country $5=sni
    printf "\n"
    _box "Hysteria2" "配置摘要"
    hr
    printf "    ${D}地区${Z}  %s\n" "$4"
    printf "    ${D}IP  ${Z}  %s\n" "$3"
    printf "    ${D}端口${Z}  %s\n" "$1"
    printf "    ${D}密码${Z}  %s\n" "$2"
    printf "    ${D}SNI ${Z}  %s\n" "$5"
    hr
    printf "  ${D}Surge 节点:${Z}\n"
    printf "  ${C}%s = hysteria2, %s, %s, password=%s, sni=%s, skip-cert-verify=true${Z}\n" \
        "$4" "$3" "$1" "$2" "$5"
    printf "  ${D}通用 URI:${Z}\n"
    printf "  ${C}hysteria2://%s@%s:%s?insecure=1&sni=%s#%s${Z}\n" \
        "$2" "$3" "$1" "$5" "$4"
    hr; printf "\n"
}

_hy_url()   { printf "https://github.com/apernet/hysteria/releases/download/app/%s/hysteria-linux-%s" "$1" "$(_arch go)"; }

# 单次请求 /latest → HY_LATEST_VER
hy_fetch_latest() {
    local json
    json=$(curl -sf --connect-timeout 5 --max-time 10 "${HY_API}/latest")
    if [ -z "$json" ]; then
        warn "无法访问 GitHub API，回退到内置版本 ${HY_VERSION}"
        HY_LATEST_VER="$HY_VERSION"; return
    fi
    HY_LATEST_VER=$(echo "$json" | grep '"tag_name"' | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+')
    [ -z "$HY_LATEST_VER" ] && { warn "无法解析最新版本"; HY_LATEST_VER="$HY_VERSION"; }
}

hy_download() {
    local ver="${1:-$HY_VERSION}" bin="/tmp/hysteria-$$"
    info "下载 Hysteria2 ${ver} ..."
    wget -q "$(_hy_url "$ver")" -O "$bin" || { rm -f "$bin"; die "下载失败，请检查网络"; }
    [ -s "$bin" ] || { rm -f "$bin"; die "下载文件为空"; }
    [ -f "$HY_BIN" ] && cp "$HY_BIN" "$HY_BIN_BAK"
    if ! mv "$bin" "$HY_BIN"; then
        [ -f "$HY_BIN_BAK" ] && mv "$HY_BIN_BAK" "$HY_BIN"
        die "部署 Hysteria2 失败"
    fi
    rm -f "$HY_BIN_BAK"
    chmod +x "$HY_BIN"
    ok "Hysteria2 ${ver} 部署完成"
}

###############################################################################
# §5  Snell 动作
###############################################################################

snell_install() {
    printf "\n"
    if snell_is_installed; then
        warn "Snell 已安装（$(snell_get_version)），继续将覆盖现有配置"
        confirm "确认继续？" "n" || { ok "已取消"; return; }
        printf "\n"
    fi
    steps_init 5
    _box "安装 Snell" "${SNELL_VERSION}"
    hr

    step "检查并安装依赖"; ensure_pkgs wget unzip curl gcompat upx
    step "下载并部署二进制"; snell_download "$SNELL_VERSION"

    step "创建系统用户"
    if id "$SNELL_USER" > /dev/null 2>&1; then
        info "用户 ${SNELL_USER} 已存在，跳过"
    else
        adduser -D -H -s /sbin/nologin "$SNELL_USER"; ok "用户 ${SNELL_USER} 已创建"
    fi

    step "生成配置"
    local port psk
    port=$(gen_port); psk=$(gen_secret)
    snell_write_conf "$port" "$psk" || die "配置写入失败"
    snell_write_init; ok "配置已写入"

    step "启动服务"
    svc enable snell; svc start snell
    if _wait_for_service snell; then ok "Snell 已启动"; else warn "启动超时，请手动检查"; fi

    fetch_public_ip
    snell_write_info "$port" "$psk" "$PUB_IP" "$PUB_COUNTRY"
    snell_show_summary "$port" "$psk" "$PUB_IP" "$PUB_COUNTRY"
}

snell_configure() {
    printf "\n"
    [ -f "$SNELL_CONF" ] || { warn "未找到配置文件，请先安装 Snell"; return; }
    snell_read_conf
    _box "Snell" "当前配置"
    hr
    printf "    ${D}端口${Z}  %s\n" "$CONF_PORT"
    printf "    ${D}PSK ${Z}  %s\n" "$CONF_PSK"
    hr; printf "\n"
    confirm "修改配置？" "n" || return
    printf "\n${D}  回车保留当前值${Z}\n\n"
    ask "端口" "$CONF_PORT"; local new_port="$REPLY"
    ask "PSK"  "$CONF_PSK";  local new_psk="$REPLY"
    printf "\n"
    case "$new_port" in ''|*[!0-9]*) warn "端口须为纯数字，操作取消"; return ;; esac
    if [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then warn "端口范围 1–65535，操作取消"; return; fi
    [ -z "$new_psk" ] && { warn "PSK 不能为空，操作取消"; return; }
    case "$new_psk" in *' '*|*'	'*) warn "PSK 不能含空白，操作取消"; return ;; esac
    if [ "$new_port" = "$CONF_PORT" ] && [ "$new_psk" = "$CONF_PSK" ]; then info "配置未变更"; return; fi

    svc stop snell
    if [ "$new_port" != "$CONF_PORT" ] && _port_in_use "$new_port"; then
        warn "端口 ${new_port} 已被占用"; svc start snell; return
    fi
    cp "$SNELL_CONF" "$SNELL_CONF_BAK" 2>/dev/null
    if ! snell_write_conf "$new_port" "$new_psk"; then
        [ -f "$SNELL_CONF_BAK" ] && mv "$SNELL_CONF_BAK" "$SNELL_CONF"
        warn "配置写入失败，已恢复"; svc start snell; return
    fi
    rm -f "$SNELL_CONF_BAK"
    svc start snell
    if _wait_for_service snell; then ok "新配置已生效"; else warn "重启超时，请手动检查"; fi
    fetch_public_ip
    snell_write_info "$new_port" "$new_psk" "$PUB_IP" "$PUB_COUNTRY"
    snell_show_summary "$new_port" "$new_psk" "$PUB_IP" "$PUB_COUNTRY"
}

snell_update() {
    printf "\n"
    snell_is_installed || { warn "Snell 未安装"; return; }
    steps_init 4
    _box "更新 Snell"
    hr
    step "探测最新版本"
    local old_ver new_ver
    old_ver=$(snell_get_version); SNELL_VERSION="$old_ver"
    info "当前版本: ${old_ver}，探测中..."
    new_ver=$(snell_fetch_latest)
    if [ "$old_ver" = "$new_ver" ]; then
        printf "\n"; warn "已是最新版本 (${old_ver})"
        confirm "仍要重新安装？" "n" || { ok "已取消"; return; }
        printf "\n"
    else
        ok "发现新版本: ${D}${old_ver}${Z} → ${G}${new_ver}${Z}"; printf "\n"
    fi
    step "停止服务"; svc stop snell; ok "已停止"
    step "下载并部署"; ensure_pkgs wget unzip curl gcompat upx; snell_download "$new_ver"; SNELL_VERSION="$new_ver"
    step "启动服务"; svc start snell
    if _wait_for_service snell; then ok "Snell 已启动（$(snell_get_version)）"; else warn "启动超时"; fi
    snell_read_conf
    [ -n "$CONF_PORT" ] && { fetch_public_ip; snell_write_info "$CONF_PORT" "$CONF_PSK" "$PUB_IP" "$PUB_COUNTRY"; snell_show_summary "$CONF_PORT" "$CONF_PSK" "$PUB_IP" "$PUB_COUNTRY"; }
}

snell_uninstall() {
    printf "\n"
    _box "卸载 Snell"
    hr; printf "\n"
    warn "将删除二进制、配置目录及系统用户，操作不可恢复"; printf "\n"
    confirm "确认卸载？" "n" || { ok "已取消"; return; }
    printf "\n"
    svc stop snell; svc disable snell
    rm -f "$SNELL_INIT" "$SNELL_BIN" "$SNELL_BIN_BAK"
    rm -rf /etc/snell
    _del_user "$SNELL_USER"
    printf "\n"; ok "Snell 已完全卸载"; printf "\n"
}

###############################################################################
# §6  AnyTLS 动作
###############################################################################

at_install() {
    printf "\n"
    if at_is_installed; then
        warn "AnyTLS 已安装（$(at_get_version)），继续将覆盖现有配置"
        confirm "确认继续？" "n" || { ok "已取消"; return; }
        printf "\n"
    fi
    steps_init 5
    _box "安装 AnyTLS" "${AT_VERSION}"
    hr

    step "检查并安装依赖"; ensure_pkgs wget unzip curl
    step "下载并部署二进制"; at_download "$AT_VERSION"

    step "创建系统用户"
    if id "$AT_USER" > /dev/null 2>&1; then
        info "用户 ${AT_USER} 已存在，跳过"
    else
        adduser -D -H -s /sbin/nologin "$AT_USER"; ok "用户 ${AT_USER} 已创建"
    fi

    step "生成配置"
    local port pass
    port=$(gen_port); pass=$(gen_secret)
    at_write_conf "$port" "$pass" "$AT_DEFAULT_SNI" || die "配置写入失败"
    at_write_init; ok "配置已写入"

    step "启动服务"
    svc enable anytls; svc start anytls
    if _wait_for_service anytls; then ok "AnyTLS 已启动"; else warn "启动超时，请手动检查"; fi

    fetch_public_ip
    at_write_info "$port" "$pass" "$PUB_IP" "$AT_DEFAULT_SNI"
    at_show_summary "$port" "$pass" "$PUB_IP" "$PUB_COUNTRY" "$AT_DEFAULT_SNI"
}

at_configure() {
    printf "\n"
    [ -f "$AT_CONF" ] || { warn "未找到配置文件，请先安装 AnyTLS"; return; }
    at_read_conf
    _box "AnyTLS" "当前配置"
    hr
    printf "    ${D}端口${Z}  %s\n" "$CONF_PORT"
    printf "    ${D}密码${Z}  %s\n" "$CONF_PASS"
    printf "    ${D}SNI ${Z}  %s\n" "$CONF_SNI"
    hr; printf "\n"
    confirm "修改配置？" "n" || return
    printf "\n${D}  回车保留当前值${Z}\n\n"
    ask "端口" "$CONF_PORT"; local new_port="$REPLY"
    ask "密码" "$CONF_PASS"; local new_pass="$REPLY"
    ask "SNI"  "$CONF_SNI";  local new_sni="$REPLY"
    printf "\n"
    case "$new_port" in ''|*[!0-9]*) warn "端口须为纯数字，操作取消"; return ;; esac
    if [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then warn "端口范围 1–65535，操作取消"; return; fi
    [ -z "$new_pass" ] && { warn "密码不能为空，操作取消"; return; }
    case "$new_pass" in *' '*|*'	'*) warn "密码不能含空白，操作取消"; return ;; esac
    [ -z "$new_sni" ] && { warn "SNI 不能为空，操作取消"; return; }
    if [ "$new_port" = "$CONF_PORT" ] && [ "$new_pass" = "$CONF_PASS" ] && [ "$new_sni" = "$CONF_SNI" ]; then
        info "配置未变更"; return
    fi

    svc stop anytls
    if [ "$new_port" != "$CONF_PORT" ] && _port_in_use "$new_port"; then
        warn "端口 ${new_port} 已被占用"; svc start anytls; return
    fi
    cp "$AT_CONF" "$AT_CONF_BAK" 2>/dev/null
    if ! at_write_conf "$new_port" "$new_pass" "$new_sni"; then
        [ -f "$AT_CONF_BAK" ] && mv "$AT_CONF_BAK" "$AT_CONF"
        warn "配置写入失败，已恢复"; svc start anytls; return
    fi
    rm -f "$AT_CONF_BAK"
    svc start anytls
    if _wait_for_service anytls; then ok "新配置已生效"; else warn "重启超时，请手动检查"; fi
    fetch_public_ip
    at_write_info "$new_port" "$new_pass" "$PUB_IP" "$new_sni"
    at_show_summary "$new_port" "$new_pass" "$PUB_IP" "$PUB_COUNTRY" "$new_sni"
}

at_update() {
    printf "\n"
    at_is_installed || { warn "AnyTLS 未安装"; return; }
    steps_init 4
    _box "更新 AnyTLS"
    hr
    step "查询最新版本"
    local old_ver
    old_ver=$(at_get_version)
    info "当前版本: ${old_ver}，查询中..."
    at_fetch_latest
    if [ "$old_ver" = "$AT_LATEST_VER" ]; then
        printf "\n"; warn "已是最新版本 (${old_ver})"
        confirm "仍要重新安装？" "n" || { ok "已取消"; return; }
        printf "\n"
    else
        ok "发现新版本: ${D}${old_ver}${Z} → ${G}${AT_LATEST_VER}${Z}"; printf "\n"
    fi
    step "停止服务"; svc stop anytls; ok "已停止"
    step "下载并部署"; ensure_pkgs wget unzip curl; at_download "$AT_LATEST_VER" "$AT_LATEST_SHA256"; AT_VERSION="$AT_LATEST_VER"
    step "启动服务"; svc start anytls
    if _wait_for_service anytls; then ok "AnyTLS 已启动（$(at_get_version)）"; else warn "启动超时"; fi
    at_read_conf
    [ -n "$CONF_PORT" ] && { fetch_public_ip; at_write_info "$CONF_PORT" "$CONF_PASS" "$PUB_IP" "$CONF_SNI"; at_show_summary "$CONF_PORT" "$CONF_PASS" "$PUB_IP" "$PUB_COUNTRY" "$CONF_SNI"; }
}

at_uninstall() {
    printf "\n"
    _box "卸载 AnyTLS"
    hr; printf "\n"
    warn "将删除二进制、配置目录及系统用户，操作不可恢复"; printf "\n"
    confirm "确认卸载？" "n" || { ok "已取消"; return; }
    printf "\n"
    svc stop anytls; svc disable anytls
    rm -f "$AT_INIT" "$AT_BIN" "$AT_BIN_BAK"
    rm -rf /etc/anytls
    _del_user "$AT_USER"
    printf "\n"; ok "AnyTLS 已完全卸载"; printf "\n"
}

###############################################################################
# §6b  Shadowsocks 动作
###############################################################################

ss_install() {
    printf "\n"
    if ss_is_installed; then
        warn "Shadowsocks 已安装（$(ss_get_version)），继续将覆盖现有配置"
        confirm "确认继续？" "n" || { ok "已取消"; return; }
        printf "\n"
    fi
    steps_init 5
    _box "安装 Shadowsocks" "shadowsocks-rust"
    hr

    step "检查并安装依赖"; ensure_pkgs shadowsocks-rust curl
    [ -f "$SS_BIN" ] || die "ssserver 未找到，apk 安装可能失败"
    step "准备二进制"; ok "shadowsocks-rust 已就绪（$(ss_get_version)）"

    step "创建系统用户"
    if id "$SS_USER" > /dev/null 2>&1; then
        info "用户 ${SS_USER} 已存在，跳过"
    else
        adduser -D -H -s /sbin/nologin "$SS_USER"; ok "用户 ${SS_USER} 已创建"
    fi

    step "生成配置"
    local port pass
    port=$(gen_port); pass=$(gen_secret)
    ss_write_conf "$port" "$pass" "$SS_METHOD" || die "配置写入失败"
    ss_write_init; ok "配置已写入"

    step "启动服务"
    svc enable shadowsocks; svc start shadowsocks
    if _wait_for_service shadowsocks; then ok "Shadowsocks 已启动"; else warn "启动超时，请手动检查"; fi

    fetch_public_ip
    ss_write_info "$port" "$pass" "$PUB_IP" "$PUB_COUNTRY" "$SS_METHOD"
    ss_show_summary "$port" "$pass" "$PUB_IP" "$PUB_COUNTRY" "$SS_METHOD"
}

ss_configure() {
    printf "\n"
    [ -f "$SS_CONF" ] || { warn "未找到配置文件，请先安装 Shadowsocks"; return; }
    ss_read_conf
    _box "Shadowsocks" "当前配置"
    hr
    printf "    ${D}端口${Z}  %s\n" "$CONF_PORT"
    printf "    ${D}密码${Z}  %s\n" "$CONF_PASS"
    printf "    ${D}加密${Z}  %s\n" "$CONF_METHOD"
    hr; printf "\n"
    confirm "修改配置？" "n" || return
    printf "\n${D}  回车保留当前值${Z}\n\n"
    ask "端口" "$CONF_PORT"; local new_port="$REPLY"
    ask "密码" "$CONF_PASS"; local new_pass="$REPLY"
    printf "\n"
    case "$new_port" in ''|*[!0-9]*) warn "端口须为纯数字，操作取消"; return ;; esac
    if [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then warn "端口范围 1–65535，操作取消"; return; fi
    [ -z "$new_pass" ] && { warn "密码不能为空，操作取消"; return; }
    case "$new_pass" in *' '*|*'	'*) warn "密码不能含空白，操作取消"; return ;; esac
    if [ "$new_port" = "$CONF_PORT" ] && [ "$new_pass" = "$CONF_PASS" ]; then info "配置未变更"; return; fi

    svc stop shadowsocks
    if [ "$new_port" != "$CONF_PORT" ] && _port_in_use "$new_port"; then
        warn "端口 ${new_port} 已被占用"; svc start shadowsocks; return
    fi
    cp "$SS_CONF" "$SS_CONF_BAK" 2>/dev/null
    if ! ss_write_conf "$new_port" "$new_pass" "$CONF_METHOD"; then
        [ -f "$SS_CONF_BAK" ] && mv "$SS_CONF_BAK" "$SS_CONF"
        warn "配置写入失败，已恢复"; svc start shadowsocks; return
    fi
    rm -f "$SS_CONF_BAK"
    svc start shadowsocks
    if _wait_for_service shadowsocks; then ok "新配置已生效"; else warn "重启超时，请手动检查"; fi
    fetch_public_ip
    ss_write_info "$new_port" "$new_pass" "$PUB_IP" "$PUB_COUNTRY" "$CONF_METHOD"
    ss_show_summary "$new_port" "$new_pass" "$PUB_IP" "$PUB_COUNTRY" "$CONF_METHOD"
}

ss_update() {
    printf "\n"
    ss_is_installed || { warn "Shadowsocks 未安装"; return; }
    steps_init 3
    _box "更新 Shadowsocks"
    hr
    step "更新二进制"
    local old_ver
    old_ver=$(ss_get_version)
    info "当前版本: ${old_ver}，通过 apk 升级..."
    svc stop shadowsocks
    apk update -q > /dev/null 2>&1
    apk upgrade -q shadowsocks-rust > /dev/null 2>&1 || true
    step "启动服务"; svc start shadowsocks
    if _wait_for_service shadowsocks; then ok "Shadowsocks 已启动（$(ss_get_version)）"; else warn "启动超时"; fi
    step "完成"; ok "已更新至 $(ss_get_version)"
}

ss_uninstall() {
    printf "\n"
    _box "卸载 Shadowsocks"
    hr; printf "\n"
    warn "将停止服务、删除配置目录及系统用户（保留 apk 包），操作不可恢复"; printf "\n"
    confirm "确认卸载？" "n" || { ok "已取消"; return; }
    printf "\n"
    svc stop shadowsocks; svc disable shadowsocks
    rm -f "$SS_INIT"
    rm -rf /etc/shadowsocks
    _del_user "$SS_USER"
    if confirm "是否同时卸载 shadowsocks-rust apk 包？" "n"; then
        apk del -q shadowsocks-rust > /dev/null 2>&1 || true
        ok "apk 包已卸载"
    fi
    printf "\n"; ok "Shadowsocks 已卸载"; printf "\n"
}

###############################################################################
# §6c  Hysteria2 动作
###############################################################################

hy_install() {
    printf "\n"
    if hy_is_installed; then
        warn "Hysteria2 已安装（$(hy_get_version)），继续将覆盖现有配置"
        confirm "确认继续？" "n" || { ok "已取消"; return; }
        printf "\n"
    fi
    steps_init 6
    _box "安装 Hysteria2" "${HY_VERSION}"
    hr

    step "检查并安装依赖"; ensure_pkgs wget curl openssl
    step "下载并部署二进制"; hy_download "$HY_VERSION"

    step "创建系统用户"
    if id "$HY_USER" > /dev/null 2>&1; then
        info "用户 ${HY_USER} 已存在，跳过"
    else
        adduser -D -H -s /sbin/nologin "$HY_USER"; ok "用户 ${HY_USER} 已创建"
    fi

    step "生成自签证书"
    mkdir -p "$HY_DIR"
    hy_gen_cert "$HY_DEFAULT_SNI"
    chown "$HY_USER" "$HY_CERT" "$HY_KEY" 2>/dev/null || true
    ok "证书已生成（CN=${HY_DEFAULT_SNI}）"

    step "生成配置"
    local port pass
    port=$(gen_port); pass=$(gen_secret)
    hy_write_conf "$port" "$pass" "$HY_DEFAULT_SNI" || die "配置写入失败"
    hy_write_init; ok "配置已写入"

    step "启动服务"
    svc enable hysteria; svc start hysteria
    if _wait_for_service hysteria; then ok "Hysteria2 已启动"; else warn "启动超时，请手动检查"; fi

    fetch_public_ip
    hy_write_info "$port" "$pass" "$PUB_IP" "$PUB_COUNTRY" "$HY_DEFAULT_SNI"
    hy_show_summary "$port" "$pass" "$PUB_IP" "$PUB_COUNTRY" "$HY_DEFAULT_SNI"
}

hy_configure() {
    printf "\n"
    [ -f "$HY_CONF" ] || { warn "未找到配置文件，请先安装 Hysteria2"; return; }
    hy_read_conf
    _box "Hysteria2" "当前配置"
    hr
    printf "    ${D}端口${Z}  %s\n" "$CONF_PORT"
    printf "    ${D}密码${Z}  %s\n" "$CONF_PASS"
    printf "    ${D}SNI ${Z}  %s\n" "$CONF_SNI"
    hr; printf "\n"
    confirm "修改配置？" "n" || return
    printf "\n${D}  回车保留当前值${Z}\n\n"
    ask "端口" "$CONF_PORT"; local new_port="$REPLY"
    ask "密码" "$CONF_PASS"; local new_pass="$REPLY"
    ask "SNI"  "$CONF_SNI";  local new_sni="$REPLY"
    printf "\n"
    case "$new_port" in ''|*[!0-9]*) warn "端口须为纯数字，操作取消"; return ;; esac
    if [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then warn "端口范围 1–65535，操作取消"; return; fi
    [ -z "$new_pass" ] && { warn "密码不能为空，操作取消"; return; }
    case "$new_pass" in *' '*|*'	'*) warn "密码不能含空白，操作取消"; return ;; esac
    [ -z "$new_sni" ] && { warn "SNI 不能为空，操作取消"; return; }
    if [ "$new_port" = "$CONF_PORT" ] && [ "$new_pass" = "$CONF_PASS" ] && [ "$new_sni" = "$CONF_SNI" ]; then
        info "配置未变更"; return
    fi

    svc stop hysteria
    if [ "$new_port" != "$CONF_PORT" ] && _port_in_use "$new_port"; then
        warn "端口 ${new_port} 已被占用"; svc start hysteria; return
    fi
    cp "$HY_CONF" "$HY_CONF_BAK" 2>/dev/null
    if [ "$new_sni" != "$CONF_SNI" ]; then
        hy_gen_cert "$new_sni"
        chown "$HY_USER" "$HY_CERT" "$HY_KEY" 2>/dev/null || true
    fi
    if ! hy_write_conf "$new_port" "$new_pass" "$new_sni"; then
        [ -f "$HY_CONF_BAK" ] && mv "$HY_CONF_BAK" "$HY_CONF"
        warn "配置写入失败，已恢复"; svc start hysteria; return
    fi
    rm -f "$HY_CONF_BAK"
    svc start hysteria
    if _wait_for_service hysteria; then ok "新配置已生效"; else warn "重启超时，请手动检查"; fi
    fetch_public_ip
    hy_write_info "$new_port" "$new_pass" "$PUB_IP" "$PUB_COUNTRY" "$new_sni"
    hy_show_summary "$new_port" "$new_pass" "$PUB_IP" "$PUB_COUNTRY" "$new_sni"
}

hy_update() {
    printf "\n"
    hy_is_installed || { warn "Hysteria2 未安装"; return; }
    steps_init 4
    _box "更新 Hysteria2"
    hr
    step "查询最新版本"
    local old_ver
    old_ver=$(hy_get_version)
    info "当前版本: ${old_ver}，查询中..."
    hy_fetch_latest
    if [ "$old_ver" = "$HY_LATEST_VER" ]; then
        printf "\n"; warn "已是最新版本 (${old_ver})"
        confirm "仍要重新安装？" "n" || { ok "已取消"; return; }
        printf "\n"
    else
        ok "发现新版本: ${D}${old_ver}${Z} → ${G}${HY_LATEST_VER}${Z}"; printf "\n"
    fi
    step "停止服务"; svc stop hysteria; ok "已停止"
    step "下载并部署"; ensure_pkgs wget curl; hy_download "$HY_LATEST_VER"; HY_VERSION="$HY_LATEST_VER"
    step "启动服务"; svc start hysteria
    if _wait_for_service hysteria; then ok "Hysteria2 已启动（$(hy_get_version)）"; else warn "启动超时"; fi
    hy_read_conf
    [ -n "$CONF_PORT" ] && { fetch_public_ip; hy_write_info "$CONF_PORT" "$CONF_PASS" "$PUB_IP" "$PUB_COUNTRY" "$CONF_SNI"; hy_show_summary "$CONF_PORT" "$CONF_PASS" "$PUB_IP" "$PUB_COUNTRY" "$CONF_SNI"; }
}

hy_uninstall() {
    printf "\n"
    _box "卸载 Hysteria2"
    hr; printf "\n"
    warn "将删除二进制、配置目录、证书及系统用户，操作不可恢复"; printf "\n"
    confirm "确认卸载？" "n" || { ok "已取消"; return; }
    printf "\n"
    svc stop hysteria; svc disable hysteria
    rm -f "$HY_INIT" "$HY_BIN" "$HY_BIN_BAK"
    rm -rf "$HY_DIR"
    _del_user "$HY_USER"
    printf "\n"; ok "Hysteria2 已完全卸载"; printf "\n"
}

###############################################################################
# §7  菜单
###############################################################################

# 状态行  $1=已装(0/1) $2=运行(0/1) $3=版本
_status_line() {
    if [ "$1" = "1" ]; then
        [ "$2" = "1" ] && printf "${G}● 运行中${Z}  ${D}%s${Z}" "$3" \
                       || printf "${Y}○ 已停止${Z}  ${D}%s${Z}" "$3"
    else
        printf "${D}○ 未安装${Z}"
    fi
}

# 标题头  $1=主标题  $2=副标题(可选) —— 无边框，规避中文宽度对齐问题
_box() {
    printf "\n"
    if [ -n "$2" ]; then
        printf "  ${C}◆${Z} ${W}${B}%s${Z} ${D}%s${Z}\n" "$1" "$2"
    else
        printf "  ${C}◆${Z} ${W}${B}%s${Z}\n" "$1"
    fi
}

# 服务子菜单的固定项
_svc_menu_items() {
    hr
    printf "   ${C}1${Z}  安装 / 重装\n"
    printf "   ${C}2${Z}  配置\n"
    printf "   ${C}3${Z}  更新\n"
    printf "   ${C}4${Z}  卸载\n"
    printf "   ${D}0  返回${Z}\n\n"
    hr
    printf "   请选择 ${W}❯${Z} "
}

show_main_menu() {
    clear
    local si=0 sr=0 ai=0 ar=0 ssi=0 ssr=0 hi=0 hyr=0
    snell_is_installed && si=1; snell_is_running && sr=1
    at_is_installed    && ai=1; at_is_running    && ar=1
    ss_is_installed    && ssi=1; ss_is_running   && ssr=1
    hy_is_installed    && hi=1; hy_is_running    && hyr=1
    _box "代理服务管理" "Snell · AnyTLS · SS · Hysteria2"
    printf "    ${D}Alpine Linux 专用${Z}\n"
    hr
    printf "    ${W}Snell      ${Z}  %b\n" "$(_status_line $si $sr "$(snell_get_version)")"
    printf "    ${W}AnyTLS     ${Z}  %b\n" "$(_status_line $ai $ar "$(at_get_version)")"
    printf "    ${W}Shadowsocks${Z}  %b\n" "$(_status_line $ssi $ssr "$(ss_get_version)")"
    printf "    ${W}Hysteria2  ${Z}  %b\n" "$(_status_line $hi $hyr "$(hy_get_version)")"
    hr
    printf "\n"
    printf "   ${C}1${Z}  管理 Snell\n"
    printf "   ${C}2${Z}  管理 AnyTLS\n"
    printf "   ${C}3${Z}  管理 Shadowsocks\n"
    printf "   ${C}4${Z}  管理 Hysteria2\n"
    printf "   ${D}0  退出${Z}\n\n"
    hr
    printf "   请选择 ${D}[0-4]${Z} ${W}❯${Z} "
    read -r CHOICE
}

# 服务子菜单  $1=snell|at
show_svc_menu() {
    clear
    local p="$1" inst=0 run=0 ver extra="" ip
    if [ "$p" = "snell" ]; then
        snell_is_installed && inst=1; snell_is_running && run=1
        ver=$(snell_get_version)
        if [ $inst -eq 1 ]; then
            snell_read_conf 2>/dev/null
            ip=$(grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' "$SNELL_INFO" 2>/dev/null | head -1)
            [ -n "$CONF_PORT" ] && extra="端口  ${C}${CONF_PORT}${Z}"
            [ -n "$ip" ]        && extra="${extra}   IP  ${C}${ip}${Z}"
        fi
        _box "Snell Server" "管理"
    elif [ "$p" = "at" ]; then
        at_is_installed && inst=1; at_is_running && run=1
        ver=$(at_get_version)
        if [ $inst -eq 1 ]; then
            at_read_conf 2>/dev/null
            ip=$(grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' "$AT_INFO" 2>/dev/null | head -1)
            [ -n "$CONF_PORT" ] && extra="端口  ${C}${CONF_PORT}${Z}   SNI  ${C}${CONF_SNI}${Z}"
            [ -n "$ip" ]        && extra="${extra}   IP  ${C}${ip}${Z}"
        fi
        _box "AnyTLS Server" "管理"
    elif [ "$p" = "ss" ]; then
        ss_is_installed && inst=1; ss_is_running && run=1
        ver=$(ss_get_version)
        if [ $inst -eq 1 ]; then
            ss_read_conf 2>/dev/null
            ip=$(grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' "$SS_INFO" 2>/dev/null | head -1)
            [ -n "$CONF_PORT" ] && extra="端口  ${C}${CONF_PORT}${Z}   加密  ${C}${CONF_METHOD}${Z}"
            [ -n "$ip" ]        && extra="${extra}   IP  ${C}${ip}${Z}"
        fi
        _box "Shadowsocks Server" "管理"
    else
        hy_is_installed && inst=1; hy_is_running && run=1
        ver=$(hy_get_version)
        if [ $inst -eq 1 ]; then
            hy_read_conf 2>/dev/null
            ip=$(grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' "$HY_INFO" 2>/dev/null | head -1)
            [ -n "$CONF_PORT" ] && extra="端口  ${C}${CONF_PORT}${Z}   SNI  ${C}${CONF_SNI}${Z}"
            [ -n "$ip" ]        && extra="${extra}   IP  ${C}${ip}${Z}"
        fi
        _box "Hysteria2 Server" "管理"
    fi
    hr
    printf "    状态  %b\n" "$(_status_line $inst $run "$ver")"
    [ -n "$extra" ] && printf "    ${D}%b${Z}\n" "$extra"
    _svc_menu_items
    read -r CHOICE
}

# 子菜单循环  $1=snell|at
_run_submenu() {
    local p="$1"
    while true; do
        show_svc_menu "$p"; printf "\n"
        case "${p}_${CHOICE}" in
            snell_1) snell_install   ;; snell_2) snell_configure ;;
            snell_3) snell_update    ;; snell_4) snell_uninstall ;;
            at_1)    at_install      ;; at_2)    at_configure    ;;
            at_3)    at_update       ;; at_4)    at_uninstall    ;;
            ss_1)    ss_install      ;; ss_2)    ss_configure    ;;
            ss_3)    ss_update       ;; ss_4)    ss_uninstall    ;;
            hy_1)    hy_install      ;; hy_2)    hy_configure    ;;
            hy_3)    hy_update       ;; hy_4)    hy_uninstall    ;;
            *_0)     return ;;
            *) warn "无效选项：${CHOICE}" ;;
        esac
        printf "\n${D}  按 Enter 继续...${Z}"; read -r _
    done
}

###############################################################################
# §8  入口
###############################################################################

trap 'printf "\n${R}  已中断${Z}\n"; exit 130' INT

main() {
    check_root
    check_alpine
    while true; do
        show_main_menu; printf "\n"
        case "$CHOICE" in
            1) _run_submenu snell ;;
            2) _run_submenu at    ;;
            3) _run_submenu ss    ;;
            4) _run_submenu hy    ;;
            0) ok "再见"; printf "\n"; exit 0 ;;
            *) warn "无效选项：${CHOICE}" ;;
        esac
    done
}

main
