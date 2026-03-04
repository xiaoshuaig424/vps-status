#!/usr/bin/env bash
set -euo pipefail

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

    [[ "${v6:-}" == 2a09* ]] && w6="銆怶ARP銆?
    [[ "${v4:-}" == 104.28* ]] && w4="銆怶ARP銆?

    [[ -z "${v4:-}" ]] && showv4='IPV4鍦板潃涓㈠け锛岃鍒囨崲鑷矷PV6鎴栬€呴噸瑁匰ing-box' || showv4="${v4}${w4}"
    [[ -z "${v6:-}" ]] && showv6='IPV6鍦板潃涓㈠け锛岃鍒囨崲鑷矷PV4鎴栬€呴噸瑁匰ing-box' || showv6="${v6}${w6}"

    rpip=$(sed 's://.*::g' "$cfg" | jq -r '.outbounds[0].domain_strategy' 2>/dev/null || true)
    case "${rpip:-}" in
        prefer_ipv6) v4_6="IPV6浼樺厛鍑虹珯(${showv6})" ;;
        prefer_ipv4) v4_6="IPV4浼樺厛鍑虹珯(${showv4})" ;;
        ipv4_only)   v4_6="浠匢PV4鍑虹珯(${showv4})" ;;
        ipv6_only)   v4_6="浠匢PV6鍑虹珯(${showv6})" ;;
        *)           v4_6="鏈煡(${rpip:-鏈鍙栧埌})" ;;
    esac

    echo -e "浠ｇ悊IP浼樺厛绾э細${blue}${v4_6}${plain}"
}

change_proxy_ip_priority() {
    local blue plain red
    local v4 v6 choose rrpip tip
    local tmp_json cfg

    : "${blue:=\033[0;36m}"
    : "${plain:=\033[0m}"
    : "${red:=\033[0;31m}"

    if ! command -v jq >/dev/null 2>&1; then
        echo -e "${red}閿欒锛氭湭瀹夎 jq锛屾棤娉曞垏鎹唬鐞咺P浼樺厛绾с€?{plain}"
        return 1
    fi
    cfg=$(resolve_sbox_config_path || true)
    if [ -z "${cfg:-}" ]; then
        echo -e "${red}閿欒锛氭湭鎵惧埌 /etc/s-box/sb.json 鎴?/etc/s-box/sb10.json锛屾棤娉曞垏鎹唬鐞咺P浼樺厛绾с€?{plain}"
        return 1
    fi

    v4=$(curl -s4m5 icanhazip.com -k || true)
    v6=$(curl -s6m5 icanhazip.com -k || true)

    echo "璇烽€夋嫨浠ｇ悊IP浼樺厛绾э細"
    echo "1. IPV4浼樺厛"
    echo "2. IPV6浼樺厛"
    echo "3. 浠匢PV4"
    echo "4. 浠匢PV6"
    read -r -p "璇疯緭鍏?[1-4]锛? choose

    case "${choose:-}" in
        1)
            if [ -z "${v4:-}" ]; then
                echo -e "${red}褰撳墠涓嶅瓨鍦↖PV4鍦板潃锛屾棤娉曞垏鎹负IPV4浼樺厛銆?{plain}"
                return 1
            fi
            rrpip="prefer_ipv4"
            tip="IPV4浼樺厛(${v4})"
            ;;
        2)
            if [ -z "${v6:-}" ]; then
                echo -e "${red}褰撳墠涓嶅瓨鍦↖PV6鍦板潃锛屾棤娉曞垏鎹负IPV6浼樺厛銆?{plain}"
                return 1
            fi
            rrpip="prefer_ipv6"
            tip="IPV6浼樺厛(${v6})"
            ;;
        3)
            if [ -z "${v4:-}" ]; then
                echo -e "${red}褰撳墠涓嶅瓨鍦↖PV4鍦板潃锛屾棤娉曞垏鎹负浠匢PV4銆?{plain}"
                return 1
            fi
            rrpip="ipv4_only"
            tip="浠匢PV4(${v4})"
            ;;
        4)
            if [ -z "${v6:-}" ]; then
                echo -e "${red}褰撳墠涓嶅瓨鍦↖PV6鍦板潃锛屾棤娉曞垏鎹负浠匢PV6銆?{plain}"
                return 1
            fi
            rrpip="ipv6_only"
            tip="浠匢PV6(${v6})"
            ;;
        *)
            echo -e "${red}杈撳叆閿欒锛屾湭鎵ц鍒囨崲銆?{plain}"
            return 1
            ;;
    esac

    tmp_json=$(mktemp)
    sed 's://.*::g' "$cfg" | jq --arg ds "$rrpip" '.outbounds[0].domain_strategy = $ds' > "$tmp_json"
    cp "$tmp_json" "$cfg"
    rm -f "$tmp_json"

    restart_singbox_if_possible
    echo -e "${blue}褰撳墠宸叉洿鎹㈢殑IP浼樺厛绾э細${tip}${plain}"
}

show_vps_status() {
    # 棰滆壊鍏滃簳锛堥槻姝㈠崟鐙皟鐢ㄦ椂娌″畾涔夛級
    : "${blue:=\033[0;36m}"
    : "${red:=\033[0;31m}"
    : "${plain:=\033[0m}"

    # 鍩虹淇℃伅锛堝敖閲忕嫭绔嬶紝涓嶅己渚濊禆鍏ㄥ眬鍙橀噺锛?
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

    # IP + 鍦板尯
    v4=$(curl -s4m5 icanhazip.com -k || true)
    v6=$(curl -s6m5 icanhazip.com -k || true)
    v4dq=$(curl -s4m5 -k https://ip.fm | sed -n 's/.*Location: //p' 2>/dev/null || true)
    v6dq=$(curl -s6m5 -k https://ip.fm | sed -n 's/.*Location: //p' 2>/dev/null || true)

    # WARP鏍囪瘑
    [[ "${v6:-}" == 2a09* ]] && w6="銆怶ARP銆?
    [[ "${v4:-}" == 104.28* ]] && w4="銆怶ARP銆?

    if [[ -z "${v4:-}" ]]; then
        vps_ipv4='鏃營PV4'
        vps_ipv6="${v6:-鏃營PV6}"
        location="${v6dq:-}"
    elif [[ -n "${v4:-}" && -n "${v6:-}" ]]; then
        vps_ipv4="$v4"
        vps_ipv6="$v6"
        location="${v4dq:-}"
    else
        vps_ipv4="$v4"
        vps_ipv6='鏃營PV6'
        location="${v4dq:-}"
    fi

    [ -z "${location:-}" ] && location="鑾峰彇澶辫触"

    echo -e "VPS鐘舵€佸涓嬶細"
    echo -e "绯荤粺:${blue}${op_local:-unknown}${plain}  鍐呮牳:${blue}${version_local:-unknown}${plain}  澶勭悊鍣?${blue}${cpu_local:-unknown}${plain}  铏氭嫙鍖?${blue}${vi_local}${plain}  BBR绠楁硶:${blue}${bbr_local}${plain}"
    echo -e "鏈湴IPV4鍦板潃锛?{blue}${vps_ipv4}${w4}${plain}   鏈湴IPV6鍦板潃锛?{blue}${vps_ipv6}${w6}${plain}"
    echo -e "鏈嶅姟鍣ㄥ湴鍖猴細${blue}${location}${plain}"

    if ! get_proxy_ip_priority_text; then
        echo -e "浠ｇ悊IP浼樺厛绾э細${red}鏈畨瑁匰ing-box锛堢己灏戦厤缃枃浠讹級鎴栨湭瀹夎jq锛屾棤娉曡鍙?{plain}"
    fi
}

case "${1:-}" in
    --change-ip-priority|-c)
        change_proxy_ip_priority
        show_vps_status
        ;;
    --help|-h)
        echo "鐢ㄦ硶锛?
        echo "  $0                  # 鏄剧ずVPS鐘舵€侊紙鍚唬鐞咺P浼樺厛绾э級"
        echo "  $0 --change-ip-priority|-c  # 浜や簰寮忓垏鎹唬鐞咺P浼樺厛绾у苟鏄剧ず鐘舵€?
        ;;
    *)
        show_vps_status
        ;;
esac
