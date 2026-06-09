#!/bin/sh
# =========================================
# 作者: pmj
# 日期: 2026年6月6日
# 描述: Snell 代理 安装/卸载/查看/更新 管理脚本
# 平台: Alpine Linux (OpenRC)
# 集成: ShadowTLS / BBR / 多用户管理
# =========================================

# ── 颜色 ──────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

# ── 版本 ──────────────────────────────────
SCRIPT_VERSION="1.0"

# ── 路径 ──────────────────────────────────
INSTALL_DIR="/usr/local/bin"
SNELL_CONF_DIR="/etc/snell"
SNELL_CONF_FILE="${SNELL_CONF_DIR}/users/snell-main.conf"
USERS_DIR="${SNELL_CONF_DIR}/users"
INITD_DIR="/etc/init.d"

# ── 全局变量 ──────────────────────────────
SNELL_VERSION_CHOICE=""
SNELL_VERSION=""

# ═════════════════════════════════════════
# 基础工具
# ═════════════════════════════════════════

check_root() {
    [ "$(id -u)" = "0" ] || { echo -e "${RED}请以 root 权限运行此脚本${RESET}"; exit 1; }
}

require_pkg() {
    for pkg in "$@"; do
        if ! command -v "$pkg" >/dev/null 2>&1; then
            echo -e "${YELLOW}正在安装依赖: ${pkg}...${RESET}"
            apk add --no-cache "$pkg" || { echo -e "${RED}安装 ${pkg} 失败${RESET}"; exit 1; }
        fi
    done
}

check_alpine() {
    if ! [ -f /etc/alpine-release ]; then
        echo -e "${RED}此脚本仅支持 Alpine Linux${RESET}"
        exit 1
    fi
}

# ═════════════════════════════════════════
# OpenRC 服务管理
# ═════════════════════════════════════════

svc_start()   { rc-service "$1" start; }
svc_stop()    { rc-service "$1" stop; }
svc_restart() { rc-service "$1" restart; }
svc_enable()  { rc-update add "$1" default 2>/dev/null; }
svc_disable() { rc-update del "$1" default 2>/dev/null; }
svc_active()  { rc-service "$1" status 2>/dev/null | grep -q 'started'; }

_write_initd_snell() {
    local svc_name="$1"
    local conf_file="$2"
    cat > "${INITD_DIR}/${svc_name}" <<EOF
#!/sbin/openrc-run
name="${svc_name}"
description="Snell Proxy Service"
command="${INSTALL_DIR}/snell-server"
command_args="-c ${conf_file}"
command_user="nobody"
pidfile="/run/${svc_name}.pid"
command_background=true
output_log="/var/log/${svc_name}.log"
error_log="/var/log/${svc_name}.log"
depend() { need net; }
EOF
    chmod +x "${INITD_DIR}/${svc_name}"
}

_write_initd_shadowtls() {
    local svc_name="$1"   # e.g. shadowtls-snell-12345
    local listen_port="$2"
    local backend_port="$3"
    local tls_domain="$4"
    local password="$5"
    cat > "${INITD_DIR}/${svc_name}" <<EOF
#!/sbin/openrc-run
name="${svc_name}"
description="ShadowTLS Service"
command="${INSTALL_DIR}/shadow-tls"
command_args="--v3 server --listen ::0:${listen_port} --server 127.0.0.1:${backend_port} --tls ${tls_domain} --password ${password}"
command_user="root"
pidfile="/run/${svc_name}.pid"
command_background=true
output_log="/var/log/${svc_name}.log"
error_log="/var/log/${svc_name}.log"
depend() { need net; }
EOF
    chmod +x "${INITD_DIR}/${svc_name}"
}

_remove_service() {
    local svc="$1"
    svc_stop    "$svc" 2>/dev/null
    svc_disable "$svc" 2>/dev/null
    rm -f "${INITD_DIR}/${svc}"
}

# ═════════════════════════════════════════
# Snell 版本获取
# ═════════════════════════════════════════

get_latest_snell_v4_version() {
    local ver
    ver=$(curl -s https://manual.nssurge.com/others/snell.html \
        | grep -oE 'snell-server-v4\.[0-9]+\.[0-9]+' \
        | grep -oE '4\.[0-9]+\.[0-9]+' | head -n1)
    if [ -z "$ver" ]; then
        ver=$(curl -s https://kb.nssurge.com/surge-knowledge-base/zh/release-notes/snell \
            | grep -oE 'snell-server-v4\.[0-9]+\.[0-9]+' \
            | grep -oE '4\.[0-9]+\.[0-9]+' | head -n1)
    fi
    echo "v${ver:-4.1.1}"
}

get_latest_snell_v5_version() {
    local ver
    ver=$(curl -s https://manual.nssurge.com/others/snell.html \
        | grep -oE 'snell-server-v5\.[0-9]+\.[0-9]+b[0-9]+' \
        | grep -oE '5\.[0-9]+\.[0-9]+b[0-9]+' | head -n1)
    if [ -z "$ver" ]; then
        ver=$(curl -s https://kb.nssurge.com/surge-knowledge-base/zh/release-notes/snell \
            | grep -oE 'snell-server-v5\.[0-9]+\.[0-9]+b[0-9]+' \
            | grep -oE '5\.[0-9]+\.[0-9]+b[0-9]+' | head -n1)
    fi
    if [ -z "$ver" ]; then
        ver=$(curl -s https://manual.nssurge.com/others/snell.html \
            | grep -oE 'snell-server-v5\.[0-9]+\.[0-9]+' \
            | grep -oE '5\.[0-9]+\.[0-9]+' | grep -v 'b' | head -n1)
    fi
    echo "v${ver:-5.0.1}"
}

get_latest_snell_version() {
    if [ "$SNELL_VERSION_CHOICE" = "v5" ]; then
        SNELL_VERSION=$(get_latest_snell_v5_version)
    else
        SNELL_VERSION=$(get_latest_snell_v4_version)
    fi
}

get_snell_download_url() {
    local arch suffix
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64)  suffix="amd64"   ;;
        i386|i686)     suffix="i386"    ;;
        aarch64|arm64) suffix="aarch64" ;;
        armv7l|armv7)  suffix="armv7l"  ;;
        *) echo -e "${RED}不支持的架构: ${arch}${RESET}" >&2; exit 1 ;;
    esac
    echo "https://dl.nssurge.com/snell/snell-server-${SNELL_VERSION}-linux-${suffix}.zip"
}

# ═════════════════════════════════════════
# 版本比较（纯 sh）
# ═════════════════════════════════════════

version_ge() {
    local v1="${1#[vV]}" v2="${2#[vV]}"
    v1=$(echo "$v1" | sed 's/b\([0-9]*\)$/.\1/')
    v2=$(echo "$v2" | sed 's/b\([0-9]*\)$/.\1/')
    local IFS=.
    set -- $v1; local a1=$1 a2=$2 a3=$3 a4=${4:-0}
    set -- $v2; local b1=$1 b2=$2 b3=$3 b4=${4:-0}
    for pair in "$a1:$b1" "$a2:$b2" "$a3:$b3" "$a4:$b4"; do
        local l="${pair%%:*}" r="${pair##*:}"
        l=${l:-0}; r=${r:-0}
        [ "$l" -gt "$r" ] && return 0
        [ "$l" -lt "$r" ] && return 1
    done
    return 0
}

# ═════════════════════════════════════════
# Snell 已装版本检测
# ═════════════════════════════════════════

detect_installed_snell_version() {
    if command -v snell-server >/dev/null 2>&1; then
        snell-server --v 2>&1 | grep -q 'v5' && echo "v5" || echo "v4"
    else
        echo "unknown"
    fi
}

# 数字格式（供 ShadowTLS 模块使用）
get_snell_version_num() {
    local v
    v=$(detect_installed_snell_version)
    [ "$v" = "v5" ] && echo "5" || echo "4"
}

get_current_snell_version() {
    local installed
    installed=$(detect_installed_snell_version)
    if [ "$installed" = "v5" ]; then
        CURRENT_VERSION=$(snell-server --v 2>&1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+[a-z0-9]*' | head -n1)
        CURRENT_VERSION="${CURRENT_VERSION:-v5.0.0b3}"
    else
        CURRENT_VERSION=$(snell-server --v 2>&1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
        if [ -z "$CURRENT_VERSION" ]; then
            echo -e "${RED}无法获取当前 Snell 版本${RESET}"; exit 1
        fi
    fi
}

# ═════════════════════════════════════════
# 配置备份 / 恢复
# ═════════════════════════════════════════

backup_snell_config() {
    local bak="${SNELL_CONF_DIR}/backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$bak"
    cp -a "${USERS_DIR}/"*.conf "$bak/" 2>/dev/null
    echo "$bak"
}

restore_snell_config() {
    local bak="$1"
    if [ -d "$bak" ]; then
        cp -a "${bak}/"*.conf "${USERS_DIR}/"
        echo -e "${GREEN}配置已从备份恢复${RESET}"
    else
        echo -e "${RED}备份目录不存在，无法恢复${RESET}"
    fi
}

# ═════════════════════════════════════════
# 网络 / 输入工具
# ═════════════════════════════════════════

get_public_ip() {
    IPV4_ADDR=$(curl -s4 --max-time 5 https://api.ipify.org 2>/dev/null)
    IPV6_ADDR=$(curl -s6 --max-time 5 https://api64.ipify.org 2>/dev/null)
    [ -n "$IPV4_ADDR" ] && IP_COUNTRY_IPV4=$(curl -s --max-time 5 "https://ipinfo.io/${IPV4_ADDR}/country" 2>/dev/null)
    [ -n "$IPV6_ADDR" ] && IP_COUNTRY_IPV6=$(curl -s --max-time 5 "https://ipapi.co/${IPV6_ADDR}/country/" 2>/dev/null)
}

get_server_ip() {
    local ip
    ip=$(curl -s4 --max-time 5 ip.sb 2>/dev/null)
    [ -z "$ip" ] && ip=$(curl -s6 --max-time 5 ip.sb 2>/dev/null)
    if [ -z "$ip" ]; then
        echo -e "${RED}无法获取服务器 IP${RESET}" >&2; return 1
    fi
    echo "$ip"
}

get_user_port() {
    while true; do
        printf "请输入端口号 (1-65535): "
        read -r PORT
        case "$PORT" in
            ''|*[!0-9]*) ;;
            *)
                [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ] && \
                    { echo -e "${GREEN}已选择端口: $PORT${RESET}"; break; }
                ;;
        esac
        echo -e "${RED}无效端口号，请重新输入${RESET}"
    done
}

get_dns() {
    printf "请输入 DNS 服务器 (留空使用系统DNS): "
    read -r custom_dns
    if [ -z "$custom_dns" ]; then
        DNS=$(grep -E '^nameserver' /etc/resolv.conf 2>/dev/null \
            | awk '{print $2}' | tr '\n' ',' | sed 's/,$//')
        DNS="${DNS:-1.1.1.1,8.8.8.8}"
        echo -e "${GREEN}使用系统 DNS: $DNS${RESET}"
    else
        DNS="$custom_dns"
        echo -e "${GREEN}使用自定义 DNS: $DNS${RESET}"
    fi
}

select_snell_version() {
    echo -e "${CYAN}请选择要安装的 Snell 版本：${RESET}"
    echo -e "${GREEN}1.${RESET} Snell v4"
    echo -e "${GREEN}2.${RESET} Snell v5"
    while true; do
        printf "请输入选项 [1-2]: "
        read -r ver_choice
        case "$ver_choice" in
            1) SNELL_VERSION_CHOICE="v4"; echo -e "${GREEN}已选择 Snell v4${RESET}"; break ;;
            2) SNELL_VERSION_CHOICE="v5"; echo -e "${GREEN}已选择 Snell v5${RESET}"; break ;;
            *) echo -e "${RED}请输入正确的选项 [1-2]${RESET}" ;;
        esac
    done
}

open_port() {
    local p="$1"
    if command -v iptables >/dev/null 2>&1; then
        iptables -I INPUT -p tcp --dport "$p" -j ACCEPT 2>/dev/null
        mkdir -p /etc/iptables
        iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    fi
}

# ═════════════════════════════════════════
# Surge 配置输出
# ═════════════════════════════════════════

generate_surge_config() {
    local ip="$1" port="$2" psk="$3" snell_ver="$4" country="$5"
    local base="${country} = snell, ${ip}, ${port}, psk = ${psk}, reuse = true, tfo = true"
    if [ "$snell_ver" = "v5" ]; then
        echo -e "${GREEN}${base}, version = 4${RESET}"
        echo -e "${GREEN}${base}, version = 5${RESET}"
    else
        echo -e "${GREEN}${base}, version = 4${RESET}"
    fi
}

# ═════════════════════════════════════════
# Snell 端口 / 配置读取
# ═════════════════════════════════════════

get_snell_main_port() {
    [ -f "$SNELL_CONF_FILE" ] && \
        grep -E '^listen' "$SNELL_CONF_FILE" | sed -n 's/.*::0:\([0-9]*\)/\1/p'
}

# 输出所有 snell 用户的 port|psk，主用户优先
get_all_snell_users() {
    [ -d "$USERS_DIR" ] || return 1
    if [ -f "$SNELL_CONF_FILE" ]; then
        local p psk
        p=$(grep -E '^listen' "$SNELL_CONF_FILE" | sed -n 's/.*::0:\([0-9]*\)/\1/p')
        psk=$(grep -E '^psk' "$SNELL_CONF_FILE" | awk -F'=' '{print $2}' | tr -d ' ')
        [ -n "$p" ] && [ -n "$psk" ] && echo "${p}|${psk}"
    fi
    for conf in "${USERS_DIR}"/snell-*.conf; do
        [ -f "$conf" ] || continue
        case "$conf" in *snell-main.conf) continue ;; esac
        local p psk
        p=$(grep -E '^listen' "$conf" | sed -n 's/.*::0:\([0-9]*\)/\1/p')
        psk=$(grep -E '^psk' "$conf" | awk -F'=' '{print $2}' | tr -d ' ')
        [ -n "$p" ] && [ -n "$psk" ] && echo "${p}|${psk}"
    done
}

check_port_in_use() {
    local port="$1"
    # 检查已有 snell 配置文件
    for conf in "${USERS_DIR}"/snell-*.conf; do
        [ -f "$conf" ] || continue
        local p
        p=$(grep -E '^listen' "$conf" | sed -n 's/.*::0:\([0-9]*\)/\1/p')
        [ "$p" = "$port" ] && return 0
    done
    return 1
}

# ═════════════════════════════════════════
# Snell 安装
# ═════════════════════════════════════════

install_snell() {
    echo -e "${CYAN}正在安装 Snell${RESET}"
    require_pkg wget unzip

    select_snell_version
    get_latest_snell_version

    local url
    url=$(get_snell_download_url)
    echo -e "${CYAN}下载 Snell ${SNELL_VERSION_CHOICE} (${SNELL_VERSION})...${RESET}"
    echo -e "${YELLOW}下载链接: ${url}${RESET}"

    wget -q "$url" -O /tmp/snell-server.zip || { echo -e "${RED}下载失败${RESET}"; exit 1; }
    unzip -oq /tmp/snell-server.zip -d "$INSTALL_DIR" || { echo -e "${RED}解压失败${RESET}"; exit 1; }
    rm -f /tmp/snell-server.zip
    chmod +x "${INSTALL_DIR}/snell-server"

    get_user_port
    get_dns
    local PSK
    PSK=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20)

    mkdir -p "${USERS_DIR}"
    cat > "$SNELL_CONF_FILE" <<EOF
[snell-server]
listen = ::0:${PORT}
psk = ${PSK}
ipv6 = true
dns = ${DNS}
EOF

    _write_initd_snell "snell" "$SNELL_CONF_FILE"
    svc_enable "snell"
    svc_start  "snell" || { echo -e "${RED}服务启动失败${RESET}"; exit 1; }
    open_port "$PORT"

    # 安装快捷命令
    cat > /usr/local/bin/snell <<'WRAPPER'
#!/bin/sh
[ "$(id -u)" = "0" ] || { echo "请以 root 权限运行"; exit 1; }
TMP=$(mktemp)
curl -sL https://raw.githubusercontent.com/pmjkkk/script/refs/heads/main/bash/snell.sh -o "$TMP" \
    && sh "$TMP"; rm -f "$TMP"
WRAPPER
    chmod +x /usr/local/bin/snell

    echo -e "\n${GREEN}安装完成！配置信息：${RESET}"
    echo -e "${CYAN}--------------------------------${RESET}"
    echo -e "${YELLOW}监听端口: ${PORT}  PSK: ${PSK}  DNS: ${DNS}${RESET}"
    echo -e "${CYAN}--------------------------------${RESET}"

    get_public_ip
    [ -n "$IPV4_ADDR" ] && echo -e "IPv4: ${IPV4_ADDR}  国家: ${IP_COUNTRY_IPV4}"
    [ -n "$IPV6_ADDR" ] && echo -e "IPv6: ${IPV6_ADDR}  国家: ${IP_COUNTRY_IPV6}"

    local inst_ver
    inst_ver=$(detect_installed_snell_version)
    echo -e "\n${GREEN}Surge 配置格式：${RESET}"
    [ -n "$IPV4_ADDR" ] && generate_surge_config "$IPV4_ADDR" "$PORT" "$PSK" "$inst_ver" "${IP_COUNTRY_IPV4:-Unknown}"
    [ -n "$IPV6_ADDR" ] && generate_surge_config "$IPV6_ADDR" "$PORT" "$PSK" "$inst_ver" "${IP_COUNTRY_IPV6:-Unknown}"
    echo -e "\n${YELLOW}可输入 'snell' 进入管理菜单（需要 root）${RESET}"
}

# ═════════════════════════════════════════
# Snell 卸载
# ═════════════════════════════════════════

uninstall_snell() {
    echo -e "${CYAN}正在卸载 Snell${RESET}"
    _remove_service "snell"
    if [ -d "$USERS_DIR" ]; then
        for conf in "${USERS_DIR}"/*.conf; do
            [ -f "$conf" ] || continue
            case "$conf" in *snell-main.conf) continue ;; esac
            local p
            p=$(grep -E '^listen' "$conf" | sed -n 's/.*::0:\([0-9]*\)/\1/p')
            [ -n "$p" ] && _remove_service "snell-${p}"
        done
    fi
    rm -f "${INSTALL_DIR}/snell-server" "${INSTALL_DIR}/snell"
    rm -rf "$SNELL_CONF_DIR"
    echo -e "${GREEN}Snell 已完整卸载${RESET}"
}

# ═════════════════════════════════════════
# Snell 重启
# ═════════════════════════════════════════

restart_snell() {
    echo -e "${YELLOW}正在重启所有 Snell 服务...${RESET}"
    svc_restart "snell" && echo -e "${GREEN}主服务已重启${RESET}" \
        || echo -e "${RED}主服务重启失败${RESET}"
    if [ -d "$USERS_DIR" ]; then
        for conf in "${USERS_DIR}"/*.conf; do
            [ -f "$conf" ] || continue
            case "$conf" in *snell-main.conf) continue ;; esac
            local p
            p=$(grep -E '^listen' "$conf" | sed -n 's/.*::0:\([0-9]*\)/\1/p')
            [ -n "$p" ] && {
                svc_restart "snell-${p}" 2>/dev/null \
                    && echo -e "${GREEN}用户服务 (端口: $p) 已重启${RESET}" \
                    || echo -e "${RED}用户服务 (端口: $p) 重启失败${RESET}"
            }
        done
    fi
}

# ═════════════════════════════════════════
# Snell 查看配置
# ═════════════════════════════════════════

_show_conf_entry() {
    local label="$1" conf="$2" inst_ver="$3"
    local port psk ipv6 dns
    port=$(grep -E '^listen' "$conf" | sed -n 's/.*::0:\([0-9]*\)/\1/p')
    psk=$(grep  -E '^psk'    "$conf" | awk -F'=' '{print $2}' | tr -d ' ')
    ipv6=$(grep -E '^ipv6'   "$conf" | awk -F'=' '{print $2}' | tr -d ' ')
    dns=$(grep  -E '^dns'    "$conf" | awk -F'=' '{print $2}' | tr -d ' ')
    echo -e "\n${GREEN}${label}：${RESET}"
    echo -e "${YELLOW}端口: ${port}  PSK: ${psk}  IPv6: ${ipv6}  DNS: ${dns}${RESET}"
    echo -e "${GREEN}Surge 配置：${RESET}"
    [ -n "$IPV4_ADDR" ] && generate_surge_config "$IPV4_ADDR" "$port" "$psk" "$inst_ver" "${IP_COUNTRY_IPV4:-Unknown}"
    [ -n "$IPV6_ADDR" ] && generate_surge_config "$IPV6_ADDR" "$port" "$psk" "$inst_ver" "${IP_COUNTRY_IPV6:-Unknown}"
}

_show_shadowtls_configs() {
    local inst_ver="$1"
    local found=0
    for svc_file in "${INITD_DIR}"/shadowtls-snell-*; do
        [ -f "$svc_file" ] || continue
        found=1
        break
    done
    [ "$found" = "0" ] && return

    echo -e "\n${YELLOW}=== ShadowTLS 组合配置 ===${RESET}"
    for svc_file in "${INITD_DIR}"/shadowtls-snell-*; do
        [ -f "$svc_file" ] || continue
        local args
        args=$(grep 'command_args' "$svc_file" | sed "s/command_args=//;s/\"//g")
        local snell_port stls_port stls_pass stls_domain
        snell_port=$(echo "$args" | grep -oE '127\.0\.0\.1:[0-9]+' | cut -d: -f2)
        stls_port=$(echo "$args" | grep -oE '::0:[0-9]+' | cut -d: -f2)
        stls_pass=$(echo "$args" | grep -oE '\-\-password [^ ]+' | awk '{print $2}')
        stls_domain=$(echo "$args" | grep -oE '\-\-tls [^ ]+' | awk '{print $2}')
        [ -z "$snell_port" ] || [ -z "$stls_port" ] && continue

        local psk=""
        if [ -f "${USERS_DIR}/snell-${snell_port}.conf" ]; then
            psk=$(grep -E '^psk' "${USERS_DIR}/snell-${snell_port}.conf" | awk -F'=' '{print $2}' | tr -d ' ')
        elif [ -f "$SNELL_CONF_FILE" ]; then
            psk=$(grep -E '^psk' "$SNELL_CONF_FILE" | awk -F'=' '{print $2}' | tr -d ' ')
        fi
        [ -z "$psk" ] && continue

        local base_stls="psk = ${psk}, reuse = true, tfo = true, shadow-tls-password = ${stls_pass}, shadow-tls-sni = ${stls_domain}, shadow-tls-version = 3"
        echo -e "\n${GREEN}ShadowTLS 配置 (Snell端口: ${snell_port})：${RESET}"
        echo -e "  ShadowTLS 监听端口: ${stls_port}  密码: ${stls_pass}  SNI: ${stls_domain}"
        if [ -n "$IPV4_ADDR" ]; then
            local c="${IP_COUNTRY_IPV4:-Unknown}"
            if [ "$inst_ver" = "v5" ]; then
                echo -e "${GREEN}${c} = snell, ${IPV4_ADDR}, ${stls_port}, ${base_stls}, version = 4${RESET}"
                echo -e "${GREEN}${c} = snell, ${IPV4_ADDR}, ${stls_port}, ${base_stls}, version = 5${RESET}"
            else
                echo -e "${GREEN}${c} = snell, ${IPV4_ADDR}, ${stls_port}, ${base_stls}, version = 4${RESET}"
            fi
        fi
        if [ -n "$IPV6_ADDR" ]; then
            local c="${IP_COUNTRY_IPV6:-Unknown}"
            if [ "$inst_ver" = "v5" ]; then
                echo -e "${GREEN}${c} = snell, ${IPV6_ADDR}, ${stls_port}, ${base_stls}, version = 4${RESET}"
                echo -e "${GREEN}${c} = snell, ${IPV6_ADDR}, ${stls_port}, ${base_stls}, version = 5${RESET}"
            else
                echo -e "${GREEN}${c} = snell, ${IPV6_ADDR}, ${stls_port}, ${base_stls}, version = 4${RESET}"
            fi
        fi
    done
}

view_snell_config() {
    echo -e "${GREEN}Snell 配置信息:${RESET}"
    echo -e "${CYAN}================================${RESET}"
    local inst_ver
    inst_ver=$(detect_installed_snell_version)
    [ "$inst_ver" != "unknown" ] && echo -e "${YELLOW}当前安装版本: Snell ${inst_ver}${RESET}"

    get_public_ip
    if [ -z "$IPV4_ADDR" ] && [ -z "$IPV6_ADDR" ]; then
        echo -e "${RED}无法获取公网 IP，请检查网络${RESET}"; return
    fi
    [ -n "$IPV4_ADDR" ] && echo -e "${GREEN}IPv4: ${RESET}${IPV4_ADDR}  国家: ${IP_COUNTRY_IPV4}"
    [ -n "$IPV6_ADDR" ] && echo -e "${GREEN}IPv6: ${RESET}${IPV6_ADDR}  国家: ${IP_COUNTRY_IPV6}"

    echo -e "\n${YELLOW}=== 用户配置列表 ===${RESET}"
    [ -f "$SNELL_CONF_FILE" ] && _show_conf_entry "主用户" "$SNELL_CONF_FILE" "$inst_ver"
    if [ -d "$USERS_DIR" ]; then
        for conf in "${USERS_DIR}"/snell-*.conf; do
            [ -f "$conf" ] || continue
            case "$conf" in *snell-main.conf) continue ;; esac
            local p
            p=$(grep -E '^listen' "$conf" | sed -n 's/.*::0:\([0-9]*\)/\1/p')
            _show_conf_entry "用户 (端口: ${p})" "$conf" "$inst_ver"
        done
    fi
    _show_shadowtls_configs "$inst_ver"
    echo -e "\n${YELLOW}注意：Snell 仅支持 Surge 客户端${RESET}"
    printf "按任意键返回主菜单..."; read -r _
}

# ═════════════════════════════════════════
# Snell 更新
# ═════════════════════════════════════════

update_snell_binary() {
    local bak
    bak=$(backup_snell_config)
    echo -e "${GREEN}配置已备份到: $bak${RESET}"
    get_latest_snell_version
    local url
    url=$(get_snell_download_url)
    echo -e "${CYAN}下载 Snell ${SNELL_VERSION_CHOICE} (${SNELL_VERSION})...${RESET}"
    wget -q "$url" -O /tmp/snell-server.zip || {
        echo -e "${RED}下载失败，恢复配置...${RESET}"; restore_snell_config "$bak"; exit 1
    }
    unzip -oq /tmp/snell-server.zip -d "$INSTALL_DIR" || {
        echo -e "${RED}解压失败，恢复配置...${RESET}"; restore_snell_config "$bak"; exit 1
    }
    rm -f /tmp/snell-server.zip
    chmod +x "${INSTALL_DIR}/snell-server"
    svc_restart "snell" || { restore_snell_config "$bak"; svc_restart "snell"; }
    if [ -d "$USERS_DIR" ]; then
        for conf in "${USERS_DIR}"/*.conf; do
            [ -f "$conf" ] || continue
            case "$conf" in *snell-main.conf) continue ;; esac
            local p
            p=$(grep -E '^listen' "$conf" | sed -n 's/.*::0:\([0-9]*\)/\1/p')
            [ -n "$p" ] && svc_restart "snell-${p}" 2>/dev/null
        done
    fi
    echo -e "${GREEN}✅ 更新完成：${SNELL_VERSION_CHOICE} (${SNELL_VERSION})${RESET}"
    echo -e "${YELLOW}备份目录: $bak${RESET}"
}

check_snell_update() {
    echo -e "\n${CYAN}====== 检查 Snell 更新 ======${RESET}"
    local inst_ver
    inst_ver=$(detect_installed_snell_version)
    if [ "$inst_ver" = "unknown" ]; then
        echo -e "${RED}Snell 未安装${RESET}"; return 1
    fi
    echo -e "${YELLOW}当前安装: Snell ${inst_ver}${RESET}"
    if [ "$inst_ver" = "v4" ]; then
        echo -e "${CYAN}是否要升级到 v5？(v5 为测试版)${RESET}"
        echo -e "${GREEN}1.${RESET} 升级到 Snell v5"
        echo -e "${GREEN}2.${RESET} 继续使用 v4（检查 v4 更新）"
        echo -e "${GREEN}3.${RESET} 取消"
        while true; do
            printf "请选择 [1-3]: "; read -r c
            case "$c" in
                1) SNELL_VERSION_CHOICE="v5"; break ;;
                2) SNELL_VERSION_CHOICE="v4"; break ;;
                3) echo -e "${CYAN}已取消${RESET}"; return 0 ;;
                *) echo -e "${RED}请输入正确选项${RESET}" ;;
            esac
        done
    else
        SNELL_VERSION_CHOICE="v5"
        echo -e "${GREEN}当前为 v5，检查 v5 更新${RESET}"
    fi
    get_latest_snell_version
    get_current_snell_version
    echo -e "${YELLOW}已安装版本: ${CURRENT_VERSION}${RESET}"
    echo -e "${YELLOW}最新版本:   ${SNELL_VERSION}${RESET}"
    if ! version_ge "$CURRENT_VERSION" "$SNELL_VERSION"; then
        printf "发现新版本，是否更新？[y/N] "; read -r c
        case "$c" in y|Y) update_snell_binary ;; *) echo -e "${CYAN}已取消${RESET}" ;; esac
    else
        echo -e "${GREEN}已是最新版本 (${CURRENT_VERSION})${RESET}"
    fi
}

# ═════════════════════════════════════════
# 脚本自更新
# ═════════════════════════════════════════

update_script() {
    echo -e "${CYAN}正在检查脚本更新...${RESET}"
    local tmp
    tmp=$(mktemp)
    if curl -sL https://raw.githubusercontent.com/pmjkkk/script/refs/heads/main/bash/snell.sh -o "$tmp"; then
        local new_ver
        new_ver=$(grep 'SCRIPT_VERSION=' "$tmp" | cut -d'"' -f2 | head -n1)
        [ -z "$new_ver" ] && { echo -e "${RED}无法获取新版本号${RESET}"; rm -f "$tmp"; return 1; }
        echo -e "${YELLOW}当前版本: ${SCRIPT_VERSION}  最新版本: ${new_ver}${RESET}"
        if [ "$new_ver" != "$SCRIPT_VERSION" ]; then
            printf "是否更新到新版本？[y/N] "; read -r c
            case "$c" in
                y|Y)
                    local self; self=$(readlink -f "$0")
                    cp "$self" "${self}.backup"
                    mv "$tmp" "$self"
                    chmod +x "$self"
                    echo -e "${GREEN}脚本已更新，备份: ${self}.backup${RESET}"
                    echo -e "${CYAN}请重新运行脚本${RESET}"; exit 0
                    ;;
                *) echo -e "${YELLOW}已取消${RESET}"; rm -f "$tmp" ;;
            esac
        else
            echo -e "${GREEN}已是最新版本${RESET}"; rm -f "$tmp"
        fi
    else
        echo -e "${RED}下载失败，请检查网络${RESET}"; rm -f "$tmp"
    fi
}

# ═════════════════════════════════════════
# 状态显示
# ═════════════════════════════════════════

check_and_show_status() {
    echo -e "\n${CYAN}====== 服务状态 ======${RESET}"
    if command -v snell-server >/dev/null 2>&1; then
        local total=0 running=0
        svc_active "snell" && running=$((running+1))
        total=$((total+1))
        if [ -d "$USERS_DIR" ]; then
            for conf in "${USERS_DIR}"/*.conf; do
                [ -f "$conf" ] || continue
                case "$conf" in *snell-main.conf) continue ;; esac
                local p
                p=$(grep -E '^listen' "$conf" | sed -n 's/.*::0:\([0-9]*\)/\1/p')
                [ -z "$p" ] && continue
                total=$((total+1))
                svc_active "snell-${p}" && running=$((running+1))
            done
        fi
        echo -e "${GREEN}Snell 已安装  运行中: ${running}/${total}${RESET}"
    else
        echo -e "${YELLOW}Snell 未安装${RESET}"
    fi

    if [ -f "${INSTALL_DIR}/shadow-tls" ]; then
        local stotal=0 srunning=0
        for svc_file in "${INITD_DIR}"/shadowtls-snell-*; do
            [ -f "$svc_file" ] || continue
            stotal=$((stotal+1))
            svc_active "$(basename "$svc_file")" && srunning=$((srunning+1))
        done
        if [ "$stotal" -gt 0 ]; then
            echo -e "${GREEN}ShadowTLS 已安装  运行中: ${srunning}/${stotal}${RESET}"
        else
            echo -e "${YELLOW}ShadowTLS 未安装${RESET}"
        fi
    else
        echo -e "${YELLOW}ShadowTLS 未安装${RESET}"
    fi
    echo -e "${CYAN}======================${RESET}\n"
}

# ═════════════════════════════════════════
# ███ ShadowTLS 管理模块 ███
# ═════════════════════════════════════════

_stls_get_latest_version() {
    local ver
    ver=$(curl -fsSL --max-time 10 \
        "https://api.github.com/repos/ihciah/shadow-tls/releases/latest" 2>/dev/null \
        | grep '"tag_name"' | cut -d'"' -f4)
    if [ -z "$ver" ] || [ "$ver" = "null" ]; then
        ver=$(curl -fsSL --max-time 10 -o /dev/null -w '%{url_effective}' \
            "https://github.com/ihciah/shadow-tls/releases/latest" 2>/dev/null \
            | sed -E 's#.*/tag/##')
    fi
    if [ -z "$ver" ] || [ "$ver" = "null" ]; then
        echo -e "${RED}获取 ShadowTLS 最新版本失败${RESET}" >&2; return 1
    fi
    echo "$ver"
}

_stls_check_port_used() {
    local port="$1"
    for svc_file in "${INITD_DIR}"/shadowtls-snell-*; do
        [ -f "$svc_file" ] || continue
        local p
        p=$(grep 'command_args' "$svc_file" | grep -oE '::0:[0-9]+' | cut -d: -f2)
        [ "$p" = "$port" ] && return 0
    done
    return 1
}

_stls_get_available_port() {
    local port="$1"
    if [ -n "$port" ]; then
        if _stls_check_port_used "$port"; then
            echo -e "${RED}端口 ${port} 已被其他 ShadowTLS 服务使用${RESET}" >&2; return 1
        fi
        echo "$port"; return 0
    fi
    local attempts=0
    while [ "$attempts" -lt 10 ]; do
        local rp
        rp=$(awk 'BEGIN{srand(); print int(rand()*55535)+10000}')
        if ! _stls_check_port_used "$rp"; then
            echo "$rp"; return 0
        fi
        attempts=$((attempts+1))
    done
    echo -e "${RED}无法找到可用端口${RESET}" >&2; return 1
}

install_shadowtls() {
    echo -e "${CYAN}正在安装 ShadowTLS...${RESET}"

    if ! command -v snell-server >/dev/null 2>&1; then
        echo -e "${RED}未检测到 Snell，请先安装 Snell${RESET}"; return 1
    fi
    echo -e "${GREEN}检测到已安装 Snell${RESET}"

    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64)  arch="x86_64-unknown-linux-musl" ;;
        aarch64) arch="aarch64-unknown-linux-musl" ;;
        *) echo -e "${RED}不支持的架构: $arch${RESET}"; return 1 ;;
    esac

    local version
    version=$(_stls_get_latest_version) || return 1

    local dl_url="https://github.com/ihciah/shadow-tls/releases/download/${version}/shadow-tls-${arch}"
    echo -e "${CYAN}下载 ShadowTLS ${version}...${RESET}"
    wget -q "$dl_url" -O /tmp/shadow-tls.tmp || { echo -e "${RED}下载失败${RESET}"; return 1; }
    mv /tmp/shadow-tls.tmp "${INSTALL_DIR}/shadow-tls"
    chmod +x "${INSTALL_DIR}/shadow-tls"

    local password tls_domain
    password=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)
    printf "请输入 TLS 伪装域名 (留空默认 www.microsoft.com): "; read -r tls_domain
    tls_domain="${tls_domain:-www.microsoft.com}"

    # 获取所有 Snell 用户
    local user_configs
    user_configs=$(get_all_snell_users)
    if [ -z "$user_configs" ]; then
        echo -e "${RED}未找到有效的 Snell 用户配置${RESET}"; return 1
    fi

    echo -e "\n${YELLOW}当前的 Snell 端口列表：${RESET}"
    local port_list="" idx=0
    while IFS='|' read -r port psk; do
        [ -z "$port" ] && continue
        idx=$((idx+1))
        port_list="${port_list}${port} "
        local label=""
        [ "$port" = "$(get_snell_main_port)" ] && label=" (主用户)"
        echo -e "${GREEN}${idx}.${RESET} ${port}${label}"
    done <<< "$user_configs"

    echo -e "\n${YELLOW}请选择要配置的端口（0=全部）：${RESET}"
    printf "请选择: "; read -r port_choice

    local selected_ports=""
    if [ "$port_choice" = "0" ]; then
        selected_ports="$port_list"
    else
        local n=0
        for p in $port_list; do
            n=$((n+1))
            [ "$n" = "$port_choice" ] && { selected_ports="$p"; break; }
        done
        if [ -z "$selected_ports" ]; then
            echo -e "${RED}无效的选择${RESET}"; return 1
        fi
    fi

    local server_ip
    server_ip=$(get_server_ip) || return 1

    for snell_port in $selected_ports; do
        snell_port=$(echo "$snell_port" | tr -d ' ')
        [ -z "$snell_port" ] && continue
        echo -e "\n${YELLOW}为 Snell 端口 ${snell_port} 配置 ShadowTLS${RESET}"
        printf "请输入 ShadowTLS 监听端口 (留空随机生成): "; read -r stls_port_input
        local stls_port
        stls_port=$(_stls_get_available_port "$stls_port_input") || { echo -e "${YELLOW}跳过端口 ${snell_port}${RESET}"; continue; }
        echo -e "${GREEN}将使用端口: ${stls_port}${RESET}"

        local svc_name="shadowtls-snell-${snell_port}"
        _write_initd_shadowtls "$svc_name" "$stls_port" "$snell_port" "$tls_domain" "$password"
        svc_enable "$svc_name"
        svc_start  "$svc_name"

        # 显示 Surge 配置
        local psk=""
        if [ -f "${USERS_DIR}/snell-${snell_port}.conf" ]; then
            psk=$(grep -E '^psk' "${USERS_DIR}/snell-${snell_port}.conf" | awk -F'=' '{print $2}' | tr -d ' ')
        else
            psk=$(grep -E '^psk' "$SNELL_CONF_FILE" | awk -F'=' '{print $2}' | tr -d ' ')
        fi
        local snell_ver; snell_ver=$(get_snell_version_num)
        local base_stls="psk = ${psk}, reuse = true, tfo = true, shadow-tls-password = ${password}, shadow-tls-sni = ${tls_domain}, shadow-tls-version = 3"
        echo -e "\n${GREEN}Surge 配置：${RESET}"
        if [ "$snell_ver" = "5" ]; then
            echo -e "${GREEN}Snell v4+STLS = snell, ${server_ip}, ${stls_port}, ${base_stls}, version = 4${RESET}"
            echo -e "${GREEN}Snell v5+STLS = snell, ${server_ip}, ${stls_port}, ${base_stls}, version = 5${RESET}"
        else
            echo -e "${GREEN}Snell+STLS = snell, ${server_ip}, ${stls_port}, ${base_stls}, version = 4${RESET}"
        fi
    done

    echo -e "\n${GREEN}ShadowTLS 安装完成，服务已启动并设置开机自启${RESET}"
}

uninstall_shadowtls() {
    echo -e "${CYAN}正在卸载 ShadowTLS...${RESET}"
    for svc_file in "${INITD_DIR}"/shadowtls-snell-*; do
        [ -f "$svc_file" ] || continue
        _remove_service "$(basename "$svc_file")"
    done
    rm -f "${INSTALL_DIR}/shadow-tls"
    echo -e "${GREEN}ShadowTLS 已成功卸载${RESET}"
}

view_shadowtls_config() {
    local found=0
    for svc_file in "${INITD_DIR}"/shadowtls-snell-*; do
        [ -f "$svc_file" ] && found=1 && break
    done
    if [ "$found" = "0" ]; then
        echo -e "${RED}ShadowTLS 未安装${RESET}"; return 1
    fi
    local server_ip; server_ip=$(get_server_ip) || return 1
    local snell_ver; snell_ver=$(get_snell_version_num)
    echo -e "\n${YELLOW}=== Snell + ShadowTLS 配置 ===${RESET}"
    for svc_file in "${INITD_DIR}"/shadowtls-snell-*; do
        [ -f "$svc_file" ] || continue
        local args
        args=$(grep 'command_args' "$svc_file" | sed "s/command_args=//;s/\"//g")
        local snell_port stls_port stls_pass stls_domain
        snell_port=$(echo "$args" | grep -oE '127\.0\.0\.1:[0-9]+' | cut -d: -f2)
        stls_port=$(echo "$args" | grep -oE '::0:[0-9]+' | cut -d: -f2)
        stls_pass=$(echo "$args" | grep -oE '\-\-password [^ ]+' | awk '{print $2}')
        stls_domain=$(echo "$args" | grep -oE '\-\-tls [^ ]+' | awk '{print $2}')
        [ -z "$snell_port" ] && continue

        local psk=""
        if [ -f "${USERS_DIR}/snell-${snell_port}.conf" ]; then
            psk=$(grep -E '^psk' "${USERS_DIR}/snell-${snell_port}.conf" | awk -F'=' '{print $2}' | tr -d ' ')
        elif [ -f "$SNELL_CONF_FILE" ]; then
            psk=$(grep -E '^psk' "$SNELL_CONF_FILE" | awk -F'=' '{print $2}' | tr -d ' ')
        fi

        local label="用户 (Snell 端口: ${snell_port})"
        [ "$snell_port" = "$(get_snell_main_port)" ] && label="主用户"
        echo -e "\n${GREEN}${label}：${RESET}"
        echo -e "  Snell 端口: ${snell_port}  PSK: ${psk}"
        echo -e "  ShadowTLS 监听端口: ${stls_port}  密码: ${stls_pass}  SNI: ${stls_domain}"

        local base_stls="psk = ${psk}, reuse = true, tfo = true, shadow-tls-password = ${stls_pass}, shadow-tls-sni = ${stls_domain}, shadow-tls-version = 3"
        echo -e "${GREEN}Surge 配置：${RESET}"
        if [ "$snell_ver" = "5" ]; then
            echo -e "${GREEN}Snell v4+STLS = snell, ${server_ip}, ${stls_port}, ${base_stls}, version = 4${RESET}"
            echo -e "${GREEN}Snell v5+STLS = snell, ${server_ip}, ${stls_port}, ${base_stls}, version = 5${RESET}"
        else
            echo -e "${GREEN}Snell+STLS = snell, ${server_ip}, ${stls_port}, ${base_stls}, version = 4${RESET}"
        fi

        local status="未运行"
        svc_active "shadowtls-snell-${snell_port}" && status="${GREEN}运行中${RESET}" || status="${RED}未运行${RESET}"
        echo -e "  服务状态: ${status}"
    done
}

add_shadowtls_config() {
    echo -e "${CYAN}新增 ShadowTLS 配置...${RESET}"
    if ! command -v snell-server >/dev/null 2>&1; then
        echo -e "${RED}未检测到 Snell${RESET}"; return 1
    fi

    local user_configs
    user_configs=$(get_all_snell_users)
    if [ -z "$user_configs" ]; then
        echo -e "${RED}未找到有效的 Snell 用户配置${RESET}"; return 1
    fi

    echo -e "\n${YELLOW}未配置 ShadowTLS 的 Snell 端口：${RESET}"
    local port_list="" idx=0
    while IFS='|' read -r port psk; do
        [ -z "$port" ] && continue
        if [ ! -f "${INITD_DIR}/shadowtls-snell-${port}" ]; then
            idx=$((idx+1))
            port_list="${port_list}${port} "
            local label=""
            [ "$port" = "$(get_snell_main_port)" ] && label=" (主用户)"
            echo -e "${GREEN}${idx}.${RESET} ${port}${label}"
        fi
    done <<< "$user_configs"

    if [ -z "$port_list" ]; then
        echo -e "${YELLOW}所有 Snell 端口都已配置 ShadowTLS${RESET}"; return 0
    fi

    local password tls_domain
    password=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)
    printf "请输入 TLS 伪装域名 (留空默认 www.microsoft.com): "; read -r tls_domain
    tls_domain="${tls_domain:-www.microsoft.com}"

    printf "请选择要配置的端口（0=全部）: "; read -r port_choice

    local selected_ports=""
    if [ "$port_choice" = "0" ]; then
        selected_ports="$port_list"
    else
        local n=0
        for p in $port_list; do
            n=$((n+1))
            [ "$n" = "$port_choice" ] && { selected_ports="$p"; break; }
        done
        [ -z "$selected_ports" ] && { echo -e "${RED}无效的选择${RESET}"; return 1; }
    fi

    local server_ip; server_ip=$(get_server_ip) || return 1

    for snell_port in $selected_ports; do
        snell_port=$(echo "$snell_port" | tr -d ' ')
        [ -z "$snell_port" ] && continue
        printf "请输入 Snell端口 ${snell_port} 的 ShadowTLS 监听端口 (留空随机): "; read -r stls_port_input
        local stls_port
        stls_port=$(_stls_get_available_port "$stls_port_input") || continue

        local svc_name="shadowtls-snell-${snell_port}"
        _write_initd_shadowtls "$svc_name" "$stls_port" "$snell_port" "$tls_domain" "$password"
        svc_enable "$svc_name"; svc_start "$svc_name"

        local psk=""
        if [ -f "${USERS_DIR}/snell-${snell_port}.conf" ]; then
            psk=$(grep -E '^psk' "${USERS_DIR}/snell-${snell_port}.conf" | awk -F'=' '{print $2}' | tr -d ' ')
        else
            psk=$(grep -E '^psk' "$SNELL_CONF_FILE" | awk -F'=' '{print $2}' | tr -d ' ')
        fi
        local snell_ver; snell_ver=$(get_snell_version_num)
        local base_stls="psk = ${psk}, reuse = true, tfo = true, shadow-tls-password = ${password}, shadow-tls-sni = ${tls_domain}, shadow-tls-version = 3"
        echo -e "${GREEN}Surge 配置：${RESET}"
        if [ "$snell_ver" = "5" ]; then
            echo -e "${GREEN}Snell v4+STLS = snell, ${server_ip}, ${stls_port}, ${base_stls}, version = 4${RESET}"
            echo -e "${GREEN}Snell v5+STLS = snell, ${server_ip}, ${stls_port}, ${base_stls}, version = 5${RESET}"
        else
            echo -e "${GREEN}Snell+STLS = snell, ${server_ip}, ${stls_port}, ${base_stls}, version = 4${RESET}"
        fi
    done
    echo -e "\n${GREEN}新增配置完成${RESET}"
}

restart_shadowtls() {
    echo -e "${CYAN}重启 ShadowTLS 服务...${RESET}"
    local found=0
    for svc_file in "${INITD_DIR}"/shadowtls-snell-*; do
        [ -f "$svc_file" ] || continue
        found=1
        local svc; svc=$(basename "$svc_file")
        svc_restart "$svc" \
            && echo -e "${GREEN}${svc} 重启成功${RESET}" \
            || echo -e "${RED}${svc} 重启失败${RESET}"
    done
    [ "$found" = "0" ] && echo -e "${RED}未找到任何 ShadowTLS 服务${RESET}"
}

setup_shadowtls() {
    while true; do
        echo -e "\n${CYAN}====== ShadowTLS 管理 ======${RESET}"
        echo -e "${GREEN}1.${RESET} 安装 ShadowTLS"
        echo -e "${GREEN}2.${RESET} 卸载 ShadowTLS"
        echo -e "${GREEN}3.${RESET} 查看配置"
        echo -e "${GREEN}4.${RESET} 新增配置"
        echo -e "${GREEN}5.${RESET} 重启服务"
        echo -e "${GREEN}0.${RESET} 返回主菜单"
        printf "请选择 [0-5]: "; read -r c
        case "$c" in
            1) install_shadowtls ;;
            2) uninstall_shadowtls ;;
            3) view_shadowtls_config ;;
            4) add_shadowtls_config ;;
            5) restart_shadowtls ;;
            0) return ;;
            *) echo -e "${RED}无效选项${RESET}" ;;
        esac
        printf "\n按任意键继续..."; read -r _
    done
}

# ═════════════════════════════════════════
# ███ BBR 管理模块 ███
# ═════════════════════════════════════════

_bbr_configure_sysctl() {
    echo -e "${YELLOW}配置系统参数和 BBR...${RESET}"
    cat > /etc/sysctl.conf <<EOF
fs.file-max = 6815744
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_ecn = 0
net.ipv4.tcp_frto = 0
net.ipv4.tcp_mtu_probing = 0
net.ipv4.tcp_rfc1337 = 0
net.ipv4.tcp_sack = 1
net.ipv4.tcp_fack = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_adv_win_scale = 1
net.ipv4.tcp_moderate_rcvbuf = 1
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.ipv4.tcp_rmem = 4096 87380 33554432
net.ipv4.tcp_wmem = 4096 16384 33554432
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192
net.ipv4.ip_forward = 1
net.ipv4.conf.all.route_localnet = 1
net.ipv4.conf.all.forwarding = 1
net.ipv4.conf.default.forwarding = 1
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1
EOF
    sysctl -p
    if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q bbr; then
        echo -e "${GREEN}BBR 已成功配置${RESET}"
    else
        echo -e "${YELLOW}BBR 配置可能需要重启后生效${RESET}"
    fi
}

enable_bbr() {
    echo -e "${YELLOW}正在启用标准 BBR...${RESET}"
    if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q bbr; then
        echo -e "${GREEN}BBR 已经启用${RESET}"; return 0
    fi
    _bbr_configure_sysctl
}

# Alpine 使用 apk 安装内核（XanMod 仅适用于 Debian/Ubuntu，提示用户）
install_xanmod_bbr() {
    echo -e "${RED}XanMod 内核仅支持 Debian/Ubuntu，Alpine 不适用${RESET}"
    echo -e "${YELLOW}Alpine 建议直接使用标准 BBR（选项1），或手动编译内核${RESET}"
}

install_bbr3_manual() {
    echo -e "${YELLOW}准备手动编译安装 BBR v3...${RESET}"
    echo -e "${YELLOW}正在安装编译依赖...${RESET}"
    apk add --no-cache build-base git linux-headers || { echo -e "${RED}依赖安装失败${RESET}"; return 1; }
    git clone -b v3 https://github.com/google/bbr.git /tmp/bbr-src || { echo -e "${RED}克隆失败${RESET}"; return 1; }
    cd /tmp/bbr-src && make && make install
    _bbr_configure_sysctl
    echo -e "${GREEN}BBR v3 编译安装完成${RESET}"
    printf "是否现在重启系统？[y/N] "; read -r c
    case "$c" in y|Y) reboot ;; esac
}

setup_bbr() {
    while true; do
        echo -e "\n${CYAN}====== BBR 管理 ======${RESET}"
        echo -e "${GREEN}1.${RESET} 启用标准 BBR"
        echo -e "${GREEN}2.${RESET} 安装 BBR v3（手动编译）"
        echo -e "${GREEN}0.${RESET} 返回主菜单"
        printf "请选择 [0-2]: "; read -r c
        case "$c" in
            1) enable_bbr ;;
            2) install_bbr3_manual ;;
            0) return ;;
            *) echo -e "${RED}无效选项${RESET}" ;;
        esac
        printf "\n按任意键继续..."; read -r _
    done
}

# ═════════════════════════════════════════
# ███ 多用户管理模块 ███
# ═════════════════════════════════════════

mu_list_users() {
    echo -e "\n${YELLOW}=== 当前用户列表 ===${RESET}"
    if [ ! -d "$USERS_DIR" ]; then
        echo -e "${YELLOW}当前没有配置的用户${RESET}"; return
    fi
    local count=0
    for conf in "${USERS_DIR}"/snell-*.conf; do
        [ -f "$conf" ] || continue
        count=$((count+1))
        local port psk label=""
        port=$(grep -E '^listen' "$conf" | sed -n 's/.*::0:\([0-9]*\)/\1/p')
        psk=$(grep  -E '^psk'    "$conf" | awk -F'=' '{print $2}' | tr -d ' ')
        case "$conf" in *snell-main.conf) label=" (主用户)" ;; esac
        echo -e "${GREEN}用户 ${count}${label}：${RESET} 端口: ${port}  PSK: ${psk}"
    done
    [ "$count" -eq 0 ] && echo -e "${YELLOW}当前没有配置的用户${RESET}"
}

mu_add_user() {
    echo -e "\n${YELLOW}=== 添加新用户 ===${RESET}"
    mkdir -p "$USERS_DIR"

    local PORT
    while true; do
        printf "请输入新用户端口号 (1-65535): "; read -r PORT
        case "$PORT" in
            ''|*[!0-9]*) echo -e "${RED}无效端口号${RESET}"; continue ;;
        esac
        [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ] || { echo -e "${RED}端口超出范围${RESET}"; continue; }
        if check_port_in_use "$PORT"; then
            echo -e "${RED}端口 $PORT 已被使用${RESET}"; continue
        fi
        break
    done

    local PSK DNS
    PSK=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20)
    get_dns

    local user_conf="${USERS_DIR}/snell-${PORT}.conf"
    cat > "$user_conf" <<EOF
[snell-server]
listen = ::0:${PORT}
psk = ${PSK}
ipv6 = true
dns = ${DNS}
EOF

    local svc_name="snell-${PORT}"
    _write_initd_snell "$svc_name" "$user_conf"
    svc_enable "$svc_name"
    svc_start  "$svc_name"
    open_port  "$PORT"

    echo -e "\n${GREEN}用户添加成功！${RESET}"
    echo -e "${YELLOW}端口: ${PORT}  PSK: ${PSK}${RESET}"
}

mu_delete_user() {
    echo -e "\n${YELLOW}=== 删除用户 ===${RESET}"
    mu_list_users
    printf "请输入要删除的用户端口号: "; read -r del_port

    local user_conf="${USERS_DIR}/snell-${del_port}.conf"
    if [ ! -f "$user_conf" ]; then
        echo -e "${RED}未找到端口 ${del_port} 的用户${RESET}"; return
    fi
    _remove_service "snell-${del_port}"
    rm -f "$user_conf"
    echo -e "${GREEN}用户已成功删除${RESET}"
}

mu_modify_user() {
    echo -e "\n${YELLOW}=== 修改用户配置 ===${RESET}"
    mu_list_users
    printf "请输入要修改的用户端口号: "; read -r mod_port

    local user_conf="${USERS_DIR}/snell-${mod_port}.conf"
    if [ ! -f "$user_conf" ]; then
        echo -e "${RED}未找到端口 ${mod_port} 的用户${RESET}"; return
    fi

    local svc_name="snell-${mod_port}"
    echo -e "${GREEN}1.${RESET} 修改端口  ${GREEN}2.${RESET} 重置 PSK  ${GREEN}3.${RESET} 修改 DNS  ${GREEN}0.${RESET} 返回"
    printf "请输入选项 [0-3]: "; read -r mod_choice
    case "$mod_choice" in
        1)
            local new_port
            while true; do
                printf "请输入新端口号 (1-65535): "; read -r new_port
                case "$new_port" in ''|*[!0-9]*) echo -e "${RED}无效端口号${RESET}"; continue ;; esac
                [ "$new_port" -ge 1 ] && [ "$new_port" -le 65535 ] || { echo -e "${RED}端口超出范围${RESET}"; continue; }
                check_port_in_use "$new_port" && { echo -e "${RED}端口已被使用${RESET}"; continue; }
                break
            done
            svc_stop "$svc_name" 2>/dev/null
            sed -i "s/listen = ::0:${mod_port}/listen = ::0:${new_port}/" "$user_conf"
            mv "$user_conf" "${USERS_DIR}/snell-${new_port}.conf"
            _remove_service "$svc_name"
            local new_svc="snell-${new_port}"
            _write_initd_snell "$new_svc" "${USERS_DIR}/snell-${new_port}.conf"
            svc_enable "$new_svc"; svc_start "$new_svc"
            open_port "$new_port"
            echo -e "${GREEN}端口修改成功${RESET}"
            ;;
        2)
            local new_psk
            new_psk=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20)
            sed -i "s/^psk = .*/psk = ${new_psk}/" "$user_conf"
            svc_restart "$svc_name"
            echo -e "${GREEN}PSK 已重置为: ${new_psk}${RESET}"
            ;;
        3)
            get_dns
            sed -i "s/^dns = .*/dns = ${DNS}/" "$user_conf"
            svc_restart "$svc_name"
            echo -e "${GREEN}DNS 修改成功${RESET}"
            ;;
        0) return ;;
        *) echo -e "${RED}无效选项${RESET}" ;;
    esac
}

mu_show_user_config() {
    echo -e "\n${YELLOW}=== 用户配置信息 ===${RESET}"
    mu_list_users
    printf "请输入要查看的用户端口号: "; read -r view_port

    local user_conf="${USERS_DIR}/snell-${view_port}.conf"
    if [ ! -f "$user_conf" ]; then
        echo -e "${RED}未找到端口 ${view_port} 的用户${RESET}"; return
    fi

    local port psk dns
    port=$(grep -E '^listen' "$user_conf" | sed -n 's/.*::0:\([0-9]*\)/\1/p')
    psk=$(grep  -E '^psk'    "$user_conf" | awk -F'=' '{print $2}' | tr -d ' ')
    dns=$(grep  -E '^dns'    "$user_conf" | awk -F'=' '{print $2}' | tr -d ' ')

    echo -e "\n${GREEN}用户配置详情：${RESET}"
    echo -e "${YELLOW}端口: ${port}  PSK: ${psk}  DNS: ${dns}${RESET}"

    get_public_ip
    local inst_ver; inst_ver=$(detect_installed_snell_version)
    echo -e "\n${GREEN}Surge 配置：${RESET}"
    [ -n "$IPV4_ADDR" ] && generate_surge_config "$IPV4_ADDR" "$port" "$psk" "$inst_ver" "${IP_COUNTRY_IPV4:-Unknown}"
    [ -n "$IPV6_ADDR" ] && generate_surge_config "$IPV6_ADDR" "$port" "$psk" "$inst_ver" "${IP_COUNTRY_IPV6:-Unknown}"
}

setup_multi_user() {
    if ! command -v snell-server >/dev/null 2>&1; then
        echo -e "${RED}未检测到 Snell 安装，请先安装 Snell${RESET}"; return
    fi
    while true; do
        echo -e "\n${CYAN}====== 多用户管理 ======${RESET}"
        echo -e "${GREEN}1.${RESET} 查看所有用户"
        echo -e "${GREEN}2.${RESET} 添加新用户"
        echo -e "${GREEN}3.${RESET} 删除用户"
        echo -e "${GREEN}4.${RESET} 修改用户配置"
        echo -e "${GREEN}5.${RESET} 查看用户详细配置"
        echo -e "${GREEN}0.${RESET} 返回主菜单"
        printf "请输入选项 [0-5]: "; read -r choice
        case "$choice" in
            1) mu_list_users ;;
            2) mu_add_user ;;
            3) mu_delete_user ;;
            4) mu_modify_user ;;
            5) mu_show_user_config ;;
            0) return ;;
            *) echo -e "${RED}请输入正确的选项 [0-5]${RESET}" ;;
        esac
        printf "\n按任意键继续..."; read -r _
    done
}

# ═════════════════════════════════════════
# 主菜单
# ═════════════════════════════════════════

show_menu() {
    clear
    echo -e "${CYAN}============================================${RESET}"
    echo -e "${CYAN}       Snell 管理脚本 v${SCRIPT_VERSION} (Alpine)${RESET}"
    echo -e "${CYAN}============================================${RESET}"
    echo -e "${GREEN}作者: pmj${RESET}"
    echo -e "${CYAN}============================================${RESET}"
    check_and_show_status
    echo -e "${YELLOW}=== 基础功能 ===${RESET}"
    echo -e "${GREEN}1.${RESET} 安装 Snell"
    echo -e "${GREEN}2.${RESET} 卸载 Snell"
    echo -e "${GREEN}3.${RESET} 查看配置"
    echo -e "${GREEN}4.${RESET} 重启服务"
    echo -e "\n${YELLOW}=== 增强功能 ===${RESET}"
    echo -e "${GREEN}5.${RESET} ShadowTLS 管理"
    echo -e "${GREEN}6.${RESET} BBR 管理"
    echo -e "${GREEN}7.${RESET} 多用户管理"
    echo -e "\n${YELLOW}=== 系统功能 ===${RESET}"
    echo -e "${GREEN}8.${RESET} 更新 Snell"
    echo -e "${GREEN}9.${RESET} 更新脚本"
    echo -e "${GREEN}10.${RESET} 查看服务状态"
    echo -e "${GREEN}0.${RESET} 退出"
    echo -e "${CYAN}============================================${RESET}"
    printf "请输入选项 [0-10]: "
    read -r num
}

# ═════════════════════════════════════════
# 入口
# ═════════════════════════════════════════

check_alpine
check_root
require_pkg curl

while true; do
    show_menu
    case "$num" in
        1)  install_snell ;;
        2)  uninstall_snell ;;
        3)  view_snell_config ;;
        4)  restart_snell ;;
        5)  setup_shadowtls ;;
        6)  setup_bbr ;;
        7)  setup_multi_user ;;
        8)  check_snell_update ;;
        9)  update_script ;;
        10) check_and_show_status; printf "按任意键继续..."; read -r _ ;;
        0)  echo -e "${GREEN}感谢使用，再见！${RESET}"; exit 0 ;;
        *)  echo -e "${RED}请输入正确的选项 [0-10]${RESET}" ;;
    esac
    printf "\n${CYAN}按任意键返回主菜单...${RESET}"
    read -r _
done
