#!/bin/sh
# shellcheck disable=SC2059  # ANSI 颜色变量出现在 printf 格式串中，属故意为之
#=============================================================================
# realm.sh  ·  Realm 端口转发管理面板  ·  Alpine Linux / OpenRC 专用
#
#   安装 / 升级（自动检测架构与最新版）· 转发规则增删改查 · 服务管理
#   状态查看 · 日志查看（尾部/实时/清空）· 一键卸载
#   配置变更自动备份，服务运行时自动重启生效
#
#   参考: https://www.nodeseek.com/post-179931-1
#=============================================================================

# ---- 颜色 ----
R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m'
C='\033[0;36m' W='\033[1;37m' B='\033[1m' D='\033[2m' N='\033[0m'

# ---- 分隔线（2空格缩进 · dim 灰 · 46 长度）----
line() { echo -e "${D}  ──────────────────────────────────────────────${N}"; }

# ---- 路径 ----
BIN="/usr/local/bin/realm"
CONFIG="/etc/realm/realm.toml"
INITD="/etc/init.d/realm"
LOGFILE="/var/log/realm.log"
WORKDIR="/etc/realm"
LAUNCHER="/etc/realm/launcher.sh"

# ---- 工具函数 ----
pause()              { echo -n "  按回车${1:-返回} ..."; read -r _; }
ok()                 { echo -e "  ${G}✓ $*${N}"; }
warn()               { echo -e "  ${Y}⚠ $*${N}"; }
info()               { echo -e "  ${C}! $*${N}"; }
die_msg()            { echo -e "  ${R}✗ $*${N}"; }

# confirm  $1=提示  $2=默认 yes|no（默认 no）—— 仅接受完整 yes/no
confirm() {
    local msg="$1" def="${2:-no}" ans hint
    [ "$def" = "yes" ] && hint="${B}yes${N}/no" || hint="yes/${B}no${N}"
    while true; do
        echo -ne "  ${Y}${msg}${N} [${hint}]: "
        read -r ans
        [ -z "$ans" ] && ans="$def"
        case "$ans" in
            yes) return 0 ;;
            no)  return 1 ;;
            *)   warn "请输入 yes 或 no" ;;
        esac
    done
}
_st=0; _st_n=0
steps_init()         { _st_n="$1"; _st=0; }
step()               { _st=$((_st+1)); echo -e "  ${C}[$_st/$_st_n]${N} $1"; }
is_installed()       { [ -x "$BIN" ]; }
is_running()         { pidof realm >/dev/null 2>&1; }
is_service_enabled() { [ -f "$INITD" ] && rc-update show 2>/dev/null | grep -q "realm"; }

# 统计转发规则数量（安全：grep -c 无匹配会返回非零退出码且输出0，
# 直接用命令替换捕获其 stdout，不加 || echo 0 以免产生 "0\n0"）
count_rules() {
    [ -f "$CONFIG" ] || { echo 0; return; }
    grep -c '^\[\[endpoints\]\]' "$CONFIG" 2>/dev/null
}

require_config() {
    [ -f "$CONFIG" ] && return 0
    die_msg "配置文件不存在，请先安装 Realm"; pause; return 1
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
    local _ok
    if [ "$2" = up ]; then is_running && _ok=1 || _ok=0
    else                   is_running && _ok=0 || _ok=1; fi
    if [ "$_ok" = 1 ]; then ok "$3"; else die_msg "$4"; fi
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
    is_installed       && s="${G}● 已安装${N}"    || s="${D}○ 未安装${N}"
    is_running         && s="$s   ${G}● 运行中${N}" || s="$s   ${Y}● 已停止${N}"
    is_service_enabled && s="$s   ${G}● 自启${N}"   || s="$s   ${D}○ 自启关${N}"
    echo "$s"
}

# ---- 标题头（╭─── 装饰线，左对齐规避中文宽度问题）----
_box() {
    echo ''
    if [ -n "$2" ]; then
        echo -e "  ${C}╭───${N} ${W}${B}$1${N}  ${D}$2${N}"
    else
        echo -e "  ${C}╭───${N} ${W}${B}$1${N}"
    fi
}

# ---- 主横幅 ----
banner() {
    clear
    _box "Realm 端口转发" "Alpine · OpenRC · v1.4"
    line
    echo -e "    $(status_line)"
    line
    echo ''
    echo -e "   ${C}[1]${N}  安装 / 升级"
    echo -e "   ${C}[2]${N}  规则管理"
    echo -e "   ${C}[3]${N}  服务管理"
    echo -e "   ${C}[4]${N}  状态 & 配置"
    echo -e "   ${C}[5]${N}  查看日志"
    echo -e "   ${C}[6]${N}  卸载"
    echo -e "   ${D}[0]  退出${N}"
    echo ''
    line
    echo -ne "   ${C}❯${N} 请选择 ${D}[0-6]${N} "
}

# ---- 子菜单横幅（╭─── 风格，不依赖宽度计算）----
sub_banner() {
    clear
    _box "$1"
    line
    echo ''
}

# 内部：下载并安装 realm 二进制  $1=版本 $2=架构
_do_install_bin() {
    local ver="$1" arch="$2" url tmpdir
    url="https://github.com/zhboner/realm/releases/download/${ver}/realm-${arch}.tar.gz"
    info "下载: $url"

    tmpdir=$(mktemp -d)
    cd "$tmpdir" || return 1

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$url" -o realm.tar.gz
    else
        wget -q "$url" -O realm.tar.gz
    fi

    if [ ! -f realm.tar.gz ]; then
        die_msg "下载失败，请检查网络或版本号"
        cd / && rm -rf "$tmpdir"; return 1
    fi

    tar xzf realm.tar.gz
    if [ ! -f realm ]; then
        die_msg "解压后未找到可执行文件"
        cd / && rm -rf "$tmpdir"; return 1
    fi

    chmod +x realm && mv realm "$BIN"
    cd / && rm -rf "$tmpdir"
    ok "二进制已安装: $BIN"
}

###############################################################################
# §1  安装 / 升级
###############################################################################
install_realm() {
    sub_banner "安装 / 升级 Realm"
    [ "$(id -u)" -ne 0 ] && { die_msg "请以 root 运行"; pause; return; }

    local arch cur_ver latest_ver
    arch=$(detect_arch) || { die_msg "不支持的架构: $(uname -m)"; pause; return; }

    if is_installed; then
        cur_ver=$($BIN --version 2>/dev/null | head -1)
        info "当前版本: ${cur_ver:-未知}"
    fi

    info "正在获取最新版本..."
    latest_ver=$(fetch_version)
    if [ "$latest_ver" = "unknown" ]; then
        warn "无法获取版本号 (API 限流或网络问题)"
        echo -ne "  请手动输入版本号 (如 v2.0.0，留空取消): "
        read -r latest_ver
        [ -z "$latest_ver" ] && { warn "已取消"; pause; return; }
    fi
    info "最新版本: $latest_ver"
    echo ''

    if is_installed; then
        confirm "确认安装/覆盖为 ${C}$latest_ver${N}？" "yes" || { warn "已取消"; pause; return; }
        echo ''
    fi

    steps_init 4
    line

    step "下载并安装 Realm $latest_ver"
    _do_install_bin "$latest_ver" "$arch" || { pause; return; }

    step "写入服务配置"
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
    fi
    ok "服务文件就绪"

    step "生成基础配置"
    if [ -f "$CONFIG" ]; then
        info "配置文件已存在，保留不覆盖"
    else
        cfg_header; ok "realm.toml 已创建"
    fi
    touch "$LOGFILE" 2>/dev/null

    step "应用新版本"
    apply_config

    line
    echo ''
    ok "安装完成！版本 ${latest_ver}"
    info "下一步: 规则管理 → 添加转发规则，服务管理 → 启动并设为自启"
    echo ''
    pause "返回菜单"
}

# 内部：交互录入一条规则并追加到 CONFIG  返回 0=已写入 1=用户取消
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
            *[!0-9]*) die_msg "端口必须为纯数字"; continue ;;
        esac
        if [ "$listen_port" -lt 1 ] || [ "$listen_port" -gt 65535 ]; then
            die_msg "端口范围 1-65535"; continue
        fi
        # 重复检测
        if grep -q "\"${listen_ip}:${listen_port}\"" "$CONFIG" 2>/dev/null; then
            confirm "该监听地址已存在，仍要使用?" "no" || continue
        fi
        break
    done

    # 目标地址
    echo -ne "  目标地址  (如 1.2.3.4:443，留空取消): "
    read -r remote_addr
    [ -z "$remote_addr" ] && return 1

    printf '[[endpoints]]\nlisten = "%s:%s"\nremote = "%s"\n\n' \
        "$listen_ip" "$listen_port" "$remote_addr" >> "$CONFIG"
    ok "${listen_ip}:${listen_port} → ${remote_addr}"
    return 0
}

# 内部：打印规则列表（供删除/查看共用）  规则总数写入全局 _RULE_COUNT
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

# 内部：删除第 N 条规则（不含确认/备份，由调用方负责）  $1=规则序号
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

###############################################################################
# §2  规则管理
###############################################################################
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
                warn "暂无转发规则"
                echo ''
            fi
        else
            warn "配置文件不存在"
            echo ''
        fi

        line
        echo -e "   ${C}[1]${N}  添加规则"
        echo -e "   ${C}[2]${N}  删除规则"
        echo -e "   ${C}[3]${N}  重置所有规则"
        echo -e "   ${C}[4]${N}  备份 / 还原"
        echo -e "   ${D}[0]  返回主菜单${N}\n"
        echo -ne "   ${C}❯${N} 请选择 ${D}[0-4]${N} "
        read -r choice

        # 改动后若服务在运行会自动重启生效（各函数内部处理）
        case "$choice" in
            1) _rule_add ;;
            2) _rule_delete ;;
            3) _rule_reset ;;
            4) _rule_backup ;;
            0) return ;;
        *) die_msg "无效选项"; sleep 1 ;;
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
        echo ''
        ok "共添加 $added 条规则"
        apply_config
        pause "继续"; return 0
    fi
    warn "未添加任何规则"; pause "继续"; return 1
}

# ---- 规则管理：删除（成功返回0，取消返回1）----
_rule_delete() {
    sub_banner "删除规则"
    require_config || return 1

    local count
    count=$(count_rules)
    if [ "$count" -eq 0 ]; then
        warn "暂无规则可删除"; pause "继续"; return 1
    fi

    _list_rules
    echo ''
    echo -ne "  输入要删除的规则编号 (${R}0${N} 取消): "
    read -r choice

    case "$choice" in
        ''|*[!0-9]*) die_msg "无效编号"; pause "继续"; return 1 ;;
    esac
    [ "$choice" -eq 0 ] && { warn "已取消"; pause "继续"; return 1; }
    [ "$choice" -gt "$count" ] && { die_msg "编号超出范围"; pause "继续"; return 1; }

    backup_config >/dev/null
    _remove_rule "$choice"
    ok "已删除规则 #${choice}"
    apply_config
    pause "继续"; return 0
}

# ---- 规则管理：重置（成功录入返回0，取消/空返回1）----
_rule_reset() {
    sub_banner "重置所有规则"
    require_config || return 1

    warn "危险操作: 将清空所有现有规则后重新录入"
    echo -ne "  确认继续? 输入 ${R}yes${N} 确认 (其它取消): "
    read -r ans
    [ "$ans" != "yes" ] && { warn "已取消"; pause "继续"; return 1; }
    echo ''

    local bak
    bak=$(backup_config)
    info "已备份旧配置 → $(basename "$bak")"
    echo ''

    cfg_header

    local count=0
    while true; do
        echo -e "  ${W}── 规则 #$((count+1)) ──${N}"
        if _input_one_rule; then count=$((count+1)); echo ''; else break; fi
    done

    if grep -q '\[\[endpoints\]\]' "$CONFIG" 2>/dev/null; then
        echo ''
        ok "共 $count 条规则已保存"
        apply_config
        pause "继续"; return 0
    fi
    echo ''
    warn "未录入任何规则，恢复备份"
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
        [ "$i" -eq 0 ] && warn "暂无备份文件"
        echo ''

        line
        echo -e "   ${C}m${N}  立即备份当前配置"
        echo -e "   ${D}[0]  返回${N}\n"
        echo -ne "   ${C}❯${N} 输入编号还原，或选项 "
        read -r bc

        case "$bc" in
            0) return ;;
            m)
                if [ ! -f "$CONFIG" ]; then
                    die_msg "配置文件不存在"
                else
                    nb=$(backup_config)
                    ok "已备份 → $(basename "$nb")"
                fi
                pause "继续"
                ;;
            ''|*[!0-9]*) die_msg "无效输入"; sleep 1 ;;
            *)
                [ "$bc" -lt 1 ] || [ "$bc" -gt "$i" ] && {
                    die_msg "编号超出范围"; sleep 1; continue; }
                eval "target=\"\$bak_$bc\""
                echo -e "\n  将还原: ${C}$(basename "$target")${N}"
                if confirm "确认还原? 当前配置会先自动备份" "no"; then
                    [ -f "$CONFIG" ] && backup_config >/dev/null
                    cp "$target" "$CONFIG"
                    ok "已还原"
                    apply_config
                else
                    warn "已取消"
                fi
                pause "继续"
                ;;
        esac
    done
}

###############################################################################
# §3  服务管理
###############################################################################
manage_service() {
    while true; do
        sub_banner "服务管理"

        # 实时状态显示
        if is_running; then
            echo -e "  ${G}● 运行中${N}  ${D}PID: $(pidof realm | tr ' ' ',')${N}"
        else
            echo -e "  ${R}○ 已停止${N}"
        fi
        is_service_enabled \
            && echo -e "  ${G}● 自启已启用${N}\n" \
            || echo -e "  ${D}○ 自启未启用${N}\n"

        line
        echo -e "   ${C}[1]${N}  启动"
        echo -e "   ${C}[2]${N}  停止"
        echo -e "   ${C}[3]${N}  重启"
        echo -e "   ${C}[4]${N}  开机自启"
        echo -e "   ${D}[0]  返回主菜单${N}\n"
        echo -ne "   ${C}❯${N} 请选择 ${D}[0-4]${N} "
        read -r choice

        case "$choice" in
            1)
                if ! is_installed; then
                    die_msg "Realm 未安装"
                elif is_running; then
                    warn "服务已在运行"
                else
                    svc start up "已启动" "启动失败，请查看日志"
                fi
                pause "继续"
                ;;
            2)
                if ! is_running; then
                    warn "服务未在运行"
                else
                    svc stop down "已停止" "停止失败"
                fi
                pause "继续"
                ;;
            3)
                if ! is_installed; then
                    die_msg "Realm 未安装"
                else
                    svc restart up "已重启" "重启失败，请查看日志"
                fi
                pause "继续"
                ;;
            4)
                if ! is_installed; then
                    die_msg "Realm 未安装"
                elif is_service_enabled; then
                    rc-update del realm 2>&1
                    ok "已取消开机自启"
                else
                    rc-update add realm default 2>&1
                    ok "已设为开机自启"
                fi
                pause "继续"
                ;;
            0) return ;;
            *) die_msg "无效选项"; sleep 1 ;;
        esac
    done
}

###############################################################################
# §4  状态 & 配置
###############################################################################
check_status() {
    sub_banner "状态 & 配置"

    if ! is_installed; then
        warn "Realm 未安装"
        echo ''
        pause "返回菜单"; return
    fi

    local bin_ver
    bin_ver=$($BIN --version 2>/dev/null | head -1 || echo "未知")

    # 版本 & 路径
    printf "  ${D}版本${N}  ${W}%s${N}\n" "$bin_ver"
    printf "  ${D}程序${N}  ${C}%s${N}\n" "$BIN"
    printf "  ${D}配置${N}  ${C}%s${N}\n" "$CONFIG"
    echo ''

    # 运行状态
    if is_running; then
        printf "  ${G}● 运行中${N}  ${D}PID: %s${N}\n" "$(pidof realm | tr ' ' ',')"
    else
        printf "  ${R}○ 已停止${N}\n"
    fi
    is_service_enabled \
        && printf "  ${G}● 自启已启用${N}\n" \
        || printf "  ${D}○ 自启未启用${N}\n"

    # 转发规则
    echo ''
    if [ ! -f "$CONFIG" ]; then
        warn "配置文件不存在"
    else
        local count
        count=$(count_rules)
        printf "  ${D}规则${N}  ${W}%s${N} 条\n" "$count"
        if [ "$count" -gt 0 ]; then
            echo ''
            awk -v RS='' -v FS='\n' '
            /^\[\[endpoints\]\]/ {
                listen = ""; remote = ""
                for (i=1;i<=NF;i++) {
                    if ($i~/^listen/) { gsub(/.*= *"|"$/,"",$i); listen=$i }
                    if ($i~/^remote/) { gsub(/.*= *"|"$/,"",$i); remote=$i }
                }
                printf "    %s  →  %s\n", listen, remote
            }' "$CONFIG"

            if command -v ss >/dev/null 2>&1; then
                echo ''
                ports=$(grep '^listen' "$CONFIG" | sed 's/.*:\([0-9]*\)".*/\1/')
                for p in $ports; do
                    ss -tlnp sport = :"$p" 2>/dev/null | grep -q realm \
                        && printf "    ${G}● :%s 监听中${N}\n" "$p" \
                        || printf "    ${R}○ :%s 未监听${N}\n" "$p"
                done
            fi
        fi

        line
        printf "  ${D}realm.toml${N}\n${C}"
        sed 's/^/  /' "$CONFIG"
        printf "${N}"
    fi
    echo ''
    pause "返回菜单"
}

###############################################################################
# §5  日志
###############################################################################
view_logs() {
    while true; do
        sub_banner "查看日志"

        if [ ! -f "$LOGFILE" ]; then
            warn "日志文件不存在: $LOGFILE"
            echo ''
            pause; return
        fi

        local size lines
        size=$(wc -c < "$LOGFILE" 2>/dev/null || echo 0)
        if [ "$size" -eq 0 ]; then
            warn "日志文件为空"
            echo ''
        else
            lines=$(wc -l < "$LOGFILE" 2>/dev/null || echo 0)
            printf "  ${C}%s${N}  ${D}%s 行 / %s 字节${N}\n\n" "$LOGFILE" "$lines" "$size"
            echo -e "  ${D}最近 30 行:${N}"
            tail -30 "$LOGFILE" | sed 's/^/  /'
            echo ''
        fi

        line
        echo -e "   ${C}[1]${N}  刷新    ${C}[2]${N}  清空    ${C}[3]${N}  实时跟踪    ${D}[0]  返回${N}\n"
        echo -ne "   ${C}❯${N} 请选择 "
        read -r lc

        case "$lc" in
            1) continue ;;
            2)
                if confirm "确认清空日志?" "no"; then
                    : > "$LOGFILE"; ok "已清空"; sleep 1
                else
                    warn "已取消"
                fi
                ;;
            3)
                echo -e "${Y}  实时日志 (Ctrl+C 退出)${N}"
                trap ':' INT; tail -f "$LOGFILE"; trap - INT
                echo ''; pause "继续"
                ;;
            0) return ;;
        esac
    done
}

###############################################################################
# §6  卸载
###############################################################################
uninstall_realm() {
    sub_banner "卸载 Realm"
    warn "以下内容将被永久删除:"
    echo -e "    ${D}• $BIN${N}"
    echo -e "    ${D}• $WORKDIR  (含配置与所有备份)${N}"
    echo -e "    ${D}• $INITD${N}"
    echo -e "    ${D}• $LOGFILE${N}"
    echo ''
    echo -ne "  确认卸载? 输入 ${R}yes${N} 确认: "
    read -r confirm
    [ "$confirm" != "yes" ] && { warn "已取消"; pause; return; }

    is_running && { info "停止服务..."; rc-service realm stop 2>/dev/null; sleep 1; }
    rc-update del realm 2>/dev/null
    rm -f "$BIN" "$INITD" "$LOGFILE"
    rm -rf "$WORKDIR"

    echo ''
    ok "Realm 已完全卸载"
    echo ''
    pause "返回菜单"
}

###############################################################################
# §7  入口
###############################################################################
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
        *) die_msg "无效选项: $choice"; sleep 1 ;;
    esac
done
