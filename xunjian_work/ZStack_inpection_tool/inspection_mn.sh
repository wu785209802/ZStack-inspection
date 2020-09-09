#!/bin/bash
PARSE_JSON="./json.sh -l -p -b"
dd=$(date '+%Y-%m-%d')
log_dir=/tmp/inspectionlog-"$dd"
. ./.env
. /root/.bashrc
cat<<EOF
+------------------------------------------+
|             <管理节点巡检>               |
+------------------------------------------+
EOF

zs_sql_pwd_encrypt=$(grep DB.password /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/zstack.properties | awk '{print $3}')
zs_sql_pwd=`python ./aes.py ${zs_sql_pwd_encrypt}`
mysql_cmd=$(echo "mysql -uzstack -p${zs_sql_pwd} -e")

Passwd_Path="./.UnSecurity_Passwd.txt"
DB_User_1="root"
DB_User_2="zstack"
DB_Passwd_1="zstack.mysql.password"
DB_Passwd_2="zstack.password"
zs_properties=`zstack-ctl status|grep [z]stack.properties|awk '{print $2}'`
DB_IP=`cat $zs_properties|awk -F ":" '/DB.url /{print $3}'`
DB_IP=`echo ${DB_IP#*//}`
DB_Port=`cat  $zs_properties|awk -F ":" '/DB.url /{print $4}'`
SQL_Access="mysql -u $DB_User -p$DB_Password zstack -h $DB_IP -P $DB_Port"
UnSecurity_Passwd=$(cat $Passwd_Path)
Passwd_List=$(mysql -u $DB_User_1 -p$DB_Passwd_1 zstack -h $DB_IP -P $DB_Port -e "select * from KVMHostVO;" | grep "$DB_User_1" | awk -F " " '{print $3}')

function check_unsecurity_passwd(){
    Passwd_List=$(mysql -u $DB_User_1 -p$DB_Passwd_1 zstack -h $DB_IP -P $DB_Port -e "select * from KVMHostVO;" | grep "$DB_User_1" | awk -F " " '{print $3}')
    flag_1=0
    for passwd in ${Passwd_List[@]}
    do
        for pwd in ${UnSecurity_Passwd[@]}
        do
            if [[ $pwd == $passwd ]];then
                HOST_IP[$flag_1]=`mysql -u $DB_User_1 -p$DB_Passwd_1 zstack -h $DB_IP -P $DB_Port -e "select KVMHostVO.password,KVMHostVO.username,HostVO.managementIp from KVMHostVO,HostVO where KVMHostVO.uuid=HostVO.uuid and KVMHostVO.password in ('$pwd');" | awk -F " " '{print $3}' | sed "1d"`
            fi
            ((flag_1++))
        done
    done

    for ip_1 in ${HOST_IP[@]}
    do
        echo $ip_1 >> tmp_1.log
    done

    if [[ -f tmp_1.log  ]];then
        sort tmp_1.log | uniq >> ip_1.log
        ip_list=$(cat ./ip_1.log)
    fi

    for ip_2 in ${ip_list[@]};
    do
        echo "Important: 物理机($ip_2)的密码为弱密码"
    done
    if [[ -f tmp_1.log && ip_1.log ]];then
        rm -rf tmp_1.log && rm -rf ip_1.log
    fi
}

function check_passwd_len(){
    flag_2=0
    for passwd in ${Passwd_List[@]}
    do
        Passwd_LEN=${#passwd}
        if [[ $Passwd_LEN -lt 9 ]];then
            HOST_IP[$flag_2]=`mysql -u $DB_User_1 -p$DB_Passwd_1 zstack -h $DB_IP -P $DB_Port -e "select KVMHostVO.password,KVMHostVO.username,HostVO.managementIp from KVMHostVO,HostVO where KVMHostVO.uuid=HostVO.uuid and KVMHostVO.password in ('$passwd');" | awk -F " " '{print $3}' | sed "1d"`
        fi
        ((flag_2++))
    done

    for ip_3 in ${HOST_IP[@]}
    do
        echo $ip_3 >> tmp_2.log
    done

    if [[ -f tmp_2.log ]];then
        sort tmp_2.log | uniq >> ip_2.log
        ip_list=$(cat ./ip_2.log)
    fi

    for ip_4 in ${ip_list[@]}
    do
        echo "Important: 物理机($ip_4)的密码小于9位"
    done

    if [[ -f tmp_2.log && ip_2.log ]];then
      rm -rf tmp_2.log && rm -rf ip_2.log
    fi
}

function check_sql(){
    DB_User=$1
    DB_Password=$2
    DB_IP=$3
    DB_Port=$4
    SQL_Result=`mysql -u $DB_User -p$DB_Password zstack -h $DB_IP -P $DB_Port -e quit 2>&1`
    SQL_Result_Len=${#SQL_Result}
    if [[ ${SQL_Result_Len} -eq 0 ]];then
        echo "Important: 请修改数据库用户$1的默认密码"
    else
        echo "Important: 不是默认密码!"
    fi
}


function check_password(){
cat<<EOF
+------------------------------------------------------+
|             #检查物理机密码是否为弱密码#             |
+------------------------------------------------------+
EOF
    simple_password=$(check_unsecurity_passwd)
    if [[ -z $simple_password ]];then
       echo "物理机密码不是弱密码"
    else
       echo "$simple_password"
    fi
    echo ""

cat<<EOF
+------------------------------------------------------+
|             #检查物理机密码是否小于9位#              |
+------------------------------------------------------+
EOF
    password_len=$(check_passwd_len)
    if [[ -z $password_len ]];then
       echo "物理机密码长度大于9位"
    else
       echo "$password_len"
    fi
    echo ""

cat<<EOF
+------------------------------------------------------+
|             #检查数据库密码是否为默认#               |
+------------------------------------------------------+
EOF
    check_sql $DB_User_1 $DB_Passwd_1 $DB_IP $DB_Port
    check_sql $DB_User_2 $DB_Passwd_2 $DB_IP $DB_Port
    echo ""

}

function check_pool_size(){
cat<<EOF
+------------------------------------------+
|             #检查pool的容量#             |
+------------------------------------------+
EOF
    zstack-cli QueryPrimaryStorage | grep Ceph >>/dev/null 2>&1
    flag=`echo $?`
    if [[ $flag -eq 0 ]];then
        echo -e "pool_name\t总容量(T)\t使用容量(T)\t可用容量(T)\t使用率"
        body=`zstack-cli QueryPrimaryStorage type!=VCenter | $PARSE_JSON`
        count=`echo $body | grep '"pools",[0-9],"poolName"'| awk -F " " '{print $2}' | sort -u | wc -l`
        for i in ${count[@]}
        do
            poolName=`echo "$body" | grep "\"pools\"\,$i\,\"poolName\"" | awk -F '"' '{print $8}'`
            totalCapacity=`echo "$body" | grep "\"pools\"\,$i\,\"totalCapacity\"" | awk -F " " '{print $2}' |awk '{print $0/1024/1024/1024/1024}'`
            usedCapacity=`echo "$body" | grep "\"pools\"\,$i\,\"usedCapacity\"" | awk -F " " '{print $2}' |awk '{print $0/1024/1024/1024/1024}'`
            availableCapacity=`echo "$body" | grep "\"pools\"\,$i\,\"availableCapacity\"" | awk -F " " '{print $2}' |awk '{print $0/1024/1024/1024/1024}'`
            UtilizationRate=`awk "BEGIN {print $usedCapacity/$totalCapacity}"`
            echo -e "$poolName\t$totalCapacity\t$usedCapacity\t$availableCapacity\t$UtilizationRate"
        done
    fi
    echo ""
}

# 检查ZStack版本、运行状态及高可用方案
function get_mn_version(){
cat<<EOF
+----------------------------------------------+
|             #ZStack运行状态检查#             |
+----------------------------------------------+
EOF
    zstack_status=$(zstack-ctl status | grep status | awk  '{print $3}' | uniq |sed -r 's:\x1B\[[0-9;]*[mK]::g')
    zstack_version=$(zstack-ctl status | grep version)
    os_version=$(cat /etc/redhat-release && uname -r)
    # 拷贝zstack.properties配置文件
    cp /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/zstack.properties $LOG_PATH/log
    #cp /usr/local/zstack/zstack-ui/zstack.ui.properties $LOG_PATH/log
    chronyServer1=$(grep chrony.serverIp $LOG_PATH/log/zstack.properties | awk '{print $3}')
    echo "管理节点zstack.properties配置的时间同步源: ${chronyServer1}"
    echo ""
    # 版本及运行状态
    echo "${zstack_version}"
    echo ""
    echo "管理节点OS版本: ${os_version}" | xargs
    echo ""
    if [ "$zstack_status" == "Running" ];then
    	echo "ZStack服务运行中，状态为: ${zstack_status}"
        echo ""
    else
    	echo "ZStack服务未运行，状态为: ${zstack_status}"
        echo ""
    fi
    if [ -f /opt/zstack-dvd/.repo_version ];then
        echo "当前管理节点repo版本为`cat /opt/zstack-dvd/.repo_version`"
        echo ""
    else
        echo "当前管理节点repo版本为`cat /opt/zstack-dvd/x86_64/$YUM0/.repo_version`"
        echo ""
    fi
    # 高可用方案，注意，嵌套环境结果不正确
    ifVm=$(dmidecode -t system | grep Manufacturer | awk '{print $2$3}')
    ifZsha2=$($mysql_cmd "use zstack;SELECT COUNT(*) FROM ManagementNodeVO;" -N)
    if [ "${ifVm}" == "RedHat" ];then
        which zsha2 >/dev/null 2>&1
        if [ $? == 0 ];then
            slaveIoRunning=`zsha2 status --json | egrep  "slaveIoRunning|slaveSqlRuning" | sed 's/ //g' | xargs -n 3|awk -F ":|,| " '{print $2}'`
            slaveSqlRuning=`zsha2 status --json | egrep  "slaveIoRunning|slaveSqlRuning" | sed 's/ //g' | xargs -n 3|awk -F ":|,| " '{print $5}'`
            if [[ $slaveIoRunning == "true" && $slaveSqlRuning == "true" ]];then
                echo "Normal: zsha2 status数据库一致"
                echo ""
            else
                echo "Urgent: zsha2 status数据库不一致"
            fi
            echo "管理节点高可用方案为: 管理节点虚拟机HA"
        else
            echo "当前环境为嵌套环境，未配置高可用"
        fi
    fi
    if [ $ifZsha2 == 2 ];then
        echo "管理节点高可用方案为: 多管理节点HA"
        echo ""
        # 若是双管理节点，则拷贝slave节点的zstack.properties文件
        #self_IP=$(zstack-ctl status | grep status |grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}')
        IPs=$($mysql_cmd "use zstack;SELECT hostName FROM ManagementNodeVO;" -N)
        for ip in $IPs;do
            myip=$(hostname -I | grep -o $ip)
            if [ "$myip" ];then
                cp $log_dir/log/zstack.properties $log_dir/log/${myip}.zstack.properties
                cp /usr/local/zstack/zstack-ui/zstack.ui.properties $log_dir/log/${myip}.zstack.ui.properties
            else
                if [ -f /opt/zstack-dvd/.repo_version ];then
                    echo "远端管理节点repo版本为`ssh -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa $ip cat /opt/zstack-dvd/.repo_version`"
                    echo ""
                else
                    echo "当前管理节点repo版本为`ssh -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa $ip cat /opt/zstack-dvd/x86_64/$YUM0/.repo_version`"
                    echo ""
                fi
                scp -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa -v $ip:/usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/zstack.properties $log_dir/log/${ip}.zstack.properties >> /dev/null 2>&1
                scp -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa $ip:/usr/local/zstack/zstack-ui/zstack.ui.properties $log_dir/log/${ip}.zstack.ui.properties >> /dev/null 2>&1
                chronyServer2=$(grep chrony.serverIp $log_dir/log/${ip}.zstack.properties | awk '{print $3}')
                echo "管理节点(peer)zstack.properties配置的时间同步源: ${chronyServer2}"
                echo ""
            fi
        done
    else
        echo "未配置管理节点高可用"
        echo ""
    fi


    # 是否复用为计算节点
    ifHost=$($mysql_cmd "use zstack;SELECT mn.hostName FROM ManagementNodeVO mn JOIN HostVO hv ON mn.hostName = hv.managementIp;" | grep -v hostName)
    if [ -n "$ifHost" ];then
        echo "管理节点复用为计算节点，IP: "
        echo "${ifHost}"
        echo ""
    else
        echo "管理节点未复用为计算节点"
        echo ""
    fi
    # 是否复用为镜像服务器
    ifMnBs=$($mysql_cmd "use zstack;SELECT ibs.hostname FROM ImageStoreBackupStorageVO ibs JOIN ManagementNodeVO mn on ibs.hostname = mn.hostName;"| grep -v hostname)
    if [ -n "$ifMnBs" ];then
    	echo "管理节点复用为镜像服务器，IP: "
        echo "${ifMnBs}"
        echo ""
    else
    	echo "管理节点未复用为镜像服务器"
        echo ""
    fi
    # 计算节点是否复用为镜像服务器
    ifHoBs=$($mysql_cmd "use zstack;SELECT ibs.hostname FROM ImageStoreBackupStorageVO ibs JOIN HostVO hv on ibs.hostname = hv.managementIp;"| grep -v hostname)
    if [ -n "$ifHoBs" ];then
    	echo "计算节点复用为镜像服务器，IP: "
        echo "${ifHoBs}"
        echo ""
    else
    	echo "计算节点未复用为镜像服务器"
        echo ""
    fi
}

function check_addons(){
cat<<EOF
+---------------------------------------------+
|             #附加增值模块检查#              |
+---------------------------------------------+
EOF
    addon_num=$(zstack-cli GetLicenseAddOns | grep uuid |wc -l)
    echo "购买了以下 $addon_num 个附加模块:"
    licinfo=$(zstack-cli GetLicenseAddOns | egrep 'expiredDate|issuedDate|service-7x24|project-management|disaster-recovery|baremetal|arm64|vmware|v2v' | sed 's/ //g' | xargs -n3 | awk -F ':|T| |,' '{print$15,$9,$2}'| grep -v '^ ' | sed 's/ /,/g')
    for i in $licinfo;
    do
        licName=$(echo $i | awk -F ',' '{print $1}')
        expiredDate=$(echo $i | awk -F ',' '{print $3}')
        avaliableTime=$(($(date +%s -d "${expiredDate}")-$(date -d "`date  "+%Y-%m-%d"`" +%s)))
        avaliableDays=$(echo $avaliableTime | awk '{print $1/86400}')
        echo $licName $avaliableDays | awk '{if($2>15)print $1": 正常，还有"$2"天过期";else if($2<0) print "Important: "$1"已过期";else {print "Important: "$1"还有"$2"天过期"}}'
        echo ""
    done
}

function check_license(){
cat<<EOF
+-------------------------------------------+
|             #平台License检查#             |
+-------------------------------------------+
EOF
    licinfo=$(zstack-cli GetLicenseInfo | egrep 'expiredDate|issuedDate' | sed 's/ //g' | xargs -n3 | awk -F ':|T| |,' '{print $9,$2}' |sed 's/ /,/g')
    expiredDate=$(echo $licinfo | awk -F ',' '{print $2}')
    avaliableTime=$(($(date +%s -d "${expiredDate}")-$(date -d "`date  "+%Y-%m-%d"`" +%s)))
    avaliableDays=$(echo $avaliableTime | awk '{print $1/86400}')
    echo $avaliableDays | awk '{if($1>15)print "License: 正常，还有"$1"天过期";else if($1<0) print "Urgent: License已过期";else {print "Urgent: License还有"$1"天过期"}}'
    echo ""
}

function check_crontab(){
cat<<EOF
+----------------------------------------+
|             #备份任务检查#             |
+----------------------------------------+
EOF
    echo "管理节点备份任务: "
    sudo crontab -l | grep "dump_mysql" | grep "zstack-ctl"
    echo ""
    if [ -f /etc/zsha2.conf ];then
        echo "管理节点备份任务(Peer): "
        peer_ip=`cat /etc/zsha2.conf | grep peer | awk -F '"' '{print $4}'`
        ssh -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa ${peer_ip} "crontab -l" | grep "dump_mysql" | grep "zstack-ctl"
        echo ""
    fi

}

function check_db_backup(){
cat<<EOF
+-------------------------------------------+
|             #数据库备份检查#              |
+-------------------------------------------+
EOF
    localBackupDir='/var/lib/zstack/mysql-backup'
    remoteBackupDir='/var/lib/zstack/from-zstack-remote-backup'
    backup_host_list=$(crontab -l| grep 'zstack-ctl dump_mysql' | grep -oE "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}")
    # 本地数据库备份信息
    echo '本地数据库备份文件如下: '
    ls $localBackupDir/zstack-backup-db* | head -5 | grep -v total | awk -F '/' '{print$NF}'
    back_num=`ls $localBackupDir/ | wc -l`
    echo ""
    echo "本地数据库备份文件数量: "
    echo "$back_num"
    echo ""
    echo '本地数据库备份大小: '
    du -sh $localBackupDir/ | awk '{print $2,$1}'
    echo ""
    # 远程数据库备份信息
    if [[ $backup_host_list ]];then
        for host_list in $backup_host_list
        do
            echo "远程主机IP: "
            echo "$host_list"
            echo ""
            dbBackupFiles=$(ssh -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa $host_list ls $remoteBackupDir 2>/dev/null |grep 'zstack-backup-db' | head -5 2>/dev/null)
            dbBackupFiles_num=$(ssh -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa $host_list ls $remoteBackupDir/ |wc -l)
            dbbackupSize=$(ssh -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa $host_list du -sh $remoteBackupDir/ 2>/dev/null | awk '{print $2,$1}')
        if [ "$dbBackupFiles" == "" ];then
            echo "Urgent: 远程主机 ${host_list} 远程备份未生效，请检查！"
        else
            echo "远程数据库备份文件: ${dbBackupFiles}" | sed 's/ /\n/g'
            echo ""
            echo "远程数据库备份文件数量: "
            echo "$dbBackupFiles_num"
            echo ""
            echo -e "远程数据库备份大小:\n${dbbackupSize}"
            echo ""
        fi
        done
    else
        echo "Urgent: 未配置远程备份，请检查！"
        echo ""
    fi

    mnIPs=$($mysql_cmd "use zstack;SELECT hostName FROM ManagementNodeVO;" | grep -v hostName)
    for mnIP in $mnIPs
    do
    hostname -I | grep $mnIP >> /dev/null 2>&1
    if [ $? -ne 0 ];then
        #echo $mnIP
        echo "(管理节点$mnIP)本地数据库备份文件如下: "
        ssh -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa $mnIP ls $localBackupDir | head -5 | grep -v total | awk -F '/' '{print$NF}'
        echo ""
        echo "(管理节点$mnIP)本地数据库备份文件数量: "
        remote_back_num=`ssh -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa $mnIP ls $localBackupDir/ | wc -l`
        echo "$remote_back_num"
        echo ""
        echo "(管理节点$mnIP)本地数据库备份大小: "
        ssh -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa $mnIP du -sh $localBackupDir/ | awk '{print $2,$1}'
        echo ""
        backup_host_list=$(ssh -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa $mnIP crontab -l| grep 'zstack-ctl dump_mysql' | grep -oE "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}")
        #echo $backup_host_list
        if [[ $backup_host_list ]];then
            for host_list in $backup_host_list
            do
                echo "(管理节点$mnIP)远程主机IP: "
                echo "$host_list"
                #ssh $mnIP sshpass -p password ssh $host_list ls $remoteBackupDir
                dbBackupFiles=$(ssh -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa $mnIP  ssh -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa $host_list ls $remoteBackupDir 2>/dev/null |grep 'zstack-backup-db' | head -5 2>/dev/null)
                dbBackupFiles_num=$(ssh -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa $mnIP  ssh -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa $host_list ls $remoteBackupDir/ |wc -l)
                dbbackupSize=$(ssh -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa $mnIP  ssh -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa $host_list du -sh $remoteBackupDir/ 2>/dev/null | awk '{print $2,$1}')
                if [ "$dbBackupFiles" == "" ];then
                    echo "Urgent: (管理节点$mnIP)远程主机 ${host_list} 远程备份未生效，请检查！"
                else
                    echo "远程数据库备份文件: ${dbBackupFiles}" | sed 's/ /\n/g'
                    echo ""
                    echo "远程数据库备份文件数量: "
                    echo "$dbBackupFiles_num"
                    echo ""
                    echo -e "远程数据库备份大小:\n${dbbackupSize}"
                    echo ""
                fi
            done
        else
            echo "Urgent: (管理节点$mnIP)未配置远程备份，请检查!"
        fi
    fi
    done
}

function check_pre_allocation(){
cat<<EOF
+--------------------------------------------------------+
|             #本地存储的云盘预分配策略检查#             |
+--------------------------------------------------------+
EOF
    Body=`zstack-cli QueryPrimaryStorage`
    if [[ $Body =~ "LocalStorage" ]];then
       allocation_str=$($mysql_cmd "use zstack;SELECT GlobalConfigVO.NAME,GlobalConfigVO.VALUE FROM GlobalConfigVO WHERE category='localStoragePrimaryStorage' AND description='qcow2 allocation policy, can be none, metadata, falloc, full';"| grep -v "NAME" | sed 's/\t/,/g')
       allocation=`echo $allocation_str | awk -F "," '{print $2}'`
       if [[ "$allocation_str" =~ "falloc" ]];then
           echo "Normal: 本地存储的云盘预分配策略为falloc"
       else
           echo "Urgent: 本地存储的云盘的预分配策略为$allocation"
       fi
       echo ""
    else
       echo "Normal: 没有使用本地存储"
       echo ""
    fi
}

function check_auto_mount(){
cat<<EOF
+------------------------------------------------------+
|             #镜像服务器是否单独挂载检查#             |
+------------------------------------------------------+
EOF
     # 镜像服务器是否单独挂载
    im_bs_mount_info=$(zstack-cli QueryImageStoreBackupStorage fields=hostname,url | egrep 'hostname|url' | awk -F '"' '{print $4}' |sed -n '{N;s/\n/ /p}' |sed 's/ /,/g')
    if [ -n "${im_bs_mount_info}" ];then
        for bs_info in $(echo $im_bs_mount_info | sed 's/ /\n/g');do
             host_IP=$(echo $bs_info | awk -F ',' '{print $1}')
             mount_point=$(echo $bs_info | awk -F ',' '{print $2}')
             ssh $host_IP -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa grep $mount_point /etc/rc.local >> /dev/null 2>&1
             if [ $? -ne 0 ];then
                 echo "Normal: 镜像服务器${host_IP}上${mount_point}与 / 共用"
                 # echo "镜像服务器:${host_IP}上${mount_point}未单独挂载(若与/共用，请忽略该消息)"
             else
                 ssh $host_IP -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa df -Th 2> /dev/null | grep $mount_point > /dev/null 2>&1
                 if [ $? -ne 0 ];then
                     echo "Urgent: 镜像服务器${host_IP}上${mount_point}未单独挂载，请检查！"
                 else
                     echo "Normal: 镜像服务器${host_IP}上${mount_point}已单独挂载"
                 fi
             fi
             echo ""
        done
    else
        echo '未使用镜像服务器'
    fi
     # 主存储是否单独挂载
cat<<EOF
+--------------------------------------------------+
|             #主存储是否单独挂载检查#             |
+--------------------------------------------------+
EOF
     local_ps_mount_info=$($mysql_cmd "use zstack;SELECT hv.managementIp,psv.url FROM PrimaryStorageVO psv,PrimaryStorageClusterRefVO psa,HostVO hv WHERE psv.type='LocalStorage' AND psa.primaryStorageUuid = psv.uuid AND hv.clusterUuid = psa.clusterUuid ORDER BY hv.managementIp"|grep -v url | sed 's/\t/,/g')
     if [ -n "${local_ps_mount_info}" ];then
         for ps_info in $(echo $local_ps_mount_info | sed 's/ /\n/g');do
             host_IP=$(echo $ps_info | awk -F ',' '{print $1}')
             mount_point=$(echo $ps_info | awk -F ',' '{print $2}')
             #ssh $host_IP -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa df -lh 2>> /dev/null | grep $mount_point >> /dev/null 2>&1
             ssh $host_IP -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa grep $mount_point /etc/rc.local >> /dev/null 2>&1
             if [ $? -ne 0 ];then
                 ssh $host_IP -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa grep $mount_point /etc/rc.local >> /dev/null 2>&1
                 echo "Normal: 本地存储${host_IP}上${mount_point} 与 / 共用"
                 #echo "本地存储:${host_IP}上${mount_point}未单独挂载(若与/共用，请忽略该消息)"
             else
                 echo "Normal: 本地存储${host_IP}上${mount_point}已单独挂载"
             fi
         done
     else
         echo '未使用本地存储'
         echo ""
     fi

     # Ceph类型主存储是否填写了pool UUID


cat<<EOF
+---------------------------------------------------------------+
|             #Ceph主存储是否填写了唯一的pool UUID#             |
+---------------------------------------------------------------+
EOF
     pool_info=$($mysql_cmd "use zstack;SELECT DISTINCT(primaryStorageUuid) AS psUuid,poolName,count(poolName) AS poolNum FROM CephPrimaryStoragePoolVO;" | grep -v psUuid | sed 's/\t/,/g')

     for p_info in $(echo ${pool_info} | sed 's/ /\n/g');do
         p_num=$(echo ${p_info} | awk -F ',' '{print $3}')
         ps_uuid=$(echo ${p_info} | awk -F ',' '{print $1}')
         p_uuid=$(echo ${p_info} | awk -F ',' '{print $2}')
         if [ $p_num -eq 3 ];then
             echo "主存储(UUID): ${ps_uuid} 填写了唯一的pool UUID: ${p_uuid}"
         elif [ $p_num -eq 0 ];then
             echo '未使用Ceph类型的主存储'
         else
             echo "主存储(UUID): ${ps_uuid} 未填写唯一的pool UUID: ${p_uuid}"
         fi
     done
     echo ""
}


function QueryPrimaryStorageInfo(){
cat<<EOF
+------------------------------------------+
|             #主存储容量查询#             |
+------------------------------------------+
EOF
    #ps_totalPhysicalCapacity=$(zstack-cli QueryPrimaryStorage type!=VCenter | grep totalPhysicalCapacity | grep -oE '[0-9]+' | awk '{sum+=$1}END{print sum/1024/1024/1024}')
    #ps_availablePhysicalCapacity=$(zstack-cli QueryPrimaryStorage type!=VCenter | grep availablePhysicalCapacity | grep -oE '[0-9]+' | awk '{sum+=$1}END{print sum/1024/1024/1024}')
    ps_info=$($mysql_cmd "
    use zstack;
    SELECT
    	t1.total_phy_cap,
    	ROUND( ( t1.total_phy_cap - t1.ava_phy_cap ) / t1.total_phy_cap, 2 ) AS used_phy_per,
    	t1.total_cap,
    	ROUND( ( t1.total_cap - t1.ava_cap ) / t1.total_cap, 2 ) AS used_per
    FROM
    	(
    SELECT
    	ROUND( SUM( psv.totalCapacity / 1024 / 1024 / 1024 ) ) AS total_cap,
    	ROUND( SUM( psv.totalPhysicalCapacity / 1024 / 1024 / 1024 ) ) AS total_phy_cap,
    	ROUND( SUM( psv.availableCapacity / 1024 / 1024 / 1024 ) ) AS ava_cap,
    	ROUND( SUM( psv.availablePhysicalCapacity / 1024 / 1024 / 1024 ) ) AS ava_phy_cap
    FROM
    	PrimaryStorageCapacityVO psv,
    	PrimaryStorageVO ps
    WHERE
    	ps.uuid = psv.uuid
    	AND ps.type != 'VCenter'
    	) t1;
    quit" | grep -v total_phy_cap)

    # 15 主存储总物理容量(GB)
    #echo $(echo $ps_info | awk '{print $1}')>>$result
    ps_info_1=$(echo $ps_info | awk '{print $1}')
    echo "主存储总物理容量: $ps_info_1"
    echo ""

    # 16 主存储已用物理容量百分比(0.00)
    #echo $(echo $ps_info | awk '{print $2}')>>$result
    ps_info_2=$(echo $ps_info | awk '{print $2}')
    echo "主存储已用物理容量百分比: $ps_info_2"
    echo ""

    #15-1 主存储总容量(GB)
    #echo $(echo $ps_info | awk '{print $3}')>>$result
    ps_info_3=$(echo $ps_info | awk '{print $3}')
    echo "主存储总容量: $ps_info_3"
    echo ""

    # 16 主存储已用容量百分比(0.00)
    #echo $(echo $ps_info | awk '{print $4}')>>$result
    ps_info_4=$(echo $ps_info | awk '{print $4}')
    echo "主存储已用容量百分比: $ps_info_4"
    echo ""
}

function QueryWarnning(){
cat<<EOF
+----------------------------------------+
|             #全局设置检查#             |
+----------------------------------------+
EOF
    # 该函数为检查全局设置中设置不合理的值进行报警
    bsReservedCapacity=$($mysql_cmd "use zstack;SELECT value FROM GlobalConfigVO WHERE name='ReservedCapacity' AND category='backupStorage';" | grep -v value | sed 's/G//g')
    psReservedCapacity=$($mysql_cmd "use zstack;SELECT value FROM GlobalConfigVO WHERE name='ReservedCapacity' AND category='primaryStorage';" | grep -v value | sed 's/G//g')
    vmHA=$($mysql_cmd "use zstack;SELECT value FROM GlobalConfigVO WHERE name='Enable' AND category='HA'; " | grep -v value)
    CPUOverProvisioningRatio=$($mysql_cmd  "use zstack;SELECT value FROM GlobalConfigVO WHERE name='CPU.overProvisioning.ratio';" | grep -v value)
    ReservedMemory=$($mysql_cmd "use zstack;SELECT value FROM GlobalConfigVO WHERE name='ReservedMemory';" | grep -v value | sed 's/G//g')
    MemOverProvisioning=$($mysql_cmd "use zstack;SELECT value FROM GlobalConfigVO WHERE name = 'overProvisioning.memory';" | grep -v value)
    psOverProvisioning=$($mysql_cmd "use zstack;SELECT value FROM GlobalConfigVO WHERE name = 'overProvisioning.primaryStorage';" | grep -v value)
    psThreshold=$($mysql_cmd "use zstack;SELECT value FROM GlobalConfigVO WHERE name = 'threshold.primaryStorage.physicalCapacity';" | grep -v value)

    echo $bsReservedCapacity | awk '{if($0<1){print "Important: 镜像服务器保留容量设置过小，当前为: "$0"GB"}}'
    echo $psReservedCapacity | awk '{if($0<1){print "Important: 主存储保留容量设置过小，当前为: "$0"GB"}}'
    echo $vmHA | awk '{if($0=="false"){print "Important: 云主机高可用全局开关为关闭状态，建议打开"}}'
    echo $CPUOverProvisioningRatio | awk '{if($0>10){print "Important: CPU超分率设置过高，当前为: $0"}}'
    echo $ReservedMemory | awk '{if($0<1){print "Important: 物理机保留内存设置过小，当前为: "$0"GB"}}'
    echo $MemOverProvisioning | awk '{if($0>1.2){print "Important: 内存超分率设置过高，当前为: "$0}}'
    echo $psOverProvisioning | awk '{if($0>1.2){print "Important: 主存储超分率设置过高，当前为: "$0}}'
    echo $psThreshold | awk '{if($0>0.85){print "Important: 主存储使用阈值设置过高，当前为: "$0}}'
}

function check_logmonitor(){
cat<<EOF
+----------------------------------------------+
|             #Prometheus版本查询#             |
+----------------------------------------------+
EOF
IPs=$($mysql_cmd "use zstack;SELECT hostName FROM ManagementNodeVO;" -N)
    for mnip in $IPs
    do
        hostname -I | grep $mnip >> /dev/null 2>&1
        if [ $? -eq 0 ];then
            PrometheusVersion=`zstack-ctl show_configuration |grep Prometheus.ver|awk '{print$NF}'`
            if [ "s$PrometheusVersion" = s"1.8.2" ];then
                echo "当前管理节点$mnip使用prometheus版本为1.8.2"
            elif [ "s$PrometheusVersion" = s ];then
                echo "当前管理节点$mnip使用prometheus版本为1.8.2"
            elif [ "s$PrometheusVersion" = s"2.x" ];then
                echo "当前管理节点$mnip使用prometheus版本为2.9.2版本"
            elif [ "s$PrometheusVersion" = s"2.x-compatible" ];then
                echo "当前管理节点$mnip使用prometheus版本为2.9.2版本，兼容1.8.2版本数据"
            elif [ "s$PrometheusVersion" = s"none" ];then
                echo "当前管理节点$mnip环境已禁用Prometheus"
            fi
            echo ""
            echo "prometheus监控大小: "
            du -sBG /var/lib/zstack/prometheus
            echo ""
            echo "influxdb监控大小: "
            du -sBG /var/lib/zstack/influxdb/
        else
            RemotePrometheusVersion=$(ssh $mnip zstack-ctl show_configuration |grep Prometheus.ver|awk '{print$NF}')
            if [ "s$RemotePrometheusVersion" = s"1.8.2" ];then
                echo "远端管理节点$mnip使用prometheus版本为1.8.2"
            elif [ "s$RemotePrometheusVersion" = s ];then
                echo "远端管理节点$mnip使用prometheus版本为1.8.2"
            elif [ "s$RemotePrometheusVersion" = s"2.x" ];then
                echo "远端管理节点$mnip使用prometheus版本为2.9.2版本"
            elif [ "s$RemotePrometheusVersion" = s"2.x-compatible" ];then
                echo "远端管理节点$mnip使用prometheus版本为2.9.2版本，兼容1.8.2版本数据"
            elif [ "s$RemotePrometheusVersion" = s"none" ];then
                echo "远端管理节点$mnip当前已禁用Prometheus"
            fi
            echo ""
            echo "prometheus监控大小: "
            ssh $mnip du -sBG /var/lib/zstack/prometheus
            echo ""
            echo "influxdb监控大小: "
            ssh $mnip du -sBG /var/lib/zstack/influxdb/
        fi
    done
}

function check_storage_network(){
cat<<EOF
+--------------------------------------------------+
|             #存储心跳网络正确性检查#             |
+--------------------------------------------------+
EOF
    primaryStorageUuid=$(zstack-cli QuerySystemTag tag~=primaryStorage::gateway::cidr::|grep uuid| awk -F '"' '{print $4}')
    hostnum=$(zstack-cli QueryHost count=true | grep total | awk -F ':' '{print $2}'|tr -d " ")
    my_array=$(zstack-cli QueryHost fields=clusterUuid,managementIp |egrep "clusterUuid|managementIp"| awk -F '"' '{print $4}')
    gatewayNetwork=$(zstack-cli QuerySystemTag tag~=primaryStorage::gateway::cidr:: | grep tag | awk -F '"' '{print $4}'|awk -F "::" '{print$4}')
    hostnum=$(($hostnum-1))
    for netmask in $gatewayNetwork
    do
        resourceprimaryUuid=$(zstack-cli QuerySystemTag tag~=primaryStorage::gateway::cidr::$netmask|grep resourceUuid|awk -F '"' '{print $4}')
        attachedClusterUuids=$(zstack-cli QueryPrimaryStorage uuid=$resourceprimaryUuid | grep attachedClusterUuids -A 1 |grep -v attachedClusterUuids | awk -F '"' '{print $2}')
        declare -a names=($my_array)
        for hostnumcount in `seq 0 $hostnum`
        do
            Subnet=$(echo $netmask|awk -F "/" '{print$2}')
            if [ $Subnet = 8 ];then
                 netmask_changed=$(echo $netmask |awk -F "." '{print$1".0.0.0/8"}')
            elif [ $Subnet = 16 ];then
                 netmask_changed=$(echo $netmask |awk -F "." '{print$1"."$2".0.0/16"}')
            elif [ $Subnet = 17 ];then
                 netmask_changed=$(echo $netmask |awk -F "." '{print$1"."$2"."$3".0/17"}')
            elif [ $Subnet = 18 ];then
                 netmask_changed=$(echo $netmask |awk -F "." '{print$1"."$2"."$3".0/18"}')
            elif [ $Subnet = 19 ];then
                 netmask_changed=$(echo $netmask |awk -F "." '{print$1"."$2"."$3".0/19"}')
            elif [ $Subnet = 20 ];then
                 netmask_changed=$(echo $netmask |awk -F "." '{print$1"."$2"."$3".0/20"}')
            elif [ $Subnet = 21 ];then
                 netmask_changed=$(echo $netmask |awk -F "." '{print$1"."$2"."$3".0/21"}')
            elif [ $Subnet = 22 ];then
                 netmask_changed=$(echo $netmask |awk -F "." '{print$1"."$2"."$3".0/22"}')
            elif [ $Subnet = 23 ];then
                 netmask_changed=$(echo $netmask |awk -F "." '{print$1"."$2"."$3".0/23"}')
            elif [ $Subnet = 24 ];then
                 netmask_changed=$(echo $netmask |awk -F ".|/" '{print$1"."$2"."$3"."$4"/24"}')
            elif [ $Subnet = 25 ];then
                 netmask_changed=$(echo $netmask |awk -F ".|/" '{print$1"."$2"."$3"."$4"/25"}')
            elif [ $Subnet = 26 ];then
                 netmask_changed=$(echo $netmask |awk -F ".|/" '{print$1"."$2"."$3"."$4"/26"}')
            elif [ $Subnet = 27 ];then
                 netmask_changed=$(echo $netmask |awk -F ".|/" '{print$1"."$2"."$3"."$4"/27"}')
            elif [ $Subnet = 28 ];then
                 netmask_changed=$(echo $netmask |awk -F ".|/" '{print$1"."$2"."$3"."$4"/28"}')
            elif [ $Subnet = 29 ];then
                 netmask_changed=$(echo $netmask |awk -F ".|/" '{print$1"."$2"."$3"."$4"/29"}')
            elif [ $Subnet = 30 ];then
                 netmask_changed=$(echo $netmask |awk -F ".|/" '{print$1"."$2"."$3"."$4"/30"}')
            fi
            if [ "$attachedClusterUuids" = "${names[$(($hostnumcount*2))]}" ];then
               remoteipr=$(ssh -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa ${names[$(($hostnumcount*2+1))]} ip r)
               echo $remoteipr |grep $netmask_changed >/dev/null 2>&1
               if [ $? -eq 0 ];then
                   echo "Normal: The ${names[$(($hostnumcount*2+1))]} Storage Network is correct"
               else
                   echo "Urgent: The ${names[$(($hostnumcount*2+1))]} Storage Network is error"
               fi
            fi
        done
    done
    echo ""
}


function QueryHostMemoryUsedInPercent(){
cat<<EOF
+-------------------------------------------+
|             #物理机内存负载#              |
+-------------------------------------------+
EOF
    echo "物理机UUID                       内存负载"
    zstack-cli GetMetricData namespace=ZStack/Host metricName=MemoryUsedInPercent | egrep 'HostUuid|value' | xargs -n2 | xargs -n8 |sed 'N;s/\n/ /'|awk 'used=($4+$8+$12+$16)/4 {if(used>0)print $2,used"%";else print $2}'|sort -k2 -rn
    echo ""
}

function QueryNwIo(){
cat<<EOF
+---------------------------------------+
|             #网络吞吐量#              |
+---------------------------------------+
EOF
    # 网络吞吐量--发送
    net_load_out=$(zstack-cli GetMetricData metricName='NetworkAllOutBytes' offsetAheadOfCurrentTime=310 period=10 namespace=ZStack/Host | grep value | awk -F ' ' '{sum+=$2}END{print sum/NR/1024}')
    # 网络吞吐量--接收
    net_load_in=$(zstack-cli GetMetricData metricName='NetworkAllInBytes' offsetAheadOfCurrentTime=310 period=10 namespace=ZStack/Host | grep value | awk -F ' ' '{sum+=$2}END{print sum/NR/1024}')
    echo "网络吞吐量--发送: $net_load_out KB"
    echo ""
    echo "网络吞吐量--接收: $net_load_in KB"
    echo ""
}

function QueryDiskIo(){
cat<<EOF
+-----------------------------------+
|             #磁盘IO#              |
+-----------------------------------+
EOF
    # 磁盘IO
    disk_load_write=$(zstack-cli GetMetricData metricName='DiskAllWriteBytes' offsetAheadOfCurrentTime=310 period=10 namespace=ZStack/Host  | grep value | awk -F ' ' '{sum+=$2}END{print sum/NR/1024}')
    # 磁盘IO
    disk_load_read=$(zstack-cli GetMetricData metricName='DiskAllReadBytes' offsetAheadOfCurrentTime=310 period=10 namespace=ZStack/Host  | grep value | awk -F ' ' '{sum+=$2}END{print sum/NR/1024}')
    echo "磁盘IO--写: $disk_load_write KB"
    echo ""
    echo "磁盘IO--读: $disk_load_read KB"
    echo ""
}

function QueryZsCheck(){
cat<<EOF
+------------------------------------------------+
|             #90天内未操作的云主机#             |
+------------------------------------------------+
EOF
    #没有闲置90天的云主机
    notoperatingvm=`$mysql_cmd "use zstack;SELECT count(*) FROM VmInstanceVO vv WHERE  DATE_ADD(vv.lastOpDate,INTERVAL 90 DAY)< CURRENT_DATE ORDER BY vv.lastOpDate;"| grep -v count`
    if [ "$notoperatingvm" -lt 1 ];then
        echo "没有闲置90天的云主机"
    else
        $mysql_cmd "
        use zstack;
        SELECT vv.name,vv.uuid,lastOpDate
        FROM VmInstanceVO vv WHERE  DATE_ADD(vv.lastOpDate,INTERVAL 90 DAY)< CURRENT_DATE ORDER BY vv.lastOpDate;
        quit"
    fi
    echo ""

cat<<EOF
+--------------------------------------------------------+
|             #占用物理存储最多的云主机TOP5#             |
+--------------------------------------------------------+
EOF
    $mysql_cmd "
    use zstack;
    SELECT vv1.name AS vmName,vv.uuid AS rootVolumeUuid,ROUND(vv.actualSize/1024/1024/1024) AS 'actualSize(GB)'
    FROM VolumeVO vv, VmInstanceVO vv1
    WHERE vv.type = 'Root'
    AND vv.uuid = vv1.rootVolumeUuid
    ORDER BY vv.actualSize DESC
    LIMIT 5;
    quit"
    echo ""

cat<<EOF
+------------------------------------------------------+
|             #占用物理存储最多的云盘TOP5#             |
+------------------------------------------------------+
EOF
    $mysql_cmd "
    use zstack;
    SELECT vv.name AS volumeName,vv.uuid AS dataVolumeUuid,ROUND(vv.actualSize/1024/1024/1024) AS 'actualSize(GB)'
    FROM VolumeVO vv
    WHERE vv.type = 'Data'
    #AND vv.vmInstanceUuid IS NOT NULL
    ORDER BY vv.actualSize DESC
    LIMIT 5;
    quit"
    echo ""

cat<<EOF
+--------------------------------------------------------+
|             #占用物理存储最多的镜像TOP10#              |
+--------------------------------------------------------+
EOF
    $mysql_cmd "
    use zstack;
    SELECT iv.name AS imageName,iv.uuid AS imageUuid,ROUND(iv.actualSize/1024/1024/1024) AS 'actualSize(GB)'
    FROM ImageVO iv
    ORDER BY iv.actualSize DESC
    LIMIT 10;
    quit"
    echo ""

cat<<EOF
+-----------------------------------------------------+
|             #CPU利用率超过80%的云主机#              |
+-----------------------------------------------------+
EOF
    cpuallusedutilizstion=`zstack-cli GetMetricData metricName=CPUAllUsedUtilization offsetAheadOfCurrentTime=310 period=10 namespace=ZStack/VM | egrep 'VMUuid|value' | sed -n '{N;s/\n/\t/p}' | awk -F '"' '{print $4,$NF}' |awk '{s[$1] += $3}END{ for(i in s){ print s[i]/32,i } }' | sort -nr | awk '{if($1>80) print $2,$1}'`
    if [ -z "$cpuallusedutilizstion" ];then
        echo "无CPU利用率超过80%的云主机"
    else
        zstack-cli GetMetricData metricName=CPUAllUsedUtilization offsetAheadOfCurrentTime=310 period=10 namespace=ZStack/VM | egrep 'VMUuid|value' | sed -n '{N;s/\n/\t/p}' | awk -F '"' '{print $4,$NF}' |awk '{s[$1] += $3}END{ for(i in s){ print s[i]/32,i } }' | sort -nr | awk '{if($1>80) print $2,$1}'
    fi
    echo ""

cat<<EOF
+--------------------------------------------------+
|             #CPU负载高于80%的物理机#             |
+--------------------------------------------------+
EOF
    CPUAllUsedUtilization=`zstack-cli GetMetricData metricName=CPUAllUsedUtilization offsetAheadOfCurrentTime=310 period=10 namespace=ZStack/Host | egrep 'HostUuid|value' | sed -n '{N;s/\n/\t/p}' | awk -F '"' '{print $4,$NF}' |awk '{s[$1] += $3}END{ for(i in s){ print s[i]/32,i}}' | sort -nr | awk '{if($1>80) print $2,$1}'`
    if [ -z "$CPUAllUsedUtilization" ];then
        echo "无CPU负载超过80%的物理机"
    else
        zstack-cli GetMetricData metricName=CPUAllUsedUtilization offsetAheadOfCurrentTime=310 period=10 namespace=ZStack/Host | egrep 'HostUuid|value' | sed -n '{N;s/\n/\t/p}' | awk -F '"' '{print $4,$NF}' |awk '{s[$1] += $3}END{ for(i in s){ print s[i]/32,i}}' | sort -nr | awk '{if($1>80) print $2,$1}'
    fi
    echo ""

cat<<EOF
+----------------------------------------------------+
|             #内存负载高于80%的物理机#              |
+----------------------------------------------------+
EOF
    MemoryUsedCapacityPerHostInPercent=`zstack-cli GetMetricData metricName=MemoryUsedCapacityPerHostInPercent offsetAheadOfCurrentTime=310 period=10 namespace=ZStack/Host | egrep 'HostUuid|value' | sed -n '{N;s/\n/\t/p}' | awk -F '"' '{print $4,$NF}' |awk '{s[$1] += $3}END{ for(i in s){ print s[i]/32,i}}' | sort -nr | awk '{if($1>80) print $2,$1}'`
    if [ -z "$MemoryUsedCapacityPerHostInPercent" ];then
        echo "无内存负载高于80%的物理机"
    else
        zstack-cli GetMetricData metricName=MemoryUsedCapacityPerHostInPercent offsetAheadOfCurrentTime=310 period=10 namespace=ZStack/Host | egrep 'HostUuid|value' | sed -n '{N;s/\n/\t/p}' | awk -F '"' '{print $4,$NF}' |awk '{s[$1] += $3}END{ for(i in s){ print s[i]/32,i}}' | sort -nr | awk '{if($1>80) print $2,$1}'
    fi
    echo ""

cat<<EOF
+-------------------------------------------------------+
|             #磁盘已用空间高于80%的物理机#             |
+-------------------------------------------------------+
EOF
    DiskRootUsedCapacityInPercent=`zstack-cli GetMetricData metricName=DiskRootUsedCapacityInPercent offsetAheadOfCurrentTime=310 period=10 namespace=ZStack/Host | egrep 'HostUuid|value' | sed -n '{N;s/\n/\t/p}' | awk -F '"' '{print $4,$NF}' |awk '{s[$1] += $3}END{ for(i in s){ print s[i]/32,i}}' | sort -nr | awk '{if($1>80) print $2,$1}'`
    if [ -z "$DiskRootUsedCapacityInPercent" ];then
        echo "无磁盘占用超过80%的物理机"
    else
        zstack-cli GetMetricData metricName=DiskRootUsedCapacityInPercent offsetAheadOfCurrentTime=310 period=10 namespace=ZStack/Host | egrep 'HostUuid|value' | sed -n '{N;s/\n/\t/p}' | awk -F '"' '{print $4,$NF}' |awk '{s[$1] += $3}END{ for(i in s){ print s[i]/32,i}}' | sort -nr | awk '{if($1>60) print $2,$1}'
    fi
    echo ""

cat<<EOF
+--------------------------------------------+
|             #未加载状态的云盘#             |
+--------------------------------------------+
EOF
    umountvolume=`$mysql_cmd "use zstack;SELECT count(*) FROM VolumeVO vv WHERE vv.format in ('raw','qcow2') AND vv.vmInstanceUuid IS NULL ORDER BY size DESC,actualSize DESC;"|grep -v count`
    if [ "$umountvolume" -lt 1 ];then
        echo "无未加载状态的云盘"
    else
        $mysql_cmd "
        use zstack;
        SELECT vv.name,vv.uuid,ROUND(vv.size/1024/1024/1024) AS 'size(GB)',ROUND(vv.actualSize/1024/1024/1024) AS 'actualSize(GB)' FROM VolumeVO vv
        WHERE vv.format in ('raw','qcow2') AND vv.vmInstanceUuid IS NULL ORDER BY size DESC,actualSize DESC;
        quit"
    fi
    echo ""


cat<<EOF
+-----------------------------------------------------+
|             #用物理容量超过80%的主存储#             |
+-----------------------------------------------------+
EOF
    Costphysicalprimarycapacity=`$mysql_cmd "use zstack;
    SELECT count(*) FROM PrimaryStorageVO ps,PrimaryStorageCapacityVO psv
    WHERE type != 'VCenter'
    AND ps.uuid = psv.uuid
    AND psv.availableCapacity / psv.totalCapacity < 0.2;"|grep -v count`
    if [ "$Costphysicalprimarycapacity" -lt 1 ];then
        echo "无已用物理容量超过80%的主存储"
    else
        $mysql_cmd "
        use zstack;
        SELECT ps.name,ps.uuid,
        ROUND(psv.totalPhysicalCapacity/1024/1024/1024/1024) AS 'totalPhysicalCapacity(TB)',
        ROUND(psv.availablePhysicalCapacity/1024/1024/1024/1024) AS 'availablePhysicalCapacity(TB)',
        ROUND(psv.totalCapacity/1024/1024/1024/1024) AS 'totalCapacity(TB)',
        ROUND(psv.availableCapacity/1024/1024/1024/1024) AS 'availableCapacity(TB)'
        FROM PrimaryStorageVO ps,PrimaryStorageCapacityVO psv
        WHERE type != 'VCenter'
        AND ps.uuid = psv.uuid
        AND psv.availableCapacity / psv.totalCapacity < 0.2;
        quit"
    fi
    echo ""

cat<<EOF
+--------------------------------------------------------+
|             #已用容量超过80%的镜像服务器#              |
+--------------------------------------------------------+
EOF
    Costphysicalimagecapacity=`$mysql_cmd "use zstack; SELECT count(*) FROM BackupStorageVO bs
    WHERE bs.type != 'VCenter'
    AND bs.availableCapacity / bs.totalCapacity < 0.2
    AND bs.uuid NOT IN (SELECT DISTINCT(st.resourceUuid) FROM SystemTagVO st WHERE st.resourceUuid = bs.uuid AND st.tag = 'onlybackup');"|grep -v count`
    if [ "$Costphysicalimagecapacity" -lt 1 ];then
        echo "无已用容量超过80%的镜像服务器"
    else
        $mysql_cmd "
        use zstack;
        SELECT bs.name,bs.uuid,
        ROUND(bs.totalCapacity/1024/1024/1024/1024) AS 'totalCapacity(TB)',
        ROUND(bs.availableCapacity/1024/1024/1024/1024) AS 'availableCapacity(TB)'
        FROM BackupStorageVO bs
        WHERE bs.type != 'VCenter'
        AND bs.availableCapacity / bs.totalCapacity < 0.2
        AND bs.uuid NOT IN (SELECT DISTINCT(st.resourceUuid) FROM SystemTagVO st WHERE st.resourceUuid = bs.uuid AND st.tag = 'onlybackup');
        quit"
    fi
    echo ""

cat<<EOF
+-----------------------------------------+
|             #已失联物理机#              |
+-----------------------------------------+
EOF
    disconnecthost=`$mysql_cmd "use zstack;SELECT count(*) FROM HostVO hv WHERE hv.hypervisorType = 'KVM' AND hv.status = 'Disconnected';" | grep -v count`
    if [ "$disconnecthost" -lt 1 ];then
        echo "没有失联的物理机"
    else
        $mysql_cmd "
        use zstack;
        SELECT hv.name,hv.managementIp,hv.state,hv.status
        FROM HostVO hv
        WHERE hv.hypervisorType = 'KVM'
        AND hv.status = 'Disconnected';
        quit"
    fi
    echo ""

cat<<EOF
+----------------------------------------+
|             #已失联主存储#             |
+----------------------------------------+
EOF
    disconnectprimarystroage=`$mysql_cmd "
    use zstack;
    SELECT count(*) FROM PrimaryStorageVO ps
    WHERE ps.type != 'VCenter'
    AND ps.status = 'Disconnected';"|grep -v count`
    if [ "$disconnectprimarystroage" -lt 1 ];then
        echo "没有失联主存储"
    else
        $mysql_cmd "
        use zstack;
        SELECT ps.name,ps.uuid,ps.state,ps.status
        FROM PrimaryStorageVO ps
        WHERE ps.type != 'VCenter'
        AND ps.status = 'Disconnected';
        quit"
    fi
    echo ""

cat<<EOF
+----------------------------------------------+
|              #已失联镜像服务器#              |
+----------------------------------------------+
EOF
    disconnectimagestory=`$mysql_cmd "
    use zstack;
    SELECT count(*) FROM BackupStorageVO bs
    WHERE bs.type != 'VCenter'
    AND bs.status = 'Disconnected'
    AND bs.uuid NOT IN (SELECT DISTINCT(st.resourceUuid) FROM SystemTagVO st WHERE st.resourceUuid = bs.uuid AND st.tag = 'onlybackup');"|grep -v count`
    if [ "$disconnectimagestory" -lt 1 ];then
        echo "没有失联镜像服务器"
    else
        $mysql_cmd "
        use zstack;
        SELECT bs.name,bs.uuid,bs.state,bs.status
        FROM BackupStorageVO bs
        WHERE bs.type != 'VCenter'
        AND bs.status = 'Disconnected'
        AND bs.uuid NOT IN (SELECT DISTINCT(st.resourceUuid) FROM SystemTagVO st WHERE st.resourceUuid = bs.uuid AND st.tag = 'onlybackup');
        quit"
    fi
    echo ""


cat<<EOF
+--------------------------------------------+
|              #非运行中云主机#              |
+--------------------------------------------+
EOF
    notrunningvm=`$mysql_cmd "
    use zstack;
    SELECT count(*) FROM VmInstanceVO vv
    WHERE vv.state != 'Running'
    AND vv.hypervisorType = 'KVM';"|grep -v count`
    if [ "$notrunningvm" -lt 1  ];then
        echo "没有非运行中的云主机"
    else
        $mysql_cmd "
        use zstack;
        SELECT vv.name,vv.uuid,vv.state FROM VmInstanceVO vv
        WHERE vv.state != 'Running'
        AND vv.hypervisorType = 'KVM';
        quit" | column -t
    fi
    echo ""
}

function check_fragmentation(){
cat<<EOF
+--------------------------------------------+
|              #磁盘碎片化检查#              |
+--------------------------------------------+
EOF
    echo "物理机碎片化检查: "
    zstack-cli GetMetricData namespace=ZStack/Host metricName=DiskXfsFragInPercent| egrep 'HostUuid|value' | xargs -n2 |xargs -n16 |awk 'used=($4+$8+$12+$16)/4 {if(used>10)print "Important: " $2,used"%";else print "Normal: " $2,used"%"}'
    echo ""
    echo "云盘碎片化检查: "
    zstack-cli GetMetricData metricName=VolumeXfsFragCount namespace=ZStack/Volume | egrep 'VolumeUuid|value' | xargs -n2 |xargs -n16|awk 'used=($4+$8+$12+$16)/4 {if(used>10)print "Important: " $2,used"%";else print "Normal: " $2,used"%"}'
    echo ""
}

function check_user(){
cat<<EOF
+--------------------------------------+
|              #用户检查#              |
+--------------------------------------+
EOF
    user_info=$(zstack-cli GetAuditData limit=1 auditType=Login conditions=apiName=org.zstack.header.identity.APILogInByUserMsg |grep createDate|tail -n 1|awk -F"createDate\":\"" '{print$2}'|awk -F"\"" '{print$1}')
    if [[ -z $user_info ]];then
        echo "用户检查为空"
    else
        echo "$user_info"
    fi
}

function get_zs_version(){
cat<<EOF
+--------------------------------------------+
|              #版本及运行状态#              |
+--------------------------------------------+
EOF
    # 版本及运行状态
    zstack_status=$(zstack-ctl status | grep status | awk  '{print $3}' | uniq |sed -r 's:\x1B\[[0-9;]*[mK]::g')
    zstack_version=$(zstack-ctl status | grep version)
    os_version=$(cat /etc/redhat-release && uname -r)
    echo "ZStack版本: ${zstack_version}"
    echo ""
    echo "管理节点OS版本: ${os_version}" | xargs
    echo ""
    if [ "$zstack_status" == "Running" ];then
        echo "ZStack服务运行中，状态为: ${zstack_status}"
    else
        echo "ZStack服务未运行，状态为: ${zstack_status}"
    fi
    echo ""
    # 高可用方案，注意:未检测管理节点HA方案
    ifVm=$(dmidecode -t system | grep Manufacturer | awk '{print $2$3}')
    ifZsha2=$($mysql_cmd "use zstack; SELECT count(*) FROM ManagementNodeVO;" -N)
    if [ "${ifZsha2}" == "2" ];then
        echo "管理节点高可用方案为：多管理节点HA"
    elif [ "${ifVm}" == "RedHat" ];then
        echo "管理节点高可用方案为：管理节点虚拟机HA"
    else
        echo "未配置管理节点高可用方案"
    fi
    echo ""
}

function get_resource(){
cat<<EOF
+------------------------------------------+
|              #资源数量查询#              |
+------------------------------------------+
EOF
    IPAvailableCapacity=$(zstack-cli GetIpAddressCapacity all=true | grep availableCapacity | grep -oE [0-9]+ | uniq )
    IPTotalCapacity=$(zstack-cli GetIpAddressCapacity all=true | grep totalCapacity | grep -oE [0-9]+ | uniq)
    hostTotal=$($mysql_cmd "
        use zstack;
        SELECT count(*) AS hostTotal FROM HostVO hv
        WHERE hv.hypervisorType = 'KVM';
        quit" | grep -v hostTotal)
      psTotal=$($mysql_cmd "
        use zstack;
        SELECT COUNT(*) AS psTotal FROM PrimaryStorageVO psv
        WHERE psv.type != 'VCenter';
        quit" | grep -v psTotal)
      bsTotal=$($mysql_cmd "
        use zstack;
          SELECT count(*) AS bsTotal FROM BackupStorageVO bsv
          WHERE bsv.type != 'VCenter'
          AND bsv.uuid NOT IN (SELECT st.resourceUuid FROM SystemTagVO st WHERE st.tag = 'onlybackup');
          quit" | grep -v bsTotal)
      vmTotal=$($mysql_cmd "
        use zstack;
          SELECT COUNT( * ) AS vmTotal
          FROM VmInstanceVO vv
          WHERE vv.hypervisorType = 'KVM'
          AND vv.type = 'UserVm'
          AND state IN ('Running','Stopped','Unknown','Paused');
          quit" | grep -v vmTotal)
      vmRunningTotal=$($mysql_cmd "
        use zstack;
          SELECT COUNT( * ) AS vmRunningTotal
          FROM VmInstanceVO vv
          WHERE vv.hypervisorType = 'KVM'
          AND vv.type = 'UserVm'
          AND state = 'Running';
          quit" | grep -v vmRunningTotal)


    echo "物理机数量: ${hostTotal}"
    echo ""
    echo "云主机数量: ${vmTotal}"
    echo ""
    echo "运行中云主机数量: ${vmRunningTotal}"
    echo ""
    echo "主存储数量: ${psTotal}"
    echo ""
    echo "镜像服务器数量: ${bsTotal}"
    echo ""
    echo "IP地址总量: ${IPTotalCapacity}"
    echo ""
    echo "可用IP地址量: ${IPAvailableCapacity}"
    echo ""

    vmVol_info=$($mysql_cmd "
    use zstack;
    SELECT ROUND(SUM(vv.size/1024/1024/1024)) AS 'volCap(GB)'
    FROM VolumeVO vv
    WHERE vv.type = 'Root'
    AND vv.format != 'vmtx';
    quit"  | grep -v volCap)
    echo "云主机系统盘容量总和(GB): $vmVol_info"
    echo ""

    dataVol_info=$($mysql_cmd "
    use zstack;
    SELECT COUNT(*) AS volNum, ROUND(SUM(vv.size/1024/1024/1024)) AS 'volCap(GB)'
    FROM VolumeVO vv
    WHERE vv.type = 'Data'
    AND vv.format != 'vmtx';
    quit"  | grep -v volNum)

    echo "数据云盘数量: "$(echo $dataVol_info | awk '{print $1}')
    echo ""
    echo "数据云盘总容量(GB): "$(echo $dataVol_info | awk '{print $2}')
    echo ""

cat<<EOF
+------------------------------------------+
|              #集群阈值设置#              |
+------------------------------------------+
EOF
    threshold_setting=$($mysql_cmd "
    use zstack;
    SELECT cs.name,cs.uuid,
    CASE
    WHEN rc.name = 'reservedMemory' THEN '保留内存'
    WHEN rc.name = 'cpu.overProvisioning.ratio' THEN 'CPU超分率'
    WHEN rc.name = 'overProvisioning.memory' THEN '内存超分率'
    ELSE ''
    END AS 'configName',rc.category,REPLACE(gv.defaultValue,'G','') AS defaultValue,REPLACE(rc.value,'G','') AS value,
    CASE
      WHEN rc.category = 'mevoco' AND rc.name = 'overProvisioning.memory' AND rc.value > 1.5 THEN 'Urgent: 集群内存超分率过高！'
      WHEN rc.category = 'mevoco' AND rc.name = 'overProvisioning.memory' AND rc.value > 1.2 THEN 'Important: 集群内存超分率过高！'
      WHEN rc.category = 'mevoco' AND rc.name = 'overProvisioning.memory' AND rc.value > 1 THEN 'Warninig：集群内存超分率过高！'
      WHEN rc.category = 'host' AND rc.name = 'cpu.overProvisioning.ratio' AND rc.value > 11 THEN 'Important: 集群CPU超分率过高！'
      WHEN rc.category = 'host' AND rc.name = 'cpu.overProvisioning.ratio' AND rc.value > 5 THEN 'Warninig: 集群CPU超分率过高！'
      WHEN rc.category = 'kvm' AND rc.name = 'reservedMemory' AND rc.value < 1 THEN 'Important: 集群内存保留设置过低！'
      WHEN rc.category = 'kvm' AND rc.name = 'reservedMemory' AND rc.value < 16 THEN 'Warninig: 集群内存保留设置过低！'
      ELSE	'' END AS 'COMMENT'
    FROM ClusterVO cs,ResourceConfigVO rc,GlobalConfigVO gv
    WHERE cs.uuid = rc.resourceUuid
    AND rc.category = gv.category
    AND rc.name = gv.name;
    quit")
    if [[ -n $threshold_setting ]];then
        echo "$threshold_setting"
    else
        echo "集群阈值设置为空"
    fi
    echo ""

cat<<EOF
+------------------------------------------------+
|              #运行中的云主机概览#              |
+------------------------------------------------+
EOF
    $mysql_cmd "
    use zstack;
    SELECT
    	@rowno :=@rowno + 1 AS ID,
    	t1. NAME,
    	t1.uuid as 'uuid                            ',
    	t1.cpuNum,
    	ROUND(
    		t1.memorySize / 1024 / 1024 / 1024,
    		2
    	) AS 'memorySize(GB)'
    FROM
    	VmInstanceVO t1,
    	(SELECT @rowno := 0) t
    WHERE
    	t1.state = 'Running';
    quit"
    echo ""

cat<<EOF
+------------------------------------------------+
|              #暂停中的云主机概览#              |
+------------------------------------------------+
EOF
    pause_vm=$($mysql_cmd "
    use zstack;
    SELECT
    	t.NAME,
    	t.uuid,
    	t.hostUuid,
    CASE
    		t.state
    		WHEN 'Paused' THEN
    		'Urgent: 存在暂停的云主机'
    	ELSE ''
    	END AS 'comment'
    FROM
    	VmInstanceVO t
    WHERE
    	t.state = 'Paused';
    quit")
    if [[ -n $pause_vm ]];then
        echo "$pause_vm"
    else
        echo "暂停中的云主机为空"
    fi
    echo ""

cat<<EOF
+----------------------------------------+
|              #主存储概览#              |
+----------------------------------------+
EOF
    $mysql_cmd "
    use zstack;
    SELECT
    	@rowno :=@rowno + 1 AS ID,
    	t2. NAME,
    	t2.status,
    	t2.state,
    	t2.uuid as 'uuid',
    	ROUND(t3.totalCapacity / 1024 / 1024 / 1024 / 1024,2) AS 'totalCapacity(TB)',
    	ROUND(t3.availableCapacity / 1024 / 1024 / 1024 / 1024,2) AS 'availableCapacity(TB)',
    	ROUND(t3.totalPhysicalCapacity / 1024 / 1024 / 1024 / 1024,2) AS 'totalPhysicalCapacity(TB)',
    	ROUND(t3.availablePhysicalCapacity / 1024 / 1024 / 1024 / 1024,2) AS 'availablePhysicalCapacity(TB)',
    	ROUND((t3.totalPhysicalCapacity - t3.availablePhysicalCapacity)/t3.totalPhysicalCapacity,4) AS '主存储已用物理容量百分比',
    	CASE
    		WHEN (t3.totalPhysicalCapacity - t3.availablePhysicalCapacity)/t3.totalPhysicalCapacity > 0.65 THEN 'Important: 主存储已用物理容量超过65%，请尽快扩容'
    	ELSE ''
    	END AS 'comment'

    FROM
    	PrimaryStorageVO t2,
    	PrimaryStorageCapacityVO t3,
    	(SELECT @rowno := 0) t
    WHERE
	t2.uuid = t3.uuid
	AND t2.type != 'VCenter';
    quit"
    echo ""

cat<<EOF
+--------------------------------------------+
|              #主存储保留容量#              |
+--------------------------------------------+
EOF
    $mysql_cmd "
    use zstack;
    SELECT name,category,defaultValue,value,
     CASE
    	WHEN UPPER(SUBSTR(value,(LENGTH(value)),LENGTH(value))) LIKE 'G'
    		THEN (CASE WHEN SUBSTR(value,1,(LENGTH(value)-1))*1 < 200 THEN 'Important: 主存储保留容量过低，建议设置200GB及以上' ELSE '' END)
    	WHEN UPPER(SUBSTR(value,(LENGTH(value)),LENGTH(value))) LIKE 'M'
    		THEN (CASE WHEN SUBSTR(value,1,(LENGTH(value)-1))/1024 < 200 THEN 'Important: 主存储保留容量过低，建议设置200GB及以上' ELSE '' END)
    	WHEN UPPER(SUBSTR(value,(LENGTH(value)),LENGTH(value))) LIKE 'K'
    		THEN (CASE WHEN SUBSTR(value,1,(LENGTH(value)-1))/1024/1024 < 200 THEN 'Important: 主存储保留容量过低，建议设置200GB及以上' ELSE '' END)
    	WHEN UPPER(SUBSTR(value,(LENGTH(value)),LENGTH(value))) LIKE 'B'
    		THEN (CASE WHEN SUBSTR(value,1,(LENGTH(value)-1))/1024/1024/1024 < 200 THEN 'Important: 主存储保留容量过低，建议设置200GB及以上' ELSE '' END)
    	WHEN UPPER(SUBSTR(value,(LENGTH(value)),LENGTH(value))) LIKE 'T'
    		THEN (CASE WHEN SUBSTR(value,1,(LENGTH(value)-1))*1024 < 200 THEN 'Important: 主存储保留容量过低，建议设置200GB及以上' ELSE '' END)
    	ELSE 'NULL'
    	END AS 'comment'
    FROM GlobalConfigVO WHERE name ='reservedCapacity' AND category = 'primaryStorage';
    quit"
    echo ""

cat<<EOF
+--------------------------------------------+
|              #主存储阈值设置#              |
+--------------------------------------------+
EOF
    $mysql_cmd "
    use zstack;
    SELECT name,category,defaultValue,value,
    	CASE
    	WHEN value > 0.8 THEN 'Important: 主存储使用阈值设置过大，建议设置小于等于0.8'
    	ELSE ''
    END AS 'comment'

    FROM GlobalConfigVO
    WHERE name = 'Threshold.primaryStorage.physicalCapacity';
    quit"
    echo ""

cat<<EOF
+--------------------------------------------+
|              #镜像服务器概览#              |
+--------------------------------------------+
EOF
    $mysql_cmd "
    use zstack;

    SELECT
    	@rowno :=@rowno + 1 AS ID,
    	(SELECT COUNT(*) FROM ImageVO) AS ImageCount,
    	t4. NAME,
    	t4.type,
    	t4.state,
    	t4. STATUS,
    	t4.url,
    	t4.uuid AS 'uuid',
    	ROUND(
    		t4.availableCapacity / 1024 / 1024 / 1024 / 1024,
    		2
    	) AS 'availableCapacity(TB)',
    	ROUND(
    		t4.totalCapacity / 1024 / 1024 / 1024 / 1024,
    		2
    	) AS 'totalCapacity(TB)'
    FROM
	BackupStorageVO t4,
	(SELECT @rowno := 0) t
    WHERE
	t4.type != 'VCenter'
	AND t4.uuid NOT IN(SELECT st.resourceUuid FROM SystemTagVO st WHERE st.tag = 'onlybackup');
    quit"
    echo ""

cat<<EOF
+------------------------------------------+
|              #灾备信息查询#              |
+------------------------------------------+
EOF
#1，灾备数据的总大小；2，灾备任务的数量；3，灾备容量排序（资源）4、备份服务器数量
    $mysql_cmd "
    use zstack;
      SELECT sjv.jobClassName AS '备份类型',COUNT(*) '任务数量' FROM SchedulerJobVO sjv
      WHERE sjv.jobClassName IN ('org.zstack.storage.backup.CreateVolumeBackupJob','org.zstack.storage.backup.CreateVmBackupJob','org.zstack.storage.backup.CreateDatabaseBackupJob')
      GROUP BY sjv.jobClassName;

      SELECT ROUND(SUM(vbv.size)/1024/1024/1024,4) AS '资源备份大小(GB)',
      ROUND(SUM(dbv.size/1024/1024/1024),4) AS '数据库备份大小(GB)'
      FROM VolumeBackupVO vbv,DatabaseBackupVO dbv;

      SELECT vbv.volumeUuid,type,ROUND(SUM(vbv.size)/1024/1024/1024,4) AS 'size(GB)'
      FROM VolumeBackupVO vbv
      GROUP BY vbv.volumeUuid
      ORDER BY SUM(vbv.size) DESC;
      SELECT
        CASE tag
        WHEN 'allowbackup' THEN '本地备份服务器个数（复用）'
        WHEN  'onlybackup' THEN '本地备份服务器个数（独占）'
        WHEN 'remotebackup' THEN '异地备份服务器个数'
        ELSE  'NULL'
        END AS '类型',
        COUNT(DISTINCT tag)  AS '数量'
      FROM BackupStorageVO bs,SystemTagVO st
      WHERE bs.uuid = st.resourceUuid
      AND tag IN ('remotebackup','allowbackup','onlybackup')
      GROUP BY tag;
    quit"
    echo ""

cat<<EOF
+--------------------------------------------+
|              #灾备服务器概览#              |
+--------------------------------------------+
EOF
    $mysql_cmd "
    use zstack;
    SELECT
    	bs.NAME,
    	bs.url,
    	ROUND( bs.totalCapacity / 1024 / 1024 / 1024 / 1024, 2 )  AS 'totalCapacity(TB)',
    	ROUND( bs.availableCapacity / 1024 / 1024 / 1024 / 1024, 2 ) AS 'availableCapacity(TB)',
    	CONCAT(ROUND( (1 - bs.availableCapacity / bs.totalCapacity ) * 100 ,1),'%') AS '使用率',
    	bs.STATUS,
    	CASE
    	WHEN st.tag = 'onlybackup' THEN '仅用于灾备服务器'
    	WHEN st.tag = 'allowbackup' THEN '镜像服务器复用灾备服务器'
    	WHEN st.tag = 'remotebackup' THEN '远端灾备服务器'
    ELSE
    		''
    END AS '使用方式',
    CASE
    		WHEN 1 - bs.availableCapacity / bs.totalCapacity >= 0.9 THEN	'Urgent: 备份服务器使用率过高！'
    		WHEN 1 - bs.availableCapacity / bs.totalCapacity > 0.7 AND 1 - bs.availableCapacity / bs.totalCapacity <= 0.8 THEN	'Important: 备份服务器使用率过高！'
    		WHEN 1 - bs.availableCapacity / bs.totalCapacity > 0.6 AND 1 - bs.availableCapacity / bs.totalCapacity <= 0.7 THEN	'Warning: 备份服务器使用率过高！'
    		ELSE ''
    END AS 'COMMENT'
    FROM
    	BackupStorageVO bs,
    	SystemTagVO st
    WHERE
    	bs.uuid = st.resourceUuid
    	AND st.tag IN ( 'allowbackup', 'onlybackup', 'remotebackup' );
    quit"
    echo ""

cat<<EOF
+------------------------------------------+
|              #灾备任务概览#              |
+------------------------------------------+
EOF
    disaster_recovery=$($mysql_cmd "
    use zstack;
    SELECT
    t.name AS '任务名称',
    t.schedulerJobGroupUuid AS '任务uuid',
    t.startTime AS '执行时间',
    t.success AS '上次执行结果',
    CASE t.success
    	WHEN 0 THEN
    	'Urgent: 最后一次灾备任务执行失败，请检查'
    	ELSE
    		''
    END AS 'comment'
     FROM (SELECT sh.schedulerJobGroupUuid,sv.name,MAX(sh.startTime) AS 'startTime',
    SUBSTR(MAX(CONCAT(sh.startTime,':',sh.success)),LENGTH(MAX(CONCAT(sh.startTime,':',sh.success)))) AS 'success'
    FROM SchedulerJobHistoryVO sh,SchedulerJobGroupVO sv WHERE sh.schedulerJobGroupUuid = sv.uuid GROUP BY sh.schedulerJobGroupUuid)t;
    quit")
    if [[ -n $disaster_recovery ]];then
        echo "$disaster_recovery"
    else
        echo "灾备任务概览为空"
    fi

    echo ""

cat<<EOF
+--------------------------------------------------+
|              #管理节点消息队列查询#              |
+--------------------------------------------------+
EOF
    $mysql_cmd "
    use zstack;
    SELECT
    	COUNT( * ) AS queueNum,
    CASE
  	WHEN COUNT( * ) > 100 THEN
    	'Important: 管理节点消息队列超过100 ' ELSE ''
    END AS COMMENT
    FROM
    	JobQueueVO;
    quit"
    echo ""

cat<<EOF
+--------------------------------------------------------+
|              #物理机上的虚拟机虚拟机规格#              |
+--------------------------------------------------------+
EOF
    $mysql_cmd "
    use zstack;
    SELECT
    	t1.NAME AS HostName,
    	t1.managementIp AS HostIP,
    	t2.NAME AS VmName,
    	t2.state,
    	t2.cpuNum,
    	round( t2.memorySize / 1024 / 1024 / 1024 ) AS 'memorySize(GB)'
    FROM
    	HostVO t1
    	JOIN VmInstanceVO t2 ON t1.uuid = t2.hostUuid
    	ORDER BY t1.name;
    quit"
    echo ""

cat<<EOF
+--------------------------------------------------------------------------+
|              #物理机上云主机的数量 和使用的虚拟CPU数量总和#              |
+--------------------------------------------------------------------------+
EOF
    $mysql_cmd "
    use zstack;
    SELECT
    	t3.NAME AS clusterName,
    	t2.NAME AS HostName,
    	t2.managementIp AS HostIP,
    	count( t1.uuid ) AS VmNumber,
    	SUM( t1.cpuNum ) AS 'CpuTotalNum',
    CASE

    		WHEN count( t1.uuid ) >= 20 THEN
    		'Warning: 该物理机上的云主机数量超过20个' ELSE ''
    	END AS 'comment'
    FROM
    	VmInstanceVO t1,
    	HostVO t2,
    	ClusterVO t3
    WHERE
    	t1.hostUuid = t2.uuid
    	AND t2.clusterUuid = t3.uuid
    	AND t1.state = 'Running'
    GROUP BY
    	t1.hostUuid,
    	t1.state
    ORDER BY
    	t3.NAME,
    	t2.NAME;
    quit"
    echo ""

cat<<EOF
+---------------------------------------------+
|              #硬件设施-物理机#              |
+---------------------------------------------+
EOF
    $mysql_cmd "
    use zstack;

    SELECT
    	hv.NAME,
    	hv.state,
    	hv.STATUS,
    	hv.managementIp
    FROM
    	HostVO hv;
    quit"
    echo ""

cat<<EOF
+--------------------------------------------------------+
|              #集群主存储类型及物理机数量#              |
+--------------------------------------------------------+
EOF
# 增加检查全局设置物理机保留内存检查
    $mysql_cmd "
    use zstack;
    SELECT cs.name AS 'Cluster Name',ps.name AS 'Primary Storage Name',ps.type AS 'Primary Storage Type',ps.url,t.Host_total
    FROM ClusterVO cs,PrimaryStorageVO ps,PrimaryStorageClusterRefVO psr,
    																(SELECT hv.clusterUuid,COUNT(hv.uuid) AS 'Host_total' FROM HostVO hv GROUP BY hv.clusterUuid) t
    WHERE cs.uuid = psr.clusterUuid
    AND ps.uuid = psr.primaryStorageUuid
    AND t.clusterUuid = cs.uuid
    AND cs.hypervisorType = 'KVM'
    ORDER BY cs.name,ps.name;
    quit"
    echo ""

cat<<EOF
+------------------------------------------------+
|              #物理机保留内存检查#              |
+------------------------------------------------+
EOF
    $mysql_cmd "
    use zstack;
    SELECT name,category,defaultValue,value,
     CASE
      WHEN UPPER(SUBSTR(value,(LENGTH(value)),LENGTH(value))) LIKE 'G'
      	THEN (CASE WHEN SUBSTR(value,1,(LENGTH(value)-1))*1 < 8 THEN 'Important: 物理机保留内存过低' ELSE '' END)
      WHEN UPPER(SUBSTR(value,(LENGTH(value)),LENGTH(value))) LIKE 'M'
      	THEN (CASE WHEN SUBSTR(value,1,(LENGTH(value)-1))/1024 < 8 THEN 'Important: 物理机保留内存过低' ELSE '' END)
      WHEN UPPER(SUBSTR(value,(LENGTH(value)),LENGTH(value))) LIKE 'K'
      	THEN (CASE WHEN SUBSTR(value,1,(LENGTH(value)-1))/1024/1024 < 8 THEN 'Important: 物理机保留内存过低' ELSE '' END)
      WHEN UPPER(SUBSTR(value,(LENGTH(value)),LENGTH(value))) LIKE 'B'
      	THEN (CASE WHEN SUBSTR(value,1,(LENGTH(value)-1))/1024/1024/1024 < 8 THEN 'Important: 物理机保留内存过低' ELSE '' END)
      WHEN UPPER(SUBSTR(value,(LENGTH(value)),LENGTH(value))) LIKE 'T'
      	THEN (CASE WHEN SUBSTR(value,1,(LENGTH(value)-1))*1024 < 8 THEN 'Important: 物理机保留内存过低' ELSE '' END)
      ELSE 'NULL'
      END AS 'comment'

    FROM GlobalConfigVO WHERE name = 'ReservedMemory';
    quit"
    echo ""

cat<<EOF
+-----------------------------------------------------------+
|              #物理机上CPU-内存 超线程后总量#              |
+-----------------------------------------------------------+
EOF
    $mysql_cmd "
    use zstack;
    SELECT
    	hv.managementIp,
    	round(
    		hcv.totalPhysicalMemory / 1073741824
    	) AS '总物理内存(GB)',
    	round(
    		hcv.availablePhysicalMemory / 1073741824
    	) AS '可用物理内存(GB)',
    	round(hcv.totalMemory / 1073741824) AS '总内存(GB)',
    	round(
    		hcv.availableMemory / 1073741824
    	) AS '可用内存(GB)',
    	hcv.totalCpu,
    	hcv.availableCpu,
    	hcv.cpuNum,
    	hcv.cpuSockets
    FROM
    	HostCapacityVO hcv,
    	HostVO hv
    WHERE
    	hv.uuid = hcv.uuid;
    quit"
    echo ""

cat<<EOF
+----------------------------------------+
|              #迁移服务器#              |
+----------------------------------------+
EOF
    $mysql_cmd "
    use zstack;
    SELECT
    	*
    FROM
    	V2VConversionHostVO;
    quit"
    echo ""

cat<<EOF
+--------------------------------------+
|              #迁移任务#              |
+--------------------------------------+
EOF
    migration_task=$($mysql_cmd "
    use zstack;
    SELECT
    	*
    FROM
    	V2VConversionCacheVO;
    quit")
    if [[ -n $migration_task ]];then
        echo "$migration_task"
    else
        echo "迁移任务为空"
    fi
    echo ""

cat<<EOF
+----------------------------------------+
|              #裸金属设备#              |
+----------------------------------------+
EOF
    baremetal=$($mysql_cmd "
    use zstack;
    SELECT
    	*
    FROM
    	BaremetalChassisVO;
    quit")
    if [[ -n $baremetal ]];then
        echo "$baremetal"
    else
        echo "裸金属设备为空"
    fi
    echo ""

cat<<EOF
+----------------------------------------+
|              #裸金属主机#              |
+----------------------------------------+
EOF
    baremetal_host=$($mysql_cmd "
    use zstack;
    SELECT
    	*
    FROM
    	BaremetalInstanceVO;
    quit")
    if [[ -n $baremetal_host ]];then
        echo "$baremetal_host"
    else
        echo "裸金属主机为空"
    fi
    echo ""

cat<<EOF
+-----------------------------------------+
|              #Lun透传检查#              |
+-----------------------------------------+
EOF
    lun_info=$($mysql_cmd "
    use zstack;
    SELECT
    	vv.NAME,
    	sf.vmInstanceUuid,
    	sf.scsiLunUuid
    FROM
    	VmInstanceVO vv,
    	ScsiLunVmInstanceRefVO sf
    WHERE
    	vv.uuid = sf.vmInstanceUuid;
    quit")
    if [[ -n $lun_info ]];then
        echo "$lun_info"
    else
        echo "lun透传为空"
    fi
    echo ""

cat<<EOF
+-----------------------------------------+
|              #USB设备检查#              |
+-----------------------------------------+
EOF
    usb_info=$($mysql_cmd "
    use zstack;
    SELECT hv.managementIp,ud.name,ud.iManufacturer,ud.iProduct,ud.iSerial,ud.usbVersion,ud.state,ud.vmInstanceUuid
    FROM HostVO hv,UsbDeviceVO ud
    WHERE hv.hypervisorType='KVM'
    AND hv.uuid=ud.hostUuid
    AND ud.iManufacturer <> 'QEMU';
    quit")
    if [[ -n $usb_info ]];then
        echo "$usb_info"
    else
        echo "USB设备为空"
    fi
    echo ""

cat<<EOF
+--------------------------------------------------+
|              #云主机云盘及快照检查#              |
+--------------------------------------------------+
EOF
    vm_disk_snapshot=$($mysql_cmd "
    USE zstack;
    SELECT
    	t1.*,
    CASE

    		WHEN t1.volumeSanpshotNum > 10 THEN
    		'Warning: 云盘快照数量大于10个' ELSE ''
    	END AS 'Comment'
    FROM
    	(
    	SELECT
    		t1.vmInstanceUuid,
    		t3.type,
    		t1.type AS 'volumeType',
    		COUNT( DISTINCT t1.uuid ) AS 'volumnNum',
    		COUNT( t2.uuid ) AS 'volumeSanpshotNum'
    	FROM
    		VolumeEO t1
    		LEFT JOIN VolumeSnapshotEO t2 ON t1.uuid = t2.volumeUuid
    		RIGHT JOIN PrimaryStorageVO t3 ON t1.primaryStorageUuid = t3.uuid
    	WHERE
    		t1.vmInstanceUuid IS NOT NULL
    		AND t1.STATUS = 'Ready'
    	GROUP BY
    		t1.vmInstanceUuid,
    		t1.type
    	) t1
    WHERE
    	t1.volumeSanpshotNum > 0
    ORDER BY
    	volumeSanpshotNum DESC;
    quit")
    if [[ -n $vm_disk_snapshot ]];then
        echo "$vm_disk_snapshot"
    else
        echo "云主机云盘及快照为空"
    fi
    echo ""

cat<<EOF
+----------------------------------------+
|              #网络规划查#              |
+----------------------------------------+
EOF
    $mysql_cmd "
    USE zstack;
    SELECT
    	ll2.NAME AS '二层网络名称',
    	ll2.physicalInterface '网卡',
    	ll2.vlan AS 'VLAN_ID',
    	ll2.type AS '二层网络类型',
    	l3.NAME AS '三层网络名称',
    	l3.category AS '三层网络分类',
    	l3.type AS '三层网络类型',
    	ipr.startIp AS '起始IP',
    	ipr.endIp AS '结束IP',
    	ipr.networkCidr AS 'IP(CIDR)'
    FROM
    	L3NetworkVO l3,
    	IpRangeVO ipr,(
    	SELECT
    		l2.uuid,
    		l2.NAME,
    		l2.physicalInterface,
    		l2v.vlan,
    		l2.type
    	FROM
    		L2NetworkVO l2
    		LEFT JOIN L2VlanNetworkVO l2v ON l2.uuid = l2v.uuid
    	) ll2
    WHERE
    	l3.l2NetworkUuid = ll2.uuid
    	AND l3.uuid = ipr.l3NetworkUuid;
    quit"
    echo ""

cat<<EOF
+-----------------------------------------------------------+
|              #加载网卡数量大于1的云主机查询#              |
+-----------------------------------------------------------+
EOF
    $mysql_cmd "
    USE zstack;
    SELECT
        b.vmInstanceUuid as uuid,
    	b.NAME AS '云主机名称',
    	b.count AS '网卡数量'
    FROM
    	(
    	SELECT
    		a.vmInstanceUuid,
    		a.name,
    		count( vmInstanceUuid ) AS count
    	FROM
    		(
    		SELECT
    			VmInstanceVO.NAME,
    			VmNicVO.vmInstanceUuid
    		FROM
    			VmInstanceVO,
    			VmNicVO
    		WHERE
    			VmInstanceVO.uuid = VmNicVO.vmInstanceUuid
    		) AS a
    	GROUP BY
    		a.vmInstanceUuid
    HAVING
	count > 1) AS b;
    quit"
    echo ""

cat<<EOF
+----------------------------------------+
|              #弹性IP查询#              |
+----------------------------------------+
EOF
# 均为已加载云主机的弹性IP信息
    $mysql_cmd "
    USE zstack;
    SELECT
    	CONCAT(
    		'扁平网络EIP个数 ',
    	COUNT( ev.uuid )) AS EipInfo
    FROM
    	EipVO ev,
    	L3NetworkVO lv,
    	VmNicVO vv
    WHERE
    	ev.vmNicUuid = vv.uuid
    	AND vv.l3NetworkUuid = lv.uuid
    	AND lv.type = 'L3BasicNetwork'
    	AND lv.category = 'Private'
    	AND lv.uuid NOT IN ( SELECT nv.l3NetworkUuid FROM NetworkServiceL3NetworkRefVO nv WHERE nv.networkServiceType = 'LoadBalancer' ) UNION
    SELECT
    	CONCAT(
    		'EIP总数 ',
    	COUNT(*))
    FROM
    	EipVO
    WHERE
    	vmNicUuid IS NOT NULL;
    quit"
    echo ""

cat<<EOF
+------------------------------------------------+
|              #云主机平台类型查询#              |
+------------------------------------------------+
EOF
    $mysql_cmd "
    USE zstack;
    SELECT
    	vv.platform AS '云主机平台',
    	COUNT( vv.uuid ) AS '云主机个数'
    FROM
    	VmInstanceVO vv
    WHERE
    	vv.hypervisorType = 'KVM'
    GROUP BY
    	vv.platform;
    quit"
    echo ""

cat<<EOF
+---------------------------------------------------------+
|              #NeverStop云主机资源占用查询#              |
+---------------------------------------------------------+
EOF
    $mysql_cmd "
    USE zstack;
    SELECT
    	COUNT( vm.NAME ) AS '高可用数量',
    	SUM( vm.cpuNum ) AS totalCPU,
    	ROUND(
    	SUM( memorySize / 1024 / 1024 / 1024 )) AS totalMem
    FROM
    	SystemTagVO st,
    	VmInstanceVO vm
    WHERE
    	st.resourceUuid = vm.uuid
    	AND vm.hypervisorType = 'KVM'
    	AND tag = 'ha::NeverStop';
    quit"
    echo ""

cat<<EOF
+-------------------------------------------------+
|              #云主机规格TOP10查询#              |
+-------------------------------------------------+
EOF
    $mysql_cmd "
    USE zstack;
    SELECT
    	vm.NAME,
    	vm.uuid,
    	vm.cpuNum,
    	ROUND( vm.memorySize / 1024 / 1024 / 1024 ) AS 'memSize(GB)'
    FROM
    	VmInstanceVO vm
    WHERE
    	vm.hypervisorType = 'KVM'
    	AND vm.state = 'Running'
    ORDER BY
    	vm.cpuNum DESC,
    	vm.memorySize DESC
    	LIMIT 10;
    quit"
    echo ""

cat<<EOF
+--------------------------------------------+
|              #云主机镜像名称#              |
+--------------------------------------------+
EOF
    $mysql_cmd "
    USE zstack;
    SELECT
    	vv.NAME AS vmName,
    	vv.platform,
    	iv.NAME AS imageNmae
    FROM
    	VmInstanceVO vv,
    	ImageVO iv
    WHERE
    	vv.imageUuid = iv.uuid
    ORDER BY
    	vv.platform,
    	iv.NAME;
    quit"
    echo ""

cat<<EOF
+------------------------------------------+
|              #资源标签数查#              |
+------------------------------------------+
EOF
    resource_tag=$($mysql_cmd "
    USE zstack;
    SELECT
    	ut.resourceType,
    	COUNT(*) AS tagCount
    FROM
    	UserTagVO ut,
    	TagPatternVO tv
    WHERE
    	ut.tagPatternUuid = tv.uuid
    GROUP BY
    	ut.resourceType;
    quit")
    if [[ -n $resource_tag ]];then
        echo "$resource_tag"
    else
        echo "资源标签数为空"
    fi
    echo ""

cat<<EOF
+--------------------------------------------+
|              #亲和组数量查询#              |
+--------------------------------------------+
EOF
    affinity_group=$($mysql_cmd "
    USE zstack;
    SELECT
    	AGVO.NAME AS '亲和组名称',
    CASE

    		WHEN AGVO.policy = 'ANTIHARD' THEN
    		'强制' ELSE '非强制'
    	END AS 'policy',
    	VIVO.NAME AS '云主机名称',
    	IOVO.cpuNum,
    	ROUND( IOVO.memorySize / 1024 / 1024 / 1024 ) AS '内存'
    FROM
    	VmInstanceVO VIVO,
    	AffinityGroupVO AGVO,
    	AffinityGroupUsageVO AGUVO,
    	InstanceOfferingVO IOVO
    WHERE
    	AGUVO.resourceUuid = VIVO.uuid
    	AND AGUVO.affinityGroupUuid = AGVO.uuid
    	AND IOVO.uuid = VIVO.instanceOfferingUuid
    	AND AGVO.appliance = 'CUSTOMER';
    quit")
    if [[ -n $affinity_group ]];then
        echo "$affinity_group"
    else
        echo "亲和组数量为空"
    fi
    echo ""

cat<<EOF
+------------------------------------------------+
|              #全局设置自定义内容#              |
+------------------------------------------------+
EOF
    $mysql_cmd "
    USE zstack;
    SELECT NAME
    	,
    	category,
    	defaultValue,

    VALUE

    FROM
    	GlobalConfigVO
    WHERE

    VALUE
    	!= defaultValue;
    quit"
    echo ""

cat<<EOF
+--------------------------------------------+
|              #集群自定义设置#              |
+--------------------------------------------+
EOF
    default_setting=$($mysql_cmd "
    USE zstack;
    SELECT
    	cs.NAME AS 'clusterName',
    	cs.uuid AS 'clusterUuid',
    	rv.NAME AS 'configName',
    	rv.category AS 'configCategory',
    	rv.
    VALUE

    FROM
    	ResourceConfigVO rv,
    	ClusterVO cs
    WHERE
    	rv.resourceUuid = cs.uuid;
    quit")
    if [[ -n $default_setting ]];then
        echo "$default_setting"
    else
        echo "集群自定义设置为空"
    fi

    echo ""

cat<<EOF
+------------------------------------------------+
|              #集群Prometheus设置#              |
+------------------------------------------------+
EOF
    $mysql_cmd "
    USE zstack;
    SELECT
    CASE
    	NAME
    	WHEN
    		'storage.local.retention.size' THEN
    			'监控数据保留大小'
    			WHEN 'storage.local.retention' THEN
    			'监控数据保留周期'
    		END AS '名称',
    		defaultValue AS '默认值',

    	VALUE
    		AS '设置值'
    	FROM
    		GlobalConfigVO
    	WHERE
    		category = 'Prometheus';
    	SELECT
    		type,
    		COUNT( type ) AS '云主机类型'
    	FROM
    		VmInstanceVO
    	GROUP BY
    	type;
    quit"
    echo ""

cat<<EOF
+--------------------------------------------+
|              #安全组数量查询#              |
+--------------------------------------------+
EOF
    $mysql_cmd "
    USE zstack;
    SELECT
    	COUNT(*) AS '安全组总数量'
    FROM
    	SecurityGroupVO sv;
    SELECT
    	sgr.vmInstanceUuid AS '云主机UUID',
    	COUNT( sgr.vmInstanceUuid ) AS '安全组数量'
    FROM
    	VmNicSecurityGroupRefVO sgr
    GROUP BY
    	sgr.vmNicUuid
    ORDER BY
    	COUNT( sgr.vmInstanceUuid ) DESC
    	LIMIT 10;
    quit"
    echo ""

cat<<EOF
+------------------------------------------+
|              #网络服务统计#              |
+------------------------------------------+
EOF
    $mysql_cmd "
    USE zstack;
    SELECT
    	COUNT( NAME ) AS 'EIP数量'
    FROM
    	EipVO;
    SELECT
    	COUNT(*) AS '端口转发'
    FROM
    	( SELECT COUNT( NAME ) FROM PortForwardingRuleVO GROUP BY NAME ) t1;
    SELECT
    	COUNT( uuid ) AS '负载均衡器'
    FROM
    	LoadBalancerVO;
    SELECT
    	COUNT( uuid ) AS 'IPSEC数量'
    FROM
    	IPsecConnectionVO;
    quit"
    echo ""

cat<<EOF
+---------------------------------------+
|              #IPSEC查询#              |
+---------------------------------------+
EOF
    psec_info=$($mysql_cmd "
    use zstack;
    SELECT
        IPsecConnectionVO.name as 'IPSEC名称',
        IPsecConnectionVO.state as '启用状态'
    FROM
        IPsecConnectionVO;
    quit")
    if [[ -n $ipsec_info ]];then
        echo "$ipsec_info"
    else
        echo "IPSEC为空"
    fi
    echo ""

cat<<EOF
+------------------------------------------+
|              #端口转发查询#              |
+------------------------------------------+
EOF
    port_transport=$($mysql_cmd "
    use zstack;
    SELECT
        PortForwardingRuleVO.name as '端口转发名称',
        PortForwardingRuleVO.state as '启用状态'
    FROM
        PortForwardingRuleVO;
    quit")
    if [[ -n $ipsec_info ]];then
        echo "$port_transport"
    else
        echo "端口转发为空"
    fi
    echo ""

cat<<EOF
+------------------------------------------------+
|              #负载均衡器数量查询#              |
+------------------------------------------------+
EOF
    $mysql_cmd "
    USE zstack;
    SELECT
    	COUNT(*) AS '负载均衡器总数量'
    FROM
    	LoadBalancerVO;
    SELECT
    	lbv.loadBalancerUuid AS '负载均衡器UUID',
    	COUNT( lbv.uuid ) AS '监听器数量'
    FROM
    	LoadBalancerListenerVO lbv
    GROUP BY
    	lbv.loadBalancerUuid
    ORDER BY
    	COUNT( lbv.uuid ) DESC
    	LIMIT 10;
    quit"
    echo ""

cat<<EOF
+------------------------------------------------+
|              #路由器数量规格查询#              |
+------------------------------------------------+
EOF
    $mysql_cmd "
    USE zstack;
    SELECT
    	av.applianceVmType AS '路由器类型',
    	COUNT( * ) AS '路由器个数'
    FROM
    	ApplianceVmVO av
    GROUP BY
    	av.applianceVmType;
    SELECT
    	iov.NAME,
    	iov.cpuNum,
    	CONCAT( ROUND( iov.memorySize / 1024 / 1024 / 1024 ), 'GB' ) AS 'memorySize',
    	iov.state,
    	vrv.managementNetworkUuid,
    	vrv.publicNetworkUuid
    FROM
    	VirtualRouterOfferingVO vrv,
    	InstanceOfferingVO iov
    WHERE
    	vrv.uuid = iov.uuid;
    quit"
    echo ""

cat<<EOF
+--------------------------------------+
|              #OSPF查询#              |
+--------------------------------------+
EOF
    $mysql_cmd "
    USE zstack;
    SELECT
    CASE
    		ospfCount
    		WHEN 0 THEN
    		'没有使用OSPF' ELSE '已使用OSPF'
    	END AS 'OSPF使用情况'
    FROM
    	( SELECT COUNT(*) AS ospfCount FROM RouterAreaVO ) t;
    quit"
    echo ""

cat<<EOF
+--------------------------------------------+
|              #已触发报警查询#              |
+--------------------------------------------+
EOF
    alarm_trapped=$($mysql_cmd "
    use zstack;
    	SELECT av.name,av.metricName,av.comparisonOperator,av.threshold,av.namespace,av.state
    	FROM AlarmVO av WHERE av.status = 'Alarm' ;
    quit")
    if [[ -n $alarm_trapped ]];then
        echo "$alarm_trapped"
    else
        echo "已触发报警为空"
    fi
    echo ""


cat<<EOF
+------------------------------------------+
|              #镜像类型查询#              |
+------------------------------------------+
EOF
    # 含云路由镜像，不含VCenter镜像
    $mysql_cmd "
    use zstack;
    	SELECT iv.format,COUNT(*) AS 'ImageNum'
    	FROM ImageVO iv
    	WHERE iv.format != 'vmtx'
    	GROUP BY iv.format;
    quit"
    echo ""

cat<<EOF
+---------------------------------------------+
|              #VCenter信息查询#              |
+---------------------------------------------+
EOF
    $mysql_cmd "
    USE zstack;
    SELECT
    	COUNT(*) AS 'VCenter数量'
    FROM
    	VCenterVO;
    SELECT
    	ps.NAME,
    	ps.type,
    	ps.state,
    	ps.STATUS,
    	ROUND( psc.totalCapacity / 1024 / 1024 / 1024, 4 ) AS 'totalCapacity(GB)',
    	ROUND( psc.availableCapacity / 1024 / 1024 / 1024, 4 ) AS 'availableCapacity(GB)',
    	ROUND( psc.totalPhysicalCapacity / 1024 / 1024 / 1024, 4 ) AS 'totalPhysicalCapacity(GB)',
    	ROUND( psc.availablePhysicalCapacity / 1024 / 1024 / 1024, 4 ) AS 'availablePhysicalCapacity(GB)'
    FROM
    	PrimaryStorageVO ps,
    	PrimaryStorageCapacityVO psc
    WHERE
    	ps.uuid = psc.uuid
    	AND ps.type = 'VCenter';
    SELECT
    	vm.zoneUuid,
    	vm.clusterUuid,
    	COUNT( vm.uuid ) AS '云主机数量'
    FROM
    	VmInstanceVO vm
    WHERE
    	hypervisorType = 'ESX'
    GROUP BY
    	vm.zoneUuid,
    	vm.clusterUuid;
    quit"
    echo ""

cat<<EOF
+--------------------------------------------+
|              #混合云信息查询#              |
+--------------------------------------------+
EOF
    hybrid_cloud=$($mysql_cmd "
    USE zstack;
    SELECT
    	*
    FROM
    	DataCenterVO;
    SELECT
    	*
    FROM
    	IdentityZoneVO;
    quit")
    if [[ -n $hybrid_cloud ]];then
        echo "$hybrid_cloud"
    else
        echo "混合云信息为空"
    fi
    echo ""


cat<<EOF
+------------------------------------------+
|              #计费单价查询#              |
+------------------------------------------+
EOF
    $mysql_cmd "
    USE zstack;
    SELECT
    	pv.resourceName,
    	pv.timeUnit,
    	pv.resourceUnit,
    	pv.price
    FROM
    	PriceVO pv;
    quit"
    echo ""


cat<<EOF
+------------------------------------------+
|              #企业管理查询#              |
+------------------------------------------+
EOF
    $mysql_cmd "
    USE zstack;
    SELECT
    	COUNT( DISTINCT ipv.uuid ) AS '项目数量',
    	COUNT( DISTINCT ivid.uuid ) AS '用户数量(含平台管理员)'
    FROM
    	IAM2ProjectVO ipv,
    	IAM2VirtualIDVO ivid;
    quit"
    echo ""


cat<<EOF
+------------------------------------------------+
|              #裸金属主机数量查询#              |
+------------------------------------------------+
EOF
    $mysql_cmd "
    USE zstack;
    SELECT
    	COUNT(*)
    FROM
    	BaremetalInstanceVO;
    quit"
    echo ""


cat<<EOF
+----------------------------------------+
|              #接收端检查#              |
+----------------------------------------+
EOF
    $mysql_cmd "
    USE zstack;
    SELECT NAME
    	,
    CASE

    		WHEN endPointNum = 0
    		AND NAME = 'Email' THEN
    			'Warning: 未配置邮箱接收端！' ELSE endPointNum
    			END AS 'endPointNum'
    	FROM
    		(
    		SELECT
    			'DingTalk' AS 'name',
    			COUNT(*) AS 'endPointNum'
    		FROM
    			SNSDingTalkEndpointVO UNION
    		SELECT
    			'Http' AS 'name',
    			COUNT(*) AS 'endPointNum'
    		FROM
    			SNSHttpEndpointVO UNION
    		SELECT
    			'Email' AS 'name',
    			COUNT(*) AS 'endPointNum'
    		FROM
    			SNSEmailEndpointVO
    		) t1;
    quit"
    echo ""

cat<<EOF
+------------------------------------------+
|              #置备方式查询#              |
+------------------------------------------+
EOF
    preparation_method=$($mysql_cmd "
    USE zstack;
    SELECT
    	*
    FROM
    	(
    	SELECT
    		ps.NAME,
    		ps.type,
    		ps.uuid,
    	CASE
    			st.tag
    			WHEN 'primaryStorageVolumeProvisioningStrategy::ThinProvisioning' THEN
    			'精简置备' ELSE '厚置备'
    		END AS '置备方式'
    	FROM
    		PrimaryStorageVO ps
    		LEFT JOIN SystemTagVO st ON ps.uuid = st.resourceUuid
    		AND st.tag = 'primaryStorageVolumeProvisioningStrategy::ThinProvisioning'
    	) t
    WHERE
    	t.type = 'SharedBlock';
    SELECT
    	VolumeVO.NAME,
    	ROUND( VolumeVO.size / 1024 / 1024 / 1024 ) AS '云盘大小',
    CASE
    		SystemTagVO.tag
    		WHEN 'volumeProvisioningStrategy::ThinProvisioning' THEN
    		'精简置备'
    		WHEN 'volumeProvisioningStrategy::ThickProvisioning' THEN
    		'厚置备'
    	END AS '置备方式'
    FROM
    	SystemTagVO,
    	VolumeVO
    WHERE
    	VolumeVO.uuid = SystemTagVO.resourceUuid
    	AND SystemTagVO.tag LIKE '%volumeProvisioningStrategy%';
    quit")
    if [[ -n $preparation_method ]];then
        echo "$preparation_method"
    else
        echo "置备方式查询为空"
    fi
    echo ""

cat<<EOF
+----------------------------------------------+
|              #存储心跳网络查询#              |
+----------------------------------------------+
EOF
    $mysql_cmd "
    USE zstack;
    SELECT
    	t2.*,
    CASE

    		WHEN t2.type = 'SharedBlock'
    		AND t2.heartBeatCidr IS NULL THEN
    			'Urgent: 未设置存储心跳网络（若为存储为FCSAN，请忽略）'
    			WHEN t2.type != 'LocalStorage'
    			AND t2.heartBeatCidr IS NULL THEN
    				'Urgent: 未设置存储心跳网络，请检查' ELSE ''
    				END AS 'comment'
    		FROM
    			(
    			SELECT
    				ps.NAME,
    				ps.type,
    				ps.uuid,
    				t1.tag,
    				SUBSTR(
    					t1.tag,
    					32,
    				LENGTH( tag )) AS 'heartBeatCidr'
    			FROM
    				PrimaryStorageVO ps
    				LEFT OUTER JOIN ( SELECT * FROM SystemTagVO st WHERE st.resourceType = 'PrimaryStorageVO' AND st.tag LIKE 'primaryStorage::gateway::cidr::%' ) t1 ON ps.uuid = t1.resourceUuid
    			) t2
    		WHERE
    		t2.type != 'VCenter';
    quit"
    echo ""

cat<<EOF
+------------------------------------------+
|              #迁移网络查询#              |
+------------------------------------------+
EOF
    $mysql_cmd "
    USE zstack;
    SELECT
    	t2.NAME,
    	t2.uuid,
    	t2.tag,
    CASE

    		WHEN t2.tag IS NOT NULL THEN
    		SUBSTR(
    			t2.tag,
    			34,
    		LENGTH( t2.tag )) ELSE ''
    	END AS 'migrateCidr'
    FROM
    	(
    	SELECT
    		*
    	FROM
    		ClusterVO cv
    		LEFT OUTER JOIN ( SELECT st.tag, st.resourceUuid FROM SystemTagVO st WHERE st.resourceType = 'ClusterVO' AND st.tag LIKE 'cluster::migrate::network::cidr::%' ) t1 ON cv.uuid = t1.resourceUuid
    	) t2
    WHERE
    	t2.hypervisorType = 'KVM';
    quit"
    echo ""

cat<<EOF
+-----------------------------------------+
|              #GPU设备检查#              |
+-----------------------------------------+
EOF
    $mysql_cmd "
    USE zstack;
    SELECT
            hv.managementIp,
            pd.*
    FROM
            PciDeviceVO pd,
            HostVO hv
    WHERE
            hv.uuid = pd.hostUuid
            AND hv.hypervisorType = 'KVM'
            AND pd.type LIKE '%GPU%';
    SELECT
            *
    FROM
            FiberChannelStorageVO;
    quit"
    echo ""
}

function get_global_confg(){
cat<<EOF
+--------------------------------------+
|              #全局设置#              |
+--------------------------------------+
EOF
    $mysql_cmd "
    use zstack;
    SELECT
        gc.id,
        gc.NAME,
        gc.category,
        SUBSTR(gc.value,1,20)
    VALUE

    FROM
        GlobalConfigVO gc;

    quit"
    echo ""
}

function get_audit_info(){
cat<<EOF
+------------------------------------------+
|              #审计信息查询#              |
+------------------------------------------+
EOF
    mysql -uzstack_ui -pzstack.ui.password -e "
    USE zstack_ui;
    SELECT
        *
    FROM
        event ent
    WHERE
        ent.create_time > DATE_SUB( CURRENT_DATE (), INTERVAL 30 DAY )
    ORDER BY
        ent.create_time DESC;
    quit"
    echo ""
}

main(){
    get_zs_version
    get_mn_version
    get_resource
    get_global_confg > ${LOG_PATH}/log/GlobalConfig.cfg 2>&1
    get_audit_info > ${LOG_PATH}/log/audit_30day.log 2>&1
    check_addons
    check_license
    check_password
    check_pool_size
    check_crontab
    check_db_backup
    check_pre_allocation
    check_auto_mount
    check_logmonitor
    check_storage_network
    check_user
    check_fragmentation
    QueryWarnning
    QueryPrimaryStorageInfo
    QueryHostMemoryUsedInPercent
    QueryDiskIo
    QueryNwIo
    QueryZsCheck
}


main
