#!/bin/bash
export PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/root/bin
source /etc/profile

#日志相关
PROGPATH=`echo $0 | sed -e 's,[\\/][^\\/][^\\/]*$,,'`
[ -f $PROGPATH ] && PROGPATH="."
LOGPATH="$PROGPATH/log"
[ -e $LOGPATH ] || mkdir $LOGPATH
RESULTFILE="$LOGPATH/HostDailyCheck-`hostname`-`date +%Y%m%d`.txt"

DateTime=$(date +"%F %T")
HostName=$(hostname)
OsRelease=$(cat /etc/redhat-release)
KernelRelease=$(uname -r)
SeLinux=$(/usr/sbin/sestatus | grep "SELinux status: " | awk '{print $3}')
LastReboot=$(who -b | awk '{print $3,$4}')
OpenProcesNum=$(expr $(ps aux | wc -l) - 1)
UpTime=$(uptime | sed 's/.*up \([^,]*\), .*/\1/')
CpuCoreNumber=$(cat /proc/cpuinfo |grep -c processor)
CpuLoad=$(cat /proc/loadavg|awk '{print $3}')
UsedMemory=$(free -m | awk 'NR==2{printf "%sMB/%sMB (%.2f%%)\n", $3,$2,$3*100/$2 }')
SwapValue=$(free -m |sed -n 3p|awk '{print$2}')
if [[ $SwapValue != 0 ]];then
    UsedSwap=$(free -m | awk 'NR==3{printf "%sMB/%sMB (%.2f%%)\n", $3,$2,$3*100/$2 }')
else
    UsedSwap=0
fi
UsedSystemDisk=$(df -lh | awk '$NF=="/"{printf "%s/%s (%s)\n", $3,$2,$5}')
SystemDisk=$(df -lh |grep "/boot$"|awk '{print$1}'|sed 's/[0-9]//')
centosVersion=$(awk '{print $(NF-1)}' /etc/redhat-release)


function get_system_info () {
cat<<EOF
+-----------------------------------------------+
|               #系统的相关信息#                |
+-----------------------------------------------+
EOF
    echo "系统发行版本: $OsRelease"
    echo ""
    if [[ -e /etc/sysconfig/i18n ]];then
        default_LANG="$(grep "LANG=" /etc/sysconfig/i18n | grep -v "^#" | awk -F '"' '{print $2}')"
    else
        default_LANG=$LANG
    fi
    export LANG="en_US.UTF-8"
    echo "系统语言编码: $default_LANG"
    echo ""
    echo "CPU核心数: $CpuCoreNumber"
    echo ""
    echo "系统盘使用: $UsedSystemDisk"
    echo ""
    echo "系统盘盘符: $SystemDisk"
    echo ""
    echo "主机名称: $HostName"
    echo ""
    echo "内核版本: $KernelRelease"
    echo ""
    echo "当前时间: $DateTime"
    echo ""
    echo "运行时间: $UpTime"
    echo ""
    echo "SELinux: $SeLinux"
    echo ""
    echo "最后启动: $LastReboot"
    echo ""
    echo "进程数量: $OpenProcesNum"
    echo ""
    echo "系统负载: $CpuLoad"
    echo ""
    echo "已用内存: $UsedMemory"
    echo ""
    echo "已用Swap: $UsedSwap"
    echo ""
}


function check_cpu_c_state(){
cat<<EOF
+-------------------------------------------------------+
|               #检查CPU C State是否打开#               |
+-------------------------------------------------------+
EOF
    Hostname=$(uname -n)
    CPU_list=$(cat /proc/cpuinfo | grep 'cpu MHz' | awk -F " " '{print $4}')
    flag_1=$(cat /proc/cpuinfo | grep 'cpu MHz' | awk -F " " 'NR==1 {print $4}')
    flag_2=0
    if [[ $flag_2 = 0 ]];then
        for i in ${CPU_list[@]}
        do
            if [[ "$flag_1" != "$i" ]];then
                flag_2=1
                break
            fi
        done
        if [[ $flag_2 = 1 ]];then
            echo "Urgent: $Hostname CPU C State is enable"
            echo ""
        else
            echo "Normal: $Hostname CPU C state is disable"
            echo ""
        fi
    fi
}

function check_temperature(){
cat<<EOF
+---------------------------------------------------+
|               #检查CPU温度是否过高#               |
+---------------------------------------------------+
EOF
    Hostname=$(uname -n)
    temperature_str="temperature above threshold"
    temperature_log=`cat /var/log/messages* | grep "temperature above threshold"`
    if [[ "$temperature_log" =~ "$temperature_str" ]];then
        echo "Warning: $Hostname CPU temperature too high"
        echo ""
    else
        echo "Normal: $Hostname CPU temperature is ok"
        echo ""
    fi
}

function get_cpu_info(){
cat<<EOF
+-----------------------------------------------+
|               #获取CPU详细信息#               |
+-----------------------------------------------+
EOF
    Physical_CPUs=$(grep "physical id" /proc/cpuinfo| sort | uniq | wc -l)
    Virt_CPUs=$(grep "processor" /proc/cpuinfo | wc -l)
    CPU_Kernels=$(grep "cores" /proc/cpuinfo|uniq| awk -F ': ' '{print $2}')
    CPU_Type=$(grep "model name" /proc/cpuinfo | awk -F ': ' '{print $2}' | sort | uniq)
    CPU_Arch=$(uname -m)
    echo "物理CPU颗数: $Physical_CPUs"
    echo ""
    echo "逻辑CPU个数: $Virt_CPUs"
    echo ""
    echo "每CPU核心数: $CPU_Kernels"
    echo ""
    echo "CPU型号: $CPU_Type"
    echo ""
    echo "CPU架构: $CPU_Arch"
    echo ""

}

function get_qemu_process_list(){
cat<<EOF
+------------------------------------------------+
|               #获取qemu进程列表#               |
+------------------------------------------------+
EOF
    NameList=$(ps -ef|grep [q]emu-kvm |awk -F "guest=|," '{print $2}'|tr -s '\n')
    echo "$NameList"
    echo ""
}

function get_virsh_list_running_npaused(){
cat<<EOF
+--------------------------------------------------+
|               #获取virsh list列表#               |
+--------------------------------------------------+
EOF
VirshList=$(virsh list|sed  '1,2d'|awk '{print $2}'|tr -s '\n')
   echo "$VirshList"
   echo ""
}

function get_mem_status(){
cat<<EOF
+------------------------------------------------+
|               #获取内存状态信息#               |
+------------------------------------------------+
EOF
    free -h
    echo ""
    echo "System Memory RSS Info: "  
    echo "`ps -eo rss 2>/dev/null | awk '/[0-9]/{total += $1 * 1024} END {printf "%.2f", total/1024/1024/1024}'`GB"
    echo ""
    echo "System VM info: "
    sysctl vm.swappiness
    sysctl vm.dirty_ratio
    sysctl vm.dirty_background_ratio
    sysctl vm.dirty_bytes
    sysctl vm.dirty_background_bytes
    echo ""
}

function check_disk_status(){
cat<<EOF
+----------------------------------------------+
|               #检查磁盘的信息#               |
+----------------------------------------------+
EOF
    df -lhiP | sed 's/Mounted on/Mounted/'> /tmp/inode
    df -lhTP | sed 's/Mounted on/Mounted/'> /tmp/disk
    join /tmp/disk /tmp/inode | awk '{print $1,$2,"|",$3,$4,$5,$6,"|",$8,$9,$10,$11,"|",$12}'| column -t
    echo ""
    echo "系统磁盘调度程序和队列大小: "
    for disk in $(ls /sys/block/ | grep -v -e ram -e loop -e 'fd[0-9]'); do
        if [ -e "/sys/block/${disk}/queue/scheduler" ]; then
            echo "${disk}" "$(cat /sys/block/${disk}/queue/scheduler | grep -o '\[.*\]') $(cat /sys/block/${disk}/queue/nr_requests)"
        fi
    done
    echo ""
cat<<EOF
+-----------------------------------------------+
|               #检查inode的信息#               |
+-----------------------------------------------+
EOF
    inodestat=$(df -li |grep  '/$' | awk '{print$2}')
    echo ""
    if [[ $inodestat -lt 1000000 ]];then
    	echo "Important: inode总量小于100W"
        echo ""
    else
    	echo "Normal: inode总量大于100W"
        echo ""
    fi
    inodeusestat=$(expr 100 - `df -li |grep  '/$' | awk '{print$5}'|sed 's/%//g'`)
    if [[ $inodeusestat -lt 20 ]];then
        echo "Important: inode可用量低于20%"
        echo ""
    else
    	echo "Normal: inode可用量大于20%"
        echo ""
    fi
    inodedata=$(df -liTP | sed '1d' | awk '$2!="tmpfs"{print}')
    inodetotal=$(echo "$inodedata" | awk '{total+=$3}END{print total}')
    inodeused=$(echo "$inodedata" | awk '{total+=$4}END{print total}')
    inodefree=$((inodetotal-inodeused))
    inodeusedpercent=$(echo $inodetotal $inodeused | awk '{if($1==0){printf 100}else{printf "%.2f",$2*100/$1}}')
    report_InodeTotal=$((inodetotal/1000))"K"       #Inode总量
    report_InodeFree=$((inodefree/1000))"K"         #Inode剩余
    report_InodeUsedPercent="$inodeusedpercent""%"  #Inode使用率%
    echo "Inode总量: $report_InodeTotal"
    echo ""
    echo "Inode剩余: $report_InodeFree"
    echo ""
    echo "Inode使用: $report_InodeUsedPercent"
    echo ""
    echo "LVM Volumes Info: "
    lvs
    echo ""
    echo "fstab Info: "
    cat /etc/fstab|grep -v ^#
    echo ""
    cat /etc/fstab | egrep -v '^#|^$' | awk '{print $2}'| egrep -v '/|/boot|swap'
    echo ""
    diskdata=$(df -lTP | sed '1d' | awk '$2!="tmpfs"{print}') #KB
    disktotal=$(echo "$diskdata" | awk '{total+=$3}END{print total}') #KB
    diskused=$(echo "$diskdata" | awk '{total+=$4}END{print total}')  #KB
    diskfree=$((disktotal-diskused)) #KB
    diskusedpercent=$(echo $disktotal $diskused | awk '{if($1==0){printf 100}else{printf "%.2f",$2*100/$1}}')
    echo -e "DiskData: \n$diskdata"
    echo ""
    echo "DiskTotal: $disktotal"
    echo ""
    echo "DiskUsed: $diskused"
    echo ""
    echo "DiskFree: $diskfree"
    echo ""
    echo "DiskUsedPercent: $diskusedpercent"
    echo ""
cat<<EOF
+------------------------------------------------+
|               #检查kvmagent状态#               |
+------------------------------------------------+
EOF
    kvmagentopenfile=$(lsof -p `pgrep -f 'from kvmagent'`|wc -l)
    if [ "$kvmagentopenfile" -lt 300 ];then
        echo "Normal: kvmagent文件打开数 $kvmagentopenfile"
        echo ""
    else
        echo "Urgent: kvmagent文件打开数已大于300，现在为 $kvmagentopenfile"
        echo ""
    fi
    kvmagentmem=$(ps -aux  |grep -v grep|grep `pgrep -f "from kvmagent"`|awk '{print$4}')
    if [ `expr $kvmagentmem \< 8` -eq 1 ];then
        echo "Normal: kvmagent使用内存 $kvmagentmem G"
        echo ""
    else
        echo "Urgent: kvmagent已使用内存大于8G,现在为 $kvmagentmem G"
        echo ""
    fi

cat<<EOF
+----------------------------------------------------+
|               #检查/dev/shm挂载状态#               |
+----------------------------------------------------+
EOF
    shm=$(df -lh |awk '{print$NF}'|grep /dev/shm )
    if [[ -n $shm ]];then
        echo "Nomal: /dev/shm已挂载"
        echo ""
    else
        echo "Urgent: /dev/shm未挂载"
        echo ""
    fi

cat<<EOF
+----------------------------------------------+
|               #检查磁盘IO信息#               |
+----------------------------------------------+
EOF
    sar -d -p 2 1
    echo ""
}

function get_health_status(){
cat<<EOF
+----------------------------------------+
|               #健康检查#               |
+----------------------------------------+
EOF
    rm -f /tmp/error
    cat /proc/loadavg |awk '{if ($3>=10) printf "Urgent: CPU总负载超过10	当前负载 %s\n", $3}'|tee /tmp/error
    load_15=`uptime | awk '{print $NF}'`
    cpu_num=`grep -c 'model name' /proc/cpuinfo`
    free -m |awk 'NR==2 {if($3*100/$2 >=80) printf "Urgent: 内存使用超过80%，当前使用率为%.2f%，总内存 %dMB，已用内存%dMB\n", $3*100/$2,$2,$3}'|tee -a /tmp/error
    echo ""
    swap_num=$(free -m |sed -n 3p|awk '{print$2}')
    `ceph verison >/dev/null 2>&1`
    val=`echo $?`
    if [[ $val -eq 0 ]];then
        if [ $swap_num = 0 ];then
            echo "没有开启SWAP分区"
            echo ""
        else
            free -m |awk 'NR==3 {if($3*100/$2 >=10) printf "Urgent: Swap使用超过10%，当前使用率为%.2f%，总计 %dMB，已用%dMB\n", $3*100/$2,$2,$3}'|tee -a /tmp/error
            echo ""
        fi
    fi
    df -lhTP | awk '{if($6+0 >= 70) printf "Important: %s 分区使用超过70%，总容量 %s，已用 %s，可用%s \n",$NF,$3,$4,$5}'|column -t | grep -v iso|tee -a /tmp/error
    echo ""
    df -lhiP | awk '{if($5+0 >= 80) printf "Important: %s Inodes使用超过80%，已用%s，可用 %s\n",$1,$3,$4 }'|column -t | grep -v iso|tee -a /tmp/error
    echo ""
    df -lBG | grep ' /$' | awk '{print $2}'| grep -oE [0-9]+ | awk '{if($1 <= 480) printf "Warning: 系统盘容量小于480GB，为%sGB \n",$1}' |tee -a /tmp/error
    echo ""

    echo ""
    rm -f /tmp/dmesg
    more /var/log/messages|grep -E '[C]all Trace|[O]ut of memory' |awk '{for(i=3+1;i<=NF;i++)printf $i " ";printf"\n"}'|uniq >/tmp/dmesg
    more /var/log/messages|grep -E '[C]all Trace' |awk '{for(i=3+1;i<=NF;i++)printf $i " ";printf"\n"}'|uniq
    [ -s /tmp/dmesg ] && grep -E '[C]all Trace' /tmp/dmesg && echo "Urgent: Call Trace happened" && grep -E '[C]all Trace' /tmp/dmesg
    more /var/log/messages|grep -E '[O]ut of memory' |awk '{for(i=3+1;i<=NF;i++)printf $i " ";printf"\n"}'|uniq
    [ -s /tmp/dmesg ] && grep -E '[O]ut of memory' /tmp/dmesg  && echo "Important: Out of memory happened" && grep -E '[O]ut of memory' /tmp/dmesg
}

function get_service_status(){
cat<<EOF
+----------------------------------------+
|               #服务检查#               |
+----------------------------------------+
EOF
    if [[ $centosVersion > 7 ]];then
        conf=$(systemctl list-unit-files --type=service --state=enabled --no-pager | grep "enabled")
        process=$(systemctl list-units --type=service --state=running --no-pager | grep ".service")
        #报表信息
        report_SelfInitiatedService="$(echo "$conf" | wc -l)"       #自启动服务数量
        echo "自启动服务数量: $report_SelfInitiatedService"
        echo ""
        report_RuningService="$(echo "$process" | wc -l)"           #运行中服务数量
        echo "运行中服务数量: $report_RuningService"
        echo ""
    else
        conf=$(/sbin/chkconfig | grep -E ":on|:启用")
        process=$(/sbin/service --status-all 2>/dev/null | grep -E "is running|正在运行")
        #报表信息
        report_SelfInitiatedService="$(echo "$conf" | wc -l)"       #自启动服务数量
        echo "自启动服务数量: $report_SelfInitiatedService"
        echo ""
        report_RuningService="$(echo "$process" | wc -l)"           #运行中服务数量
        echo "行中服务数量: $report_RuningService"
        echo ""
    fi
    echo "开机自启动的服务列表: "
    echo "$conf"  | column -t
    echo ""
    echo "目前正在运行的服务列表: "
    echo "$process"
}

function get_auto_start_status(){
cat<<EOF
+------------------------------------------+
|               #自启动检查#               |
+------------------------------------------+
EOF
    conf=$(grep -v "^#" /etc/rc.d/rc.local| sed '/^$/d')
    echo "rc.local 配置: "
    echo "$conf"
    echo ""
    echo "rc.local 信息: "
    ls -l /etc/rc.d/rc.local
    #报表信息
    echo ""
    report_SelfInitiatedProgram="$(echo $conf | wc -l)"    #自启动程序数量
    echo "自启动程序数量: $report_SelfInitiatedProgram"
    echo ""
}

function get_login_status(){
cat<<EOF
+------------------------------------------+
|               #IP登录统计#               |
+------------------------------------------+
EOF
    echo "登录成功次数最多的IP地址: "
    last | awk '{ print $3}' | grep "^[0-9]" | sort |uniq -c |sort -nr |head -n 5
    echo ""
    echo "登录失败次数最多的IP地址: "
    grep "Failed" /var/log/secure* |awk '{print $9 '=' $11}' |grep  "^[0-9]" |sort |uniq -c |sort -nr
    echo ""
}

function get_network_status(){
cat<<EOF
+----------------------------------------+
|               #网络检查#               |
+----------------------------------------+
EOF
    echo "device|link_status|driver|speed|vendor_device" |column -t -s  "|"
    for i in `ip a|grep mtu|egrep -v "vnic|docker|vxlan|lo|@"|awk -F ":" '{print $2}' | awk -F " " '{print $1}' | grep -v 'br'`
    do
        driver=`ethtool -i $i|grep driver|awk '{print $NF}'|sed 's/[[:space:]]//g'`
        link_status=`ethtool $i|grep "Link detected"|awk  '{print $3}'`
        speed=`ethtool $i|grep Speed|awk  '{print $2}'|sed 's/ *$//g'`

        if [ "X$driver" == "Xbonding" ] ; then
            echo "$i|$link_status|$driver|$speed" |column -t -s "|"
        else
            bus_info=`ethtool -i $i|grep bus|awk  '{print $2}'|sed 's/ *$//g'`
            vendor_device=`lspci -s $bus_info|sed 's/ *$//g'`
            echo "$i|$link_status|$driver|$speed|$vendor_device"|column -t -s "|"
        fi
    done

    echo ""
    echo "Bonding Mode Slave Info: "
    for i in `cat /sys/class/net/bonding_masters | sed 's/\ /\n/g' `
    do 
        echo "Bond_Info|$i|`cat /sys/class/net/$i/bonding/mode`|`cat /sys/class/net/$i/bonding/slaves`"
    done
    echo ""
    echo "IP地址信息: "
    ip -f inet addr | grep -v 127.0.0.1 |  grep inet | awk '{print $NF,$2}' |column -t
    echo ""
    echo "MAC 地址信息: "
    ip link | egrep -v "LOOPBACK\|loopback|uuid" | awk '{print $2 }'|grep -v uuid | grep -v phy_nic | xargs -n2 |column -t
    echo ""
    GATEWAY=$(ip route | grep default | awk '{print $3}')
    echo "网关: $GATEWAY"
    DNS=$(grep nameserver /etc/resolv.conf| grep -v "#" | awk '{print $2}' | tr '\n' ',' | sed 's/,$//')
    echo "DNS: $DNS"
    echo ""
    echo "Bond Info: "
    zs-show-network | egrep -v '^\ |^[0-9]|^$'
    echo ""

cat<<EOF
+------------------------------------------+
|               #网络IO信息#               |
+------------------------------------------+
EOF
    sar -n DEV 2 1|egrep -v "vnic|vxlan|outer|vx|docker0|lo" |column -t
    echo ""
}

function get_listen_status(){
cat<<EOF
+----------------------------------------+
|               #端口检查#               |
+----------------------------------------+
EOF
    TCPListen=$(netstat -anp|egrep " 8056|:8051|:8052|:8053|:5432|:5433|:2379|:2380|:9200|:9300|:9090|:8061|:6789|:6800|:7480|:2049|:3260|:8005|:8009|:8080|:8080|:8081|:8090|:5000|:5443|:80|:9100|:9103|:7069|:8086|:8088|:9089|:9091|:4900|:5900|:7758|:53|:4369|:7070|:16509|:5345|:25|:3306|:123|:7171|:7762|:7761|:7770|:7771|:7772|:6080")
    echo "$TCPListen"
    echo ""
}

function get_cron_status(){
cat<<EOF
+--------------------------------------------+
|               #计划任务检查#               |
+--------------------------------------------+
EOF
    Crontab=0
    for shell in $(grep -v "/sbin/nologin" /etc/shells);do
        for user in $(grep "$shell" /etc/passwd| awk -F: '{print $1}');do
            crontab -l -u $user >/dev/null 2>&1
            status=$?
            if [ $status -eq 0 ];then
                echo "用户${user}的计划任务检查: "
                crontab -l -u $user | grep -v -E "^\#" | sed '/^$/d'
                echo ""
                let Crontab=Crontab+$(crontab -l -u $user | wc -l)
                echo "用户计划任务数: $Crontab"
                echo ""
            fi
        done
    done

    let Crontab=Crontab+$(find /etc/cron* -type f | wc -l)
    #报表信息
    echo "总计划任务数: $Crontab"
    echo ""
    echo "计划任务文件: "
    find /etc/cron* -type f | xargs -i ls -l {} | column  -t
}

function getHowLongAgo(){
    datetime="$*"
    [ -z "$datetime" ] && echo "错误的参数: getHowLongAgo() $*"
    Timestamp=$(date +%s -d "$datetime")    #转化为时间戳
    Now_Timestamp=$(date +%s)
    Difference_Timestamp=$(($Now_Timestamp-$Timestamp))
    days=0;hours=0;minutes=0;
    sec_in_day=$((60*60*24));
    sec_in_hour=$((60*60));
    sec_in_minute=60
    while (( $(($Difference_Timestamp-$sec_in_day)) > 1 ))
    do
        let Difference_Timestamp=Difference_Timestamp-sec_in_day
        let days++
    done
    while (( $(($Difference_Timestamp-$sec_in_hour)) > 1 ))
    do
        let Difference_Timestamp=Difference_Timestamp-sec_in_hour
        let hours++
    done
    echo "$days 天 $hours 小时前"
}

function getUserLastLogin(){
    username=$1
    : ${username:="`whoami`"}
    thisYear=$(date +%Y)
    oldesYear=$(last | tail -n1 | awk '{print $NF}')
    while(( $thisYear >= $oldesYear));do
        loginBeforeToday=$(last $username | grep $username | wc -l)
        loginBeforeNewYearsDayOfThisYear=$(last $username -t $thisYear"0101000000" | grep $username | wc -l)
        if [ $loginBeforeToday -eq 0 ];then
            echo "从未登录过"
            break
        elif [ $loginBeforeToday -gt $loginBeforeNewYearsDayOfThisYear ];then
            lastDateTime=$(last -i $username | head -n1 | awk '{for(i=4;i<(NF-2);i++)printf"%s ",$i}')" $thisYear" #格式如: Sat Nov 2 20:33 2015
            lastDateTime=$(date "+%Y-%m-%d %H:%M:%S" -d "$lastDateTime")
            echo "$lastDateTime"
            break
        else
            thisYear=$((thisYear-1))
        fi
    done

}

function get_user_status(){
cat<<EOF
+----------------------------------------+
|               #用户检查#               |
+----------------------------------------+
EOF
    #/etc/passwd 最后修改时间
    pwdfile="$(cat /etc/passwd)"
    Modify=$(stat /etc/passwd | grep Modify | tr '.' ' ' | awk '{print $2,$3}')

    echo "/etc/passwd 最后修改时间: $Modify ($(getHowLongAgo $Modify))"
    echo ""
    echo "特权用户: "
    RootUser=""
    for user in $(echo "$pwdfile" | awk -F: '{print $1}');do
        if [ $(id -u $user) -eq 0 ];then
            echo "$user"
            RootUser="$RootUser,$user"
        fi
    done
    echo ""
    echo "用户列表: "
    USERs=0
    echo "$(
    echo "用户名 UID GID HOME SHELL 最后一次登录"
    for shell in $(grep -v "/sbin/nologin" /etc/shells);do
        for username in $(grep "$shell" /etc/passwd| awk -F: '{print $1}');do
            userLastLogin="$(getUserLastLogin $username)"
            echo "$pwdfile" | grep -w "$username" |grep -w "$shell"| awk -F: -v lastlogin="$(echo "$userLastLogin" | tr ' ' '_')" '{print $1,$3,$4,$6,$7,lastlogin}'
        done
        let USERs=USERs+$(echo "$pwdfile" | grep "$shell"| wc -l)
    done
    )" | column -t
    echo ""
    echo "空密码用户: "
    USEREmptyPassword=""
    for shell in $(grep -v "/sbin/nologin" /etc/shells);do
        for user in $(echo "$pwdfile" | grep "$shell" | cut -d: -f1);do
        r=$(awk -F: '$2=="!!"{print $1}' /etc/shadow | grep -w $user)
        if [ ! -z $r ];then
            echo $r
            USEREmptyPassword="$USEREmptyPassword,"$r
        fi
        done
    done
    echo ""
    echo "相同ID的用户: "
    USERTheSameUID=""
    UIDs=$(cut -d: -f3 /etc/passwd | sort | uniq -c | awk '$1>1{print $2}')
    for uid in $UIDs;do
        echo -n "$uid";
        USERTheSameUID="$uid"
        r=$(awk -F: 'ORS="";$3=='"$uid"'{print ":",$1}' /etc/passwd)
        echo "$r"
        echo ""
        USERTheSameUID="$USERTheSameUID $r,"
    done
}

function get_password_status(){
cat <<EOF
+----------------------------------------+
|               #密码检查#               |
+----------------------------------------+
EOF
    pwdfile="$(cat /etc/passwd)"
    echo "密码过期检查: "
    result=""
    for shell in $(grep -v "/sbin/nologin" /etc/shells);do
        for user in $(echo "$pwdfile" | grep "$shell" | cut -d: -f1);do
            get_expiry_date=$(/usr/bin/chage -l $user | grep 'Password expires' | cut -d: -f2)
            if [[ $get_expiry_date = ' never' || $get_expiry_date = 'never' ]];then
                printf "%-15s 永不过期\n" $user
                result="$result,$user:never"
            else
                password_expiry_date=$(date -d "$get_expiry_date" "+%s")
                current_date=$(date "+%s")
                diff=$(($password_expiry_date-$current_date))
                let DAYS=$(($diff/(60*60*24)))
                printf "%-15s %s天后过期\n" $user $DAYS
                result="$result,$user:$DAYS days"
            fi
        done
    done
    report_PasswordExpiry=$(echo $result | sed 's/^,//')

    echo ""
    echo "密码策略检查: "
    grep -v "#" /etc/login.defs | grep -E "PASS_MAX_DAYS|PASS_MIN_DAYS|PASS_MIN_LEN|PASS_WARN_AGE"
}

function get_sudoers_status(){
cat <<EOF
+-------------------------------------------+
|               #Sudoers检查#               |
+-------------------------------------------+
EOF
    conf=$(grep -v "^#" /etc/sudoers| grep -v "^Defaults" | sed '/^$/d' | column -t)
    echo "$conf"
    echo ""
    report_Sudoers="$(echo $conf | wc -l)"
    echo "Sudoers数量: $report_Sudoers"
    echo ""
}

function get_mn_status(){
cat <<EOF
+--------------------------------------------------+
|               #ZStack管理节点状态#               |
+--------------------------------------------------+
EOF
    if [ -f /usr/bin/zstack-ctl ]; then
        echo "ZStack服务状态: "
	zstack-ctl status
        echo ""

        echo "ZStack相关文件: "
	du -sh /usr/local/zstack/apache-tomcat/logs
        du -sh /usr/local/zstack
        du -sh /var/lib/zstack
	du -sBG /var/lib/zstack/prometheus
        echo ""
  
        if [[ -f /var/lib/zstack/prometheus ]];then
	    pro_data_capacity=$(du -sBG /var/lib/zstack/prometheus | awk '{print $1}' | sed 's/G//g')
            if [[ $pro_data_capacity -gt 120 ]];then
                echo 'Urgent: 监控数据(prometheus)已用空间超过120GB'
                echo ""
            fi
        fi
        
        if [[ -f /var/lib/zstack/prometheus2 ]];then
            pro_data_capacity2=$(du -sBG /var/lib/zstack/prometheus2 | awk '{print $1}' | sed 's/G//g') 
            if [[ $pro_data_capacity2 -gt 120 ]];then
                echo 'Urgent: 监控数据(prometheus2)已用空间超过120GB'
                echo ""
            fi
        fi

	if [ -d /opt/sds ];then 
            echo "sds相关文件: "
            du -h  /opt/sds  --max-depth=1
            echo ""
        fi
    fi
    
    `which zsha2 >/dev/null 2>&1`
    zsha2_val=`echo $?`
    if [[ $zsha2_val -eq 0 ]];then
        echo ""
        echo "ZStack Multi MN HA Info: "
        zsha2 status
    fi

    `which zsha >/dev/null 2>&1`
    zsha_val=`echo $?`
    if [[ $zsha_val -eq 0 ]]; then
        echo ""
        echo "ZStack MN VM HA Info: "
        zsha status
    fi
}

function get_process_status(){
cat <<EOF
+----------------------------------------+
|               #进程检查#               |
+----------------------------------------+
EOF
    if [ $(ps -ef | grep [d]efunct | wc -l) -ge 1 ];then
        echo "Urgent: 存在僵尸进程 " ps -ef | grep [d]efunct ;
        echo ""
        ps -ef | head -n1
        ps -ef | grep [d]efunct
    fi
    echo "内存占用TOP20: "
    echo -e "PID %MEM RSS(GB) COMMAND
    $(ps aux | awk '{print $2, $4, $6/1024/1024, $11}' | sort -k3rn | head -n 20 )"| column -t
    echo ""
    echo "CPU占用TOP20: "
    top b -n1 | head -27 | tail -21|column -t
    echo ""

    echo "物理机上所有VM内存/总内存: ` ps aux | awk '{print $2, $4, $6/1024/1024, $11}'|grep qemu-kvm|awk '{sum+=$3} END{printf "%.2f GB",sum}'`/`free -h|grep Mem|awk '{print $2}'`"
    echo ""
    echo "物理机上所有VM CPU/总CPU: `top b -n1|grep qemu-kvm|awk '{sum+=$9} END{printf "%.0f",sum/100}'`/` cat /proc/cpuinfo |grep process -c`"
}

function get_jdk_status(){
cat <<EOF
+---------------------------------------+
|               #JDK检查#               |
+---------------------------------------+
EOF
    java -version 2>/dev/null
    if [ $? -eq 0 ];then
        java -version 2>&1
    fi
}

function get_influxdb_info(){
cat <<EOF
+--------------------------------------------+
|               #influxdb检查#               |
+--------------------------------------------+
EOF
    echo "进程实际占用物理内存大小: "
    influxdbPid=$(ps -ef | grep [i]nfluxdb | awk '{print $2}')
    cat /proc/$influxdbPid/status | grep VmRSS | awk '{if(($2/1024/1024)>16) print "Important: xxx";else print $2/1024/1024"GB"}'
}

function get_syslog_status(){
cat <<EOF
+------------------------------------------+
|               #syslog检查#               |
+------------------------------------------+
EOF
    echo "服务状态: $(getState rsyslog)"
    echo ""
    echo "/etc/rsyslog.conf信息: "
    cat /etc/rsyslog.conf 2>/dev/null | grep -v "^#" | grep -v "^\\$" | sed '/^$/d'  | column -t
    #报表信息
    report_Syslog="$(getState rsyslog)"
}

function getState(){
    if [[ $centosVersion < 7 ]];then
        if [ -e "/etc/init.d/$1" ];then
            if [ `/etc/init.d/$1 status 2>/dev/null | grep -E "is running|正在运行" | wc -l` -ge 1 ];then
                r="active"
            else
                r="inactive"
            fi
        else
            r="unknown"
        fi
    else
        #CentOS 7+
        r="$(systemctl is-active $1 2>&1)"
    fi
    echo "$r"
}

function get_firewall_status(){
cat <<EOF
+------------------------------------------+
|               #防火墙检查#               |
+------------------------------------------+
EOF
    if [[ $centosVersion < 7 ]];then
        /etc/init.d/iptables status >/dev/null  2>&1
        status=$?
        if [ $status -eq 0 ];then
            iptabless="active"
        elif [ $status -eq 3 ];then
            iptabless="inactive"
        elif [ $status -eq 4 ];then
            iptabless="permission denied"
        else
            iptabless="unknown"
        fi
    else
        iptabless="$(getState iptables)"
    fi
    echo "iptables: $iptabless"
    echo ""
    echo "iptables -nL: "
    iptables -nL 2>/dev/null
}

function get_ebtables_status(){
cat <<EOF
+--------------------------------------------+
|               #ebtables检查#               |
+--------------------------------------------+
EOF
    #防火墙状态，策略等
    systemctl status ebtables.service >/dev/null  2>&1
    status=$?
    if [ $status -eq 0 ];then
        ebtabless="active"
    elif [ $status -eq 3 ];then
        ebtabless="inactive"
    elif [ $status -eq 4 ];then
        ebtabless="permission denied"
    else
        ebtabless="unknown"
    fi
    echo "ebtables: $ebtabless"
    echo ""
    echo "ebtables -L: "
    ebtables -L 2>/dev/null
}

function get_libvirtd_status(){
cat <<EOF
+--------------------------------------------+
|               #Libvirtd检查#               |
+--------------------------------------------+
EOF
    status="$(getState libvirtd)"
    echo "服务状态: $status"
    echo ""
    if [ -e /etc/libvirt/libvirtd.conf ];then
        echo "/etc/libvirt/libvirtd.conf: "
        cat /etc/libvirt/libvirtd.conf 2>/dev/null | grep -v "^#" | sed '/^$/d'
    fi
}

function get_agent_status(){
cat <<EOF
+------------------------------------------------------+
|               #ZStack Agent及服务检查#               |
+------------------------------------------------------+
EOF
    [ `ps -ef|grep [t]ools/prometheus -c` -gt 1 ]   && echo "prometheus info: " `ps -ef|grep [t]ools/prometheus |awk '{for(i=7+1;i<=NF;i++)printf $i " ";printf"\n"}'`
    [ `ps -ef|grep [k]vmagent -c` -gt 1 ]           && echo "kvmagent info: " `ps -ef|grep [k]vmagent|awk '{for(i=7+1;i<=NF;i++)printf $i " ";printf"\n"}'`
    [ `ps -ef|grep [z]sn-agent -c` -gt 1 ]          && echo "zsn-agent info: " `ps -ef|grep [z]sn-agent|awk '{for(i=7+1;i<=NF;i++)printf $i " ";printf"\n"}'`
    [ `ps -ef|grep [c]ephprimarystorage -c` -gt 1 ] && echo "cephprimarystorage info: " `ps -ef|grep [c]ephprimarystorage|awk '{for(i=7+1;i<=NF;i++)printf $i " ";printf"\n"}'`
    [ `ps -ef|grep [c]ephbackupstorage -c` -gt 1 ]  && echo "cephbackupstorage info: " `ps -ef|grep [c]ephbackupstorage|awk '{for(i=7+1;i<=NF;i++)printf $i " ";printf"\n"}'`
    [ `ps -ef|grep [z]stack_tui -c` -gt 1 ]         && echo "zstack_tui info: " `ps -ef|grep [z]stack_tui|awk '{for(i=7+1;i<=NF;i++)printf $i " ";printf"\n"}'`
    [ `ps -ef|grep [c]onsoleproxy -c` -gt 1 ]       && echo "consoleproxy info: " `ps -ef|grep [c]onsoleproxy|awk '{for(i=7+1;i<=NF;i++)printf $i " ";printf"\n"}'`
    [ `ps -ef|grep [d]nsmasq -c` -gt 1 ]            && echo "dnsmasq info: " `ps -ef|grep [d]nsmasq |awk '{for(i=7+1;i<=NF;i++)printf $i " ";printf"\n"}'`
    [ `ps -ef|grep [l]ighttpd -c` -gt 1 ]           && echo "lighttpd info: " `ps -ef|grep [l]ighttpd |awk '{for(i=7+1;i<=NF;i++)printf $i " ";printf"\n"}'`
    [ `ps -ef|grep [c]ollectd -c` -gt 1 ]           && echo "collectd info: " `ps -ef|grep [c]ollectd |awk '{for(i=7+1;i<=NF;i++)printf $i " ";printf"\n"}'`
}

function get_log_info(){
cat <<EOF
+---------------------------------------------------+
|               #ZStack 相关日志路径#               |
+---------------------------------------------------+
管理节点日志: /usr/local/zstack/apache-tomcat/logs/management-server.log
管理节点UI日志: /usr/local/zstack/apache-tomcat/logs/zstack-ui.log
管理节点部署日志: /var/log/zstack/deploy.log
物理机shell命令日志: /var/log/zstack/zstack.log
物理机KVMagent日志: /var/log/zstack/zstack-kvmagent.log
镜像仓库日志: /var/log/zstack/zstack-store/zstore.log
Ceph主存储日志: /var/log/zstack/ceph-primarystorage.log
Ceph镜像服务器日志: /var/log/zstack/ceph-backupstorage.log

EOF
    promethous_log=/var/lib/zstack/prometheus/data*
    apache_tomcat_log=/usr/local/zstack/apache-tomcat/logs/
    mysql_log=/var/lib/mysql
    zstack_log=/var/log/zstack/
    echo -e "log size :\n`du -sh ${apache_tomcat_log} ${promethous_log} ${zstack_log} ${mysql_log} 2> /dev/null`"
    size=`du -sh $mysql_log | awk -F " " '{print $1}' 2> /dev/null`
    if [[ -f $mysql_log ]];then
        if [[ $size =~ "G" ]];then
            echo ${size%G} | awk '{if($1>10) print "Important: 数据库日志文件大小超过10G";else print "Normal: 数据库日志文件大小少于10G"}'
        else
            echo "Normal: 数据库日志文件大小少于10G"
        fi
    fi
    echo ""
}

function get_ssh_status(){
cat <<EOF
+---------------------------------------+
|               #SSH检查#               |
+---------------------------------------+
EOF
    pwdfile="$(cat /etc/passwd)"
    echo "服务状态: $(getState sshd)"
    Protocol_Version=$(cat /etc/ssh/sshd_config | grep Protocol | awk '{print $2}')
    echo "SSH协议版本: $Protocol_Version"
    echo ""
    echo "信任主机: "
    authorized=0
    for user in $(echo "$pwdfile" | grep /bin/bash | awk -F: '{print $1}');do
        authorize_file=$(echo "$pwdfile" | grep -w $user | awk -F: '{printf $6"/.ssh/authorized_keys"}')
        authorized_host=$(cat $authorize_file 2>/dev/null | awk '{print $3}' | tr '\n' ',' | sed 's/,$//')
        if [ ! -z $authorized_host ];then
            echo "$user 授权 \"$authorized_host\" 无密码访问"
        fi
        let authorized=authorized+$(cat $authorize_file 2>/dev/null | awk '{print $3}'|wc -l)
    done

    echo ""
    echo "是否允许ROOT远程登录: "
    config=$(cat /etc/ssh/sshd_config | grep PermitRootLogin)
    firstChar=${config:0:1}
    if [ $firstChar == "#" ];then
        PermitRootLogin="yes"  #默认是允许ROOT远程登录的
    else
        PermitRootLogin=$(echo $config | awk '{print $2}')
    fi
    echo "PermitRootLogin $PermitRootLogin"

    echo ""
    echo "/etc/ssh/sshd_config: "
    cat /etc/ssh/sshd_config | grep -v "^#" | sed '/^$/d'
}

function get_hardware_information(){
cat <<EOF
+--------------------------------------------+
|               #硬件信息概览#               |
+--------------------------------------------+
EOF
    /tmp/hardware.pl -d
    #echo -e "\nBIOS:\^"$(dmidecode -s bios-vendor) $(dmidecode -s bios-version) $(dmidecode -s bios-release-date)\
	#"\nOS:\^"$(cat /etc/redhat-release),$(uname -srm)\
	#"\nProduct:\^"$(dmidecode -s system-product-name 2>/dev/null | sed 's/ *$//g')\
	#"\nProduct Version:\^"$(dmidecode -s system-version 2>/dev/null | sed 's/ *$//g')\
	#"\nProduct Chassis:\^"$(dmidecode -s chassis-type 2>/dev/null | sed 's/ *$//g')\
	#"\nProduct Service Tag:\^"$(dmidecode -s system-serial-number 2>/dev/null | sed 's/ *$//g')\
	#"\nNetwork:\^"$(lspci|grep network)|column -ts "\^"
}

function get_time_sync_status(){
cat <<EOF
+--------------------------------------------+
|               #时间同步检查#               |
+--------------------------------------------+
EOF
    if [ `pgrep chronyd` ];then
        echo ""
        chronyc sources -v
        echo ""
        echo "Chrony服务配置: "
        cat /etc/chrony.conf|grep -v "^#"|tr -s '\n' |sed '/^$/d'
	chronyc sources -v | grep ? | grep -v unreachable
	if [ $? -eq 0 ];then echo "Important: Chrony server is unreachable";fi
        echo ""
        echo "chronyd服务状态: $(getState chronyd)"
    elif [ `pgrep ntp` ];then
        echo ""
        ntpq -np
        echo ""
        echo "NTP服务配置: "
        cat /etc/ntp.conf|grep -v ^# |tr -s '\n'
        #报表信息
        echo ""
        echo "ntpd服务状态: $(getState ntpd)"
    fi
    echo ""
    echo '系统时间: '
    timedatectl
    hwclock

}

function get_hosts(){
cat <<EOF
+-----------------------------------------------+
|               #hosts一致性检查#               |
+-----------------------------------------------+
EOF
    cat /etc/hosts | column -t
    echo ""
}

function get_libvirt_qemu_version(){
cat <<EOF
+----------------------------------------------------+
|               #Libvirt/Qemu版本检查#               |
+----------------------------------------------------+
EOF
    virsh version 
    echo ""
}

function get_raid_info(){
cat <<EOF
+--------------------------------------------+
|               #Raid信息检查#               |
+--------------------------------------------+
EOF
    lspci | grep -i raid
    echo ""
}

function get_san_info(){
cat <<EOF
+-------------------------------------------+
|               #SAN信息检查#               |
+-------------------------------------------+
EOF
    if [ -x /usr/sbin/multipath ]; then
        cat /etc/multipath.conf|grep -v ^#
        multipathd show maps raw format "%n %w %N %d %S %t %s %e"
        multipath -ll
    fi
    # 检查多路径链路是否一致
    MultiPath=$(multipath -ll | grep [m]path | sort | xargs)
    echo "MultiPath ${MultiPath}"
    echo ""
}

function get_vm_list(){
cat <<EOF
+--------------------------------------------------+
|               #物理机上vm信息检查#               |
+--------------------------------------------------+
EOF
        [ `ps -ef|grep [q]emu-kvm -c` -lt 1 ] && echo "NO VM Running" && return 0
	qemu_kvm_lists=$(ps -ef | grep [q]emu-kvm |awk -F ' ' '{print$10}' |sed 's/guest=//g'|cut -c -32|sort|sed ':t;N;s/\n//;b t')
	virsh_lists=$(virsh list|sed  '1,2d'|awk '{print $2}'|tr -s '\n'|sort|sed ':t;N;s/\n//;b t')
	qemu_kvm_list_num=$(ps -ef | grep [q]emu-kvm |awk -F ' ' '{print$10}' |sed 's/guest=//g'|cut -c -32|wc -l)
	virsh_list_num=$(virsh list|sed  '1,2d'|awk '{print $2}'|tr -s '\n'|wc -l)
	if [ "X$qemu_kvm_list_num" != "X$virsh_list_num" ]; then
            echo "Important: VM Number in QEMU-KVM and Virsh list not equal, it's on high risk"
        elif [ "X$qemu_kvm_lists" != "X$virsh_lists" ]; then
            echo "Important: VM in QEMU-KVM and Virsh list are not equal , it's on high risk"
        else
            echo "Normal: VM in QEMU-KVM and Virsh List are equal"
	fi
}

function get_websocokify(){
cat <<EOF
+-----------------------------------------------------------+
|               #物理机上websocokify信息检查#               |
+-----------------------------------------------------------+
EOF
    echo  "websocokify个数为: $(ps axjf |grep -v 'import websocokify' -c)"
}

function get_gpu_info(){
cat <<EOF
+-------------------------------------------+
|               #GPU信息检查#               |
+-------------------------------------------+
EOF
    lspci -vnn |grep  VGA -A 12 2>/dev/null
}

function get_installed_packages(){
cat <<EOF
+-----------------------------------------------+
|               #已安装rpm包检查#               |
+-----------------------------------------------+
EOF
    rpm -qa | sort 
    echo ""
}

function check_ept_parameters(){
cat <<EOF
+---------------------------------------------------------+
|               #物理机的 ept|npt 配置检测#               |
+---------------------------------------------------------+
EOF
    ept_para=$(cat /sys/module/kvm_*/parameters/*pt)
    if [[ "$ept_para" == "Y" || "$ept_para" == "1" ]];then
        echo 'Normal: ept(npt)参数已打开'
    else
        echo 'Important: ept(npt)参数未打开，请检查'
    fi
}


function get_sysctl_info(){
cat <<EOF
+-------------------------------------------+
|               #sysctl info#               |
+-------------------------------------------+
EOF
    sysctl -a 
}


function get_xsos_info(){
cat <<EOF
+------------------------------------------+
|               #xsos infoa#               |
+------------------------------------------+
EOF
    bash /tmp/xsos -a -x 
}

function check_disk_ssd(){
cat <<EOF
+-----------------------------------------------------+
|               #MON节点系统盘类型检查#               |
+-----------------------------------------------------+
EOF
    `ceph mon stat >/dev/null 2>&1`
    result_vlaue=`echo $?`
    #monip_list=`echo "$mon_stat" | awk -F "{|}" '{print $2}' | sed "s/,/\n/g" | awk -F "=|:" '{print $2}'`
    boot_disk=`lsblk | grep boot | awk -F "├─| " '{print $2}' | awk -F "[0-9$]" '{print $1}'`
    disk_value=`grep ^ /sys/block/${boot_disk}/queue/rotational`
    if [[ $result_vlaue -eq 0 ]];then
        container_num=`docker ps -a -q | wc -l`
            if [[ $container_num -gt 3 ]];then
                if [[ $disk_value -eq 0  ]];then
                    echo "Normal: system disk ${boot_disk} type is SSD"
                elif [[ $disk_value -eq 1 ]];then
                    echo "Urgent: system disk ${boot_disk} type is HDD"
                fi
            else
                break
            fi
    else
        break
    fi
    echo ""
}

main(){
    get_system_info
    get_cpu_info
    get_qemu_process_list
    get_virsh_list_running_npaused
    get_health_status
    get_mem_status
    check_cpu_c_state
    check_temperature
    check_disk_status
    check_ept_parameters
    check_disk_ssd
    get_auto_start_status
    get_login_status
    get_network_status
    get_service_status
    get_cron_status
    get_user_status
    get_password_status
    get_sudoers_status
    get_mn_status
    get_process_status
    get_jdk_status
    get_influxdb_info
    get_syslog_status
    get_firewall_status
    get_ebtables_status
    get_libvirtd_status
    get_agent_status
    get_log_info
    get_ssh_status
    get_hardware_information
    get_hosts
    get_time_sync_status
    get_libvirt_qemu_version
    get_raid_info
    get_san_info
    get_vm_list
    get_websocokify
    get_gpu_info
    get_sysctl_info > $LOGPATH/sysctl.log
    get_listen_status > $LOGPATH/netstat.log
    get_installed_packages > $LOGPATH/rpm.log
    get_xsos_info >$LOGPATH/xsos.log
}

main > $RESULTFILE
echo "检查结果: $RESULTFILE"
