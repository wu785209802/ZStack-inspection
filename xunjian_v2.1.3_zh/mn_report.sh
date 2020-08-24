#!/bin/bash
# Author: bo.zhang
# Create Date: 2019-03-06
. ./.env
function basic_info(){
	check_date=$(date '+%Y/%m/%d %H:%M:%S')
	mn_hostname=$(hostname)
	mn_url=$(zstack-ctl status | awk 'END{print $5}')
	mn_version=$(zstack-ctl status | grep version | awk '{for(i=2;i<=NF;i++) printf $i;printf "\n"}')
	os_release=$(cat /etc/redhat-release)
	os_kernel=$(uname -r)
	mn_pre_status=$(zstack-ctl status | grep MN | awk '{print $3}')
	mn_ui_status=$(zstack-ctl status | grep UI | awk '{print $3}')
#	echo "巡检时间,$check_date,"
#	echo "管理节点,$mn_hostname,登录信息,$mn_url,"
#	echo "云平台版本,$mn_version,"
#	echo "系统版本,$os_release,内核版本,$os_kernel,"
#	echo "管理服务运行状态,$mn_pre_status,UI服务运行状态,$mn_ui_status,"
	
	echo "$check_date,"
	echo "$mn_hostname,$mn_url,"
	echo "$mn_version,"
	echo "$os_release,$os_kernel,"
	echo "$mn_pre_status,$mn_ui_status,"
}
function ps_overview(){
	. ./.env
	
#	echo -e "主存储概览"
	$mysql_cmd "
	use zstack;
        SELECT 名称,总容量,可用容量,百分比,CONCAT(启用状态,'/',就绪状态) AS '当前状态' FROM
                (SELECT
                        
                        REPLACE(ps.name,' ','') AS '名称',
                        CONCAT(ROUND(psc.totalCapacity/1024/1024/1024/1024,2),'TB') as '总容量',
                        CONCAT(ROUND(psc.availableCapacity/1024/1024/1024/1024,2),'TB') as '可用容量',  
                        ROUND((psc.totalCapacity-psc.availableCapacity)/psc.totalCapacity,2) AS '百分比',
                        CASE ps.state
                        WHEN 'Enabled' THEN '启用'
                        WHEN 'Disabled' THEN '停用'
                        WHEN 'Maintenance' THEN '维护模式'
                        ELSE '未知' END AS '启用状态',
                        CASE ps.status
                        WHEN 'Connected' THEN '已连接'
                        WHEN 'Connecting' THEN '连接中'
                        WHEN 'Disconnected' THEN '已失联'
                        ELSE '未知' END AS '就绪状态'
                FROM
                        PrimaryStorageVO ps,
                        PrimaryStorageCapacityVO psc
                WHERE
                        ps.uuid = psc.uuid
                and ps.type!='VCenter') t1,
		(SELECT @rowno := 0) t
                ;
	" 
}

function bs_overview(){
	. ./.env

#	echo -e "镜像服务器概览"
	$mysql_cmd "
	use zstack;	
	select 名称,总容量,可用容量,挂载目录,CONCAT(启用状态,'/',就绪状态) as '当前状态' FROM 
        (SELECT
                        REPLACE(bs.name,' ','') AS '名称',
                        CONCAT(ROUND(bs.totalCapacity/1024/1024/1024/1024,2),'TB') AS '总容量',
                        CONCAT(ROUND(bs.availableCapacity/1024/1024/1024/1024,2),'TB') AS '可用容量',
                        REPLACE(bs.url,' ','_') AS '挂载目录',
                        CASE bs.state
                        WHEN 'Enabled' THEN '启用'
                        WHEN 'Disabled' THEN '停用'
                        WHEN 'Maintenance' THEN '维护模式'
                        ELSE '未知' END AS '启用状态',
                        CASE bs.status
                        WHEN 'Connected' THEN '已连接'
                        WHEN 'Connecting' THEN '连接中'
                        WHEN 'Disconnected' THEN '已失联'
                        ELSE '未知' END AS '就绪状态'
                FROM
                        BackupStorageVO bs
                WHERE bs.type!='VCenter'
                AND bs.uuid not in (select st.resourceUuid FROM SystemTagVO st WHERE st.resourceType LIKE '%BackupStorageVO' AND st.tag='onlybackup')) t1,
                (SELECT @rowno := 0) t;
	"

}
function host_overview(){
	. ./.env
#	echo '物理机连接状态及云主机数量'
	$mysql_cmd "
	use zstack;	
	SELECT 名称,管理IP,CONCAT(启用状态,'/',就绪状态) as '当前状态',云主机数量 FROM
		(SELECT			
			REPLACE(hv.name,' ','') AS '名称',
			hv.managementIp AS '管理IP',
			CASE hv.state
			WHEN 'Enabled' THEN '启用'
			WHEN 'Disabled' THEN '停用'
			WHEN 'Maintenance' THEN '维护模式'
			ELSE '未知' END AS '启用状态',
			CASE hv.status
			WHEN 'Connected' THEN '已连接'
			WHEN 'Connecting' THEN '连接中'
			WHEN 'Disconnected' THEN '已失联'
			ELSE '未知' END AS '就绪状态',
			count(vmv.uuid) AS '云主机数量'
		FROM
                        HostVO hv,  
												
			VmInstanceVO vmv
								
		WHERE	vmv.hostUuid = hv.uuid
			AND hv.hypervisorType = 'KVM'
		GROUP BY
			hv.managementIp) t1,(SELECT @rowno := 0) t;

	" 
}

function vm_90oper_days(){
	. ./.env
#	echo '90天内未操作的云主机'
	$mysql_cmd "
	use zstack;		
	SELECT
		REPLACE(vm.name,' ','') AS '名称',
		vm.uuid AS 'UUID'
	FROM
		VmInstanceVO vm,
		(SELECT @rowno := 0) t
	WHERE
		DATE_SUB(
			CURRENT_DATE (),
			INTERVAL 90 DAY
		) > DATE(vm.lastOpDate)
	ORDER BY
		vm.lastOpDate DESC;

	"
	vm_90oper_num=$($mysql_cmd "
	use zstack;
	SELECT
		count(*)
	FROM
		VmInstanceVO vm
	WHERE
		DATE_SUB(CURRENT_DATE (),INTERVAL 90 DAY) > DATE(vm.lastOpDate);" | tail -n 1)
	if [ $vm_90oper_num -eq 0 ];then echo -e "\n无,无";fi
	
}

function vm_CPUAllUsedUtilization (){
#	echo 'CPU利用率超过80%的云主机'
#	dd=$(date '+%Y-%m-%d')
#	export LOG_PATH=/tmp/xunjianlog-"$dd"
	vm_used_80=$(echo $LOG_PATH/log/vm_used_80.txt)
	vm_name=$(echo $LOG_PATH/log/vm_name.txt)
	if [ ! -d $LOG_PATH/log ];then mkdir -p $LOG_PATH/log;fi
	zstack-cli GetMetricData  namespace=ZStack/VM metricName=CPUAllUsedUtilization | egrep 'VMUuid|value' | awk '{printf (NR%8)==0?$0"\n":$0}' |awk -F '"' '{print $4,$7}' | awk '{if($3>80)printf "%.2f %s\n",$3,$1}' | sort | awk '{print $2,$1}'  > $LOG_PATH/log/vm_used_80.txt
	zstack-cli QueryVmInstance fields=name,uuid | egrep 'name|uuid' | awk '{printf (NR%2)==0?$0"\n":$0}' | sed 's/ //g' | awk -F '"' '{print $8,$4}' | sort > $LOG_PATH/log/vm_name.txt	
	join $vm_used_80 $vm_name | awk '{print $2,$1,$3}' | sort | awk '{print $3,$2,$1}'
	if [ ! -s $vm_used_80 ];then echo '无,无,无';fi
	rm -f $LOG_PATH/log/vm_used_80.txt $LOG_PATH/log/vm_name.txt
}

function db_backup_info(){
	localBackupDir='/var/lib/zstack/mysql-backup'
	remoteBackupDir='/var/lib/zstack/from-zstack-remote-backup'
	backup_host_list=`crontab -l| grep -v ^# | grep 'zstack-ctl dump_mysql' | grep -oE "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}"`
	
	local_db_backup_num=$(ls $localBackupDir/zstack-backup-db* | wc -l)
	local_db_backup_capacity=$(du -sh $localBackupDir | awk '{print $1}')
	echo "$local_db_backup_num,$local_db_backup_capacity"
	
	#echo '远程主机IP,数据库备份文件,数据库备份容量'

	if [[ $backup_host_list ]];then
			for host_list in $backup_host_list
			do
				sshpass -p 'password' ssh $host_list -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa echo >> /dev/null 2>&1
				if [ $? -eq 0 ];then
					remote_db_backup_num=$(sshpass -p 'password' ssh $host_list -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa ls $remoteBackupDir  | wc -l 2> /dev/null)
					remote_db_backup_capacity=$(sshpass -p 'password' ssh $host_list -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa du -sh $remoteBackupDir/  | awk '{print $1}' 2> /dev/null)
					echo $host_list,$remote_db_backup_num,$remote_db_backup_capacity
				else
					break
				fi
			done
			if [ -z $remote_db_backup_num ];then echo '无,无,无';fi
	fi
}

function check_date_info (){
	time_zone=$(timedatectl | grep zone | sed 's/,//g' | awk -F ' ' '{if($3=="Asia/Shanghai")print $3}')
	time_server=$(chronyc sources -v | grep ^^ | awk '{print $2}' | xargs | sed 's/ /,/g')
#	echo '时区一致性,时间同步源'
#	if [ "$time_zone" == "Asia/Shanghai " ];then
#		echo "时区设置错误，当前时区为$time_zone,$time_server"
#	else
#		echo "时区设置正确，当前时区为$time_zone,$time_server"
#	fi
	echo $time_server
}

function check(){
	basic_info | xargs |sed -r "s:\x1B\[[0-9;]*[mK]::g"
	ps_overview  | sed 1d | awk '{for(i=1;i<=NF;i++){a[FNR,i]=$i}}END{for(i=1;i<=NF;i++){for(j=1;j<=FNR;j++){printf a[j,i]" "}print ""}}'
	bs_overview | sed 1d | awk '{for(i=1;i<=NF;i++){a[FNR,i]=$i}}END{for(i=1;i<=NF;i++){for(j=1;j<=FNR;j++){printf a[j,i]" "}print ""}}'
	host_overview  | sed 1d | awk '{for(i=1;i<=NF;i++){a[FNR,i]=$i}}END{for(i=1;i<=NF;i++){for(j=1;j<=FNR;j++){printf a[j,i]" "}print ""}}'
	vm_90oper_days  | sed 1d | awk '{for(i=1;i<=NF;i++){a[FNR,i]=$i}}END{for(i=1;i<=NF;i++){for(j=1;j<=FNR;j++){printf a[j,i]" "}print ""}}'
	vm_CPUAllUsedUtilization | awk '{for(i=1;i<=NF;i++){a[FNR,i]=$i}}END{for(i=1;i<=NF;i++){for(j=1;j<=FNR;j++){printf a[j,i]" "}print ""}}'
	db_backup_info | xargs | sed 's/ /,/g'
	check_date_info | xargs
}

check > $LOG_PATH/log/mn_report.csv
# iconv -f UTF8 -t GBK $LOG_PATH/log/mn_report.csv -o $LOG_PATH/log/mn_report.csv
