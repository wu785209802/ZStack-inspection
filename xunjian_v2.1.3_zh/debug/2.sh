#!/bin/bash

function getHealthStatus(){
    echo ""
    echo "############################ 健康检查 ############################"
    rm -f /tmp/error
    cat /proc/loadavg |awk '{if ($3>=10) printf "Urgent:CPU总负载超过10	当前负载 %s\n", $3}'|tee /tmp/error
    load_15=`uptime | awk '{print $NF}'`
    cpu_num=`grep -c 'model name' /proc/cpuinfo`
    free -m |awk 'NR==2 {if($3*100/$2 >=80) printf "Urgent:内存使用超过80%，当前使用率为%.2f%，总内存 %dMB，已用内存%dMB\n", $3*100/$2,$2,$3}'|tee -a /tmp/error
    swap_num=$(free -m |sed -n 3p|awk '{print$2}')
    `ceph version >/dev/null 2>&1`
    val=`echo $?`
    if [[ $val -eq 0 ]];then
        if [ $swap_num = 0 ];then
            echo "没有开启SWAP分区"
        else
            free -m |awk 'NR==3 {if($3*100/$2 >=10) printf "Urgent:Swap使用超过10%，当前使用率为%.2f%，总计 %dMB，已用%dMB\n", $3*100/$2,$2,$3}'|tee -a /tmp/error
        fi
    fi
    df -lhTP | awk '{if($6+0 >= 70) printf "Important:%s 分区使用超过70%，总容量 %s，已用 %s，可用%s \n",$NF,$3,$4,$5}'|column -t | grep -v iso|tee -a /tmp/error
    df -lhiP | awk '{if($5+0 >= 80) printf "Important:%s Inodes使用超过80%，已用%s，可用 %s\n",$1,$3,$4 }'|column -t | grep -v iso|tee -a /tmp/error
    df -lBG | grep ' /$' | awk '{print $2}'| grep -oE [0-9]+ | awk '{if($1 <= 480) printf "Warning:系统盘容量小于480GB，为%sGB \n",$1}' |tee -a /tmp/error

    echo ""
    rm -f /tmp/dmesg
    more /var/log/messages|grep -E '[C]all Trace|[O]ut of memory' |awk '{for(i=3+1;i<=NF;i++)printf $i " ";printf"\n"}'|uniq >/tmp/dmesg
    more /var/log/messages|grep -E '[C]all Trace' |awk '{for(i=3+1;i<=NF;i++)printf $i " ";printf"\n"}'|uniq
    [ -s /tmp/dmesg ] && grep -E '[C]all Trace' /tmp/dmesg && echo "Urgent：Call_Trace_happened" && grep -E '[C]all Trace' /tmp/dmesg
    more /var/log/messages|grep -E '[O]ut of memory' |awk '{for(i=3+1;i<=NF;i++)printf $i " ";printf"\n"}'|uniq
    [ -s /tmp/dmesg ] && grep -E '[O]ut of memory' /tmp/dmesg  && echo "Important：Out_of_memory_happened" && grep -E '[O]ut of memory' /tmp/dmesg
}

getHealthStatus
