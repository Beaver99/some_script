#!/bin/bash

RED="\033[31m"      # Error message
GREEN="\033[32m"    # Success message
YELLOW="\033[33m"   # Warning message
BLUE="\033[36m"     # Info message
PLAIN='\033[0m'

OS=`hostnamectl | grep -i system | cut -d: -f2`

V6_PROXY=""
IP=`curl -sL -4 ip.sb`
if [[ "$?" != "0" ]]; then
    IP=`curl -sL -6 ip.sb`
    V6_PROXY=""
fi

CONFIG_FILE="/usr/local/etc/v2ray/config.json"

colorEcho() {
    echo -e "${1}${@:2}${PLAIN}"
}

checkSystem() {
    result=$(id | awk '{print $1}')
    if [ $result != "uid=0(root)" ]; then
        colorEcho $RED " 请以root身份执行该脚本"
        exit 1
    fi

    res=`lsb_release -d | grep -i ubuntu`
    if [ "$?" != "0" ]; then
        res=`which apt`
        if [ "$?" != "0" ]; then
           colorEcho $RED " 系统不是Ubuntu"
            exit 1
        fi
        res=`which systemctl`
         if [ "$?" != "0" ]; then
            colorEcho $RED " 系统版本过低，请重装系统到高版本后再使用本脚本！"
            exit 1
         fi
    else
        result=`lsb_release -d | grep -oE "[0-9.]+"`
        main=${result%%.*}
        if [ $main -lt 16 ]; then
            colorEcho $RED " 不受支持的Ubuntu版本"
            exit 1
        fi
     fi
}

# my custom
getData() {
    while true
    do
        #read -p " 请输入v2ray的端口[1-65535]:" PORT
        #[ -z "$PORT" ] && PORT="21568"
        PORT="31468"
        if [ "${PORT:0:1}" = "0" ]; then
            echo -e " ${RED}端口不能以0开头${PLAIN}"
            exit 1
        fi
        
        expr $PORT + 0 &>/dev/null
        if [ $? -eq 0 ]; then
            if [ $PORT -ge 1 ] && [ $PORT -le 65535 ]; then
                echo ""
                colorEcho $BLUE " 端口号： $PORT"
                echo ""
                break
            else
                colorEcho $RED " 输入错误，端口号为1-65535的数字"
            fi
        else
            colorEcho $RED " 输入错误，端口号为1-65535的数字"
        fi
    done
}

preinstall() {
    colorEcho $BLUE " 更新系统..."
    apt clean all
    apt update
    apt -y upgrade
    colorEcho $BLUE " 安装必要软件"
    apt install -y telnet wget vim net-tools ntpdate unzip selinux-utils
    res=`which wget`
    [ "$?" != "0" ] && apt install -y wget
    res=`which netstat`
    [ "$?" != "0" ] && apt install -y net-tools
    apt autoremove -y
}

installV2ray() {
    setenforce 0

    colorEcho $BLUE " 安装v2ray..."
    #问题出现在这里，config file 空空如也
    #bash <(curl -sL https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh)
    bash <(curl -sL https://raw.githubusercontent.com/Beaver99/some_script/master/goV2.sh)

    if [ ! -f $CONFIG_FILE ]; then
        colorEcho $RED " $OS 安装V2ray失败，请到 https://hijk.art 网站反馈"
        exit 1
    fi

    sed -i -e "s/port\":.*[0-9]*,/port\": ${PORT},/" $CONFIG_FILE

    #alterid=`shuf -i50-80 -n1`
    alterid=`date -u +%-e`
    alterid=`expr $((${alterid} + 49))`
    sed -i -e "s/alterId\":.*[0-9]*/alterId\": ${alterid}/" $CONFIG_FILE

    uid=`grep id $CONFIG_FILE| cut -d: -f2 | tr -d \",' '`
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    ntpdate -u time.nist.gov
    
    systemctl enable v2ray
    systemctl restart v2ray
    sleep 3
    # 问题，启动也没有成功
    res=`netstat -ntlp| grep ${PORT} | grep v2ray`
    if [ "${res}" = "" ]; then
        colorEcho $red " $OS 端口号：${PORT}，v2启动失败，请检查端口是否被占用！"
        #exit 1
    fi
    colorEcho $GREEN " v2ray安装成功！"
}

setFirewall() {
    res=`ufw status | grep -i inactive`
    if [ "$res" = "" ];then
        ufw allow ${PORT}/tcp
        ufw allow ${PORT}/udp
    fi
}

info() {
    if [ ! -f $CONFIG_FILE ]; then
        echo -e " ${RED}未安装v2ray!${PLAIN}"
        exit 1
    fi

    port=`grep port $CONFIG_FILE| cut -d: -f2 | tr -d \",' '`
    res=`netstat -nltp | grep ${port} | grep v2ray`
    [ -z "$res" ] && status="${RED}已停止${PLAIN}" || status="${GREEN}正在运行${PLAIN}"
    uid=`grep id $CONFIG_FILE| cut -d: -f2 | tr -d \",' '`
    alterid=`grep alterId $CONFIG_FILE| cut -d: -f2 | tr -d \",' '`
    res=`grep network $CONFIG_FILE`
    [ -z "$res" ] && network="tcp" || network=`grep network $CONFIG_FILE| cut -d: -f2 | tr -d \",' '`
    security="auto"
        
    raw="{
  \"v\":\"2\",
  \"ps\":\"\",
  \"add\":\"$IP\",
  \"port\":\"${port}\",
  \"id\":\"${uid}\",
  \"aid\":\"$alterid\",
  \"net\":\"tcp\",
  \"type\":\"none\",
  \"host\":\"\",
  \"path\":\"\",
  \"tls\":\"\"
}"
    link=`echo -n ${raw} | base64 -w 0`
    link="vmess://${link}"

    echo ============================================
    echo -e " ${BLUE}v2ray运行状态：${PLAIN}${status}"
    echo -e " ${BLUE}v2ray配置文件：${PLAIN}${RED}$CONFIG_FILE${PLAIN}"
    echo ""
    echo -e " ${RED}v2ray配置信息：${PLAIN}               "
    echo -e "   ${BLUE}IP(address):${PLAIN}  ${RED}${IP}${PLAIN}"
    echo -e "   ${BLUE}端口(port)：${PLAIN}${RED}${port}${PLAIN}"
    echo -e "   ${BLUE}id(uuid)：${PLAIN}${RED}${uid}${PLAIN}"
    echo -e "   ${BLUE}额外id(alterid)：${PLAIN} ${RED}${alterid}${PLAIN}"
    echo -e "   ${BLUE}加密方式(security)：${PLAIN} ${RED}$security${PLAIN}"
    echo -e "   ${BLUE}传输协议(network)：${PLAIN} ${RED}${network}${PLAIN}"
    echo
    echo -e " ${BLUE}vmess链接:${PLAIN} $link"
}


install() {
    echo -n " 系统版本:  "
    lsb_release -a

    checkSystem
    getData
    preinstall
#     installBBR
    installV2ray
    setFirewall
    
    info
#     bbrReboot
}

install
