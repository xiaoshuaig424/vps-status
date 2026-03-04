#!/usr/bin/env bash
set -euo pipefail

show_vps_status() {
    # 颜色兜底（防止单独调用时没定义）
    : "${blue:=\033[0;36m}"
    : "${plain:=\033[0m}"

    # 基础信息（尽量独立，不强依赖全局变量）
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

    # IP + 地区
    v4=$(curl -s4m5 icanhazip.com -k || true)
    v6=$(curl -s6m5 icanhazip.com -k || true)
    v4dq=$(curl -s4m5 -k https://ip.fm | sed -n 's/.*Location: //p' 2>/dev/null || true)
    v6dq=$(curl -s6m5 -k https://ip.fm | sed -n 's/.*Location: //p' 2>/dev/null || true)

    # WARP标识
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
}

show_vps_status
