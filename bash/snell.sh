#!/bin/sh
#=============================================================================
# Snell 管理工具 — Alpine Linux 专用
#=============================================================================
VERSION="v5.0.1"
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[0;33m'
CYAN='\033[0;36m'; RESET='\033[0m'

#=============================================================================
# 工具函数
#=============================================================================
die()  { echo -e "${RED}$1${RESET}"; exit 1; }
ok()   { echo -e "${GREEN}$1${RESET}"; }
warn() { echo -e "${YELLOW}$1${RESET}"; }
info() { echo -e "${CYAN}$1${RESET}"; }

confirm() {
    # $1: 提示文字, $2: 超时秒数 (0=不超时)
    local prompt="$1" timeout="${2:-0}" ans
    read -p "" ans
    [ "$ans" = "y" ] || [ "$ans" = "Y" ]
}

#=============================================================================
# 系统检查
#=============================================================================
check_alpine() {
    [ -f /etc/alpine-release ] || die "此脚本仅支持 Alpine Linux。当前系统非 Alpine，退出。"
}

check_root() {
    [ "$(id -u)" = "0" ] || die "请以 root 权限运行此脚本。"
}

#=============================================================================
# 依赖管理 — 惰性安装，已装则跳过
#=============================================================================
REQUIRED_PKGS="wget unzip curl gcompat upx"

ensure_packages() {
    local missing=""
    for pkg in $REQUIRED_PKGS; do
        apk info -e "$pkg" > /dev/null 2>&1 || missing="$missing $pkg"
    done
    [ -z "$missing" ] && return 0
    echo -e "${GREEN}安装必要软件包:${missing}${RESET}"
    apk update && apk add $missing || die "安装软件包失败"
}

#=============================================================================
# Snell 状态查询
#=============================================================================
is_installed() { [ -f /usr/local/bin/snell-server ]; }

is_running() {
    [ -f /etc/init.d/snell ] || return 1
    rc-service snell status > /dev/null 2>&1
}

get_version() {
    local out
    out=$(/usr/local/bin/snell-server -version 2>&1) || { echo "未知"; return; }
    echo "$out" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' || echo "未知"
}

#=============================================================================
# 下载 & 解压（安装/更新共用）
#=============================================================================
snell_download_url() {
    local arch
    arch=$(uname -m)
    if [ "$arch" = "aarch64" ]; then
        echo "https://dl.nssurge.com/snell/snell-server-${VERSION}-linux-aarch64.zip"
    else
        echo "https://dl.nssurge.com/snell/snell-server-${VERSION}-linux-amd64.zip"
    fi
}

download_and_extract() {
    local url zip="snell-server.zip"
    url=$(snell_download_url)
    wget "${url}" -O "$zip" || die "下载 Snell 失败，请检查网络。"
    unzip -o "$zip" -d /usr/local/bin || die "解压缩 Snell 失败。"
    rm -f "$zip"
    chmod +x /usr/local/bin/snell-server
    upx -d /usr/local/bin/snell-server 2>/dev/null || true
}

#=============================================================================
# 随机密钥 & 端口
#=============================================================================
gen_port() { awk 'BEGIN{srand();print int(rand()*35000)+30000}'; }
gen_psk()  { tr -dc A-Za-z0-9 </dev/urandom | head -c 20; }

#=============================================================================
# 公网 IP 检测
#=============================================================================
fetch_public_ip() {
    HOST_IP=$(curl -s --connect-timeout 5 --max-time 10 http://checkip.amazonaws.com)
    if [ -z "$HOST_IP" ]; then
        HOST_IP="未知"
        IP_COUNTRY="未知"
    else
        IP_COUNTRY=$(curl -s --connect-timeout 5 --max-time 10 http://ipinfo.io/${HOST_IP}/country)
        [ -z "$IP_COUNTRY" ] && IP_COUNTRY="未知"
    fi
}

#=============================================================================
# 写入配置文件
#=============================================================================
write_snell_conf() {
    # $1: 端口, $2: PSK
    mkdir -p /etc/snell
    cat > /etc/snell/snell-server.conf << EOF
[snell-server]
listen = ::0:${1}
psk = ${2}
ipv6 = true
EOF
}

write_config_txt() {
    # $1: 端口, $2: PSK
    fetch_public_ip
    cat > /etc/snell/config.txt << EOF
${IP_COUNTRY} = snell, ${HOST_IP}, ${1}, psk = ${2}, version = 5, reuse = true
EOF
    cat /etc/snell/config.txt
}

#=============================================================================
# OpenRC init 脚本
#=============================================================================
write_init_script() {
    cat > /etc/init.d/snell << 'INITEOF'
#!/sbin/openrc-run

name="snell"
description="Snell Proxy Service"
command="/usr/local/bin/snell-server"
command_args="-c /etc/snell/snell-server.conf"
command_user="snell"
supervisor="supervise-daemon"
INITEOF
    chmod +x /etc/init.d/snell
}

#=============================================================================
# 等待服务就绪（轮询替代 sleep）
#=============================================================================
wait_for_service() {
    local max_wait=10 waited=0
    while [ $waited -lt $max_wait ]; do
        if is_running; then return 0; fi
        sleep 1
        waited=$((waited + 1))
    done
    return 1
}

#=============================================================================
# 1. 安装
#=============================================================================
install_snell() {
    if [ -f /usr/local/bin/snell-server ]; then
        warn "Snell 已安装，重新安装将覆盖现有配置。"
        echo -e "${YELLOW}确认继续？(y/n)${RESET}"
        confirm || { ok "已取消安装"; return; }
    fi

    ok "正在安装 Snell ${VERSION}..."
    ensure_packages
    download_and_extract

    local port psk
    port=$(gen_port)
    psk=$(gen_psk)

    if ! id "snell" > /dev/null 2>&1; then
        adduser -D -s /sbin/nologin snell
    fi

    write_snell_conf "$port" "$psk"
    write_init_script

    rc-update add snell default
    rc-service snell start

    ok "Snell 安装成功，等待服务就绪..."
    if wait_for_service; then
        ok "Snell 已启动"
    else
        warn "Snell 启动超时，请手动检查: rc-service snell status"
    fi

    write_config_txt "$port" "$psk"
}

#=============================================================================
# 2. 配置
#=============================================================================
configure_snell() {
    [ -f "/etc/snell/snell-server.conf" ] || { warn "Snell 配置文件不存在，请先安装"; return; }

    info "当前配置:"
    echo "----------------------------------------"
    cat /etc/snell/snell-server.conf
    echo "----------------------------------------"
    echo ""

    echo -e "${YELLOW}是否要修改配置？(y/n)${RESET}"
    confirm || return

    local cur_port cur_psk new_port new_psk
    cur_port=$(grep 'listen' /etc/snell/snell-server.conf | sed 's/.*://')
    cur_psk=$(grep 'psk' /etc/snell/snell-server.conf | sed 's/.*= //')

    echo -e "${YELLOW}请输入新的监听端口 (当前: ${cur_port}):${RESET}"
    read -p "" new_port
    echo -e "${YELLOW}请输入新的 PSK (当前: ${cur_psk}):${RESET}"
    read -p "" new_psk

    [ -z "$new_port" ] || [ -z "$new_psk" ] && { warn "端口和 PSK 不能为空，操作取消"; return; }

    case "$new_port" in
        ''|*[!0-9]*) warn "端口必须为纯数字，操作取消"; return ;;
    esac
    [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ] && { warn "端口范围 1-65535，操作取消"; return; }

    write_snell_conf "$new_port" "$new_psk"
    ok "配置已更新，重启 Snell..."
    rc-service snell restart

    if wait_for_service; then
        ok "新配置已生效"
    else
        warn "重启超时，请手动检查"
    fi

    write_config_txt "$new_port" "$new_psk"
}

#=============================================================================
# 3. 更新
#=============================================================================
update_snell() {
    is_installed || { warn "Snell 未安装，跳过更新"; return; }

    local old_ver
    old_ver=$(get_version)
    ok "Snell ${VERSION} 正在更新 (当前: ${old_ver})..."

    rc-service snell stop 2>/dev/null
    ensure_packages
    download_and_extract
    rc-service snell start

    if wait_for_service; then
        ok "Snell 更新成功: $(get_version)"
    else
        warn "更新后启动超时，请手动检查"
    fi

    if [ -f /etc/snell/config.txt ]; then
        cat /etc/snell/config.txt
    fi
}

#=============================================================================
# 4. 卸载
#=============================================================================
uninstall_snell() {
    ok "正在卸载 Snell..."
    rc-service snell stop 2>/dev/null
    rc-update del snell 2>/dev/null
    rm -f /etc/init.d/snell
    rm -f /usr/local/bin/snell-server
    rm -rf /etc/snell
    rm -f /run/snell.pid
    deluser snell 2>/dev/null
    ok "Snell 卸载成功"
}

#=============================================================================
# 菜单
#=============================================================================
show_menu() {
    clear

    local inst_stat run_stat ver_stat

    if is_installed; then
        inst_stat="${GREEN}已安装${RESET}"
        ver_stat="${GREEN}$(get_version)${RESET}"
        if is_running; then
            run_stat="${GREEN}已启动${RESET}"
        else
            run_stat="${RED}未启动${RESET}"
        fi
    else
        inst_stat="${RED}未安装${RESET}"
        run_stat="${RED}未启动${RESET}"
        ver_stat="—"
    fi

    echo -e "${GREEN}=== Snell 管理工具 ===${RESET}"
    echo -e "安装状态: ${inst_stat}"
    echo -e "运行状态: ${run_stat}"
    echo -e "运行版本: ${ver_stat}"
    echo ""
    echo "1. 安装 Snell 服务"
    echo "2. 配置 Snell 服务"
    echo "3. 更新 Snell 服务"
    echo "4. 卸载 Snell 服务"
    echo "0. 退出"
    echo -e "${GREEN}======================${RESET}"
    read -p "请输入选项编号: " choice
    echo ""
}

trap 'echo -e "${RED}已取消操作${RESET}"; exit' INT

#=============================================================================
# 入口
#=============================================================================
main() {
    check_root
    check_alpine

    while true; do
        show_menu
        case "${choice}" in
            1) install_snell ;;
            2) configure_snell ;;
            3) update_snell ;;
            4) uninstall_snell ;;
            0) ok "已退出"; exit 0 ;;
            *) warn "无效的选项" ;;
        esac
        read -p "按 enter 键继续..."
    done
}

main
