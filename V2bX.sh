#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'
install_script_url='https://raw.githubusercontent.com/cucklerviale339/ccaa/april-2026-base/install.sh'
management_script_url='https://raw.githubusercontent.com/cucklerviale339/ccaa/april-2026-base/V2bX.sh'
project_url='https://github.com/cucklerviale339/ccaa'

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误: ${plain} 必须使用 root 用户运行此脚本！\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif [ -f /etc/issue ] && grep -Eqi "debian" /etc/issue; then
    release="debian"
elif [ -f /etc/issue ] && grep -Eqi "ubuntu" /etc/issue; then
    release="ubuntu"
elif [ -f /etc/issue ] && grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux" /etc/issue; then
    release="centos"
elif grep -Eqi "debian" /proc/version; then
    release="debian"
elif grep -Eqi "ubuntu" /proc/version; then
    release="ubuntu"
elif grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux" /proc/version; then
    release="centos"
else
    echo -e "${red}未检测到系统版本，请检查运行环境！${plain}\n" && exit 1
fi

# os version
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        echo -e "${red}请使用 CentOS 7 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}请使用 Ubuntu 16 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}请使用 Debian 8 或更高版本的系统！${plain}\n" && exit 1
    fi
fi

confirm() {
    if [[ $# > 1 ]]; then
        echo && read -rp "$1 [默认$2]: " temp
        if [[ x"${temp}" == x"" ]]; then
            temp=$2
        fi
    else
        read -rp "$1 [y/n]: " temp
    fi
    if [[ x"${temp}" == x"y" || x"${temp}" == x"Y" ]]; then
        return 0
    else
        return 1
    fi
}

confirm_restart() {
    confirm "是否重启 V2bX" "y"
    if [[ $? == 0 ]]; then
        restart
    else
        show_menu
    fi
}

before_show_menu() {
    echo && echo -n -e "${yellow}按回车返回主菜单: ${plain}" && read temp
    show_menu
}

install() {
    bash <(curl --proto '=https' --tlsv1.2 -fsSL --retry 5 --retry-delay 2 --retry-max-time 180 "${install_script_url}")
    if [[ $? == 0 ]]; then
        if [[ $# == 0 ]]; then
            start
        else
            start 0
        fi
    fi
}

update() {
    if [[ $# == 0 ]]; then
        echo && echo -n -e "输入指定版本(默认最新版): " && read version
    else
        version=$2
    fi
    bash <(curl --proto '=https' --tlsv1.2 -fsSL --retry 5 --retry-delay 2 --retry-max-time 180 "${install_script_url}") "${version}"
    if [[ $? == 0 ]]; then
        echo -e "${green}更新完成，已自动重启 V2bX，请使用 V2bX log 查看运行日志${plain}"
        exit
    else
        echo -e "${red}更新失败：请检查 GitHub Release 是否可访问，或稍后重试。${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

config() {
    echo "V2bX 在修改配置后会自动尝试重启"
    vi /etc/V2bX/config.json
    sleep 2
    check_status
    case $? in
        0)
            echo -e "V2bX 状态: ${green}已运行${plain}"
            ;;
        1)
            echo -e "检测到 V2bX 未启动或自动重启失败，是否查看日志？[Y/n]" && echo
            read -e -rp "(默认: y):" yn
            [[ -z ${yn} ]] && yn="y"
            if [[ ${yn} == [Yy] ]]; then
               show_log
            fi
            ;;
        2)
            echo -e "V2bX 状态: ${red}未安装${plain}"
    esac
}

uninstall() {
    confirm "确定要卸载 V2bX 吗?" "n"
    if [[ $? != 0 ]]; then
        if [[ $# == 0 ]]; then
            show_menu
        fi
        return 0
    fi
    systemctl stop V2bX
    systemctl disable V2bX
    rm /etc/systemd/system/V2bX.service -f
    systemctl daemon-reload
    systemctl reset-failed
    rm /etc/V2bX/ -rf
    rm /usr/local/V2bX/ -rf

    echo ""
    echo -e "卸载成功，如果你想删除此脚本，则退出脚本后运行 ${green}rm /usr/bin/V2bX -f${plain} 进行删除"
    echo ""

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}
start() {
    check_status
    if [[ $? == 0 ]]; then
        echo ""
        echo -e "${green}V2bX 已运行，无需再次启动，如需重启请选择重启${plain}"
    else
        systemctl start V2bX
        sleep 2
        check_status
        if [[ $? == 0 ]]; then
            echo -e "${green}V2bX 启动成功，请使用 V2bX log 查看运行日志${plain}"
        else
            echo -e "${red}V2bX 可能启动失败，请稍后使用 V2bX log 查看日志信息${plain}"
        fi
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

stop() {
    systemctl stop V2bX
    sleep 2
    check_status
    if [[ $? == 1 ]]; then
        echo -e "${green}V2bX 停止成功${plain}"
    else
        echo -e "${red}V2bX 停止失败，可能是停止时间超过两秒，请稍后查看日志信息${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

restart() {
    systemctl restart V2bX
    sleep 2
    check_status
    if [[ $? == 0 ]]; then
        echo -e "${green}V2bX 重启成功，请使用 V2bX log 查看运行日志${plain}"
    else
        echo -e "${red}V2bX 可能启动失败，请稍后使用 V2bX log 查看日志信息${plain}"
    fi
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

status() {
    systemctl status V2bX --no-pager -l
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

enable() {
    systemctl enable V2bX
    if [[ $? == 0 ]]; then
        echo -e "${green}V2bX 设置开机自启成功${plain}"
    else
        echo -e "${red}V2bX 设置开机自启失败${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

disable() {
    systemctl disable V2bX
    if [[ $? == 0 ]]; then
        echo -e "${green}V2bX 取消开机自启成功${plain}"
    else
        echo -e "${red}V2bX 取消开机自启失败${plain}"
    fi

    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_log() {
    journalctl -u V2bX.service -e --no-pager -f
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

install_bbr() {
    bash <(curl -L -s https://github.com/ylx2016/Linux-NetSpeed/raw/master/tcpx.sh)
}
update_shell() {
    wget -O /usr/bin/V2bX -N --no-check-certificate ${management_script_url}
    if [[ $? != 0 ]]; then
        echo ""
        echo -e "${red}下载脚本失败，请检查本机能否连接 Github${plain}"
        before_show_menu
    else
        chmod +x /usr/bin/V2bX
        ln -sf /usr/bin/V2bX /usr/bin/v2bx
        echo -e "${green}升级脚本成功，请重新运行脚本${plain}" && exit 0
    fi
}
# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f /etc/systemd/system/V2bX.service ]]; then
        return 2
    fi
    temp=$(systemctl status V2bX | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
    if [[ x"${temp}" == x"running" ]]; then
        return 0
    else
        return 1
    fi
}

check_enabled() {
    temp=$(systemctl is-enabled V2bX)
    if [[ x"${temp}" == x"enabled" ]]; then
        return 0
    else
        return 1;
    fi
}

check_uninstall() {
    check_status
    if [[ $? != 2 ]]; then
        echo ""
        echo -e "${red}V2bX 已安装，请不要重复安装${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

check_install() {
    check_status
    if [[ $? == 2 ]]; then
        echo ""
        echo -e "${red}请先安装 V2bX${plain}"
        if [[ $# == 0 ]]; then
            before_show_menu
        fi
        return 1
    else
        return 0
    fi
}

show_status() {
    check_status
    case $? in
        0)
            echo -e "V2bX 状态: ${green}已运行${plain}"
            show_enable_status
            ;;
        1)
            echo -e "V2bX 状态: ${yellow}未运行${plain}"
            show_enable_status
            ;;
        2)
            echo -e "V2bX 状态: ${red}未安装${plain}"
    esac
}

show_enable_status() {
    check_enabled
    if [[ $? == 0 ]]; then
        echo -e "是否开机自启: ${green}是${plain}"
    else
        echo -e "是否开机自启: ${red}否${plain}"
    fi
}

generate_x25519_key() {
    echo -n "正在生成 x25519 密钥："
    /usr/local/V2bX/V2bX x25519
    echo ""
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

show_V2bX_version() {
    echo -n "V2bX 版本："
    /usr/local/V2bX/V2bX version
    echo ""
    if [[ $# == 0 ]]; then
        before_show_menu
    fi
}

json_escape() {
    printf '%s' "$1" | sed \
        -e 's/\\/\\\\/g' \
        -e 's/"/\\"/g' \
        -e 's/	/\\t/g'
}

mask_secret() {
    local secret="$1"
    local length=${#secret}
    if [ "$length" -le 8 ]; then
        printf '已填写（长度 %s）' "$length"
    else
        printf '%s****%s' "${secret:0:4}" "${secret: -4}"
    fi
}

show_panel_info() {
    echo -e "${yellow}当前面板网址：${plain}${ApiHost}"
    echo -e "${yellow}当前 API Key：${plain}$(mask_secret "$ApiKey")"
}

read_panel_info() {
    echo -e "${yellow}请输入面板对接信息：${plain}"
    while true; do
        echo "1. 面板网址(ApiHost)"
        read -r ApiHost
        if [ -n "$ApiHost" ]; then
            break
        fi
        echo -e "${red}面板网址不能为空，请重新输入。${plain}"
    done

    while true; do
        echo "2. 面板对接 API Key(ApiKey)"
        read -r ApiKey
        if [ -n "$ApiKey" ]; then
            break
        fi
        echo -e "${red}API Key 不能为空，请重新输入。${plain}"
    done
}

select_dns_strategy() {
    echo -e "${yellow}请选择域名解析策略：${plain}"
    echo -e "${green}1. IPv4 优先/仅 IPv4（默认）${plain}"
    echo -e "${green}2. IPv6 优先/仅 IPv6${plain}"
    echo -e "${green}3. AsIs${plain}"
    read -rp "请输入：" dns_strategy_choice
    case "$dns_strategy_choice" in
        2)
            xray_dns_strategy="UseIPv6"
            sing_domain_strategy="ipv6_only"
            ;;
        3)
            xray_dns_strategy="AsIs"
            sing_domain_strategy="as_is"
            ;;
        *)
            xray_dns_strategy="UseIPv4"
            sing_domain_strategy="ipv4_only"
            ;;
    esac
}

select_source_bound_egress() {
    echo -e "${yellow}请选择源进源出设置：${plain}"
    echo -e "${green}1. 自动源进源出（默认，按入站来源自动选择出站）${plain}"
    echo -e "${green}2. 指定 SendIP（手动绑定出站 IP）${plain}"
    echo -e "${green}3. 关闭源进源出（SendIP 使用 0.0.0.0）${plain}"
    read -rp "请输入：" source_bound_choice
    case "$source_bound_choice" in
        2)
            auto_send_through_origin=true
            read -rp "请输入 SendIP：" send_ip
            [ -n "$send_ip" ] || send_ip="0.0.0.0"
            ;;
        3)
            auto_send_through_origin=false
            send_ip="0.0.0.0"
            ;;
        *)
            auto_send_through_origin=true
            send_ip="0.0.0.0"
            ;;
    esac
}

sing_uot_supported_protocol() {
    case "$NodeType" in
        shadowsocks|vless|vmess|tuic|anytls)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

select_uot_config() {
    enable_uot=false
    enable_uot_config_line=""
    if [ "$core" = "sing" ]; then
        if sing_uot_supported_protocol; then
            enable_uot=true
            enable_uot_config_line='            "EnableUot": true,'
        fi
        return
    fi
}

select_cert_config() {
    echo -e "${yellow}请选择 TLS/SNI 证书配置：${plain}"
    if [[ "$NodeType" == "hysteria2" || "$NodeType" == "anytls" ]]; then
        echo -e "${red}提示：${NodeType} 通常必须配置证书/SNI，否则节点可能无法正常使用。${plain}"
    fi
    echo -e "${green}1. 不配置证书（CertMode: none，默认）${plain}"
    echo -e "${green}2. 使用已有证书文件（CertMode: file）${plain}"
    echo -e "${green}3. HTTP 自动签发证书（CertMode: http）${plain}"
    echo -e "${green}4. DNS 自动签发证书（CertMode: dns）${plain}"
    echo -e "${green}5. 自签证书（CertMode: self）${plain}"
    read -rp "请输入：" cert_mode_choice

    case "$cert_mode_choice" in
        2) cert_mode="file" ;;
        3) cert_mode="http" ;;
        4) cert_mode="dns" ;;
        5) cert_mode="self" ;;
        *) cert_mode="none" ;;
    esac

    if [ "$cert_mode" = "none" ]; then
        cert_config='{
                "CertMode": "none"
            }'
        return
    fi

    while true; do
        echo "1. 证书域名/SNI(CertDomain)"
        read -r cert_domain
        if [ -n "$cert_domain" ]; then
            break
        fi
        echo -e "${red}证书域名/SNI 不能为空，请重新输入。${plain}"
    done

    cert_file="/etc/V2bX/fullchain.cer"
    key_file="/etc/V2bX/cert.key"
    echo "2. 是否拒绝未知 SNI？(y/n，默认 n)"
    read -r reject_unknown_sni_input
    if [[ "$reject_unknown_sni_input" == [Yy] ]]; then
        reject_unknown_sni=true
    else
        reject_unknown_sni=false
    fi

    local escaped_cert_domain escaped_cert_file escaped_key_file escaped_provider escaped_email dns_env_config acme_config_lines
    escaped_cert_domain=$(json_escape "$cert_domain")
    escaped_cert_file=$(json_escape "$cert_file")
    escaped_key_file=$(json_escape "$key_file")
    escaped_provider=""
    escaped_email=""
    dns_env_config="{}"
    acme_config_lines=""

    if [[ "$cert_mode" == "http" || "$cert_mode" == "dns" ]]; then
        echo "3. ACME 邮箱(Email)"
        read -r cert_email
        escaped_email=$(json_escape "$cert_email")
        acme_config_lines="${acme_config_lines},
                \"Email\": \"$escaped_email\""
    fi

    if [ "$cert_mode" = "dns" ]; then
        echo "4. DNS Provider（如 cloudflare/alidns）"
        read -r cert_provider
        escaped_provider=$(json_escape "$cert_provider")
        acme_config_lines="${acme_config_lines},
                \"Provider\": \"$escaped_provider\""
        dns_env_entries=""
        echo "请输入 DNS API 环境变量，格式 KEY=VALUE；直接回车结束："
        while true; do
            read -r dns_env_line
            [ -n "$dns_env_line" ] || break
            if [[ "$dns_env_line" != *=* ]]; then
                echo -e "${red}格式错误，请使用 KEY=VALUE。${plain}"
                continue
            fi
            dns_env_key=${dns_env_line%%=*}
            dns_env_value=${dns_env_line#*=}
            escaped_dns_env_key=$(json_escape "$dns_env_key")
            escaped_dns_env_value=$(json_escape "$dns_env_value")
            if [ -n "$dns_env_entries" ]; then
                dns_env_entries="${dns_env_entries},
                    \"${escaped_dns_env_key}\": \"${escaped_dns_env_value}\""
            else
                dns_env_entries="\"${escaped_dns_env_key}\": \"${escaped_dns_env_value}\""
            fi
        done
        if [ -n "$dns_env_entries" ]; then
            dns_env_config="{
                    ${dns_env_entries}
                }"
        fi
        acme_config_lines="${acme_config_lines},
                \"DNSEnv\": $dns_env_config"
    fi

    cert_config=$(cat <<EOF_CERT
{
                "CertMode": "$cert_mode",
                "RejectUnknownSni": $reject_unknown_sni,
                "CertDomain": "$escaped_cert_domain",
                "CertFile": "$escaped_cert_file",
                "KeyFile": "$escaped_key_file"$acme_config_lines
            }
EOF_CERT
)
}

add_node_config() {
    echo -e "${green}请选择节点核心类型：${plain}"
    echo -e "${green}1. xray${plain}"
    echo -e "${green}2. singbox${plain}"
    echo -e "${green}3. hysteria2${plain}"
    read -rp "请输入：" core_type

    case "$core_type" in
        1)
            core="xray"
            core_xray=true
            ;;
        2)
            core="sing"
            core_sing=true
            ;;
        3)
            core="hysteria2"
            core_hysteria2=true
            ;;
        *)
            echo "无效的选择。请选择 1、2 或 3。"
            return 1
            ;;
    esac

    while true; do
        read -rp "请输入节点 Node ID：" NodeID
        if [[ "$NodeID" =~ ^[0-9]+$ ]]; then
            break
        else
            echo "错误：请输入正确的数字作为 Node ID。"
        fi
    done

    echo -e "${yellow}请选择节点传输协议：${plain}"
    case "$core" in
        xray)
            echo -e "${green}1. Shadowsocks${plain}"
            echo -e "${green}2. Vless${plain}"
            echo -e "${green}3. Vmess${plain}"
            echo -e "${green}4. Trojan${plain}"
            read -rp "请输入：" NodeType
            case "$NodeType" in
                1) NodeType="shadowsocks" ;;
                2) NodeType="vless" ;;
                3) NodeType="vmess" ;;
                4) NodeType="trojan" ;;
                *) NodeType="shadowsocks" ;;
            esac
            ;;
        sing)
            echo -e "${green}1. Shadowsocks${plain}"
            echo -e "${green}2. Vless${plain}"
            echo -e "${green}3. Vmess${plain}"
            echo -e "${green}4. Hysteria${plain}"
            echo -e "${green}5. Hysteria2${plain}"
            echo -e "${green}6. Tuic${plain}"
            echo -e "${green}7. Trojan${plain}"
            echo -e "${green}8. AnyTLS${plain}"
            read -rp "请输入：" NodeType
            case "$NodeType" in
                1) NodeType="shadowsocks" ;;
                2) NodeType="vless" ;;
                3) NodeType="vmess" ;;
                4) NodeType="hysteria" ;;
                5) NodeType="hysteria2" ;;
                6) NodeType="tuic" ;;
                7) NodeType="trojan" ;;
                8) NodeType="anytls" ;;
                *) NodeType="shadowsocks" ;;
            esac
            ;;
        hysteria2)
            echo -e "${green}1. Hysteria2${plain}"
            read -rp "请输入：" NodeType
            NodeType="hysteria2"
            ;;
    esac

    local escaped_api_host escaped_api_key
    escaped_api_host=$(json_escape "$ApiHost")
    escaped_api_key=$(json_escape "$ApiKey")
    enable_uot_config_line=""
    select_dns_strategy
    select_source_bound_egress
    select_uot_config
    select_cert_config
    dns_strategy_config_line=""
    case "$core" in
        sing) dns_strategy_config_line="            \"DomainStrategy\": \"$sing_domain_strategy\"," ;;
        xray) dns_strategy_config_line="            \"DNSType\": \"$xray_dns_strategy\"," ;;
    esac

    node_config=$(cat <<EOF_NODE
        {
            "Core": "$core",
            "ApiHost": "$escaped_api_host",
            "ApiKey": "$escaped_api_key",
            "NodeID": $NodeID,
            "NodeType": "$NodeType",
            "Timeout": 30,
            "ListenIP": "0.0.0.0",
            "SendIP": "$send_ip",
            "EnableProxyProtocol": false,
${enable_uot_config_line}
            "EnableTFO": true,
${dns_strategy_config_line}
            "AutoSendThroughOrigin": $auto_send_through_origin,
            "CertConfig": $cert_config
        }
EOF_NODE
)
    nodes_config+=("$node_config")
}

generate_config_file() {
    echo -e "${yellow}V2bX 配置文件生成向导${plain}"
    echo -e "${red}请阅读以下注意事项：${plain}"
    echo -e "${red}1. 生成的配置文件会保存到 /etc/V2bX/config.json${plain}"
    echo -e "${red}2. 原来的配置文件会保存到 /etc/V2bX/config.json.bak${plain}"
    echo -e "${red}3. 使用此功能生成的配置文件会自带审计，确定继续？(y/n)${plain}"
    read -rp "请输入：" continue_prompt
    if [[ "$continue_prompt" =~ ^[Nn][Oo]? ]]; then
        exit 0
    fi
    
    nodes_config=()
    first_node=true
    core_xray=false
    core_sing=false
    core_hysteria2=false
    fixed_api_info=false
    check_api=false
    
    while true; do
        if [ "$first_node" = true ]; then
            read_panel_info
            read -rp "是否固定面板网址和 API Key？(y/n)" fixed_api
            if [ "$fixed_api" = "y" ] || [ "$fixed_api" = "Y" ]; then
                fixed_api_info=true
                echo -e "${red}已固定面板网址和 API Key，后续节点将复用当前信息${plain}"
            fi
            first_node=false
            show_panel_info
            add_node_config
        else
            read -rp "是否继续添加节点配置？(回车继续，输入 n 或 no 退出)" continue_adding_node
            if [[ "$continue_adding_node" =~ ^[Nn][Oo]? ]]; then
                break
            elif [ "$fixed_api_info" = false ]; then
                read_panel_info
            fi
            show_panel_info
            add_node_config
        fi
    done

    core_entries=()
    if [ "$core_xray" = true ]; then
        core_entries+=("{
            \"Type\": \"xray\",
            \"Log\": {
                \"Level\": \"error\",
                \"ErrorPath\": \"/etc/V2bX/error.log\"
            },
            \"OutboundConfigPath\": \"/etc/V2bX/custom_outbound.json\",
            \"RouteConfigPath\": \"/etc/V2bX/route.json\"
        }")
    fi
    if [ "$core_sing" = true ]; then
        core_entries+=("{
            \"Type\": \"sing\",
            \"Log\": {
                \"Level\": \"error\",
                \"Timestamp\": true
            },
            \"NTP\": {
                \"Enable\": false,
                \"Server\": \"time.apple.com\",
                \"ServerPort\": 0
            }
        }")
    fi
    if [ "$core_hysteria2" = true ]; then
        core_entries+=("{
            \"Type\": \"hysteria2\",
            \"Log\": {
                \"Level\": \"error\"
            }
        }")
    fi
    cores_config="[$(IFS=,; echo "${core_entries[*]}")]"

    # 切换到配置文件目录
    mkdir -p /etc/V2bX
    cd /etc/V2bX || return 1
    
    # 备份旧的配置文件
    if [ -f config.json ]; then
        cp -f config.json config.json.bak
    fi
    formatted_nodes_config=""
    for node_config in "${nodes_config[@]}"; do
        if [ -n "$formatted_nodes_config" ]; then
            formatted_nodes_config="${formatted_nodes_config},
${node_config}"
        else
            formatted_nodes_config="$node_config"
        fi
    done

    
    # 创建 config.json 文件
    cat <<EOF > /etc/V2bX/config.json
    {
        "Log": {
            "Level": "error",
            "Output": ""
        },
        "Cores": $cores_config,
        "Nodes": [
$formatted_nodes_config
        ]

    }
EOF
    
    # 创建 custom_outbound.json 文件
    cat <<EOF > /etc/V2bX/custom_outbound.json
    [
        {
            "tag": "IPv4_out",
            "protocol": "freedom",
            "settings": {
                "domainStrategy": "UseIPv4"
            }
        },
        {
            "tag": "IPv6_out",
            "protocol": "freedom",
            "settings": {
                "domainStrategy": "UseIPv6"
            }
        },
        {
            "tag": "direct",
            "protocol": "freedom"
        },
        {
            "protocol": "blackhole",
            "tag": "block"
        }
    ]
EOF
    
    # 创建 route.json 文件
    cat <<EOF > /etc/V2bX/route.json
    {
        "domainStrategy": "AsIs",
        "rules": [
            {
                "type": "field",
                "outboundTag": "block",
                "ip": [
                    "geoip:private",
                    "58.87.70.69"
                ]
            },
            {
                "type": "field",
                "outboundTag": "direct",
                "domain": [
                    "domain:zgovps.com"
                ]
            },
            {
                "type": "field",
                "outboundTag": "block",
                "domain": [
                    "regexp:(api|ps|sv|offnavi|newvector|ulog.imap|newloc)(.map|).(baidu|n.shifen).com",
                    "regexp:(.+.|^)(360|so).(cn|com)",
                    "regexp:(Subject|HELO|SMTP)",
                    "regexp:(torrent|.torrent|peer_id=|info_hash|get_peers|find_node|BitTorrent|announce_peer|announce.php?passkey=)",
                    "regexp:(^.@)(guerrillamail|guerrillamailblock|sharklasers|grr|pokemail|spam4|bccto|chacuo|027168).(info|biz|com|de|net|org|me|la)",
                    "regexp:(.?)(xunlei|sandai|Thunder|XLLiveUD)(.)",
                    "regexp:(..||)(dafahao|mingjinglive|botanwang|minghui|dongtaiwang|falunaz|epochtimes|ntdtv|falundafa|falungong|wujieliulan|zhengjian).(org|com|net)",
                    "regexp:(ed2k|.torrent|peer_id=|announce|info_hash|get_peers|find_node|BitTorrent|announce_peer|announce.php?passkey=|magnet:|xunlei|sandai|Thunder|XLLiveUD|bt_key)",
                    "regexp:(.+.|^)(360|speedtest|fast).(cn|com|net)",
                    "regexp:(.*.||)(guanjia.qq.com|qqpcmgr|QQPCMGR)",
                    "regexp:(.*.||)(rising|kingsoft|duba|xindubawukong|jinshanduba).(com|net|org)",
                    "regexp:(.*.||)(netvigator|torproject).(com|cn|net|org)",
                    "regexp:(..||)(visa|mycard|gov|gash|beanfun|bank).",
                    "regexp:(.*.||)(gov|12377|12315|talk.news.pts.org|creaders|zhuichaguoji|efcc.org|cyberpolice|aboluowang|tuidang|epochtimes|nytimes|zhengjian|110.qq|mingjingnews|inmediahk|xinsheng|breakgfw|chengmingmag|jinpianwang|qi-gong|mhradio|edoors|renminbao|soundofhope|xizang-zhiye|bannedbook|ntdtv|12321|secretchina|dajiyuan|boxun|chinadigitaltimes|dwnews|huaglad|oneplusnews|epochweekly|cn.rfi).(cn|com|org|net|club|net|fr|tw|hk|eu|info|me)",
                    "regexp:(.*.||)(miaozhen|cnzz|talkingdata|umeng).(cn|com)",
                    "regexp:(.*.||)(mycard).(com|tw)",
                    "regexp:(.*.||)(gash).(com|tw)",
                    "regexp:(.bank.)",
                    "regexp:(.*.||)(pincong).(rocks)",
                    "regexp:(.*.||)(taobao).(com)",
                    "regexp:(.*.||)(laomoe|jiyou|ssss|lolicp|vv1234|0z|4321q|868123|ksweb|mm126).(com|cloud|fun|cn|gs|xyz|cc)",
                    "regexp:(flows|miaoko).(pages).(dev)"
                ]
            },
            {
                "type": "field",
                "outboundTag": "block",
                "ip": [
                    "127.0.0.1/32",
                    "10.0.0.0/8",
                    "fc00::/7",
                    "fe80::/10",
                    "172.16.0.0/12"
                ]
            },
            {
                "type": "field",
                "outboundTag": "block",
                "protocol": [
                    "bittorrent"
                ]
            },
            {
                "type": "field",
                "outboundTag": "block",
                "port": "23,24,25,107,194,445,465,587,992,3389,6665-6669,6679,6697,6881-6999,7000"
            }
        ]
    }
EOF
                

    echo -e "${green}V2bX 配置文件生成完成，正在重新启动 V2bX 服务${plain}"
    restart 0
    before_show_menu
}

# 放开防火墙端口
open_ports() {
    systemctl stop firewalld.service 2>/dev/null
    systemctl disable firewalld.service 2>/dev/null
    setenforce 0 2>/dev/null
    ufw disable 2>/dev/null
    iptables -P INPUT ACCEPT 2>/dev/null
    iptables -P FORWARD ACCEPT 2>/dev/null
    iptables -P OUTPUT ACCEPT 2>/dev/null
    iptables -t nat -F 2>/dev/null
    iptables -t mangle -F 2>/dev/null
    iptables -F 2>/dev/null
    iptables -X 2>/dev/null
    netfilter-persistent save 2>/dev/null
    echo -e "${green}放开防火墙端口成功！${plain}"
}
show_usage() {
    echo "V2bX 后端管理脚本，不适用于 Docker"
    echo "------------------------------------------"
    echo "0.  修改配置"
    echo "------------------------------------------"
    echo "1.  安装 V2bX"
    echo "2.  更新 V2bX"
    echo "3.  卸载 V2bX"
    echo "------------------------------------------"
    echo "4.  启动 V2bX"
    echo "5.  停止 V2bX"
    echo "6.  重启 V2bX"
    echo "7.  查看 V2bX 状态"
    echo "8.  查看 V2bX 日志"
    echo "------------------------------------------"
    echo "9.  设置 V2bX 开机自启"
    echo "10. 取消 V2bX 开机自启"
    echo "------------------------------------------"
    echo "11. 一键安装 BBR（最新内核）"
    echo "12. 查看 V2bX 版本"
    echo "13. 生成 X25519 密钥"
    echo "14. 升级 V2bX 维护脚本"
    echo "15. 生成 V2bX 配置文件"
    echo "16. 放行 VPS 的所有网络端口"
    echo "------------------------------------------"
    echo "执行 V2bX 或 v2bx 可打开交互菜单。"
}


show_menu() {
    echo -e "
  ${green}V2bX 后端管理脚本，${plain}${red}不适用于 Docker${plain}
--- ${project_url} ---
  ${green}0.${plain} 修改配置
————————————————
  ${green}1.${plain} 安装 V2bX
  ${green}2.${plain} 更新 V2bX
  ${green}3.${plain} 卸载 V2bX
————————————————
  ${green}4.${plain} 启动 V2bX
  ${green}5.${plain} 停止 V2bX
  ${green}6.${plain} 重启 V2bX
  ${green}7.${plain} 查看 V2bX 状态
  ${green}8.${plain} 查看 V2bX 日志
————————————————
  ${green}9.${plain} 设置 V2bX 开机自启
  ${green}10.${plain} 取消 V2bX 开机自启
————————————————
  ${green}11.${plain} 一键安装 BBR（最新内核）
  ${green}12.${plain} 查看 V2bX 版本
  ${green}13.${plain} 生成 X25519 密钥
  ${green}14.${plain} 升级 V2bX 维护脚本
  ${green}15.${plain} 生成 V2bX 配置文件
  ${green}16.${plain} 放行 VPS 的所有网络端口
 "
    show_status
    echo && read -rp "请输入选择 [0-16]: " num

    case "${num}" in
        0) config ;;
        1) check_uninstall && install ;;
        2) check_install && update ;;
        3) check_install && uninstall ;;
        4) check_install && start ;;
        5) check_install && stop ;;
        6) check_install && restart ;;
        7) check_install && status ;;
        8) check_install && show_log ;;
        9) check_install && enable ;;
        10) check_install && disable ;;
        11) install_bbr ;;
        12) check_install && show_V2bX_version ;;
        13) check_install && generate_x25519_key ;;
        14) update_shell ;;
        15) generate_config_file ;;
        16) open_ports ;;
        *) echo -e "${red}请输入正确的数字 [0-16]${plain}" ;;
    esac
}


if [[ $# > 0 ]]; then
    case $1 in
        "start") check_install 0 && start 0 ;;
        "stop") check_install 0 && stop 0 ;;
        "restart") check_install 0 && restart 0 ;;
        "status") check_install 0 && status 0 ;;
        "enable") check_install 0 && enable 0 ;;
        "disable") check_install 0 && disable 0 ;;
        "log") check_install 0 && show_log 0 ;;
        "update") check_install 0 && update 0 "$2" ;;
        "config") config "$@" ;;
        "generate") generate_config_file ;;
        "install") check_uninstall 0 && install 0 ;;
        "uninstall") check_install 0 && uninstall 0 ;;
        "x25519") check_install 0 && generate_x25519_key 0 ;;
        "version") check_install 0 && show_V2bX_version 0 ;;
        "update_shell") update_shell ;;
        *) show_usage
    esac
else
    show_menu
fi
