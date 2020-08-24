#####################################
# @Author: wuqiuyang 
# @Created Time: 2020-08-18 09:33:01
# @Description: 
#####################################
#!/bin/bash


function getTimeSyncStatus(){
    #时间同步服务状态，当前时间，配置等
    echo ""
    echo "############################ 时间同步检查 #############################"
    if [ `pgrep chronyd` ];then
        echo ""
        chronyc sources -v
        echo ""
        echo "Chrony服务配置:"
        cat /etc/chrony.conf|grep -v "^#"|tr -s '\n' 
        chronyc sources -v | grep ? | grep -v unreachable
        if [ $? -eq 0 ];then echo Chrony_server_is_unreachable_please_check;fi
        #报表信息
        report_NTP="$(getState chronyd)"
    elif [ `pgrep ntp` ];then
        echo ""
        ntpq -np
        echo ""
        echo "NTP服务配置:"
        cat /etc/ntp.conf|grep -v ^# |tr -s '\n'
        #报表信息
        report_NTP="$(getState ntpd)"
    fi   
    echo ""
    echo '系统时间:'
    timedatectl
    hwclock
}

getTimeSyncStatus
