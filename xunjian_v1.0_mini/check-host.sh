#!/bin/bash
# File Name: check-host.sh
# Time:2020-08-18 20:11:06
# Version: v1.0
# Description: This is a host script.

#主机信息巡检
PARSE_JSON="./json.sh -l -p -b"
#当前脚本适用于CentOS 7.X
#增加检查计算节点libvirt qemu版本信息
export PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/root/bin
source /etc/profile
VERSION=2.1.1
#获取本地存储URL
#uploadHostDailyCheckApi="http://10.0.0.1:8080/api/uploadHostDailyCheck"
#uploadHostDailyCheckReportApi="http://10.0.0.1:8080/api/uploadHostDailyCheckReport"
centosVersion=$(awk '{print $(NF-1)}' /etc/redhat-release)

#日志相关
PROGPATH=`echo $0 | sed -e 's,[\\/][^\\/][^\\/]*$,,'`
[ -f $PROGPATH ] && PROGPATH="."
LOGPATH="$PROGPATH/log"
[ -e $LOGPATH ] || mkdir $LOGPATH
RESULTFILE="$LOGPATH/HostDailyCheck-`hostname`-`date +%Y%m%d`.txt"
HOSTREPORT="$LOGPATH/HostReport-`hostname`-`date +%Y%m%d`.csv"

#定义报表的全局变量
report_DateTime=""    #日期 ok
report_Hostname=""    #主机名 ok
report_OSRelease=""    #发行版本 ok
report_Kernel=""    #内核 ok
report_Language=""    #语言/编码 ok
report_LastReboot=""    #最近启动时间 ok
report_Uptime=""    #运行时间（天） ok
report_CPUs=""    #CPU数量 ok
report_CPUType=""    #CPU类型 ok
report_Arch=""    #CPU架构 ok
report_MemTotal=""    #内存总容量(MB) ok
report_MemUsedPercent=""    #内存使用率% ok
report_DiskTotal=""    #硬盘总容量(GB) ok
report_DiskFree=""    #硬盘剩余(GB) ok
report_DiskUsedPercent=""    #硬盘使用率% ok
report_InodeTotal=""    #Inode总量 ok
report_InodeFree=""    #Inode剩余 ok
report_InodeUsedPercent=""    #Inode使用率 ok
report_IP=""    #IP地址 ok
report_MAC=""    #MAC地址 ok
report_Gateway=""    #默认网关 ok
report_DNS=""    #DNS ok
report_Listen=""    #监听 ok
report_Selinux=""    #Selinux ok
report_Firewall=""    #防火墙 ok
report_USERs=""    #用户 ok
report_USEREmptyPassword=""   #空密码用户 ok
report_USERTheSameUID=""      #相同ID的用户 ok
report_PasswordExpiry=""    #密码过期（天） ok
report_RootUser=""    #root用户 ok
report_Sudoers=""    #sudo授权  ok
report_SSHAuthorized=""    #SSH信任主机 ok
report_SSHDProtocolVersion=""    #SSH协议版本 ok
report_SSHDPermitRootLogin=""    #允许root远程登录 ok
report_DefunctProsess=""    #僵尸进程数量 ok
report_SelfInitiatedService=""    #自启动服务数量 ok
report_SelfInitiatedProgram=""    #自启动程序数量 ok
report_RuningService=""           #运行中服务数  ok
report_Crontab=""    #计划任务数 ok
report_Syslog=""    #日志服务 ok
report_Libvirtd=""    #Libvirtd  OK
report_NTP=""    #NTP ok
report_JDK=""    #JDK版本 ok
report_OpenProcesNum=""  #当前运行进程数量
report_CPUCoreNumber=""  #CPU核心数
report_UsedMemory=""     #已用内存
report_UsedSwap=""       #已用swap
report_UsedSystemDisk="" #已用系统盘
report_CPU_Load=""       #CPU负载
report_Qemu_Kvm_Namelist="" #qemu-kvm进程namelist ok

function version(){
    echo ""
    echo ""
    echo "ZStack巡检脚本: Version $VERSION"
    echo "巡检日期: $(date)"
}

# Print a space-padded string into $line.  Then translate spaces to hashes, and
# underscores to spaces.  End result is a line of hashes with words at the
# start.
section () {
   echo "$1" | awk '{l=sprintf("#_%-60s", $0 "_"); print l}' | sed -e 's/ /#/g' -e 's/_/ /g'
}

# Print a "name | value" line.
name_val() {
   printf "%12s | %s\n" "$1" "$(echo $2)"
}

# Converts a value to units of power of 2.  Arg 1: the value.  Arg 2: precision (defaults to 2).
shorten() {
   echo $@ | awk '{
      unit = "k";
      size = 1024;
      val  = $1;
      prec = 2;
      if ( $2 ~ /./ ) {
         prec = $2;
      }
      if ( val >= 1099511627776 ) {
         size = 1099511627776;
         unit = "T";
      }
      else if ( val >= 1073741824 ) {
         size = 1073741824;
         unit = "G";
      }
      else if ( val >= 1048576 ) {
         size = 1048576;
         unit = "M";
      }
      printf "%." prec "f%s", val / size, unit;
   }'
}

function getCPU_C_State(){
    echo "############################ 检查CPU C State #############################"
    Hostname=$(uname -n)
    CPU_list=$(cat /proc/cpuinfo | grep 'cpu MHz' | awk -F " " '{print $4}')
    flag_1=$(cat /proc/cpuinfo | grep 'cpu MHz' | awk -F " " 'NR==1 {print $4}')
    flag_2=0
    if [[ $flag_2 = 0 ]];then
        for i in ${CPU_list[@]}
        do
            if [[ "$flag_1" != "$i" ]];then
                flag_2=1
            fi
        done
        if [[ $flag_2 = 1 ]];then
            echo "Urgent: $Hostname CPU C state enable"
        else
            echo "Normal: $Hostname CPU C state disable"
        fi
    fi
}

function Check_temperature(){
    echo ""
    Hostname=$(uname -n)
    echo "########################### CPU 温度检测 ############################"
    temperature_str="temperature above threshold"
    temperature_log=`cat /var/log/messages* | grep "temperature above threshold"`
    if [[ "$temperature_log" =~ "$temperature_str" ]];then
        echo "$Hostname: CPU temperature too high!"
    else
        echo "$Hostname: CPU temperature is OK."
    fi
}

function getCpuStatus(){
    echo ""
    echo "############################ CPU检查 #############################"
    Physical_CPUs=$(grep "physical id" /proc/cpuinfo| sort | uniq | wc -l)
    Virt_CPUs=$(grep "processor" /proc/cpuinfo | wc -l)
    CPU_Kernels=$(grep "cores" /proc/cpuinfo|uniq| awk -F ': ' '{print $2}')
    CPU_Type=$(grep "model name" /proc/cpuinfo | awk -F ': ' '{print $2}' | sort | uniq)
    CPU_Arch=$(uname -m)
    echo "物理CPU颗数:$Physical_CPUs"
    echo "逻辑CPU个数:$Virt_CPUs"
    echo "每CPU核心数:$CPU_Kernels"
    echo "    CPU型号:$CPU_Type"
    echo "    CPU架构:$CPU_Arch"
    #报表信息
    report_CPUs=$Virt_CPUs    #CPU数量
    report_CPUType=$CPU_Type  #CPU类型
    report_Arch=$CPU_Arch     #CPU架构
}

function getQemuKvmPNameList(){
    echo ""
    echo "############################ qemu-kvm进程namelist #############################"
    NameList=$(ps -ef|grep [q]emu-kvm |awk -F "guest=|," '{print $2}'|tr -s '\n')
    echo "$NameList"
    report_Qemu_Kvm_Namelist=$NameList #qemu-kvm进程
}

function getVirshListRunningNPaused(){
   echo ""
   echo "############################ virsh list(Running&Paused) ############################"
   VirshList=$(virsh list|sed  '1,2d'|awk '{print $2}'|tr -s '\n')
   echo "$VirshList"
   report_Virsh_List=$VirshList
}

function getMemStatus(){
    echo ""
    echo "############################ 内存检查 ############################"
    free -h
    echo ""
    echo "System Memory RSS Info:"  `ps -eo rss 2>/dev/null | awk '/[0-9]/{total += $1 * 1024} END {printf "%.2f", total/1024/1024/1024}'`GB
    echo ""
    echo "System VM info "
    sysctl vm.swappiness
    sysctl vm.dirty_ratio
    sysctl vm.dirty_background_ratio
    sysctl vm.dirty_bytes
    sysctl vm.dirty_background_bytes
    #报表信息
    MemTotal=$(free -m|awk 'NR==2{printf "%sMB\n", $2}')  #MB
    MemPercent=$(free -m | awk 'NR==2{printf "%.2f%\n", $3*100/$2 }')
    report_MemTotal=$MemTotal        #内存总容量(MB)
    report_MemUsedPercent=$(free -m | awk 'NR==2{printf "%.2f%\n", $3*100/$2 }') #内存使用率%
}

function getDiskStatus(){
    echo ""
    echo "############################ 磁盘检查 ############################"
    df -lhiP | sed 's/Mounted on/Mounted/'> /tmp/inode
    df -lhTP | sed 's/Mounted on/Mounted/'> /tmp/disk
    join /tmp/disk /tmp/inode | awk '{print $1,$2,"|",$3,$4,$5,$6,"|",$8,$9,$10,$11,"|",$12}'| column -t
    echo ""
    echo "System Disk Schedulers And Queue Size"
    for disk in $(ls /sys/block/ | grep -v -e ram -e loop -e 'fd[0-9]'); do
        if [ -e "/sys/block/${disk}/queue/scheduler" ]; then
            echo "${disk}" "$(cat /sys/block/${disk}/queue/scheduler | grep -o '\[.*\]') $(cat /sys/block/${disk}/queue/nr_requests)"
        fi
    done
    echo ""
	echo "inode检查"
	inodestat=$(df -li |grep  '/$' | awk '{print$2}')
	if [[ $inodestat -lt 1000000 ]];then
   		echo "Important，inode总量小于100W"
	else
		echo "Normal，inode总量大于100W"
	fi
	inodeusestat=$(expr 100 - `df -li |grep  '/$' | awk '{print$5}'|sed 's/%//g'`)
	if [[ $inodeusestat -lt 20 ]];then
	    echo "Important，inode可用量低于20%"
	else
		echo "Normal，inode可用量大于20%"
	fi
	echo "LVM Volumes Info "
    lvs
    echo ""
    echo "fstab Info "
    cat /etc/fstab|grep -v ^#
    cat /etc/fstab | egrep -v '^#|^$' | awk '{print $2}'| egrep -v '/|/boot|swap'
    echo ""
	#报表信息
    diskdata=$(df -lTP | sed '1d' | awk '$2!="tmpfs"{print}') #KB
    disktotal=$(echo "$diskdata" | awk '{total+=$3}END{print total}') #KB
    diskused=$(echo "$diskdata" | awk '{total+=$4}END{print total}')  #KB
    diskfree=$((disktotal-diskused)) #KB
    diskusedpercent=$(echo $disktotal $diskused | awk '{if($1==0){printf 100}else{printf "%.2f",$2*100/$1}}')

    #echo ""
    #echo "############################ delete状态文件查询 ############################"
    #echo 'delete状态文件查询'
    #lsof | awk '/deleted/ {sum+=$7} END {printf "%.3f GB\n", sum/1024/1024/1024}'
    #echo ""
    #echo 'kvmagent delete状态文件查询'
    #lsof |grep kvmagent | awk '/deleted/ {sum+=$7} END {printf "%.3f GB\n", sum/1024/1024/1024}'
    #echo ""
    echo ""
    echo "############################ kvmagent状态查询 ############################"
    kvmagentopenfile=$(lsof -p `pgrep -f 'from kvmagent'`|wc -l)
    if [ "$kvmagentopenfile" -lt 300 ];then
        echo "kvmagent文件打开数:$kvmagentopenfile"
    else
        echo "Urgent: kvmagent文件打开数已大于300，现在为:$kvmagentopenfile"
    fi
    kvmagentmem=$(ps -aux  |grep -v grep|grep `pgrep -f "from kvmagent"`|awk '{print$4}')
    if [ `expr $kvmagentmem \< 8` -eq 1 ];then
        echo "kvmagent使用内存 $kvmagentmem"G
    else
        echo "Urgent:kvmagent已使用内存大于8G,现在为:$kvmagentmem"G
    fi
		echo ""
    echo "############################ /dev/shm挂载状态查询 ############################"
	shm=$(df -Th |awk '{print$NF}'|grep /dev/shm )
	if [[ -n $shm ]];then
   	    echo '/dev/shm已挂载'
	else
	    echo 'Urgent: /dev/shm未挂载'
	fi
	echo ""

	# 检查磁盘IO
    echo '############################ 磁盘IO信息 ############################'
    sar -d -p 2 1

    inodedata=$(df -liTP | sed '1d' | awk '$2!="tmpfs"{print}')
    inodetotal=$(echo "$inodedata" | awk '{total+=$3}END{print total}')
    inodeused=$(echo "$inodedata" | awk '{total+=$4}END{print total}')
    inodefree=$((inodetotal-inodeused))
    inodeusedpercent=$(echo $inodetotal $inodeused | awk '{if($1==0){printf 100}else{printf "%.2f",$2*100/$1}}')
    report_DiskTotal=$((disktotal/1024/1024))"GB"   #硬盘总容量(GB)
    report_DiskFree=$((diskfree/1024/1024))"GB"     #硬盘剩余(GB)
    report_DiskUsedPercent="$diskusedpercent""%"    #硬盘使用率%
    report_InodeTotal=$((inodetotal/1000))"K"       #Inode总量
    report_InodeFree=$((inodefree/1000))"K"         #Inode剩余
    report_InodeUsedPercent="$inodeusedpercent""%"  #Inode使用率%

}


function getSystemStatus(){
    echo ""
    echo "############################ 系统检查 ############################"
    if [ -e /etc/sysconfig/i18n ];then
        default_LANG="$(grep "LANG=" /etc/sysconfig/i18n | grep -v "^#" | awk -F '"' '{print $2}')"
    else
        default_LANG=$LANG
    fi
    export LANG="en_US.UTF-8"
    Release=$(cat /etc/redhat-release 2>/dev/null)
    Kernel=$(uname -r)
    OS=$(uname -o)
    RepoVersion=$(cat /opt/zstack-dvd/.repo_version)
    Hostname=$(uname -n)
    SELinux=$(/usr/sbin/sestatus | grep "SELinux status: " | awk '{print $3}')
    LastReboot=$(who -b | awk '{print $3,$4}')
    uptime=$(uptime | sed 's/.*up \([^,]*\), .*/\1/')
    OpenProcesNum=$(expr $(ps aux | wc -l) - 1)
    CPUCoreNumber=$(cat /proc/cpuinfo |grep -c processor)
    UsedMemory=$(free -m | awk 'NR==2{printf "%sMB/%sMB (%.2f%%)\n", $3,$2,$3*100/$2 }')
    swap_num=$(free -m |sed -n 3p|awk '{print$2}')
	if [ $swap_num != 0 ];then
		UsedSwap=$(free -m | awk 'NR==3{printf "%sMB/%sMB (%.2f%%)\n", $3,$2,$3*100/$2 }')
	else
		UsedSwap=0
	fi
    UsedSystemDisk=$(df -lh | awk '$NF=="/"{printf "%s/%s (%s)\n", $3,$2,$5}')
    CPU_Load=$(cat /proc/loadavg|awk '{print $3}')


    echo "      系统：$OS"
    echo "  Repo版本：$RepoVersion"
    echo "  发行版本：$Release"
    echo "      内核：$Kernel"
    echo "    主机名：$Hostname"
    echo "   SELinux：$SELinux"
    echo " 语言/编码：$default_LANG"
    echo "  当前时间：$(date +'%F %T')"
    echo "  最后启动：$LastReboot"
    echo "  进程数量：$OpenProcesNum"
    echo "  运行时间：$uptime"
    echo " CPU核心数: $CPUCoreNumber"
    echo "  系统负载: $CPU_Load"
    echo "  已用内存: $UsedMemory"
    echo "  已用Swap: $UsedSwap"
    echo "系统盘使用: $UsedSystemDisk"
	echo "系统盘盘符: `df -lh |grep "/boot$"|awk '{print$1}'|sed 's/[0-9]//'`"
    echo " sysctl -p: $(sysctl -p)"

    #报表信息
    report_DateTime=$(date +"%F %T")  #日期
    report_Hostname="$Hostname"       #主机名
    report_OSRelease="$Release"       #发行版本
    report_Kernel="$Kernel"           #内核
    report_Language="$default_LANG"   #语言/编码
    report_LastReboot="$LastReboot"   #最近启动时间
    report_Uptime="$uptime"           #运行时间（天）
    report_OpenProcesNum="$OpenProcesNum" #运行中进程数量
    report_CPUCoreNumber="$CPUCoreNumber"  #CPU核心数
    report_UsedMemory="$UsedMemory"     #已用内存
    report_UsedSwap="$UsedSwap"       #已用swap
    report_UsedSystemDisk="$UsedSystemDisk" #已用系统盘
    report_Selinux="$SELinux"
    report_CPU_Load=$CPU_Load #CPU负载

    export LANG="$default_LANG"

}


function getHealthStatus(){
    echo ""
    echo "############################ 健康检查 ############################"
    rm -f /tmp/error
    cat /proc/loadavg |awk '{if ($3>=10) printf "Urgent:CPU总负载超过10	当前负载 %s\n", $3}'|tee /tmp/error
    load_15=`uptime | awk '{print $NF}'`
    cpu_num=`grep -c 'model name' /proc/cpuinfo`
    free -m |awk 'NR==2 {if($3*100/$2 >=80) printf "Urgent:内存使用超过80%，当前使用率为%.2f%，总内存 %dMB，已用内存%dMB\n", $3*100/$2,$2,$3}'|tee -a /tmp/error
    swap_num=$(free -m |sed -n 3p|awk '{print$2}')
    `ceph verison >/dev/null 2>&1`
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
    [ -s /tmp/dmesg ] && grep -E '[C]all Trace' /tmp/dmesg && echo "Urgent:Call_Trace_happened" && grep -E '[C]all Trace' /tmp/dmesg
    more /var/log/messages|grep -E '[O]ut of memory' |awk '{for(i=3+1;i<=NF;i++)printf $i " ";printf"\n"}'|uniq
    [ -s /tmp/dmesg ] && grep -E '[O]ut of memory' /tmp/dmesg  && echo "Important：Out_of_memory_happened" && grep -E '[O]ut of memory' /tmp/dmesg
}


function getServiceStatus(){
    echo ""
    echo "############################ 服务检查 ############################"
    echo ""
    if [[ $centosVersion > 7 ]];then
        conf=$(systemctl list-unit-files --type=service --state=enabled --no-pager | grep "enabled")
        process=$(systemctl list-units --type=service --state=running --no-pager | grep ".service")
        #报表信息
        report_SelfInitiatedService="$(echo "$conf" | wc -l)"       #自启动服务数量
        report_RuningService="$(echo "$process" | wc -l)"           #运行中服务数量
    else
        conf=$(/sbin/chkconfig | grep -E ":on|:启用")
        process=$(/sbin/service --status-all 2>/dev/null | grep -E "is running|正在运行")
        #报表信息
        report_SelfInitiatedService="$(echo "$conf" | wc -l)"       #自启动服务数量
        report_RuningService="$(echo "$process" | wc -l)"           #运行中服务数量
    fi
    echo "开机自启动的服务列表"
    echo "--------"
    echo "$conf"  | column -t
    echo ""
    echo "目前正在运行的服务列表"
    echo "--------------"
    echo "$process"

}



function getAutoStartStatus(){
    echo ""
    echo ""
    echo "############################ 自启动检查 ##########################"
    conf=$(grep -v "^#" /etc/rc.d/rc.local| sed '/^$/d')
    echo "$conf"
    echo ""
    echo "rc.local Info"
    ls -l /etc/rc.d/rc.local
    #报表信息
    report_SelfInitiatedProgram="$(echo $conf | wc -l)"    #自启动程序数量
}

function getLoginStatus(){
    echo ""
    echo ""
    echo "############################ 登录成功次数最多的IP地址 ############################"
    last | awk '{ print $3}' | sort |uniq -c |sort -nr |head -n 5
	echo "############################ 登录失败次数最多的IP地址 ############################"
	grep "Failed" /var/log/secure*|awk '{print $9 '=' $11}'|sort |uniq -c |sort -nr

}

function getNetworkStatus(){
    echo ""
    echo "############################ 网络检查 ############################"
    echo "device|link_status|driver|speed|vendor_device" |column -t -s  "|"
    #for i in `ip a|grep mtu|egrep -v "vnic|vxlan|br_|lo|@"|awk -F ":" '{print $2}'`;
    for i in `ip a|grep mtu|egrep -v "vnic|vxlan|lo|@"|awk -F ":" '{print $2}'`;
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
    echo "Bonding Mode Slave Info:"
    for i in `cat /sys/class/net/bonding_masters | sed 's/\ /\n/g' `;do echo "Bond_Info|$i|`cat /sys/class/net/$i/bonding/mode`|`cat /sys/class/net/$i/bonding/slaves`";done
    echo ""
    echo "IP Addr Info"
    #if [[ $centosVersion < 7 ]];then
    #    /sbin/ifconfig -a | grep -v packets | grep -v collisions | grep -v inet6
    #else
    #    #ip a
    #    for i in $(ip -d a |grep -w inet|awk  '{print $NF}');do ip add show $i | grep -E "BROADCAST|global"| awk '{print $2}' | tr '\n' ' ' ;echo "" ;done
    #fi
    ip -f inet addr | grep -v 127.0.0.1 |  grep inet | awk '{print $NF,$2}' | tr '\n' ',' | sed 's/,$//'
    echo ""
    echo "网关：$GATEWAY "
    echo "DNS：$DNS"
    echo ""
    echo "MAC Addr Info"
    ip link | egrep -v "LOOPBACK\|loopback|uuid" | awk '{print $2 }'|grep -v uuid |  sed 'N;s/\n//'
    MAC=$(ip link | grep -v "LOOPBACK\|loopback" | awk '{print $2}' | sed 'N;s/\n//' | tr '\n' ',' | sed 's/,$//')
    GATEWAY=$(ip route | grep default | awk '{print $3}')
    DNS=$(grep nameserver /etc/resolv.conf| grep -v "#" | awk '{print $2}' | tr '\n' ',' | sed 's/,$//')
    echo ""
    echo "Bond Info"
    zs-show-network | egrep -v '^\ |^[0-9]|^$'

    echo '############################ 网络IO信息 ############################'
    sar -n DEV 2 1|egrep -v "vnic|vxlan|outer|vx|docker0|lo"
    #报表信息
    report_IP="$IP"            #IP地址
    report_MAC=$MAC            #MAC地址
    report_Gateway="$GATEWAY"  #默认网关
    report_DNS="$DNS"          #DNS
}

function getListenStatus(){
    echo ""
    echo "############################ 端口检查 ############################"
    TCPListen=$(netstat -anp|egrep " 8056|:8051|:8052|:8053|:5432|:5433|:2379|:2380|:9200|:9300|:9090|:8061|:6789|:6800|:7480|:2049|:3260|:8005|:8009|:8080|:8080|:8081|:8090|:5000|:5443|:80|:9100|:9103|:7069|:8086|:8088|:9089|:9091|:4900|:5900|:7758|:53|:4369|:7070|:16509|:5345|:25|:3306|:123|:7171|:7762|:7761|:7770|:7771|:7772|:6080")
    echo "$TCPListen"
    #报表信息
	report_Listen="$(echo "$TCPListen")"
    # report_Listen="$(echo "$TCPListen"| sed '1d' | awk '/tcp/ {print $5}' | awk -F: '{print $NF}' | sort | uniq | wc -l)"
}

function getCronStatus(){
    echo ""
    echo "############################ 计划任务检查 ########################"
    Crontab=0
    for shell in $(grep -v "/sbin/nologin" /etc/shells);do
        for user in $(grep "$shell" /etc/passwd| awk -F: '{print $1}');do
            crontab -l -u $user >/dev/null 2>&1
            status=$?
            if [ $status -eq 0 ];then
                echo "$user"
                echo "--------"
                crontab -l -u $user
                let Crontab=Crontab+$(crontab -l -u $user | wc -l)
                echo ""
            fi
        done
    done
    #计划任务
    find /etc/cron* -type f | xargs -i ls -l {} | column  -t
    let Crontab=Crontab+$(find /etc/cron* -type f | wc -l)
    #报表信息
    report_Crontab="$Crontab"    #计划任务数
}

function getHowLongAgo(){
    datetime="$*"
    [ -z "$datetime" ] && echo "错误的参数：getHowLongAgo() $*"
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

function getUserStatus(){
    echo ""
    echo "############################ 用户检查 ############################"
    #/etc/passwd 最后修改时间
    pwdfile="$(cat /etc/passwd)"
    Modify=$(stat /etc/passwd | grep Modify | tr '.' ' ' | awk '{print $2,$3}')

    echo "/etc/passwd 最后修改时间：$Modify ($(getHowLongAgo $Modify))"
    echo ""
    echo "特权用户"
    echo "--------"
    RootUser=""
    for user in $(echo "$pwdfile" | awk -F: '{print $1}');do
        if [ $(id -u $user) -eq 0 ];then
            echo "$user"
            RootUser="$RootUser,$user"
        fi
    done
    echo ""
    echo "用户列表"
    echo "--------"
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
    echo "空密码用户"
    echo "----------"
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
    echo "相同ID的用户"
    echo "------------"
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
    #报表信息
    report_USERs="$USERs"    #用户
    report_USEREmptyPassword=$(echo $USEREmptyPassword | sed 's/^,//')
    report_USERTheSameUID=$(echo $USERTheSameUID | sed 's/,$//')
    report_RootUser=$(echo $RootUser | sed 's/^,//')    #特权用户
}


function getPasswordStatus {
    echo ""
    echo "############################ 密码检查 ############################"
    pwdfile="$(cat /etc/passwd)"
    echo ""
    echo "密码过期检查"
    echo "------------"
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
    echo "密码策略检查"
    echo "------------"
    grep -v "#" /etc/login.defs | grep -E "PASS_MAX_DAYS|PASS_MIN_DAYS|PASS_MIN_LEN|PASS_WARN_AGE"


}

function getSudoersStatus(){
    echo ""
    echo "############################ Sudoers检查 #########################"
    conf=$(grep -v "^#" /etc/sudoers| grep -v "^Defaults" | sed '/^$/d')
    echo "$conf"
    echo ""
    #报表信息
    report_Sudoers="$(echo $conf | wc -l)"
}

function getMNStatus(){
    echo ""
    if [ -f /usr/bin/zstack-ctl ]; then
        echo "########################## 管理节点信息检查 ##########################"
	zstack-ctl status
        echo ""
        echo "ZStack Folder Size Info"
	du -sh /usr/local/zstack/apache-tomcat/logs
        du -sh /usr/local/zstack
        du -sh /var/lib/zstack
	du -sBG /var/lib/zstack/prometheus
	pro_data_capacity=$(du -sBG /var/lib/zstack/prometheus | awk '{print $1}' | sed 's/G//g')
	if [ $pro_data_capacity -gt 120 ];then
		echo 'Urgent：监控数据(prometheus)已用空间超过120GB'
	fi
  pro_data_capacity2=$(du -sBG /var/lib/zstack/prometheus2 | awk '{print $1}' | sed 's/G//g')
	if [ $pro_data_capacity2 -gt 120 ];then
    echo 'Urgent：监控数据(prometheus2)已用空间超过120GB'
  fi
	if [ -d /opt/sds ];then du -h  /opt/sds  --max-depth=1 ;fi
    fi

    if [ `which zsha2` ]; then
        echo ""
        echo "ZStack Multi MN HA Info"
        zsha2 status
    fi

    if [ `which zsha` ]; then
        echo ""
        echo "ZStack MN VM HA Info"
        zsha status
    fi
}

function getProcessStatus(){
    echo ""
    echo "############################ 进程检查 ############################"
    if [ $(ps -ef | grep [d]efunct | wc -l) -ge 1 ];then
        echo ""
        echo "Urgent：存在僵尸进程：" ps -ef | grep [d]efunct ;
        echo "--------"
        ps -ef | head -n1
        ps -ef | grep [d]efunct
    fi
    echo ""
    echo "内存占用TOP20"
    echo "-------------"
    echo -e "PID %MEM RSS(GB) COMMAND
    $(ps aux | awk '{print $2, $4, $6/1024/1024, $11}' | sort -k3rn | head -n 20 )"| column -t
    echo ""
    echo "CPU占用TOP20"
    echo "------------"
    top b -n1 | head -27 | tail -21|column -t
    echo "物理机上所有VM内存/总内存:` ps aux | awk '{print $2, $4, $6/1024/1024, $11}'|grep qemu-kvm|awk '{sum+=$3} END{printf "%.2f GB",sum}'`/`free -h|grep Mem|awk '{print $2}'`"
    echo "物理机上所有VM CPU/总CPU: `top b -n1|grep qemu-kvm|awk '{sum+=$9} END{printf "%.0f",sum/100}'`/` cat /proc/cpuinfo |grep process -c`"
    #报表信息
    report_DefunctProsess="$(ps -ef | grep defunct | grep -v grep|wc -l)"
}

function getJDKStatus(){
    echo ""
    echo "############################ JDK检查 #############################"
    java -version 2>/dev/null
    if [ $? -eq 0 ];then
        java -version 2>&1
    fi
    echo "JAVA_HOME=\"$JAVA_HOME\""
    #报表信息
    report_JDK="$(java -version 2>&1 | grep version | awk '{print $1,$3}' | tr -d '\"')"
}

function getinfluxdbinfo(){
    echo ""
    echo "############################ influxdb检查 ##########################"
	influxdbPid=$(ps -ef | grep [i]nfluxdb | awk '{print $2}')
	cat /proc/$influxdbPid/status | grep VmRSS | awk '{if(($2/1024/1024)>16) print "Important：xxx";else print $2/1024/1024"GB"}'

}



function getSyslogStatus(){
    echo ""
    echo "############################ syslog检查 ##########################"
    echo "服务状态：$(getState rsyslog)"
    echo ""
    echo "/etc/rsyslog.conf"
    echo "-----------------"
    cat /etc/rsyslog.conf 2>/dev/null | grep -v "^#" | grep -v "^\\$" | sed '/^$/d'  | column -t
    #报表信息
    report_Syslog="$(getState rsyslog)"
}
function getFirewallStatus(){
    echo ""
    echo "############################ 防火墙检查 ##########################"
    #防火墙状态，策略等
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
    echo "iptables -nL"
    echo "-----------------------"
    iptables -nL 2>/dev/null

		#报表信息
    report_Firewall="$s"
}

function getEbtablesStatus(){
    echo ""
    echo "############################ 防火墙检查 ##########################"
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
	echo "ebtables:i $ebtabless"
	echo ""
	echo "ebtables -L"
	echo "-----------------------"
	ebtables -L 2>/dev/null
}

function getLibvirtdStatus(){
    #Libvirtd服务状态，配置等
    echo ""
    echo "############################ Libvirtd检查 ############################"
    status="$(getState libvirtd)"
    echo "服务状态：$status"
    echo ""
    if [ -e /etc/libvirt/libvirtd.conf ];then
        echo "/etc/libvirt/libvirtd.conf"
        echo "--------------------"
        cat /etc/libvirt/libvirtd.conf 2>/dev/null | grep -v "^#" | sed '/^$/d'
    fi
    #报表信息
    report_Libvirtd="$(getState libvirtd)"
}


function getAgentStatus(){
    #ZStack相关服务进程等
    echo ""
    echo "############################ ZStack Agent及服务检查 ############################"
    echo ""
    [ `ps -ef|grep [t]ools/prometheus -c` -gt 1 ]   && echo " prometheus info:" `ps -ef|grep [t]ools/prometheus |awk '{for(i=7+1;i<=NF;i++)printf $i " ";printf"\n"}'`
    [ `ps -ef|grep [k]vmagent -c` -gt 1 ]           && echo " kvmagent info:" `ps -ef|grep [k]vmagent|awk '{for(i=7+1;i<=NF;i++)printf $i " ";printf"\n"}'`
    [ `ps -ef|grep [z]sn-agent -c` -gt 1 ]          && echo " zsn-agent info:" `ps -ef|grep [z]sn-agent|awk '{for(i=7+1;i<=NF;i++)printf $i " ";printf"\n"}'`
    [ `ps -ef|grep [c]ephprimarystorage -c` -gt 1 ] && echo " cephprimarystorage info:" `ps -ef|grep [c]ephprimarystorage|awk '{for(i=7+1;i<=NF;i++)printf $i " ";printf"\n"}'`
    [ `ps -ef|grep [c]ephbackupstorage -c` -gt 1 ]  && echo " cephbackupstorage info:" `ps -ef|grep [c]ephbackupstorage|awk '{for(i=7+1;i<=NF;i++)printf $i " ";printf"\n"}'`
    [ `ps -ef|grep [z]stack_tui -c` -gt 1 ]         && echo " zstack_tui info:" `ps -ef|grep [z]stack_tui|awk '{for(i=7+1;i<=NF;i++)printf $i " ";printf"\n"}'`
    [ `ps -ef|grep [c]onsoleproxy -c` -gt 1 ]       && echo " consoleproxy info:" `ps -ef|grep [c]onsoleproxy|awk '{for(i=7+1;i<=NF;i++)printf $i " ";printf"\n"}'`
    [ `ps -ef|grep [d]nsmasq -c` -gt 1 ]            && echo " dnsmasq info:" `ps -ef|grep [d]nsmasq |awk '{for(i=7+1;i<=NF;i++)printf $i " ";printf"\n"}'`
    [ `ps -ef|grep [l]ighttpd -c` -gt 1 ]           && echo " lighttpd info:" `ps -ef|grep [l]ighttpd |awk '{for(i=7+1;i<=NF;i++)printf $i " ";printf"\n"}'`
    [ `ps -ef|grep [c]ollectd -c` -gt 1 ]           && echo " collectd info:" `ps -ef|grep [c]ollectd |awk '{for(i=7+1;i<=NF;i++)printf $i " ";printf"\n"}'`

}


function listLogInfo(){
    #列出相关日志路径
    echo ""
    echo "############################ ZStack 相关日志路径 ############################"
    echo "       管理节点日志: /usr/local/zstack/apache-tomcat/logs/management-server.log"
    echo "     管理节点UI日志: /usr/local/zstack/apache-tomcat/logs/zstack-ui.log"
    echo "   管理节点部署日志: /var/log/zstack/deploy.log"
    echo "物理机shell命令日志: /var/log/zstack/zstack.log"
    echo " 物理机KVMagent日志：/var/log/zstack/zstack-kvmagent.log"
    echo "       镜像仓库日志：/var/log/zstack/zstack-store/zstore.log"
    echo "     Ceph主存储日志：/var/log/zstack/ceph-primarystorage.log"
    echo " Ceph镜像服务器日志：/var/log/zstack/ceph-backupstorage.log"
    promethous_log=/var/lib/zstack/prometheus/data*
    apache_tomcat_log=/usr/local/zstack/apache-tomcat/logs/
    mysql_log=/var/lib/mysql
    zstack_log=/var/log/zstack/
    echo -e "log size :\n`du -sh ${apache_tomcat_log} ${promethous_log} ${zstack_log} ${mysql_log} 2> /dev/null`"
    size=`du -sh $mysql_log | awk -F " " '{print $1}' 2> /dev/null`
    if [[ -f $mysql_log ]];then
        if [[ $size =~ "G" ]];then
            echo ${size%G} | awk '{if($1>10) print "Important: 数据库日志文件大小超过10G";else print "Normal: 数据库日志文件大小低于10G"}'
        else
            echo "Normal: 数据库日志文件大小低于10G"
        fi
    fi
    echo ""
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

function getSSHStatus(){
    #SSHD服务状态，配置,受信任主机等
    echo ""
    echo "############################ SSH检查 #############################"
    #检查受信任主机
    pwdfile="$(cat /etc/passwd)"
    echo "服务状态：$(getState sshd)"
    Protocol_Version=$(cat /etc/ssh/sshd_config | grep Protocol | awk '{print $2}')
    echo "SSH协议版本：$Protocol_Version"
    echo ""
    echo "信任主机"
    echo "--------"
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
    echo "是否允许ROOT远程登录"
    echo "--------------------"
    config=$(cat /etc/ssh/sshd_config | grep PermitRootLogin)
    firstChar=${config:0:1}
    if [ $firstChar == "#" ];then
        PermitRootLogin="yes"  #默认是允许ROOT远程登录的
    else
        PermitRootLogin=$(echo $config | awk '{print $2}')
    fi
    echo "PermitRootLogin $PermitRootLogin"

    echo ""
    echo "/etc/ssh/sshd_config"
    echo "--------------------"
    cat /etc/ssh/sshd_config | grep -v "^#" | sed '/^$/d'

    #报表信息
    report_SSHAuthorized="$authorized"    #SSH信任主机
    report_SSHDProtocolVersion="$Protocol_Version"    #SSH协议版本
    report_SSHDPermitRootLogin="$PermitRootLogin"    #允许root远程登录
}

function getHardwareinformation(){
    #硬件信息
    echo ""
    echo "############################ 系统信息概览 #############################"
    /tmp/hardware.pl -d
    #echo -e "\nBIOS:\^"$(dmidecode -s bios-vendor) $(dmidecode -s bios-version) $(dmidecode -s bios-release-date)\
	#"\nOS:\^"$(cat /etc/redhat-release),$(uname -srm)\
	#"\nProduct:\^"$(dmidecode -s system-product-name 2>/dev/null | sed 's/ *$//g')\
	#"\nProduct Version:\^"$(dmidecode -s system-version 2>/dev/null | sed 's/ *$//g')\
	#"\nProduct Chassis:\^"$(dmidecode -s chassis-type 2>/dev/null | sed 's/ *$//g')\
	#"\nProduct Service Tag:\^"$(dmidecode -s system-serial-number 2>/dev/null | sed 's/ *$//g')\
	#"\nNetwork:\^"$(lspci|grep network)|column -ts "\^"
}

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

function gethosts(){
	#读取物理机hosts
	echo echo "############################ hosts一致性检查 #############################"
	cat /etc/hosts
}

# function uploadHostDailyCheckReport(){
    # json="{
        # \"DateTime\":\"$report_DateTime\",
        # \"Hostname\":\"$report_Hostname\",
        # \"OSRelease\":\"$report_OSRelease\",
        # \"Kernel\":\"$report_Kernel\",
        # \"Language\":\"$report_Language\",
        # \"LastReboot\":\"$report_LastReboot\",
        # \"Uptime\":\"$report_Uptime\",
        # \"CPUs\":\"$report_CPUs\",
        # \"CPUType\":\"$report_CPUType\",
        # \"Arch\":\"$report_Arch\",
        # \"MemTotal\":\"$report_MemTotal\",
        # \"MemFree\":\"$report_MemFree\",
        # \"MemUsedPercent\":\"$report_MemUsedPercent\",
        # \"DiskTotal\":\"$report_DiskTotal\",
        # \"DiskFree\":\"$report_DiskFree\",
        # \"DiskUsedPercent\":\"$report_DiskUsedPercent\",
        # \"InodeTotal\":\"$report_InodeTotal\",
        # \"InodeFree\":\"$report_InodeFree\",
        # \"InodeUsedPercent\":\"$report_InodeUsedPercent\",
        # \"IP\":\"$report_IP\",
        # \"MAC\":\"$report_MAC\",
        # \"Gateway\":\"$report_Gateway\",
        # \"DNS\":\"$report_DNS\",
        # \"Listen\":\"$report_Listen\",
        # \"Selinux\":\"$report_Selinux\",
        # \"Firewall\":\"$report_Firewall\",
        # \"USERs\":\"$report_USERs\",
        # \"USEREmptyPassword\":\"$report_USEREmptyPassword\",
        # \"USERTheSameUID\":\"$report_USERTheSameUID\",
        # \"PasswordExpiry\":\"$report_PasswordExpiry\",
        # \"RootUser\":\"$report_RootUser\",
        # \"Sudoers\":\"$report_Sudoers\",
        # \"SSHAuthorized\":\"$report_SSHAuthorized\",
        # \"SSHDProtocolVersion\":\"$report_SSHDProtocolVersion\",
        # \"SSHDPermitRootLogin\":\"$report_SSHDPermitRootLogin\",
        # \"DefunctProsess\":\"$report_DefunctProsess\",
        # \"SelfInitiatedService\":\"$report_SelfInitiatedService\",
        # \"SelfInitiatedProgram\":\"$report_SelfInitiatedProgram\",
        # \"RuningService\":\"$report_RuningService\",
        # \"Crontab\":\"$report_Crontab\",
        # \"Syslog\":\"$report_Syslog\",
        # \"Libvirtd\":\"$report_Libvirtd\",
        # \"NTP\":\"$report_NTP\",
        # \"JDK\":\"$report_JDK\"
    # }"
    # #echo "$json"
    # curl -l -H "Content-type: application/json" -X POST -d "$json" "$uploadHostDailyCheckReportApi" 2>/dev/null
# }

function getLibvirtQemuVersion(){
    echo ""
    echo "############################ Libvirt/Qemu版本检查 #############################"
    virsh version
}

function getRaidInfo(){
    echo "############################ Raid信息检查 #############################"
    lspci | grep -i raid
}

function getSanInfo(){
    echo "############################ SAN信息检查 #############################"
    if [ -x /usr/sbin/multipath ]; then
        cat /etc/multipath.conf|grep -v ^#
        multipathd show maps raw format "%n %w %N %d %S %t %s %e"
        multipath -ll
    fi
    # 检查多路径链路是否一致
    MultiPath=$(multipath -ll | grep [m]path | sort | xargs)
    echo "MultiPath ${MultiPath}"
}

function getVmList(){
	echo "############################ 物理机上vm信息检查 #############################"
    [ `ps -ef|grep [q]emu-kvm -c` -lt 1 ] && echo "NO VM Running" && return 0
	qemu_kvm_lists=$(ps -ef | grep [q]emu-kvm |awk -F ' ' '{print$10}' |sed 's/guest=//g'|cut -c -32|sort|sed ':t;N;s/\n//;b t')
	virsh_lists=$(virsh list|sed  '1,2d'|awk '{print $2}'|tr -s '\n'|sort|sed ':t;N;s/\n//;b t')
	qemu_kvm_list_num=$(ps -ef | grep [q]emu-kvm |awk -F ' ' '{print$10}' |sed 's/guest=//g'|cut -c -32|wc -l)
	virsh_list_num=$(virsh list|sed  '1,2d'|awk '{print $2}'|tr -s '\n'|wc -l)
	if [ "X$qemu_kvm_list_num" != "X$virsh_list_num" ]; then
        echo "Important:VM Number in QEMU-KVM and Virsh list not equal, it's on high risk"
    elif [ "X$qemu_kvm_lists" != "X$virsh_lists" ]; then
        echo "Important:VM in QEMU-KVM and Virsh list are not equal , it's on high risk"
    else
        echo "VM in QEMU-KVM and Virsh List are equal"
	fi
	virsh_num=$(virsh list | grep -i running | wc -l)
#	if [ $virsh_num -gt 20 ];then echo 'Important:该物理机上运行中的云主机超过20台，请检查！';fi
}

function chkCephConnections(){
	netstat -tulnp | grep 8056 > /dev/null 2>&1
	if [ $? -eq 0 ];then
		echo "############################ 物理机上postgresql信息检查 #############################"
		post_num=$(ps -ef | grep postgres | grep -v grep | wc -l )
		if [ "$post_num" = "" ];then
			echo '[WARNNING]: postgresql 进程不存在，请检查'
		elif [ $post_num -gt 1000 ];then
			echo "[WARNNING]: postgresql 进程数异常 ,线程数为：$post_num，请检查"
		else
			echo '[INFO]: postgresql 进程数正常'
		fi

	fi
}

function websocokify(){
	echo "############################ 物理机上websocokify信息检查 #############################"
    echo "websocokify个数为$(ps axjf |grep -v 'import websocokify' -c)"
}

# ##############################################################################
# Parse the output of dmesg, which should be in /tmp/aspersa, and detect RAID
# controllers.
# ##############################################################################
function parse_raid_controller_lspci () {
   if grep -q "RAID bus controller: LSI Logic / Symbios Logic MegaRAID SAS" /tmp/aspersa; then
      echo 'LSI Logic MegaRAID SAS'
   elif grep -q "Fusion-MPT SAS" /tmp/aspersa; then
      echo 'Fusion-MPT SAS'
   elif grep -q "RAID bus controller: LSI Logic / Symbios Logic Unknown" /tmp/aspersa; then
      echo 'LSI Logic Unknown'
   elif grep -q "RAID bus controller: Adaptec AAC-RAID" /tmp/aspersa; then
      echo 'AACRAID'
   elif grep -q "3ware [0-9]* Storage Controller" /tmp/aspersa; then
      echo '3Ware'
   elif grep -q "Hewlett-Packard Company Smart Array" /tmp/aspersa; then
      echo 'HP Smart Array'
   elif grep -q " RAID bus controller: " /tmp/aspersa; then
      awk -F: '/RAID bus controller\:/ {print $3" "$5" "$6}' /tmp/aspersa
   fi
}

# ##############################################################################
# Parse the output of dmesg, which should be in /tmp/aspersa, and detect RAID
# controllers.
# ##############################################################################
function parse_raid_controller_dmesg () {
   pat='scsi[0-9].*: .*'
   if grep -qi "${pat}megaraid" /tmp/aspersa; then
      echo 'LSI Logic MegaRAID SAS'
   elif grep -q "Fusion MPT SAS" /tmp/aspersa; then
      echo 'Fusion-MPT SAS'
   elif grep -q "${pat}aacraid" /tmp/aspersa; then
      echo 'AACRAID'
   elif grep -q "${pat}3ware [0-9]* Storage Controller" /tmp/aspersa; then
      echo '3Ware'
   fi
}

# ##############################################################################
# Parse the output of arcconf, which should be stored in /tmp/aspersa
# ##############################################################################
parse_arcconf () {
   model=$(awk -F: '/Controller Model/{print $2}' /tmp/aspersa)
   chan="$(awk -F: '/Channel description/{print $2}' /tmp/aspersa)"
   cache="$(awk -F: '/Installed memory/{print $2}' /tmp/aspersa)"
   status="$(awk -F: '/Controller Status/{print $2}' /tmp/aspersa)"
   name_val Specs "${model/ /},${chan},${cache} cache,${status}"

   battery=$(grep -A5 'Controller Battery Info' /tmp/aspersa \
      | awk '/Capacity remaining/ {c=$4}
             /Status/             {s=$3}
             /Time remaining/     {t=sprintf("%dd%dh%dm", $7, $9, $11)}
             END                  {printf("%d%%, %s remaining, %s", c, t, s)}')
   name_val Battery "${battery}"

   # ###########################################################################
   # Logical devices
   # ###########################################################################
   echo
   echo "  LogicalDev Size      RAID Disks Stripe Status  Cache"
   echo "  ========== ========= ==== ===== ====== ======= ======="
   for dev in $(awk '/Logical device number/{print $4}' /tmp/aspersa); do
      sed -n -e "/^Logical device .* ${dev}$/,/^$\|^Logical device number/p" \
         /tmp/aspersa \
      | awk '
         /Logical device name/               {d=$5}
         /Size/                              {z=$3 " " $4}
         /RAID level/                        {r=$4}
         /Group [0-9]/                       {g++}
         /Stripe-unit size/                  {p=$4 " " $5}
         /Status of logical/                 {s=$6}
         /Write-cache mode.*Ena.*write-back/ {c="On (WB)"}
         /Write-cache mode.*Ena.*write-thro/ {c="On (WT)"}
         /Write-cache mode.*Disabled/        {c="Off"}
         END {
            printf("  %-10s %-9s %4d %5d %-6s %-7s %-7s\n",
               d, z, r, g, p, s, c);
         }'
   done

   # ###########################################################################
   # Physical devices
   # ###########################################################################
   echo
   echo "  PhysiclDev State   Speed         Vendor  Model        Size        Cache"
   echo "  ========== ======= ============= ======= ============ =========== ======="

   # Find the paragraph with physical devices, tabularize with assoc arrays.
   tempresult=""
   sed -n -e '/Physical Device information/,/^$/p' /tmp/aspersa \
      | awk -F: '
         /Device #[0-9]/ {
            device=substr($0, index($0, "#"));
            devicenames[device]=device;
         }
         /Device is a/ {
            devices[device ",isa"] = substr($0, index($0, "is a") + 5);
         }
         /State/ {
            devices[device ",state"] = substr($2, 2);
         }
         /Transfer Speed/ {
            devices[device ",speed"] = substr($2, 2);
         }
         /Vendor/ {
            devices[device ",vendor"] = substr($2, 2);
         }
         /Model/ {
            devices[device ",model"] = substr($2, 2);
         }
         /Size/ {
            devices[device ",size"] = substr($2, 2);
         }
         /Write Cache/ {
            if ( $2 ~ /Enabled .write-back./ )
               devices[device ",cache"] = "On (WB)";
            else
               if ( $2 ~ /Enabled .write-th/ )
                  devices[device ",cache"] = "On (WT)";
               else
                  devices[device ",cache"] = "Off";
         }
         END {
            for ( device in devicenames ) {
               if ( devices[device ",isa"] ~ /Hard drive/ ) {
                  printf("  %-10s %-7s %-13s %-7s %-12s %-11s %-7s\n",
                     devices[device ",isa"],
                     devices[device ",state"],
                     devices[device ",speed"],
                     devices[device ",vendor"],
                     devices[device ",model"],
                     devices[device ",size"],
                     devices[device ",cache"]);
               }
            }
         }'

}

# ##############################################################################
# Parse the output of "lsiutil -i -s" from /tmp/aspersa
# ##############################################################################
parse_fusionmpt_lsiutil () {
   echo
   awk '/LSI.*Firmware/ { print " ", $0 }' /tmp/aspersa
   grep . /tmp/aspersa | sed -n -e '/B___T___L/,$ {s/^/  /; p}'
}

# ##############################################################################
# Parse the output of /opt/MegaRAID/MegaCli/MegaCli64 -AdpAllInfo -aALL from /tmp/aspersa.
# ##############################################################################
parse_lsi_megaraid_adapter_info () {
   name=$(awk -F: '/Product Name/{print substr($2, 2)}' /tmp/aspersa);
   int=$(awk '/Host Interface/{print $4}' /tmp/aspersa);
   prt=$(awk '/Number of Backend Port/{print $5}' /tmp/aspersa);
   bbu=$(awk '/^BBU             :/{print $3}' /tmp/aspersa);
   mem=$(awk '/Memory Size/{print $4}' /tmp/aspersa);
   vdr=$(awk '/Virtual Drives/{print $4}' /tmp/aspersa);
   dvd=$(awk '/Degraded/{print $3}' /tmp/aspersa);
   phy=$(awk '/^  Disks/{print $3}' /tmp/aspersa);
   crd=$(awk '/Critical Disks/{print $4}' /tmp/aspersa);
   fad=$(awk '/Failed Disks/{print $4}' /tmp/aspersa);
   name_val Model "${name}, ${int} interface, ${prt} ports"
   name_val Cache "${mem} Memory, BBU ${bbu}"
}

# ##############################################################################
# Parse the output (saved in /tmp/aspersa) of
# /opt/MegaRAID/MegaCli//opt/MegaRAID/MegaCli/MegaCli64 -AdpBbuCmd -GetBbuStatus -aALL
# ##############################################################################
parse_lsi_megaraid_bbu_status () {
   charge=$(awk '/Relative State/{print $5}' /tmp/aspersa);
   temp=$(awk '/^Temperature/{print $2}' /tmp/aspersa);
   soh=$(awk '/isSOHGood:/{print $2}' /tmp/aspersa);
   name_val BBU "${charge}% Charged, Temperature ${temp}C, isSOHGood=${soh}"
}

# ##############################################################################
# Parse physical devices from the output (saved in /tmp/aspersa) of
# /opt/MegaRAID/MegaCli//opt/MegaRAID/MegaCli/MegaCli64 -LdPdInfo -aALL
# OR, it will also work with the output of
# /opt/MegaRAID/MegaCli//opt/MegaRAID/MegaCli/MegaCli64 -PDList -aALL
# ##############################################################################
parse_lsi_megaraid_devices () {
   echo
   echo "  PhysiclDev Type State   Errors Vendor  Model        Size"
   echo "  ========== ==== ======= ====== ======= ============ ==========="
   for dev in $(awk '/Device Id/{print $3}' /tmp/aspersa); do
      sed -e '/./{H;$!d;}' -e "x;/Device Id: ${dev}/!d;" /tmp/aspersa \
      | awk '
         /Media Type/                        {d=substr($0, index($0, ":") + 2)}
         /PD Type/                           {t=$3}
         /Firmware state/                    {s=$3}
         /Media Error Count/                 {me=$4}
         /Other Error Count/                 {oe=$4}
         /Predictive Failure Count/          {pe=$4}
         /Inquiry Data/                      {v=$3; m=$4;}
         /Raw Size/                          {z=$3}
         END {
            printf("  %-10s %-4s %-7s %6s %-7s %-12s %-7s\n",
               substr(d, 0, 10), t, s, me "/" oe "/" pe, v, m, z);
         }'
   done
}

# ##############################################################################
# Parse virtual devices from the output (saved in /tmp/aspersa) of
# /opt/MegaRAID/MegaCli//opt/MegaRAID/MegaCli/MegaCli64 -LdPdInfo -aALL
# OR, it will also work with the output of
# /opt/MegaRAID/MegaCli//opt/MegaRAID/MegaCli/MegaCli64 -LDInfo -Lall -aAll
# ##############################################################################
parse_lsi_megaraid_virtual_devices () {
   # Somewhere on the Internet, I found the following guide to understanding the
   # RAID level, but I don't know the source anymore.
   #    Primary-0, Secondary-0, RAID Level Qualifier-0 = 0
   #    Primary-1, Secondary-0, RAID Level Qualifier-0 = 1
   #    Primary-5, Secondary-0, RAID Level Qualifier-3 = 5
   #    Primary-1, Secondary-3, RAID Level Qualifier-0 = 10
   # I am not sure if this is always correct or not (it seems correct).  The
   # terminology MegaRAID uses is not clear to me, and isn't documented that I
   # am aware of.  Anyone who can clarify the above, please contact me.
   echo
   echo "  VirtualDev Size      RAID Level Disks SpnDpth Stripe Status  Cache"
   echo "  ========== ========= ========== ===== ======= ====== ======= ========="
   awk '
      /^Virtual Disk:/ {
         device              = $3;
         devicenames[device] = device;
      }
      /Number Of Drives/ {
         devices[device ",numdisks"] = substr($0, index($0, ":") + 1);
      }
      /^Name:/ {
         devices[device ",name"] = $2 > "" ? $2 : "(no name)";
      }
      /RAID Level/ {
         devices[device ",primary"]   = substr($3, index($3, "-") + 1, 1);
         devices[device ",secondary"] = substr($4, index($4, "-") + 1, 1);
         devices[device ",qualifier"] = substr($NF, index($NF, "-") + 1, 1);
      }
      /Span Depth/ {
         devices[device ",spandepth"] = substr($2, index($2, ":") + 1);
      }
      /Number of Spans/ {
         devices[device ",numspans"] = $4;
      }
      /^Size:/ {
         devices[device ",size"] = substr($0, index($0, ":") + 1);
      }
      /^State:/ {
         devices[device ",state"] = $2;
      }
      /^Stripe Size:/ {
         devices[device ",stripe"] = $3;
      }
      /^Current Cache Policy/ {
         devices[device ",wpolicy"] = $4 ~ /WriteBack/ ? "WB" : "WT";
         devices[device ",rpolicy"] = $5 ~ /ReadAheadNone/ ? "no RA" : "RA";
      }
      END {
         for ( device in devicenames ) {
            raid = 0;
            if ( devices[device ",primary"] == 1 ) {
               raid = 1;
               if ( devices[device ",secondary"] == 3 ) {
                  raid = 10;
               }
            }
            else {
               if ( devices[device ",primary"] == 5 ) {
                  raid = 5;
               }
            }
            printf("  %-10s %-9s %-10s %5d %7s %6s %-7s %s\n",
               device devices[device ",name"],
               devices[device ",size"],
               raid " (" devices[device ",primary"] "-" devices[device ",secondary"] "-" devices[device ",qualifier"] ")",
               devices[device ",numdisks"],
               devices[device ",spandepth"] "-" devices[device ",numspans"],
               devices[device ",stripe"], devices[device ",state"],
               devices[device ",wpolicy"] ", " devices[device ",rpolicy"]);
         }
      }' /tmp/aspersa
}
function getGPUinfo(){
	echo "############################ GPU信息检查 #############################"
	lspci -vnn |grep  VGA -A 12 2>/dev/null
}

function getSaninfo(){
    echo "############################ SAN信息检查 #############################"
    cat /etc/multipath.conf|grep -v ^#
    multipathd show maps raw format "%n %w %N %d %S %t %s %e"
    multipath -ll
}


function getInstalledPackages(){
    echo "############################ 已安装rpm包检查 #############################"
    echo ""
    rpm -qa | sort
    echo ""
}

function chkEptParameters(){
        echo "############################ 物理机的 ept|npt 配置检测 #############################"
        ept_para=$(cat /sys/module/kvm_*/parameters/*pt)
        if [ "$ept_para" == "Y" || "$ept_para" == "1" ];then
            echo '[INFO]: ept(npt)参数已打开'
        else
            echo 'Important: ept(npt)参数未打开，请检查'
        fi
}
function hostReport(){
	echo "表$(hostname)"
	echo "计算节点巡检"
	echo "巡检时间,$(date '+%Y/%m/%d_%H:%M:%S')"
	echo "主机名,$(hostname),管理地址,$(hostname -I | head -n 1)"

	echo "系统类型,$(uname -a | awk '{print $NF}'),语言/编码 $(echo $LANG)"
	echo "系统版本,$(cat /etc/redhat-release),内核版本 $(uname -r)"
	echo "在线时长,$(uptime | sed 's/.*up \([^,]*\), .*/\1/'),最后启动 $(who -b | awk '{print $3,$4}')"
	echo "CPU型号,$(grep "model name" /proc/cpuinfo | awk -F ': ' '{print $2}' | sort | uniq),CPU核心数,$(grep "processor" /proc/cpuinfo | wc -l)"
	echo "系统负载,$(cat /proc/loadavg|awk '{print $3}'),已用内存,$(free -g | awk 'NR==2{printf "%sGB/%sGB(%.2f%%)\n", $3,$2,$3*100/$2 }')"
	echo "已用Swap,$(free -m | awk 'NR==3{if($2>0) printf "%sMB/%sMB(%.2f%%)\n", $3,$2,$3*100/$2 }'),系统盘使用,$(df -lh | awk '$NF=="/"{printf "%s/%s(%s)\n", $3,$2,$5}')"
	echo "服务检查"
	echo "序号,名称,状态"
	echo "1,Libvirtd,$(getState libvirtd)"
	echo "2,ZStack Agent,$(getState zstack-kvmagent)"
	echo "3,iptables,$(getState iptables)"
	echo "4,syslog,$(getState rsyslog)"
	echo "5,Chrony,$(getState chronyd)"

	echo "网络检查"
	echo "echo bond名称,网卡成员,Bond类型,是否丢失网卡"
	echo "$(for i in `cat /sys/class/net/bonding_masters | sed 's/\ /\n/g' `;do echo "$i,`cat /sys/class/net/$i/bonding/slaves`,`cat /sys/class/net/$i/bonding/mode`";done)"
	echo "内存占用TOP5"
	echo "PID,%MEM,RSS(GB),COMMAND"
	echo "$(echo -e "$(ps aux | awk '{print $2, $4, $6/1024/1024, $11}' | sort -k3rn | head -n 5 )" | awk -F '/' '{print $1,$NF}' | sed 's/[ ][ ]*/,/g')"
	echo "CPU占用TOP5"
	echo "$(top b -n1 | head -12 | tail -6 | awk '{print $1,$9,$NF}'  | sed 's/ /,/g')"
	echo -e "自启动检查\n$(cat /etc/rc.local | egrep -v '^#|^$|touch')"
	echo '日志占用空间大小'
	echo "$( du -sh /var/log | awk '{print $2,$1}' | sed 's/ /,/g')"
	echo "$(du -sh /usr/local/zstack | awk '{print $2,$1}' | sed 's/ /,/g')"
	echo "Libvirt/Qemu版本检查"
	echo "libvirt版本,运行中QEMU版本,libvirt API版本"
	echo "$(libvirtd -V),$(virsh version | grep 'hypervisor' | awk '{print $3,$4}'),$(virsh version | grep 'API' | awk '{print $3,$4}')"
	echo -e "时区、时间检查\n时区一致性,时间同步源"
	echo "$(timedatectl | grep zone | sed 's/,//g' | awk -F ' ' '{if($3=="Asia/Shanghai")print $3.$4,$5}'),$(chronyc sources -v | grep ^^ | awk '{print $2}' | xargs)"
	# 管理节点根盘查询
	zstack-ctl -h > /dev/null 2>&1
	if [ $? -gt 0 ];then
		rootCap=$(df -l| grep root | awk '{if($6 == "/") print $2/1024/1024}')
		echo $rootCap | awk '{if($1<600) print "Important：/分区小于600GB，建议全局设置监控数据保留周期设置为1个月，监控数据采样时间间隔设置为20秒"}'
	fi
}

function vmLists(){
  echo "############################ qemu-kvm进程列表 #############################"
  ps -ef | grep [q]emu-kvm
  echo "############################ virsh list列表 #############################"
  virsh list
}

function xsos_info(){
bash /tmp/xsos -a -x > $LOGPATH/xsos.log
}

function sysctl_info(){
sysctl -a > $LOGPATH/sysctl.log
}

function check(){
    version
    getCPU_C_State
    Check_temperature
    getSystemStatus
    getHardwareinformation
    getCpuStatus
    getMemStatus
    getDiskStatus
    getLibvirtdStatus
	getHealthStatus
    getNetworkStatus
    getProcessStatus
    getAgentStatus
    getTimeSyncStatus
    gethosts
	getLibvirtQemuVersion
    getGPUinfo
    getRaidInfo
    getSaninfo
    getAutoStartStatus
    getLoginStatus
    getCronStatus
    xsos_info
	sysctl_info
	getUserStatus
    getPasswordStatus
    getSudoersStatus
    getJDKStatus
    getFirewallStatus
    getEbtablesStatus
	getSSHStatus
    getServiceStatus
    getListenStatus
    getSyslogStatus
    listLogInfo
    getVirshListRunningNPaused
    getQemuKvmPNameList
    getVmList
    vmLists
    websocokify
    getInstalledPackages
    chkEptParameters
}



#执行检查并保存检查结果
check > $RESULTFILE

echo "检查结果：$RESULTFILE"
hostReport  > $HOSTREPORT
# iconv -f UTF8 -t GBK $HOSTREPORT -o $HOSTREPORT
#上传检查结果的文件
#curl -F "filename=@$RESULTFILE" "$uploadHostDailyCheckApi" 2>/dev/null

#上传检查结果的报表
#uploadHostDailyCheckReport 1>/dev/null

