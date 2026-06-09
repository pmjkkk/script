#!/bin/ash
# shellcheck disable=SC2059  # ANSI 颜色变量出现在 printf 格式串中，属故意为之
#=============================================================================
# snell.sh  ·  Snell Server 管理工具  ·  Alpine Linux 专用
#=============================================================================

# 路径常量
readonly SNELL_BIN="/usr/local/bin/snell-server"
readonly SNELL_BIN_BAK="/usr/local/bin/snell-server.bak"
readonly SNELL_CONF="/etc/snell/snell-server.conf"
readonly SNELL_CONF_BAK="/etc/snell/snell-server.conf.bak"
readonly SNELL_INFO="/etc/snell/config.txt"
readonly SNELL_INIT="/etc/init.d/snell"
readonly SNELL_USER="snell"

# 内置 fallback 版本（仅在版本探测全部失败时使用）
SNELL_VERSION="v5.0.1"

# ANSI
R='\033[0;31m' G='\033[0;32m' Y='\033[0;33m' C='\033[0;36m'
B='\033[1m'    D='\033[2m'    Z='\033[0m'

###############################################################################
# §1  输出工具
###############################################################################

die()  { printf "\n${R}✗ %s${Z}\n" "$*"; exit 1; }
ok()   { printf "${G}✓ %s${Z}\n" "$*"; }
warn() { printf "${Y}⚠ %s${Z}\n" "$*"; }
info() { printf "${C}ℹ %s${Z}\n" "$*"; }
hr()   { printf "${D}──────────────────────────────────────────────${Z}\n"; }

# confirm  $1=提示  $2=默认 y|n（默认 n）  $3=超时秒（0=不超时）
confirm() {
    local msg="$1" def="${2:-n}" tmo="${3:-0}" ans hint
    [ "$def" = "y" ] && hint="${B}Y${Z}/n" || hint="y/${B}N${Z}"
    printf "${Y}  %s${Z} [%b]: " "$msg" "$hint"
    # SC2162: -r 防止反斜线被吞
    if [ "$tmo" -gt 0 ]; then read -r -t "$tmo" ans; else read -r ans; fi
    [ -z "$ans" ] && ans="$def"
    [ "$ans" = "y" ] || [ "$ans" = "Y" ]
}

# ask  $1=提示  $2=默认值  →  结果写入 $REPLY
ask() {
    local msg="$1" def="$2"
    if [ -n "$def" ]; then
        printf "${C}  %-14s${Z}${D}[%s]${Z}: " "$msg" "$def"
    else
        printf "${C}  %-14s${Z}: " "$msg"
    fi
    read -r REPLY   # SC2162: -r
    [ -z "$REPLY" ] && REPLY="$def"
}

# steps_init N  →  step "描述"
_st=0; _st_n=0
steps_init() { _st_n="$1"; _st=0; }
step() { _st=$((_st+1)); printf "${C}[%d/%d]${Z} %s\n" "$_st" "$_st_n" "$1"; }

# 服务就绪等待（点动画），10s 超时
wait_for_service() {
    local i=0
    printf "${C}  等待服务启动${Z}"
    while [ $i -lt 10 ]; do
        is_running && { printf " ${G}就绪${Z}\n"; return 0; }
        printf "."; sleep 1; i=$((i+1))
    done
    printf " ${Y}超时${Z}\n"; return 1
}

# 配置摘要面板  $1=port $2=psk $3=ip $4=country
show_summary() {
    printf "\n"; hr
    printf "${G}${B}  配置摘要${Z}\n"; hr
    printf "  ${D}%-6s${Z}  %s\n" "地区" "$4"
    printf "  ${D}%-6s${Z}  %s\n" "IP"   "$3"
    printf "  ${D}%-6s${Z}  %s\n" "端口" "$1"
    printf "  ${D}%-6s${Z}  %s\n" "PSK"  "$2"
    hr
    printf "  ${D}Surge 节点:${Z}\n"
    # PSK 经 %s 参数传入，避免 \n \t \\ 等字符被解释
    printf "  ${C}%s = snell, %s, %s, psk = %s, version = 5, reuse = true${Z}\n" \
        "$4" "$3" "$1" "$2"
    hr; printf "\n"
}

###############################################################################
# §2  系统检查
###############################################################################

check_root()   { [ "$(id -u)" = "0" ] || die "请以 root 权限运行此脚本"; }
check_alpine() { [ -f /etc/alpine-release ] || die "此脚本仅支持 Alpine Linux"; }

###############################################################################
# §3  软件包
###############################################################################

readonly _PKGS="wget unzip curl gcompat upx"

ensure_packages() {
    local missing="" p
    for p in $_PKGS; do  # SC2086: $_PKGS 字段分割是故意的
        apk info -e "$p" > /dev/null 2>&1 || missing="$missing $p"
    done
    [ -z "$missing" ] && return 0
    info "安装缺失依赖:${missing}"
    # SC2015 fix: 用 if 代替 A&&B||C，避免 B 失败时 C 被误触发
    # SC2086: $missing 字段分割是故意的（多包名）
    if ! apk update -q; then die "软件包安装失败（apk update）"; fi
    # shellcheck disable=SC2086
    if ! apk add -q $missing; then die "软件包安装失败（apk add）"; fi
    ok "依赖安装完成"
}

###############################################################################
# §4  Snell 状态
###############################################################################

is_installed() { [ -f "$SNELL_BIN" ]; }

is_running() {
    [ -f "$SNELL_INIT" ] || return 1
    rc-service snell status > /dev/null 2>&1
}

get_version() {
    is_installed || { echo "未安装"; return; }
    "$SNELL_BIN" -version 2>&1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' || echo "未知"
}

# 解析配置文件 → CONF_PORT / CONF_PSK
# ^ 锚定行首，避免匹配注释或其他含关键字的行
read_snell_conf() {
    [ -f "$SNELL_CONF" ] || return 1
    CONF_PORT=$(grep '^listen' "$SNELL_CONF" | sed 's/.*://')
    CONF_PSK=$(grep  '^psk'    "$SNELL_CONF" | sed 's/.*= //')
}

###############################################################################
# §5  版本探测
# Snell 为闭源商业软件，无 GitHub Releases API，直接对下载 URL 发 HEAD 请求
###############################################################################

_version_url() {
    local arch; arch=$(uname -m)
    case "$arch" in
        aarch64)        arch="aarch64" ;;
        x86_64|amd64)   arch="amd64"   ;;
        *) die "不支持的系统架构: ${arch}（仅支持 x86_64 / aarch64）" ;;
    esac
    printf "https://dl.nssurge.com/snell/snell-server-%s-linux-%s.zip" "$1" "$arch"
}

_probe_exists() {
    curl -sf --head --connect-timeout 4 --max-time 6 \
        "$(_version_url "$1")" > /dev/null 2>&1
}

# 从内置版本向后探测 patch 版本（遇 404 即停），再检查 minor+1.0
fetch_latest_version() {
    local maj min pat best cand p
    maj=$(echo "$SNELL_VERSION" | grep -oE '[0-9]+' | sed -n '1p')
    min=$(echo "$SNELL_VERSION" | grep -oE '[0-9]+' | sed -n '2p')
    pat=$(echo "$SNELL_VERSION" | grep -oE '[0-9]+' | sed -n '3p')

    # FIX #6: 版本号解析结果非空校验，防止 SNELL_VERSION 异常时产生无意义请求
    if [ -z "$maj" ] || [ -z "$min" ] || [ -z "$pat" ]; then
        warn "版本号解析失败（${SNELL_VERSION}），跳过版本探测"
        echo "$SNELL_VERSION"; return
    fi

    best="$SNELL_VERSION"

    p=$((pat + 1))
    while [ $p -le $((pat + 10)) ]; do
        cand="v${maj}.${min}.${p}"
        if _probe_exists "$cand"; then
            best="$cand"; p=$((p + 1))
        else
            break
        fi
    done

    cand="v${maj}.$((min + 1)).0"
    _probe_exists "$cand" && best="$cand"

    echo "$best"
}

###############################################################################
# §6  网络工具
###############################################################################

# 获取公网 IP → PUB_IP / PUB_COUNTRY
# 校验 IPv4 格式，防止 HTML 错误页等异常内容被拼入后续 URL
fetch_public_ip() {
    local raw
    raw=$(curl -s --connect-timeout 5 --max-time 10 \
        https://checkip.amazonaws.com | tr -d '[:space:]')

    if echo "$raw" | grep -qE '^([0-9]{1,3}\.){3}[0-9]{1,3}$'; then
        PUB_IP="$raw"
        PUB_COUNTRY=$(curl -s --connect-timeout 5 --max-time 10 \
            "https://ipinfo.io/${PUB_IP}/country" | tr -d '[:space:]')
        [ -z "$PUB_COUNTRY" ] && PUB_COUNTRY="未知"
    else
        warn "公网 IP 获取失败（响应: ${raw:-空}）"
        PUB_IP="未知"; PUB_COUNTRY="未知"
    fi
}

###############################################################################
# §7  文件管理
###############################################################################

# PSK 经 printf %s 传参，特殊字符不经过 shell 展开
# 返回 0=成功 / 1=失败
write_snell_conf() {
    mkdir -p /etc/snell || return 1
    printf '[snell-server]\nlisten = ::0:%s\npsk = %s\nipv6 = true\n' \
        "$1" "$2" > "$SNELL_CONF" || return 1
}

write_config_txt() {
    # $1=port $2=psk $3=ip $4=country
    printf '%s = snell, %s, %s, psk = %s, version = 5, reuse = true\n' \
        "$4" "$3" "$1" "$2" > "$SNELL_INFO"
}

write_init_script() {
    # 单引号 'EOF' 锁定，防止 heredoc 内容被 shell 展开
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

###############################################################################
# §8  服务控制（统一封装，消除散落的 /dev/null 重定向）
###############################################################################

svc_start()   { rc-service snell start       > /dev/null 2>&1 || true; }
svc_stop()    { rc-service snell stop        > /dev/null 2>&1 || true; }
svc_enable()  { rc-update  add snell default > /dev/null 2>&1 || true; }
svc_disable() { rc-update  del snell         > /dev/null 2>&1 || true; }

###############################################################################
# §9  端口 & PSK 生成
###############################################################################

gen_port() {
    local port seed attempts=0
    while [ $attempts -lt 20 ]; do
        seed=$(od -An -N4 -tu4 /dev/urandom | tr -d ' \n')
        port=$(awk -v s="$seed" 'BEGIN{srand(s+0); print int(rand()*35000)+30000}')
        port_in_use "$port" || { echo "$port"; return 0; }
        attempts=$((attempts + 1))
    done
    die "无法找到可用端口，请手动指定"
}

gen_psk() { tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 24; }

port_in_use() {
    if   command -v ss      > /dev/null 2>&1; then
        ss -tlnp 2>/dev/null | grep -qE ":${1}( |$)"
    elif command -v netstat > /dev/null 2>&1; then
        netstat -tlnp 2>/dev/null | grep -qE ":${1}( |$)"
    else
        return 1   # 无检测工具，降级放行
    fi
}

###############################################################################
# §10  下载 & 解压
###############################################################################

download_and_extract() {
    local ver="${1:-$SNELL_VERSION}"
    local url zip
    url=$(_version_url "$ver")
    zip="/tmp/snell-$$.zip"

    info "下载 Snell ${ver} ..."

    # busybox wget 不支持 --show-progress；先探测再决定参数
    if wget --help 2>&1 | grep -q '\-\-show-progress'; then
        wget -q --show-progress "$url" -O "$zip" \
            || { rm -f "$zip"; die "下载失败，请检查网络"; }
    else
        info "下载中，请稍候..."
        wget "$url" -O "$zip" \
            || { rm -f "$zip"; die "下载失败，请检查网络"; }
    fi

    # 备份旧二进制；解压失败时自动回滚
    [ -f "$SNELL_BIN" ] && cp "$SNELL_BIN" "$SNELL_BIN_BAK"

    if ! unzip -oq "$zip" snell-server -d /usr/local/bin; then
        rm -f "$zip"
        if [ -f "$SNELL_BIN_BAK" ]; then
            mv "$SNELL_BIN_BAK" "$SNELL_BIN"
            warn "解压失败，已自动回滚至旧版本"
        fi
        die "解压 Snell 失败"
    fi

    rm -f "$zip" "$SNELL_BIN_BAK"
    chmod +x "$SNELL_BIN"
    upx -d "$SNELL_BIN" > /dev/null 2>&1 || true
    ok "Snell ${ver} 部署完成"
}

###############################################################################
# §11  动作：安装
###############################################################################

action_install() {
    printf "\n"
    if is_installed; then
        warn "Snell 已安装（$(get_version)），继续将覆盖现有配置"
        confirm "确认继续？" "n" || { ok "已取消"; return; }
        printf "\n"
    fi

    steps_init 5
    hr; printf "${B}  安装 Snell ${SNELL_VERSION}${Z}\n"; hr

    step "检查并安装依赖"
    ensure_packages

    step "下载并部署二进制"
    download_and_extract "$SNELL_VERSION"

    step "创建系统用户"
    if ! id "$SNELL_USER" > /dev/null 2>&1; then
        adduser -D -H -s /sbin/nologin "$SNELL_USER"
        ok "用户 ${SNELL_USER} 已创建"
    else
        info "用户 ${SNELL_USER} 已存在，跳过"
    fi

    step "生成配置"
    local port psk
    port=$(gen_port)
    psk=$(gen_psk)
    write_snell_conf "$port" "$psk" || die "配置写入失败，请检查磁盘空间或权限"
    write_init_script
    ok "配置已写入"

    step "启动服务"
    svc_enable
    svc_start
    if wait_for_service; then
        ok "Snell 服务已启动"
    else
        warn "启动超时，请运行: rc-service snell status"
    fi

    fetch_public_ip
    write_config_txt "$port" "$psk" "$PUB_IP" "$PUB_COUNTRY"
    show_summary "$port" "$psk" "$PUB_IP" "$PUB_COUNTRY"
}

###############################################################################
# §12  动作：配置
###############################################################################

action_configure() {
    printf "\n"
    [ -f "$SNELL_CONF" ] || { warn "未找到配置文件，请先安装 Snell"; return; }

    read_snell_conf

    hr; printf "${B}  当前配置${Z}\n"; hr
    printf "  ${D}%-6s${Z}  %s\n" "端口" "$CONF_PORT"
    printf "  ${D}%-6s${Z}  %s\n" "PSK"  "$CONF_PSK"
    hr; printf "\n"

    confirm "修改配置？" "n" || return
    printf "\n${D}  回车保留当前值${Z}\n\n"

    ask "端口" "$CONF_PORT"; local new_port="$REPLY"
    ask "PSK"  "$CONF_PSK";  local new_psk="$REPLY"
    printf "\n"

    # 端口格式校验
    case "$new_port" in
        ''|*[!0-9]*) warn "端口须为纯数字，操作取消"; return ;;
    esac
    if [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
        warn "端口范围 1–65535，操作取消"; return
    fi

    # PSK 校验
    [ -z "$new_psk" ] && { warn "PSK 不能为空，操作取消"; return; }
    case "$new_psk" in
        *' '*|*'	'*) warn "PSK 不能包含空白字符，操作取消"; return ;;
    esac

    # 值未变则无需重启
    if [ "$new_port" = "$CONF_PORT" ] && [ "$new_psk" = "$CONF_PSK" ]; then
        info "配置未变更，无需重启"; return
    fi

    svc_stop

    # 新端口冲突检测（仅端口发生变化时）
    if [ "$new_port" != "$CONF_PORT" ] && port_in_use "$new_port"; then
        warn "端口 ${new_port} 已被占用，操作取消"
        svc_start; return
    fi

    # 备份旧配置；写入失败时恢复并重启
    cp "$SNELL_CONF" "$SNELL_CONF_BAK" 2>/dev/null
    if ! write_snell_conf "$new_port" "$new_psk"; then
        [ -f "$SNELL_CONF_BAK" ] && mv "$SNELL_CONF_BAK" "$SNELL_CONF"
        warn "配置写入失败，已恢复原配置并重启服务"
        svc_start; return
    fi
    rm -f "$SNELL_CONF_BAK"

    info "配置已更新，重启 Snell..."
    svc_start
    if wait_for_service; then ok "新配置已生效"
    else warn "重启超时，请手动检查"; fi

    fetch_public_ip
    write_config_txt "$new_port" "$new_psk" "$PUB_IP" "$PUB_COUNTRY"
    show_summary "$new_port" "$new_psk" "$PUB_IP" "$PUB_COUNTRY"
}

###############################################################################
# §13  动作：更新
###############################################################################

action_update() {
    printf "\n"
    is_installed || { warn "Snell 未安装，请先执行安装"; return; }

    steps_init 4
    hr; printf "${B}  更新 Snell${Z}\n"; hr

    step "探测最新版本"
    local old_ver new_ver
    old_ver=$(get_version)
    # FIX #1: 以实际已安装版本为探测基准，而非脚本内置的 fallback 版本
    SNELL_VERSION="$old_ver"
    info "当前版本: ${old_ver}，探测中..."
    new_ver=$(fetch_latest_version)

    if [ "$old_ver" = "$new_ver" ]; then
        printf "\n"; warn "当前已是最新版本 (${old_ver})"
        confirm "仍要重新安装？" "n" || { ok "已取消"; return; }
        printf "\n"
    else
        ok "发现新版本: ${D}${old_ver}${Z} → ${G}${new_ver}${Z}"; printf "\n"
    fi

    step "停止服务"
    svc_stop; ok "已停止"

    step "下载并部署"
    ensure_packages
    download_and_extract "$new_ver"
    SNELL_VERSION="$new_ver"

    step "启动服务"
    svc_start
    if wait_for_service; then ok "Snell 已启动（$(get_version)）"
    else warn "启动超时，请手动检查"; fi

    read_snell_conf
    if [ -n "$CONF_PORT" ]; then
        fetch_public_ip
        write_config_txt "$CONF_PORT" "$CONF_PSK" "$PUB_IP" "$PUB_COUNTRY"
        show_summary "$CONF_PORT" "$CONF_PSK" "$PUB_IP" "$PUB_COUNTRY"
    fi
}

###############################################################################
# §14  动作：卸载
###############################################################################

action_uninstall() {
    printf "\n"; hr; printf "${B}  卸载 Snell${Z}\n"; hr; printf "\n"
    warn "将删除二进制、配置目录及系统用户，操作不可恢复"
    printf "\n"
    confirm "确认卸载？" "n" || { ok "已取消"; return; }
    printf "\n"

    info "停止并注销服务..."
    svc_stop
    svc_disable
    rm -f "$SNELL_INIT" "$SNELL_BIN" "$SNELL_BIN_BAK"
    rm -rf /etc/snell

    info "删除系统用户..."
    if id "$SNELL_USER" > /dev/null 2>&1; then
        local home
        home=$(getent passwd "$SNELL_USER" 2>/dev/null | cut -d: -f6)
        deluser "$SNELL_USER" > /dev/null 2>&1 || true
        # 安全守卫：路径非空且非根目录才删除
        [ -n "$home" ] && [ "$home" != "/" ] && [ -d "$home" ] && rm -rf "$home"
    fi

    printf "\n"; ok "Snell 已完全卸载"; printf "\n"
}

###############################################################################
# §15  菜单
###############################################################################

show_menu() {
    clear

    local status_line extra_line=""

    if is_installed; then
        local ver port ip
        ver=$(get_version)
        port=$(grep '^listen' "$SNELL_CONF" 2>/dev/null | sed 's/.*://')
        ip=$(grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' "$SNELL_INFO" 2>/dev/null | head -1)

        if is_running; then
            status_line="${G}● 运行中${Z}  ${D}${ver}${Z}"
        else
            status_line="${R}● 已停止${Z}  ${D}${ver}${Z}"
        fi
        [ -n "$port" ] && extra_line="  端口 ${C}${port}${Z}"
        [ -n "$ip" ]   && extra_line="${extra_line}   IP ${C}${ip}${Z}"
    else
        status_line="${D}● 未安装${Z}"
    fi

    printf "${G}${B}\n"
    printf "  ╔════════════════════════════════════╗\n"
    printf "  ║      Snell Server 管理工具         ║\n"
    printf "  ╚════════════════════════════════════╝\n"
    printf "${Z}\n"
    printf "  状态  %b\n" "$status_line"
    [ -n "$extra_line" ] && printf "%b\n" "$extra_line"
    printf "\n"
    hr
    printf "  ${C}1${Z}  安装\n"
    printf "  ${C}2${Z}  配置\n"
    printf "  ${C}3${Z}  更新\n"
    printf "  ${C}4${Z}  卸载\n"
    hr
    printf "  ${D}0  退出${Z}\n\n"
    printf "  请选择: "
    read -r CHOICE  # SC2162: -r
}

###############################################################################
# §16  入口
###############################################################################

trap 'printf "\n${R}  已中断${Z}\n"; exit 130' INT

main() {
    check_root
    check_alpine

    while true; do
        show_menu
        printf "\n"
        case "$CHOICE" in
            1) action_install   ;;
            2) action_configure ;;
            3) action_update    ;;
            4) action_uninstall ;;
            0) ok "再见"; printf "\n"; exit 0 ;;
            *) warn "无效选项：${CHOICE}" ;;
        esac
        printf "\n${D}  按 Enter 返回菜单...${Z}"
        read -r _  # SC2162: -r
    done
}

main
