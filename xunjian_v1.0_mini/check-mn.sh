#!/bin/bash
# Created date: 2019-03-21
# Author: bo.zhang
PARSE_JSON="./json.sh -l -p -b"
dd=$(date '+%Y-%m-%d')
log_dir=/tmp/xunjianlog-"$dd"
. ./.env
. /root/.bashrc
echo "############################ 管理节点巡检 ############################"
echo "巡检日志:`date +%Y/%m/%d_%H_%M_%S`"
bash ./query_info.sql |tee -a /$LOG_PATH/log/management.log >>/dev/null 2>&1

Passwd_Path="./UnSecurity_Passwd.txt"
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

function Check_UnSecurity_Passwd(){
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
  echo "Important: 物理机($ip_2)的密码为弱密码!"
done
if [[ -f tmp_1.log && ip_1.log ]];then
  rm -rf tmp_1.log && rm -rf ip_1.log
fi
}

function Check_Passwd_Len(){
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
  echo "Important: 物理机($ip_4)的密码小于9位!"
done

if [[ -f tmp_2.log && ip_2.log ]];then
  rm -rf tmp_2.log && rm -rf ip_2.log
fi
}

function Check_SQL(){
DB_User=$1
DB_Password=$2
DB_IP=$3
DB_Port=$4
SQL_Result=`mysql -u $DB_User -p$DB_Password zstack -h $DB_IP -P $DB_Port -e quit 2>&1`
SQL_Result_Len=${#SQL_Result}
if [[ ${SQL_Result_Len} -eq 0 ]];then
  echo "Important: 数据库用户${DB_User}使用的是默认密码!"
else
  echo "Normal: 数据库用户${DB_User}使用的不是默认密码!"
fi
}


check_password()
{
  echo "############################## 检查物理机密码是否为弱密码 ##############################"
  Check_UnSecurity_Passwd
  echo "############################## 检查物理机密码是否小于9位 ##############################"
  Check_Passwd_Len
  echo "############################## 检查数据库密码是否为默认密码 ##############################"
  Check_SQL $DB_User_1 $DB_Passwd_1 $DB_IP $DB_Port
  Check_SQL $DB_User_2 $DB_Passwd_2 $DB_IP $DB_Port
}

# 检查ZStack版本、运行状态及高可用方案
function mn_version(){
    echo "############################ ZStack运行状态检查 ############################"
    zstack_status=$(zstack-ctl status | grep status | awk  '{print $3}' | uniq |sed -r 's:\x1B\[[0-9;]*[mK]::g')
    zstack_version=$(zstack-ctl status | grep version)
    os_version=$(cat /etc/redhat-release && uname -r)
	# 拷贝zstack.properties配置文件
	cp /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/zstack.properties $LOG_PATH/log
  #cp /usr/local/zstack/zstack-ui/zstack.ui.properties $LOG_PATH/log
	chronyServer1=$(grep chrony.serverIp $LOG_PATH/log/zstack.properties | awk '{print $3}')
	echo "管理节点zstack.properties配置的时间同步源：${chronyServer1}"
	# 版本及运行状态
	echo "ZStack版本：${zstack_version}"
	echo "管理节点OS版本：${os_version}" | xargs
	if [ "$zstack_status" == "Running" ];then
		echo "ZStack服务运行中，状态为：${zstack_status}"
	else
		echo "ZStack服务未运行，状态为：${zstack_status}"
	fi
  if [ -f /opt/zstack-dvd/.repo_version ];then
                echo "当前管理节点repo版本为`cat /opt/zstack-dvd/.repo_version`"
  else
                echo "当前管理节点repo版本为`cat /opt/zstack-dvd/x86_64/$YUM0/.repo_version`"
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
      else
        echo "Urgent: zsha2 status数据库不一致"
      fi
      echo "管理节点高可用方案为：管理节点虚拟机HA"
    else
      echo "当前环境为嵌套环境，未配置高可用"
    fi
  fi
  if [ $ifZsha2 == 2 ];then
    echo "管理节点高可用方案为：多管理节点HA"
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
                          echo "远端管理节点repo版本为`ssh $ip cat /opt/zstack-dvd/.repo_version`"
                    else
                          echo "当前管理节点repo版本为`ssh $ip cat /opt/zstack-dvd/x86_64/$YUM0/.repo_version`"
                    fi
                    scp -v $ip:/usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/zstack.properties $log_dir/log/${ip}.zstack.properties >> /dev/null 2>&1
                    scp $ip:/usr/local/zstack/zstack-ui/zstack.ui.properties $log_dir/log/${ip}.zstack.ui.properties >> /dev/null 2>&1
                    chronyServer2=$(grep chrony.serverIp $log_dir/log/${ip}.zstack.properties | awk '{print $3}')
                    echo "管理节点(peer)zstack.properties配置的时间同步源：${chronyServer2}"
            fi
    done
  else
    echo "未配置管理节点高可用"
  fi


	# 是否复用为计算节点
	ifHost=$($mysql_cmd "use zstack;SELECT mn.hostName FROM ManagementNodeVO mn JOIN HostVO hv ON mn.hostName = hv.managementIp;" | grep -v hostName)
	if [ -n "$ifHost" ];then
		echo -e "管理节点复用为计算节点，IP：\n${ifHost}"
	else
		echo "管理节点未复用为计算节点"
	fi
	# 是否复用为镜像服务器
	ifMnBs=$($mysql_cmd "use zstack;SELECT ibs.hostname FROM ImageStoreBackupStorageVO ibs JOIN ManagementNodeVO mn on ibs.hostname = mn.hostName;"| grep -v hostname)
	if [ -n "$ifMnBs" ];then
		echo  -e "管理节点复用为镜像服务器，IP：\n${ifMnBs}"
	else
		echo "管理节点未复用为镜像服务器"
	fi
	# 计算节点是否复用为镜像服务器
	ifHoBs=$($mysql_cmd "use zstack;SELECT ibs.hostname FROM ImageStoreBackupStorageVO ibs JOIN HostVO hv on ibs.hostname = hv.managementIp;"| grep -v hostname)
	if [ -n "$ifHoBs" ];then
		echo -e "计算节点复用为镜像服务器，IP：\n${ifHoBs}"
	else
		echo "计算节点未复用为镜像服务器"
	fi
}

# 检查时间同步情况
function check_date_info(){
	# 时区检查
	host_num=$(find $log_dir/log/ -name HostDailyCheck* | wc -l)
	echo '############################检查所有节点时区一致性############################'
	tz_info=$(find $log_dir/log/ -name HostDailyCheck* | xargs  grep 'Time zone' | awk -F ':' '{print $NF}' | sort | uniq  | sed 's/ //g' | sed 's/,//g')
	if [ "$tz_info" == "Asia/Shanghai(CST+0800)" ];then
			echo '时区设置为上海地区，当前时区为:'$tz_info
	else
			echo '时区设置为上海之外，当前时区为:'$tz_info
	fi
	# 时间同步检查
	echo '############################检查所有节点指向同一时间同步源############################'

	time_server=$(find $log_dir/log/ -name HostDailyCheck* | xargs  grep ^^| awk -F ':' '{print $NF}' | awk '{print $2}' | sort | uniq | wc -l)
        str_time=`find $log_dir/log/ -name HostDailyCheck* | xargs  grep "^\^[*,+,-,?,x,~]" | awk -F 'log/|/Host|.txt:' '{print $2,$4}' | sort | uniq`
        echo "$str_time"
        echo "$str_time" | grep "\?" | awk -F " " '{print "Urgent: "$1" 时间没有同步" }'

}

# 数据库备份信息
function check_db_backup(){
    echo '############################数据库备份检查############################'
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
            echo '远程主机IP '$host_list
            dbBackupFiles=$(ssh -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa $host_list ls $remoteBackupDir 2>/dev/null |grep 'zstack-backup-db' | head -5 2>/dev/null)
            dbBackupFiles_num=$(ssh -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa $host_list ls $remoteBackupDir/ |wc -l)
            dbbackupSize=$(ssh -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa $host_list du -sh $remoteBackupDir/ 2>/dev/null | awk '{print $2,$1}')
        if [ "$dbBackupFiles" == "" ];then
            echo "Urgent：远程主机 ${host_list} 远程备份未生效，请检查！"
        else
            echo "远程数据库备份文件: ${dbBackupFiles}" | sed 's/ /\n/g'
            echo ""
            echo "远程数据库备份文件数量: "
            echo "$dbBackupFiles_num"
            echo ""
            echo -e "远程数据库备份大小:\n${dbbackupSize}"
        fi
        done
    else
        echo "Urgent:未配置远程备份，请检查！"
        echo ""
    fi

    echo "====="
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
                echo "(管理节点$mnIP)远程主机IP "$host_list
                #ssh $mnIP sshpass -p password ssh $host_list ls $remoteBackupDir
                dbBackupFiles=$(ssh -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa $mnIP  ssh -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa $host_list ls $remoteBackupDir 2>/dev/null |grep 'zstack-backup-db' | head -5 2>/dev/null)
                dbBackupFiles_num=$(ssh -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa $mnIP  ssh -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa $host_list ls $remoteBackupDir/ |wc -l)
                dbbackupSize=$(ssh -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa $mnIP  ssh -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa $host_list du -sh $remoteBackupDir/ 2>/dev/null | awk '{print $2,$1}')
                if [ "$dbBackupFiles" == "" ];then
                    echo "Urgent：(管理节点$mnIP)远程主机 ${host_list} 远程备份未生效，请检查！"
                else
                    echo "远程数据库备份文件: ${dbBackupFiles}" | sed 's/ /\n/g'
                    echo ""
                    echo "远程数据库备份文件数量:" 
                    echo "$dbBackupFiles_num"
                    echo -e "远程数据库备份大小:\n${dbbackupSize}"
                    echo ""
                fi
            done
        else
            echo "(管理节点$mnIP)Urgent:未配置远程备份，请检查！"
        fi
    fi
    done
}

# deploy检查
function auto_mount_check(){
        # /etc/rc.local文件应拥有可执行权限
        Body=`zstack-cli QueryPrimaryStorage`
        if [[ $Body =~ "LocalStorage" ]];then
            echo '############################/etc/rc.d/rc.local(/etc/rc.local)文件应拥有可执行权限############################'
            rc_pri=$(find $LOG_PATH/log -name HostDailyCheck* | xargs grep rc.local$ | awk '{print $1}' | awk -F '/|:' '{print $5,$NF}' | sed 's/ /,/g')
            for info in $rc_pri;do
                echo $info | grep 'x' > /dev/null 2>&1
                if [ $? -eq 0 ];then
                        echo "$info Info: /etc/rc.d/rc.local 有可执行权限" | sed 's/,/ /g'
                else
                        echo "$info WARNNING: /etc/rc.d/rc.local 没有可执行权限，请检查！" | sed 's/,/ /g'
                fi
            done
        fi
	# 镜像服务器是否单独挂载
	echo '############################镜像服务器是否单独挂载检查############################'
        im_bs_mount_info=$(zstack-cli QueryImageStoreBackupStorage fields=hostname,url | egrep 'hostname|url' | awk -F '"' '{print $4}' |sed -n '{N;s/\n/ /p}' |sed 's/ /,/g')
        if [ -n "${im_bs_mount_info}" ];then
       	for bs_info in $(echo $im_bs_mount_info | sed 's/ /\n/g');do
       	    host_IP=$(echo $bs_info | awk -F ',' '{print $1}')
       	    mount_point=$(echo $bs_info | awk -F ',' '{print $2}')
       	    ssh $host_IP -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa grep $mount_point /etc/rc.local >> /dev/null 2>&1
       	    if [ $? -ne 0 ];then
       		echo "镜像服务器:${host_IP}上${mount_point}与 / 共用"
       		# echo "镜像服务器:${host_IP}上${mount_point}未单独挂载(若与/共用，请忽略该消息)"
            else
       		ssh $host_IP -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa df -Th 2> /dev/null | grep $mount_point > /dev/null 2>&1
       		if [ $? -ne 0 ];then
       	 	    echo "Urgent: 镜像服务器:${host_IP}上${mount_point}未单独挂载，请检查！"
       		else
       		    echo "镜像服务器:${host_IP}上${mount_point}已单独挂载"
       		fi
       	    fi
       	done
        else
       	    echo '未使用镜像服务器'
        fi
	# 主存储是否单独挂载
	echo '############################主存储是否单独挂载检查############################'
	local_ps_mount_info=$($mysql_cmd "use zstack;SELECT hv.managementIp,psv.url FROM PrimaryStorageVO psv,PrimaryStorageClusterRefVO psa,HostVO hv WHERE psv.type='LocalStorage' AND psa.primaryStorageUuid = psv.uuid AND hv.clusterUuid = psa.clusterUuid ORDER BY hv.managementIp"|grep -v url | sed 's/\t/,/g')
	if [ -n "${local_ps_mount_info}" ];then
	    for ps_info in $(echo $local_ps_mount_info | sed 's/ /\n/g');do
		host_IP=$(echo $ps_info | awk -F ',' '{print $1}')
		mount_point=$(echo $ps_info | awk -F ',' '{print $2}')
		#ssh $host_IP -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa df -lh 2>> /dev/null | grep $mount_point >> /dev/null 2>&1
		ssh $host_IP -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa grep $mount_point /etc/rc.local >> /dev/null 2>&1
		if [ $? -ne 0 ];then
		    ssh $host_IP -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa grep $mount_point /etc/rc.local >> /dev/null 2>&1
		    echo "本地存储:${host_IP}上${mount_point} 与 / 共用"
		#echo "本地存储:${host_IP}上${mount_point}未单独挂载(若与/共用，请忽略该消息)"
		else
	 	    echo "本地存储:${host_IP}上${mount_point}已单独挂载"
		fi
		done
	else
            echo '未使用本地存储'
	fi
	exit
	# Ceph类型主存储是否填写了pool UUID
	echo '############################Ceph主存储是否填写了唯一的pool UUID############################'
	pool_info=$($mysql_cmd "use zstack;SELECT DISTINCT(primaryStorageUuid) AS psUuid,poolName,count(poolName) AS poolNum FROM CephPrimaryStoragePoolVO;" | grep -v psUuid | sed 's/\t/,/g')

	for p_info in $(echo ${pool_info} | sed 's/ /\n/g')
        do
	    p_num=$(echo ${p_info} | awk -F ',' '{print $3}')
	    ps_uuid=$(echo ${p_info} | awk -F ',' '{print $1}')
	    p_uuid=$(echo ${p_info} | awk -F ',' '{print $2}')
	    if [ $p_num -eq 3 ];then
	    	echo "主存储(UUID):${ps_uuid} 填写了唯一的pool UUID: ${p_uuid}"
	    elif [ $p_num -eq 0 ];then
	    	echo '未使用Ceph类型的主存储'
	    else
	    	echo "主存储(UUID):${ps_uuid} 未填写唯一的pool UUID: ${p_uuid}"
	    fi
	done
}

function QueryPrimaryStorageInfo(){
#	ps_totalPhysicalCapacity=$(zstack-cli QueryPrimaryStorage type!=VCenter | grep totalPhysicalCapacity | grep -oE '[0-9]+' | awk '{sum+=$1}END{print sum/1024/1024/1024}')
#	ps_availablePhysicalCapacity=$(zstack-cli QueryPrimaryStorage type!=VCenter | grep availablePhysicalCapacity | grep -oE '[0-9]+' | awk '{sum+=$1}END{print sum/1024/1024/1024}')
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
# 16 主存储已用物理容量百分比(0.00)
	#echo $(echo $ps_info | awk '{print $2}')>>$result
	ps_info_2=$(echo $ps_info | awk '{print $2}')
  echo "主存储已用物理容量百分比: $ps_info_2"
# 15-1 主存储总容量(GB)
	#echo $(echo $ps_info | awk '{print $3}')>>$result
	ps_info_3=$(echo $ps_info | awk '{print $3}')
  echo "主存储总容量: $ps_info_3"
# 16 主存储已用容量百分比(0.00)
	#echo $(echo $ps_info | awk '{print $4}')>>$result
	ps_info_4=$(echo $ps_info | awk '{print $4}')
  echo "主存储已用容量百分比: $ps_info_4"
}

function check_SAN_path(){
	# 物理机是否识别了相同的多路径设备
	ifSan=$(zstack-cli QueryPrimaryStorage type=SharedBlock count=true | grep -oE '[0-9]+')
	if [ $ifSan -eq 0 ];then
		# 没有SharedBlock类型主存储，退出该函数
		return
	fi
	#
	ifSame=$(find $log_dir/log/ -name HostDailyCheck* | xargs grep MultiPath |awk -F ':' '{print $2}' | sort | uniq | wc -l)
	if [ $ifSame -eq 1 ];then
		echo "物理机识别了相同的多路径设备"

	else
		echo "Important：物理机未识别了相同的多路径设备，请检查！"
	fi
}

function warnning(){
	# 该函数为检查全局设置中设置不合理的值进行报警
	bsReservedCapacity=$($mysql_cmd "use zstack;SELECT value FROM GlobalConfigVO WHERE name='ReservedCapacity' AND category='backupStorage';" | grep -v value | sed 's/G//g')
	psReservedCapacity=$($mysql_cmd "use zstack;SELECT value FROM GlobalConfigVO WHERE name='ReservedCapacity' AND category='primaryStorage';" | grep -v value | sed 's/G//g')
	vmHA=$($mysql_cmd "use zstack;SELECT value FROM GlobalConfigVO WHERE name='Enable' AND category='HA'; " | grep -v value)
	CPUOverProvisioningRatio=$($mysql_cmd  "use zstack;SELECT value FROM GlobalConfigVO WHERE name='CPU.overProvisioning.ratio';" | grep -v value)
	ReservedMemory=$($mysql_cmd "use zstack;SELECT value FROM GlobalConfigVO WHERE name='ReservedMemory';" | grep -v value | sed 's/G//g')
	MemOverProvisioning=$($mysql_cmd "use zstack;SELECT value FROM GlobalConfigVO WHERE name = 'overProvisioning.memory';" | grep -v value)
	psOverProvisioning=$($mysql_cmd "use zstack;SELECT value FROM GlobalConfigVO WHERE name = 'overProvisioning.primaryStorage';" | grep -v value)
	psThreshold=$($mysql_cmd "use zstack;SELECT value FROM GlobalConfigVO WHERE name = 'threshold.primaryStorage.physicalCapacity';" | grep -v value)
	echo $bsReservedCapacity | awk '{if($0<1){print "Important：镜像服务器保留容量设置过小，当前为："$0"GB"}}'
	echo $psReservedCapacity | awk '{if($0<1){print "Important：主存储保留容量设置过小，当前为："$0"GB"}}'
	echo $vmHA | awk '{if($0=="false"){print "Important：云主机高可用全局开关为关闭状态，建议打开"}}'
	echo $CPUOverProvisioningRatio | awk '{if($0>4){print "Important：CPU超分率设置过高，当前为：$0"}}'
	echo $ReservedMemory | awk '{if($0<1){print "Important：物理机保留内存设置过小，当前为："$0"GB"}}'
	echo $MemOverProvisioning | awk '{if($0>1){print "Important：内存超分率设置过高，当前为："$0}}'
	echo $psOverProvisioning | awk '{if($0>1){print "Important：主存储超分率设置过高，当前为："$0}}'
	echo $psThreshold | awk '{if($0>0.9){print "Important：主存储使用阈值设置过高，当前为："$0}}'
}

function logmonitor_check(){
echo "############################ 管理节点Prometheus版本查询 ############################"
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
                        echo "prometheus监控大小"
                        du -sBG /var/lib/zstack/prometheus
                        echo "influxdb监控大小"
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
                        echo "prometheus监控大小"
                        ssh $mnip du -sBG /var/lib/zstack/prometheus
                        echo "influxdb监控大小"
                        ssh $mnip du -sBG /var/lib/zstack/influxdb/
                fi
        done
}

function StorageNetworkcheck() {
echo "############################存储心跳网络正确性检查############################"
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
                                echo "Normal:The ${names[$(($hostnumcount*2+1))]} Storage Network is correct"
                        else
                                echo "Urgent:The ${names[$(($hostnumcount*2+1))]} Storage Network is error"
                        fi
                fi
        done
done
}


function HostMemoryUsedInPercent(){
  #内存负载
  echo '############################物理机内存负载############################'
  echo "物理机UUID                       内存负载"&&zstack-cli GetMetricData namespace=ZStack/Host metricName=MemoryUsedInPercent | egrep 'HostUuid|value' | xargs -n2 | xargs -n8 |sed 'N;s/\n/ /'|awk 'used=($4+$8+$12+$16)/4 {if(used>0)print $2,used"%";else print $2}'|sort -k2 -rn
}

function nw_io(){
  echo "############################网络吞吐量############################"
  # 网络吞吐量--发送
  net_load_out=$(zstack-cli GetMetricData metricName='NetworkAllOutBytes' offsetAheadOfCurrentTime=310 period=10 namespace=ZStack/Host | grep value | awk -F ' ' '{sum+=$2}END{print sum/NR/1024}')
  # 网络吞吐量--接收
  net_load_in=$(zstack-cli GetMetricData metricName='NetworkAllInBytes' offsetAheadOfCurrentTime=310 period=10 namespace=ZStack/Host | grep value | awk -F ' ' '{sum+=$2}END{print sum/NR/1024}')
  echo "网络吞吐量--发送:$net_load_out KB"
  echo "网络吞吐量--接收:$net_load_in KB"
}

function disk_io(){
  echo "###########################磁盘IO############################"
  # 磁盘IO
  disk_load_write=$(zstack-cli GetMetricData metricName='DiskAllWriteBytes' offsetAheadOfCurrentTime=310 period=10 namespace=ZStack/Host  | grep value | awk -F ' ' '{sum+=$2}END{print sum/NR/1024}')
  # 磁盘IO
  disk_load_read=$(zstack-cli GetMetricData metricName='DiskAllReadBytes' offsetAheadOfCurrentTime=310 period=10 namespace=ZStack/Host  | grep value | awk -F ' ' '{sum+=$2}END{print sum/NR/1024}')
  echo "磁盘IO--写:$disk_load_write KB"
  echo "磁盘IO--读:$disk_load_read KB"
}

function zs_check(){
  echo "############################90天内未操作的云主机############################"
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
  echo  "############################占用物理存储最多的云主机TOP5############################"
  $mysql_cmd "
  use zstack;
  SELECT vv1.name AS vmName,vv.uuid AS rootVolumeUuid,ROUND(vv.actualSize/1024/1024/1024) AS 'actualSize(GB)'
  FROM VolumeVO vv, VmInstanceVO vv1
  WHERE vv.type = 'Root'
  AND vv.uuid = vv1.rootVolumeUuid
  ORDER BY vv.actualSize DESC
  LIMIT 5;
  quit"
  echo "############################占用物理存储最多的云盘TOP5############################"
  $mysql_cmd "
  use zstack;
  SELECT vv.name AS volumeName,vv.uuid AS dataVolumeUuid,ROUND(vv.actualSize/1024/1024/1024) AS 'actualSize(GB)'
  FROM VolumeVO vv
  WHERE vv.type = 'Data'
  #AND vv.vmInstanceUuid IS NOT NULL
  ORDER BY vv.actualSize DESC
  LIMIT 5;
  quit"
  echo "############################占用物理存储最多的镜像TOP10############################"
  $mysql_cmd "
  use zstack;
  SELECT iv.name AS imageName,iv.uuid AS imageUuid,ROUND(iv.actualSize/1024/1024/1024) AS 'actualSize(GB)'
  FROM ImageVO iv
  ORDER BY iv.actualSize DESC
  LIMIT 10;
  quit"
  echo "############################CPU利用率超过80%的云主机############################"
  cpuallusedutilizstion=`zstack-cli GetMetricData metricName=CPUAllUsedUtilization offsetAheadOfCurrentTime=310 period=10 namespace=ZStack/VM | egrep 'VMUuid|value' | sed -n '{N;s/\n/\t/p}' | awk -F '"' '{print $4,$NF}' |awk '{s[$1] += $3}END{ for(i in s){ print s[i]/32,i } }' | sort -nr | awk '{if($1>80) print $2,$1}'`
  if [ -z "$cpuallusedutilizstion" ];then
  	echo "无CPU利用率超过80%的云主机"
  else
  zstack-cli GetMetricData metricName=CPUAllUsedUtilization offsetAheadOfCurrentTime=310 period=10 namespace=ZStack/VM | egrep 'VMUuid|value' | sed -n '{N;s/\n/\t/p}' | awk -F '"' '{print $4,$NF}' |awk '{s[$1] += $3}END{ for(i in s){ print s[i]/32,i } }' | sort -nr | awk '{if($1>80) print $2,$1}'
  fi
  echo "############################CPU负载高于80%的物理机############################"
  CPUAllUsedUtilization=`zstack-cli GetMetricData metricName=CPUAllUsedUtilization offsetAheadOfCurrentTime=310 period=10 namespace=ZStack/Host | egrep 'HostUuid|value' | sed -n '{N;s/\n/\t/p}' | awk -F '"' '{print $4,$NF}' |awk '{s[$1] += $3}END{ for(i in s){ print s[i]/32,i}}' | sort -nr | awk '{if($1>80) print $2,$1}'`
  if [ -z "$CPUAllUsedUtilization" ];then
  	echo "无CPU负载超过80%的物理机"
  else
  zstack-cli GetMetricData metricName=CPUAllUsedUtilization offsetAheadOfCurrentTime=310 period=10 namespace=ZStack/Host | egrep 'HostUuid|value' | sed -n '{N;s/\n/\t/p}' | awk -F '"' '{print $4,$NF}' |awk '{s[$1] += $3}END{ for(i in s){ print s[i]/32,i}}' | sort -nr | awk '{if($1>80) print $2,$1}'
  fi
  echo "############################内存负载高于80%的物理机############################"
  MemoryUsedCapacityPerHostInPercent=`zstack-cli GetMetricData metricName=MemoryUsedCapacityPerHostInPercent offsetAheadOfCurrentTime=310 period=10 namespace=ZStack/Host | egrep 'HostUuid|value' | sed -n '{N;s/\n/\t/p}' | awk -F '"' '{print $4,$NF}' |awk '{s[$1] += $3}END{ for(i in s){ print s[i]/32,i}}' | sort -nr | awk '{if($1>80) print $2,$1}'`
  if [ -z "$MemoryUsedCapacityPerHostInPercent" ];then
  	echo "无内存负载高于80%的物理机"
  else
  zstack-cli GetMetricData metricName=MemoryUsedCapacityPerHostInPercent offsetAheadOfCurrentTime=310 period=10 namespace=ZStack/Host | egrep 'HostUuid|value' | sed -n '{N;s/\n/\t/p}' | awk -F '"' '{print $4,$NF}' |awk '{s[$1] += $3}END{ for(i in s){ print s[i]/32,i}}' | sort -nr | awk '{if($1>80) print $2,$1}'
  fi
  echo "############################磁盘已用空间高于80%的物理机############################"
  DiskRootUsedCapacityInPercent=`zstack-cli GetMetricData metricName=DiskRootUsedCapacityInPercent offsetAheadOfCurrentTime=310 period=10 namespace=ZStack/Host | egrep 'HostUuid|value' | sed -n '{N;s/\n/\t/p}' | awk -F '"' '{print $4,$NF}' |awk '{s[$1] += $3}END{ for(i in s){ print s[i]/32,i}}' | sort -nr | awk '{if($1>80) print $2,$1}'`
  if [ -z "$DiskRootUsedCapacityInPercent" ];then
  	echo "无磁盘占用超过80%的物理机"
  else
  zstack-cli GetMetricData metricName=DiskRootUsedCapacityInPercent offsetAheadOfCurrentTime=310 period=10 namespace=ZStack/Host | egrep 'HostUuid|value' | sed -n '{N;s/\n/\t/p}' | awk -F '"' '{print $4,$NF}' |awk '{s[$1] += $3}END{ for(i in s){ print s[i]/32,i}}' | sort -nr | awk '{if($1>60) print $2,$1}'
  fi
  echo "############################未加载状态的云盘############################"
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
  echo "############################已用物理容量超过80%的主存储############################"
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
  echo "############################已用容量超过80%的镜像服务器############################"
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
  echo "############################已失联物理机############################"
  disconnecthost=`$mysql_cmd "use zstack;SELECT count(*) FROM HostVO hv WHERE hv.hypervisorType = 'KVM' AND hv.status = 'Disconnected';" | grep -v count`
  if [ "$disconnecthost" -lt 1 ];then
          echo "没有失联的物理机"
  else
  exit
  $mysql_cmd "
  use zstack;
  SELECT hv.name,hv.managementIp,hv.state,hv.status
  FROM HostVO hv
  WHERE hv.hypervisorType = 'KVM'
  AND hv.status = 'Disconnected';
  quit"
  fi
  echo "############################已失联主存储############################"
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
  echo "############################已失联镜像服务器############################"
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
  ############################Ceph主存储Mons检查############################
  echo "############################非运行中云主机############################"
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
  quit"
  fi
  #所有云主机都在运行中
}
function chkFragmentation (){
    echo "############################ 磁盘碎片化检查 #############################"
    echo "物理机碎片化检查"
    zstack-cli GetMetricData namespace=ZStack/Host metricName=DiskXfsFragInPercent| egrep 'HostUuid|value' | xargs -n2 |xargs -n16 |awk 'used=($4+$8+$12+$16)/4 {if(used>10)print "Important:" $2,used"%";else print "Normal:" $2,used"%"}'
    echo "云盘碎片化检查"
    zstack-cli GetMetricData metricName=VolumeXfsFragCount namespace=ZStack/Volume | egrep 'VolumeUuid|value' | xargs -n2 |xargs -n16|awk 'used=($4+$8+$12+$16)/4 {if(used>10)print "Important:" $2,used"%";else print "Normal:" $2,used"%"}'
}

function check_user(){
   echo "############################ 用户检查 #############################"
   zstack-cli GetAuditData limit=1 auditType=Login conditions=apiName=org.zstack.header.identity.APILogInByUserMsg |grep createDate|tail -n 1|awk -F"createDate\":\"" '{print$2}'|awk -F"\"" '{print$1}'
}

function check(){
  mn_version
  check_user
  check_password
  chkFragmentation
  zs_check
  HostMemoryUsedInPercent
  check_date_info
  check_db_backup
  logmonitor_check
  StorageNetworkcheck
  auto_mount_check
  warnning
  check_SAN_path
}
check
