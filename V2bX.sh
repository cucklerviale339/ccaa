#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'
install_script_url='https://raw.githubusercontent.com/cucklerviale339/ccaa/master/install.sh'
management_script_url='https://raw.githubusercontent.com/cucklerviale339/ccaa/master/V2bX.sh'
project_url='https://github.com/InazumaV/V2bX'

[[ $EUID -ne 0 ]] && echo -e "${red}错误: ${plain} 必须使用 root 用户运行此脚本！\n" && exit 1

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

before_show_menu() { echo && echo -n -e "${yellow}按回车返回主菜单: ${plain}" && read temp; show_menu; }
confirm_restart() { confirm "是否重启 V2bX" "y" && restart || show_menu; }
show_log() { journalctl -u V2bX.service -e --no-pager -f; [[ $# == 0 ]] && before_show_menu; }
show_V2bX_version() { echo -n "V2bX 版本："; /usr/local/V2bX/V2bX version; echo ""; [[ $# == 0 ]] && before_show_menu; }
generate_x25519_key() { echo -n "正在生成 x25519 密钥："; /usr/local/V2bX/V2bX x25519; echo ""; [[ $# == 0 ]] && before_show_menu; }
check_status() { systemctl is-active --quiet V2bX && return 0 || return 1; }
check_enabled() { systemctl is-enabled --quiet V2bX && return 0 || return 1; }
show_enable_status() { check_enabled && echo -e "是否开机自启: ${green}是${plain}" || echo -e "是否开机自启: ${red}否${plain}"; }
show_status() { check_status && echo -e "V2bX 状态: ${green}已运行${plain}" || echo -e "V2bX 状态: ${yellow}未运行${plain}"; show_enable_status; }
start() { systemctl start V2bX; echo -e "${green}V2bX 启动成功${plain}"; [[ $# == 0 ]] && before_show_menu; }
stop() { systemctl stop V2bX; echo -e "${green}V2bX 停止成功${plain}"; [[ $# == 0 ]] && before_show_menu; }
restart() { systemctl restart V2bX; echo -e "${green}V2bX 重启成功${plain}"; [[ $# == 0 ]] && before_show_menu; }
enable() { systemctl enable V2bX && echo -e "${green}V2bX 设置开机自启成功${plain}" || echo -e "${red}V2bX 设置开机自启失败${plain}"; [[ $# == 0 ]] && before_show_menu; }
disable() { systemctl disable V2bX && echo -e "${green}V2bX 取消开机自启成功${plain}" || echo -e "${red}V2bX 取消开机自启失败${plain}"; [[ $# == 0 ]] && before_show_menu; }
uninstall() { confirm "确定要卸载 V2bX 吗?" "n" || { [[ $# == 0 ]] && show_menu; return 0; }; systemctl stop V2bX; systemctl disable V2bX; rm -f /etc/systemd/system/V2bX.service; systemctl daemon-reload; systemctl reset-failed; rm -rf /etc/V2bX/ /usr/local/V2bX/; echo -e "卸载成功"; [[ $# == 0 ]] && before_show_menu; }
install() { bash <(curl -fsSL "${install_script_url}") "$@"; [[ $# == 0 ]] && start || start 0; }
update() { local version="${2:-}"; bash <(curl -fsSL "${install_script_url}") "${version:-latest}"; echo -e "${green}更新完成${plain}"; exit; }
check_install() { [[ -f /etc/systemd/system/V2bX.service ]] || { echo -e "${red}请先安装 V2bX${plain}"; [[ $# == 0 ]] && before_show_menu; return 1; }; }
open_ports() { systemctl stop firewalld.service 2>/dev/null; systemctl disable firewalld.service 2>/dev/null; ufw disable 2>/dev/null; iptables -P INPUT ACCEPT 2>/dev/null; iptables -P FORWARD ACCEPT 2>/dev/null; iptables -P OUTPUT ACCEPT 2>/dev/null; iptables -t nat -F 2>/dev/null; iptables -t mangle -F 2>/dev/null; iptables -F 2>/dev/null; iptables -X 2>/dev/null; echo -e "${green}放开防火墙端口成功！${plain}"; }
show_usage() { echo "V2bX 后端管理脚本，不适用于 Docker"; }
show_menu() { echo -e "${green}V2bX 后端管理脚本${plain}"; echo "0. 修改配置"; echo "1. 安装 V2bX"; echo "2. 更新 V2bX"; echo "3. 卸载 V2bX"; echo "4. 启动 V2bX"; echo "5. 停止 V2bX"; echo "6. 重启 V2bX"; echo "7. 查看 V2bX 状态"; echo "8. 查看 V2bX 日志"; echo "9. 设置 V2bX 开机自启"; echo "10. 取消 V2bX 开机自启"; echo "11. 一键安装 BBR（最新内核）"; echo "12. 查看 V2bX 版本"; echo "13. 生成 X25519 密钥"; echo "14. 升级 V2bX 维护脚本"; echo "15. 生成 V2bX 配置文件"; echo "16. 放行 VPS 的所有网络端口"; echo "执行 V2bX 或 v2bx 可打开交互菜单。"; }
show_usage
