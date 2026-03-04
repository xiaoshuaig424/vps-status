#!/usr/bin/env bash
set -euo pipefail

# 统一 UTF-8 运行环境，避免中文在部分系统上乱码
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

restart_singbox_if_possible() {
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart sing-box 2>/dev/null || true
    elif command -v rc-service >/dev/null 2>&1; then
        rc-service sing-box restart 2>/dev/null || true
    fi
}

resolve_sbox_config_path() {
    if [ -f /etc/s-box/sb.json ]; then
        echo "/etc/s-box/sb.json"
        return 0
    fi
    if [ -f /etc/s-box/sb10.json ]; then
        echo "/etc/s-box/sb10.json"
        return 0
    fi
    return 1
}

get_proxy_ip_priority_text() {
    local blue plain
    local v4 v6 w4="" w6="" showv4 showv6
    local rpip v4_6 cfg

    : "${blue:=\033[0;36m}"
    : "${plain:=\033[0m}"

    if ! command -v jq >/dev/null 2>&1; then
        return 1
    fi

    cfg=$(resolve_sbox_config_path || true)
    if [ -z "${cfg:-}" ]; then
        return 1
    fi

    v4=$(curl -s4m5 icanhazip.com -k || true)
    v6=$(curl -s6m5 icanhazip.com -k || true)

    [[ "${v6:-}" == 2a09* ]] && w6="【WARP】"
    [[ "${v4:-}" == 104.28* ]] && w4="【WARP】"

    [[ -z "${v4:-}" ]] && showv4='IPV4地址丢失，请切换至IPV6或者重装Sing-box' || showv4="${v4}${w4}"
    [[ -z "${v6:-}" ]] && showv6='IPV6地址丢失，请切换至IPV4或者重装Sing-box' || showv6="${v6}${w6}"

    rpip=$(sed 's://.*::g' "$cfg" | jq -r '.outbounds[0].domain_strategy' 2>/dev/null || true)
    case "${rpip:-}" in
        prefer_ipv6) v4_6="IPV6优先出站(${showv6})" ;;
        prefer_ipv4) v4_6="IPV4优先出站(${showv4})" ;;
        ipv4_only)   v4_6="仅IPV4出站(${showv4})" ;;
        ipv6_only)   v4_6="仅IPV6出站(${showv6})" ;;
        *)           v4_6="未知(${rpip:-未读取到})" ;;
    esac

    echo -e "代理IP优先级：${blue}${v4_6}${plain}"
}

change_proxy_ip_priority() {
    local blue plain red
    local v4 v6 choose rrpip tip
    local tmp_json cfg

    : "${blue:=\033[0;36m}"
    : "${plain:=\033[0m}"
    : "${red:=\033[0;31m}"

    if ! command -v jq >/dev/null 2>&1; then
        echo -e "${red}错误：未安装 jq，无法切换代理IP优先级。${plain}"
        return 1
    fi

    cfg=$(resolve_sbox_config_path || true)
    if [ -z "${cfg:-}" ]; then
        echo -e "${red}错误：未找到 /etc/s-box/sb.json 或 /etc/s-box/sb10.json，无法切换代理IP优先级。${plain}"
        return 1
    fi

    v4=$(curl -s4m5 icanhazip.com -k || true)
    v6=$(curl -s6m5 icanhazip.com -k || true)

    echo "请选择代理IP优先级："
    echo "1. IPV4优先"
    echo "2. IPV6优先"
    echo "3. 仅IPV4"
    echo "4. 仅IPV6"
    read -r -p "请输入 [1-4]：" choose

    case "${choose:-}" in
        1)
            if [ -z "${v4:-}" ]; then
                echo -e "${red}当前不存在IPV4地址，无法切换为IPV4优先。${plain}"
                return 1
            fi
            rrpip="prefer_ipv4"
            tip="IPV4优先(${v4})"
            ;;
        2)
            if [ -z "${v6:-}" ]; then
                echo -e "${red}当前不存在IPV6地址，无法切换为IPV6优先。${plain}"
                return 1
            fi
            rrpip="prefer_ipv6"
            tip="IPV6优先(${v6})"
            ;;
        3)
            if [ -z "${v4:-}" ]; then
                echo -e "${red}当前不存在IPV4地址，无法切换为仅IPV4。${plain}"
                return 1
            fi
            rrpip="ipv4_only"
            tip="仅IPV4(${v4})"
            ;;
        4)
            if [ -z "${v6:-}" ]; then
                echo -e "${red}当前不存在IPV6地址，无法切换为仅IPV6。${plain}"
                return 1
            fi
            rrpip="ipv6_only"
            tip="仅IPV6(${v6})"
            ;;
        *)
            echo -e "${red}输入错误，未执行切换。${plain}"
            return 1
            ;;
    esac

    tmp_json=$(mktemp)
    sed 's://.*::g' "$cfg" | jq --arg ds "$rrpip" '.outbounds[0].domain_strategy = $ds' > "$tmp_json"
    cp "$tmp_json" "$cfg"
    rm -f "$tmp_json"

    restart_singbox_if_possible
    echo -e "${blue}当前已更换的IP优先级：${tip}${plain}"
}

show_vps_status() {
    : "${blue:=\033[0;36m}"
    : "${red:=\033[0;31m}"
    : "${plain:=\033[0m}"

    local op_local version_local cpu_local vi_local bbr_local
    local v4 v6 v4dq v6dq
    local w4="" w6="" vps_ipv4 vps_ipv6 location

    op_local=$(cat /etc/redhat-release 2>/dev/null || awk -F'"' '/^PRETTY_NAME=/{print $2}' /etc/os-release 2>/dev/null)
    version_local=$(uname -r | cut -d "-" -f1)

    case "$(uname -m)" in
        armv7l)  cpu_local="armv7" ;;
        aarch64) cpu_local="arm64" ;;
        x86_64)  cpu_local="amd64" ;;
        *)       cpu_local="$(uname -m)" ;;
    esac

    if command -v systemd-detect-virt >/dev/null 2>&1; then
        vi_local=$(systemd-detect-virt 2>/dev/null)
    fi
    [ -z "${vi_local:-}" ] && vi_local=$(virt-what 2>/dev/null || true)
    [ -z "${vi_local:-}" ] && vi_local="unknown"

    bbr_local=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null || true)
    [ -z "${bbr_local:-}" ] && bbr_local="unknown"

    v4=$(curl -s4m5 icanhazip.com -k || true)
    v6=$(curl -s6m5 icanhazip.com -k || true)
    v4dq=$(curl -s4m5 -k https://ip.fm | sed -n 's/.*Location: //p' 2>/dev/null || true)
    v6dq=$(curl -s6m5 -k https://ip.fm | sed -n 's/.*Location: //p' 2>/dev/null || true)

    [[ "${v6:-}" == 2a09* ]] && w6="【WARP】"
    [[ "${v4:-}" == 104.28* ]] && w4="【WARP】"

    if [[ -z "${v4:-}" ]]; then
        vps_ipv4='无IPV4'
        vps_ipv6="${v6:-无IPV6}"
        location="${v6dq:-}"
    elif [[ -n "${v4:-}" && -n "${v6:-}" ]]; then
        vps_ipv4="$v4"
        vps_ipv6="$v6"
        location="${v4dq:-}"
    else
        vps_ipv4="$v4"
        vps_ipv6='无IPV6'
        location="${v4dq:-}"
    fi

    [ -z "${location:-}" ] && location="获取失败"

    echo -e "VPS状态如下："
    echo -e "系统:${blue}${op_local:-unknown}${plain}  内核:${blue}${version_local:-unknown}${plain}  处理器:${blue}${cpu_local:-unknown}${plain}  虚拟化:${blue}${vi_local}${plain}  BBR算法:${blue}${bbr_local}${plain}"
    echo -e "本地IPV4地址：${blue}${vps_ipv4}${w4}${plain}   本地IPV6地址：${blue}${vps_ipv6}${w6}${plain}"
    echo -e "服务器地区：${blue}${location}${plain}"

    if ! get_proxy_ip_priority_text; then
        echo -e "代理IP优先级：${red}未安装Sing-box（缺少配置文件）或未安装jq，无法读取${plain}"
    fi
}

case "${1:-}" in
    --change-ip-priority|-c)
        change_proxy_ip_priority
        show_vps_status
        ;;
    --help|-h)
        echo "用法："
        echo "  $0                  # 显示VPS状态（含代理IP优先级）"
        echo "  $0 --change-ip-priority|-c  # 交互式切换代理IP优先级并显示状态"
        ;;
    *)
        show_vps_status
        ;;
esac
