#!/bin/sh
# ============================================================
#  Realm 端口转发管理面板  v1.4
#  Alpine Linux / OpenRC 适配版
#  教程: https://www.nodeseek.com/post-179931-1
# ============================================================

# ---- 颜色 ----
R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m'
C='\033[0;36m' W='\033[1;37m' D='\033[2m' N='\033[0m'

# ---- 分隔线 ----
line() { echo -e "${C}  ────────────────────────────────────────────${N}"; }

# ---- 路径 ----
BIN="/usr/local/bin/realm"
CONFIG="/etc/realm/realm.toml"
INITD="/etc/init.d/realm"
LOGFILE="/var/log/realm.log"
WORKDIR="/etc/realm"
LAUNCHER="/etc/realm/launcher.sh"

# ---- 工具函数 ----
pause()              { echo -n "  按回车${1:-返回} ..."; read -r _; }
is_installed()       { [ -x "$BIN" ]; }
is_running()         { pidof realm >/dev/null 2>&1; }
is_service_enabled() { [ -f "$INITD" ] && rc-update show 2>/dev/null | grep -q "realm"; }

# 统计转发规则数量（安全：grep -c 无匹配会返回非零退出码且输出0，
# 直接用命令替换捕获其 stdout，不加 || echo 0 以免产生 "0\n0"）
count_rules() {
    [ -f "$CONFIG" ] || { echo 0; return; }
    grep -c '^\[\[endpoints\]\]' "$CONFIG" 2>/dev/null
}

require_installed() {
    is_installed && return 0
    echo -e "${R}✗ Realm 未安装，请先执行安装${N}"; pause; return 1
}

require_config() {
    [ -f "$CONFIG" ] && return 0
    echo -e "${R}✗ 配置文件不存在，请先安装 Realm${N}"; pause; return 1
}

# ---- 配置写入：仅基础头部（不含任何预设转发规则）----
cfg_header() {
    cat > "$CONFIG" <<'EOF'
[network]
no_tcp = false
use_udp = true

EOF
}

# 创建带时间戳的配置备份，成功时把路径打印到 stdout
backup_config() {
    local bak
    bak="${CONFIG}.bak.$(date +%Y%m%d_%H%M%S)"
    cp "$CONFIG" "$bak" 2>/dev/null && echo "$bak"
}

# 执行服务动作并按期望状态报告结果
#   svc <action> <up|down> <成功提示> <失败提示>
svc() {
    rc-service realm "$1" 2>&1; sleep 1
    local ok
    if [ "$2" = up ]; then is_running && ok=1 || ok=0
    else                   is_running && ok=0 || ok=1; fi
    [ "$ok" = 1 ] \
        && echo -e "  ${G}✓ $3${N}" \
        || echo -e "  ${R}✗ $4${N}"
}

# 配置变更后自动生效：服务在运行则直接重启，否则无需操作
apply_config() {
    is_running || return 0
    svc restart up "已重启，新配置已生效" "重启失败，请查看日志"
}

# ---- 检测架构 ----
detect_arch() {
    case "$(uname -m)" in
        x86_64)        echo "x86_64-unknown-linux-musl" ;;
        aarch64|arm64) echo "aarch64-unknown-linux-musl" ;;
        armv7l|armhf)  echo "armv7-unknown-linux-musleabi" ;;
        armv6l|arm)    echo "arm-unknown-linux-musleabi" ;;
        *)             echo ""; return 1 ;;
    esac
}

# ---- 获取最新版本（含重试）----
fetch_version() {
    local ver
    ver=$(curl -s --retry 2 --retry-delay 1 \
        https://api.github.com/repos/zhboner/realm/releases/latest 2>/dev/null \
        | grep '"tag_name"' | cut -d'"' -f4)
    [ -z "$ver" ] && ver=$(wget -q --tries=3 --wait=1 -O- \
        https://api.github.com/repos/zhboner/realm/releases/latest 2>/dev/null \
        | grep '"tag_name"' | cut -d'"' -f4)
    echo "${ver:-unknown}"
}

# ---- 状态栏（供 banner 调用）----
status_line() {
    local s
    is_installed       && s="${G}● 已安装${N}"   || s="${D}○ 未安装${N}"
    is_running         && s="$s    ${G}● 运行中${N}" || s="$s    ${R}○ 已停止${N}"
    is_service_enabled && s="$s    ${Y}⚙ 自启${N}"   || s="$s    ${D}⚙ 自启关${N}"
    echo "$s"
}

# ---- 主横幅 ----
banner() {
    clear
    echo ''
    echo -e "  ${C}${W}Realm${N}  ${W}端口转发管理面板${N}  ${D}v1.4${N}"
    echo -e "  ${D}Alpine Linux · OpenRC${N}"
    line
    echo -e "   $(status_line)"
    line
    echo ''
    echo -e "   ${W}1${N}  安装 / 升级       ${D}部署或更新 Realm${N}"
    echo -e "   ${W}2${N}  规则管理          ${D}增 · 删 · 重置 · 备份${N}"
    echo -e "   ${W}3${N}  服务管理          ${D}启动 · 停止 · 自启${N}"
    echo -e "   ${W}4${N}  状态 & 配置       ${D}查看运行详情${N}"
    echo -e "   ${W}5${N}  查看日志          ${D}尾部 · 跟踪 · 清空${N}"
    echo -e "   ${W}6${N}  卸载              ${D}完全移除${N}"
    echo -e "   ${D}0  退出${N}"
    echo ''
    line
    echo -ne "   请选择 ${D}[0-6]${N}: "
}

# ---- 子菜单横幅（不依赖宽度计算，避免中文错位）----
sub_banner() {
    clear
    echo ''
    echo -e "  ${C}${W}▸ $1${N}"
    line
    echo ''
}

# ============================================================
#  内部：下载并安装 realm 二进制
# ============================================================
_do_install_bin() {
    local ver="$1" arch="$2" url tmpdir
    url="https://github.com/zhboner/realm/releases/download/${ver}/realm-${arch}.tar.gz"
    echo -e "  下载: ${C}$url${N}"

    tmpdir=$(mktemp -d)
    cd "$tmpdir" || return 1

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o realm.tar.gz
    else
        wget -q "$url" -O realm.tar.gz
    fi

    if [ ! -f realm.tar.gz ]; then
        echo -e "${R}✗ 下载失败，请检查网络或版本号${N}"
        cd / && rm -rf "$tmpdir"; return 1
    fi

    tar xzf realm.tar.gz
    if [ ! -f realm ]; then
        echo -e "${R}✗ 解压后未找到可执行文件${N}"
        cd / && rm -rf "$tmpdir"; return 1
    fi

    chmod +x realm && mv realm "$BIN"
    cd / && rm -rf "$tmpdir"
    echo -e "${G}✓ 二进制已安装: $BIN${N}"
}

# ============================================================
#  1. 安装 / 升级
# ============================================================
install_realm() {
    sub_banner "安装 / 升级 Realm"
    [ "$(id -u)" -ne 0 ] && { echo -e "${R}✗ 请以 root 运行${N}"; pause; return; }

    local arch cur_ver latest_ver
    arch=$(detect_arch) || { echo -e "${R}✗ 不支持的架构: $(uname -m)${N}"; pause; return; }
    echo -e "  架构: ${C}$arch${N}"

    if is_installed; then
        cur_ver=$($BIN --version 2>/dev/null | head -1)
        echo -e "  当前版本: ${C}${cur_ver:-未知}${N}"
    fi

    echo -e "  正在获取最新版本..."
    latest_ver=$(fetch_version)
    if [ "$latest_ver" = "unknown" ]; then
        echo -e "${Y}  ⚠ 无法获取版本号 (API 限流或网络问题)${N}"
        echo -ne "  请手动输入版本号 (如 v2.0.0，留空取消): "
        read -r latest_ver
        [ -z "$latest_ver" ] && { echo -e "  ${Y}已取消${N}"; pause; return; }
    fi
    echo -e "  最新版本: ${C}$latest_ver${N}\n"

    if is_installed; then
        echo -ne "  确认安装/覆盖为 ${C}$latest_ver${N}? [Y/n]: "
        read -r ans
        case "$ans" in n|N) echo -e "  ${Y}已取消${N}"; pause; return ;; esac
        echo ''
    fi

    _do_install_bin "$latest_ver" "$arch" || { pause; return; }

    # 首次安装创建服务文件
    if [ ! -f "$INITD" ]; then
        mkdir -p "$WORKDIR"
        cat > "$LAUNCHER" <<'EOF'
#!/bin/sh
exec /usr/local/bin/realm -c /etc/realm/realm.toml >> /var/log/realm.log 2>&1
EOF
        chmod +x "$LAUNCHER"

        cat > "$INITD" <<'EOF'
#!/sbin/openrc-run
name="Realm"
description="Realm Port Forwarding"
command="/etc/realm/launcher.sh"
command_background=true
pidfile="/run/${RC_SVCNAME}.pid"
command_user="root"
depend() { need net; }
start_pre() { mkdir -p /etc/realm; touch /var/log/realm.log; }
EOF
        chmod +x "$INITD"
        echo -e "${G}✓ 服务文件已创建${N}"
    fi

    # 生成基础配置（仅 [network]，无预设转发规则）
    [ -f "$CONFIG" ] || cfg_header

    touch "$LOGFILE" 2>/dev/null

    # 升级且服务在运行：自动重启载入新版本
    apply_config

    echo -e "\n${G}✓ 完成！${N}"
    echo -e "  下一步: 在「规则管理」添加转发规则，再到「服务管理」启动并设为自启\n"
    pause "返回菜单"
}

# ============================================================
#  内部：交互录入一条规则并追加到 CONFIG
#  返回 0=已写入  1=用户取消（留空监听端口）
# ============================================================
_input_one_rule() {
    local listen_ip listen_port remote_addr

    # 监听 IP
    echo -ne "  监听 IP   (回车默认 ${C}0.0.0.0${N}): "
    read -r listen_ip
    listen_ip="${listen_ip:-0.0.0.0}"

    # 监听端口（含校验）
    while true; do
        echo -ne "  监听端口  (留空取消): "
        read -r listen_port
        [ -z "$listen_port" ] && return 1
        case "$listen_port" in
            *[!0-9]*) echo -e "  ${R}✗ 端口必须为纯数字${N}"; continue ;;
        esac
        if [ "$listen_port" -lt 1 ] || [ "$listen_port" -gt 65535 ]; then
            echo -e "  ${R}✗ 端口范围 1-65535${N}"; continue
        fi
        # 重复检测
        if grep -q "\"${listen_ip}:${listen_port}\"" "$CONFIG" 2>/dev/null; then
            echo -ne "  ${Y}⚠ 该监听地址已存在，仍要使用? [y/N]: ${N}"
            read -r dup
            case "$dup" in y|Y) ;; *) continue ;; esac
        fi
        break
    done

    # 目标地址
    echo -ne "  目标地址  (如 1.2.3.4:443，留空取消): "
    read -r remote_addr
    [ -z "$remote_addr" ] && return 1

    printf '[[endpoints]]\nlisten = "%s:%s"\nremote = "%s"\n\n' \
        "$listen_ip" "$listen_port" "$remote_addr" >> "$CONFIG"
    echo -e "  ${G}✓ ${listen_ip}:${listen_port} → ${remote_addr}${N}"
    return 0
}

# ============================================================
#  内部：打印规则列表（供删除/查看共用）
#  返回规则总数到全局 _RULE_COUNT
# ============================================================
_list_rules() {
    _RULE_COUNT=$(count_rules)
    awk -v RS='' -v FS='\n' '
    BEGIN { n = 0 }
    /^\[\[endpoints\]\]/ {
        n++
        listen = ""; remote = ""
        for (i = 1; i <= NF; i++) {
            if ($i ~ /^listen/) { gsub(/.*= *"|"$/, "", $i); listen = $i }
            if ($i ~ /^remote/) { gsub(/.*= *"|"$/, "", $i); remote = $i }
        }
        printf "  %2d)  %-24s→  %s\n", n, listen"  ", remote
    }
    ' "$CONFIG"
}

# ============================================================
#  内部：删除第 N 条规则（不含确认/备份，由调用方负责）
# ============================================================
_remove_rule() {
    awk -v RS='' -v FS='\n' -v del="$1" '
    BEGIN { n = 0; head = ""; body = "" }
    {
        if ($0 ~ /^\[\[endpoints\]\]/) {
            n++
            if (n != del) { body = body $0 "\n\n" }
        } else {
            head = $0 "\n\n"
        }
    }
    END { printf "%s%s", head, body }
    ' "$CONFIG" > "${CONFIG}.tmp" && mv "${CONFIG}.tmp" "$CONFIG"
}

# ============================================================
#  2. 规则管理子菜单
# ============================================================
manage_rules() {
    while true; do
        sub_banner "规则管理"
        # 先显示当前规则概览
        if [ -f "$CONFIG" ]; then
            local rc
            rc=$(count_rules)
            if [ "$rc" -gt 0 ]; then
                echo -e "  ${W}当前规则 ($rc 条):${N}"
                _list_rules
                echo ''
            else
                echo -e "  ${Y}暂无转发规则${N}\n"
            fi
        else
            echo -e "  ${Y}配置文件不存在${N}\n"
        fi

        line
        echo -e "   ${W}1${N}  添加规则          ${D}追加转发条目${N}"
        echo -e "   ${W}2${N}  删除规则          ${D}按编号移除${N}"
        echo -e "   ${W}3${N}  重置所有规则      ${D}清空后重录${N}"
        echo -e "   ${W}4${N}  备份 / 还原       ${D}配置快照${N}"
        echo -e "   ${D}0  返回主菜单${N}\n"
        echo -ne "   请选择 ${D}[0-4]${N}: "
        read -r choice

        # 改动后若服务在运行会自动重启生效（各函数内部处理）
        case "$choice" in
            1) _rule_add ;;
            2) _rule_delete ;;
            3) _rule_reset ;;
            4) _rule_backup ;;
            0) return ;;
            *) echo -e "${R}  无效选项${N}"; sleep 1 ;;
        esac
    done
}

# ---- 规则管理：添加（成功添加返回0，未添加返回1）----
_rule_add() {
    sub_banner "添加规则"
    require_config || return 1
    echo -e "  在现有配置基础上追加规则，留空监听端口结束\n"
    local added=0
    while true; do
        [ "$added" -gt 0 ] && echo ''
        echo -e "  ${W}── 规则 #$((added+1)) ──${N}"
        if _input_one_rule; then added=$((added+1)); else break; fi
    done
    if [ "$added" -gt 0 ]; then
        echo -e "\n  ${G}✓ 共添加 $added 条规则${N}"
        apply_config
        pause "继续"; return 0
    fi
    echo -e "  ${Y}未添加任何规则${N}"; pause "继续"; return 1
}

# ---- 规则管理：删除（成功返回0，取消返回1）----
_rule_delete() {
    sub_banner "删除规则"
    require_config || return 1

    local count
    count=$(count_rules)
    if [ "$count" -eq 0 ]; then
        echo -e "  ${Y}暂无规则可删除${N}"; pause "继续"; return 1
    fi

    _list_rules
    echo ''
    echo -ne "  输入要删除的规则编号 (${R}0${N} 取消): "
    read -r choice

    case "$choice" in
        ''|*[!0-9]*) echo -e "  ${R}✗ 无效编号${N}"; pause "继续"; return 1 ;;
    esac
    [ "$choice" -eq 0 ] && { echo -e "  ${Y}已取消${N}"; pause "继续"; return 1; }
    [ "$choice" -gt "$count" ] && { echo -e "  ${R}✗ 编号超出范围${N}"; pause "继续"; return 1; }

    backup_config >/dev/null
    _remove_rule "$choice"
    echo -e "  ${G}✓ 已删除规则 #${choice}${N}"
    apply_config
    pause "继续"; return 0
}

# ---- 规则管理：重置（成功录入返回0，取消/空返回1）----
_rule_reset() {
    sub_banner "重置所有规则"
    require_config || return 1

    echo -e "  ${R}⚠ 危险操作: 将清空所有现有规则后重新录入${N}"
    echo -ne "  确认继续? 输入 ${R}yes${N} 确认 (其它取消): "
    read -r ans
    [ "$ans" != "yes" ] && { echo -e "  ${Y}已取消${N}"; pause "继续"; return 1; }
    echo ''

    local bak
    bak=$(backup_config)
    echo -e "  ${Y}已备份旧配置 → $(basename "$bak")${N}\n"

    cfg_header

    local count=0
    while true; do
        echo -e "  ${W}── 规则 #$((count+1)) ──${N}"
        if _input_one_rule; then count=$((count+1)); echo ''; else break; fi
    done

    if grep -q '\[\[endpoints\]\]' "$CONFIG" 2>/dev/null; then
        echo -e "\n  ${G}✓ 共 $count 条规则已保存${N}"
        apply_config
        pause "继续"; return 0
    fi
    echo -e "\n  ${Y}⚠ 未录入任何规则，恢复备份${N}"
    cp "$bak" "$CONFIG"
    pause "继续"; return 1
}

# ---- 规则管理：备份/还原 ----
_rule_backup() {
    local i f ts sz nb bc target ans
    while true; do
        sub_banner "备份 / 还原"

        i=0
        for f in "${CONFIG}.bak."*; do
            [ -f "$f" ] || continue
            i=$((i+1))
            ts=$(echo "$f" | sed 's/.*\.bak\.//')
            sz=$(wc -c < "$f" 2>/dev/null || echo 0)
            # 时间戳 20240115_143052 → 2024-01-15 14:30:52
            ts=$(echo "$ts" | sed 's/\(....\)\(..\)\(..\)_\(..\)\(..\)\(..\)/\1-\2-\3 \4:\5:\6/')
            printf "  %2d)  %s  (%s B)\n" "$i" "$ts" "$sz"
            eval "bak_$i=\"$f\""
        done
        [ "$i" -eq 0 ] && echo -e "  ${Y}暂无备份文件${N}"
        echo ''

        line
        echo -e "   ${W}m${N}  立即备份当前配置"
        echo -e "   ${D}0  返回${N}\n"
        echo -ne "   输入编号还原，或选项: "
        read -r bc

        case "$bc" in
            0) return ;;
            m)
                if [ ! -f "$CONFIG" ]; then
                    echo -e "  ${R}✗ 配置文件不存在${N}"
                else
                    nb=$(backup_config)
                    echo -e "  ${G}✓ 已备份 → $(basename "$nb")${N}"
                fi
                pause "继续"
                ;;
            ''|*[!0-9]*) echo -e "  ${R}✗ 无效输入${N}"; sleep 1 ;;
            *)
                [ "$bc" -lt 1 ] || [ "$bc" -gt "$i" ] && {
                    echo -e "  ${R}✗ 编号超出范围${N}"; sleep 1; continue; }
                eval "target=\"\$bak_$bc\""
                echo -e "\n  将还原: ${C}$(basename "$target")${N}"
                echo -ne "  确认还原? 当前配置会先自动备份 [y/N]: "
                read -r ans
                case "$ans" in
                    y|Y)
                        [ -f "$CONFIG" ] && backup_config >/dev/null
                        cp "$target" "$CONFIG"
                        echo -e "  ${G}✓ 已还原${N}"
                        apply_config
                        ;;
                    *) echo -e "  ${Y}已取消${N}" ;;
                esac
                pause "继续"
                ;;
        esac
    done
}

# ============================================================
#  3. 服务管理子菜单
# ============================================================
manage_service() {
    while true; do
        sub_banner "服务管理"

        # 实时状态显示
        if is_running; then
            echo -e "  状态: ${G}● 运行中${N}  PID: $(pidof realm | tr ' ' ',')"
        else
            echo -e "  状态: ${R}○ 已停止${N}"
        fi
        is_service_enabled \
            && echo -e "  自启: ${Y}已启用${N}\n" \
            || echo -e "  自启: 未启用\n"

        line
        echo -e "   ${W}1${N}  启动"
        echo -e "   ${W}2${N}  停止"
        echo -e "   ${W}3${N}  重启"
        echo -e "   ${W}4${N}  开机自启          ${D}开 / 关${N}"
        echo -e "   ${D}0  返回主菜单${N}\n"
        echo -ne "   请选择 ${D}[0-4]${N}: "
        read -r choice

        case "$choice" in
            1)
                if ! is_installed; then
                    echo -e "${R}  ✗ Realm 未安装${N}"
                elif is_running; then
                    echo -e "${Y}  已在运行${N}"
                else
                    svc start up "已启动" "启动失败，请查看日志"
                fi
                pause "继续"
                ;;
            2)
                if ! is_running; then
                    echo -e "${Y}  未在运行${N}"
                else
                    svc stop down "已停止" "停止失败"
                fi
                pause "继续"
                ;;
            3)
                if ! is_installed; then
                    echo -e "${R}  ✗ Realm 未安装${N}"
                else
                    svc restart up "已重启" "重启失败，请查看日志"
                fi
                pause "继续"
                ;;
            4)
                if ! is_installed; then
                    echo -e "${R}  ✗ Realm 未安装${N}"
                elif is_service_enabled; then
                    rc-update del realm 2>&1
                    echo -e "${G}  ✓ 已取消开机自启${N}"
                else
                    rc-update add realm default 2>&1
                    echo -e "${G}  ✓ 已设为开机自启${N}"
                fi
                pause "继续"
                ;;
            0) return ;;
            *) echo -e "${R}  无效选项${N}"; sleep 1 ;;
        esac
    done
}

# ============================================================
#  4. 状态 & 配置（合并）
# ============================================================
check_status() {
    sub_banner "状态 & 配置"

    # 安装信息
    if ! is_installed; then
        echo -e "  ${R}Realm 未安装${N}\n"
        pause "返回菜单"; return
    fi

    local bin_ver
    bin_ver=$($BIN --version 2>/dev/null | head -1 || echo "未知")
    echo -e "  版本:  ${C}$bin_ver${N}"
    echo -e "  程序:  ${C}$BIN${N}"
    echo -e "  配置:  ${C}$CONFIG${N}"

    # 运行状态
    echo ''
    if is_running; then
        echo -e "  运行:  ${G}● 运行中${N}  PID: $(pidof realm | tr ' ' ',')"
    else
        echo -e "  运行:  ${R}○ 已停止${N}"
    fi
    is_service_enabled \
        && echo -e "  自启:  ${Y}已启用${N}" \
        || echo -e "  自启:  未启用"

    # 规则与端口
    echo ''
    if [ ! -f "$CONFIG" ]; then
        echo -e "  ${Y}配置文件不存在${N}"
    else
        local count
        count=$(count_rules)
        echo -e "  规则:  ${W}$count${N} 条\n"

        if [ "$count" -gt 0 ]; then
            awk -v RS='' -v FS='\n' '
            /^\[\[endpoints\]\]/ {
                listen = ""; remote = ""
                for (i=1;i<=NF;i++) {
                    if ($i~/^listen/) { gsub(/.*= *"|"$/,"",$i); listen=$i }
                    if ($i~/^remote/) { gsub(/.*= *"|"$/,"",$i); remote=$i }
                }
                printf "    %-24s→  %s\n", listen"  ", remote
            }' "$CONFIG"

            # 端口监听检测（依赖 ss）
            if command -v ss >/dev/null 2>&1; then
                echo ''
                ports=$(grep '^listen' "$CONFIG" | sed 's/.*:\([0-9]*\)".*/\1/')
                for p in $ports; do
                    ss -tlnp sport = :"$p" 2>/dev/null | grep -q realm \
                        && echo -e "    ${G}● :$p 已监听${N}" \
                        || echo -e "    ${R}○ :$p 未监听${N}"
                done
            fi
        fi

        # 显示原始 TOML
        echo -e "\n  ${Y}── realm.toml ──${N}${C}"
        sed 's/^/  /' "$CONFIG"
        echo -e "${N}"
    fi

    pause "返回菜单"
}

# ============================================================
#  5. 日志
# ============================================================
view_logs() {
    while true; do
        sub_banner "查看日志"

        if [ ! -f "$LOGFILE" ]; then
            echo -e "  ${R}日志文件不存在: $LOGFILE${N}\n"
            pause; return
        fi

        local size lines
        size=$(wc -c < "$LOGFILE" 2>/dev/null || echo 0)
        if [ "$size" -eq 0 ]; then
            echo -e "  ${Y}日志文件为空${N}\n"
        else
            lines=$(wc -l < "$LOGFILE" 2>/dev/null || echo 0)
            echo -e "  ${C}$LOGFILE${N}  (${W}${lines}行${N} / ${W}${size}字节${N})\n"
            echo -e "  ${Y}最近 30 行:${N}${C}"
            tail -30 "$LOGFILE" | sed 's/^/  /'
            echo -e "${N}"
        fi

        line
        echo -e "   ${W}1${N}  刷新    ${W}2${N}  清空    ${W}3${N}  实时跟踪    ${D}0  返回${N}\n"
        echo -ne "   请选择: "
        read -r lc

        case "$lc" in
            1) continue ;;
            2)
                echo -ne "  确认清空日志? [y/N]: "
                read -r ans
                case "$ans" in
                    y|Y) : > "$LOGFILE"; echo -e "${G}  ✓ 已清空${N}"; sleep 1 ;;
                    *)   echo -e "  ${Y}已取消${N}" ;;
                esac
                ;;
            3)
                echo -e "${Y}  实时日志 (Ctrl+C 退出)${N}"
                # 用空操作捕获 INT（而非忽略），子进程 tail 仍按默认处理，
                # 这样 Ctrl+C 能终止 tail 而不会退出整个面板
                trap ':' INT; tail -f "$LOGFILE"; trap - INT
                echo ''; pause "继续"
                ;;
            0) return ;;
        esac
    done
}

# ============================================================
#  6. 卸载
# ============================================================
uninstall_realm() {
    sub_banner "卸载 Realm"
    echo -e "  ${Y}将删除:${N}"
    echo -e "    • $BIN"
    echo -e "    • $WORKDIR  (含配置与所有备份)"
    echo -e "    • $INITD"
    echo -e "    • $LOGFILE\n"
    echo -ne "  确认卸载? 输入 ${R}yes${N} 确认: "
    read -r confirm
    [ "$confirm" != "yes" ] && { echo -e "  ${Y}已取消${N}"; pause; return; }

    is_running && { echo -e "  ${Y}停止服务...${N}"; rc-service realm stop 2>/dev/null; sleep 1; }
    rc-update del realm 2>/dev/null
    rm -f "$BIN" "$INITD" "$LOGFILE"
    rm -rf "$WORKDIR"

    echo -e "${G}✓ Realm 已完全卸载${N}\n"
    pause "返回菜单"
}

# ============================================================
#  Main
# ============================================================
while true; do
    banner
    read -r choice
    case "$choice" in
        1) install_realm ;;
        2) manage_rules ;;
        3) manage_service ;;
        4) check_status ;;
        5) view_logs ;;
        6) uninstall_realm ;;
        0) clear; echo -e "${C}再见 👋${N}"; exit 0 ;;
        *) echo -e "${R}  无效选项: $choice${N}"; sleep 1 ;;
    esac
done
