#!/bin/bash
. ./.env
#cd log
#cd $1
Total_Host_Num=`find $1 -name HostDailyCheck-*txt |wc -l`
Total_Host_Log=`find $1 -name HostDailyCheck-*txt`
if [ $Total_Host_Num -le 1 ];then
	echo 'This is a All-in-one envirment.' && exit 99
fi
function ZS_Overview(){
	# 1.管理节点概览
	#if [ -e /root/trestds ]; then
	#查询Ceph Mon 节点
	Ceph_MON_IP_Sql="select hostname from CephPrimaryStorageMonVO;"

	#查询镜像仓库IP
	Image_Store_IP_Sql="select hostname from ImageStoreBackupStorageVO;"

	#查询物理机IP
	MN_IP_Sql="select hostName from ManagementNodeVO;"

	#查询管理节点IP
	#Host_IP_Sql="select managementIp from HostVO;"
	Host_IP_Sql="select managementIp from HostVO where hypervisorType='KVM';"

	#查询管理节点是否与物理机共用
	MN_Host_IP_Sql="select managementIp from HostVO inner join ManagementNodeVO on HostVO.managementIp=ManagementNodeVO.hostName;"

	#查询管理节点是否与镜像仓库共用
	MN_Image_Store_Sql="select ManagementNodeVO.hostName from ManagementNodeVO inner join ImageStoreBackupStorageVO on ManagementNodeVO.hostName=ImageStoreBackupStorageVO.hostname;"

	#查询镜像仓库是否与物理机共用
	Image_Store_Host_Sql="select managementIp from HostVO inner join ImageStoreBackupStorageVO on HostVO.managementIp=ImageStoreBackupStorageVO.hostname;"

	#查询管理节点是否与Mon IP共用
	MN_MON_IP_Sql="select ManagementNodeVO.hostName from ManagementNodeVO inner join CephPrimaryStorageMonVO on ManagementNodeVO.hostName=CephPrimaryStorageMonVO.hostname;"

	Image_Server_Capacity_Sql="select ImageStoreBackupStorageVO.hostname,BackupStorageVO.url,name,truncate(totalCapacity/1024/1024/1024,2)Total_GB,truncate(availableCapacity/1024/1024/1024,2)Avail_GB from BackupStorageVO left join ImageStoreBackupStorageVO on BackupStorageVO.uuid=ImageStoreBackupStorageVO.uuid;"

	Ceph_Image_Serveri_Capatity_Sql="select BackupStorageVO.name,CephBackupStorageVO.poolName,truncate(totalCapacity/1024/1024/1024,2)Total_GB,truncate(availableCapacity/1024/1024/1024,2)Avail_GB,poolReplicatedSize from CephBackupStorageVO left join BackupStorageVO  on BackupStorageVO.uuid=CephBackupStorageVO.uuid;"

	PS_Capacity_Sql="select A.name PS, A.url,truncate(D.totalPhysicalCapacity/1024/1024/1024,2)Total_PS_GB,truncate(D.availableCapacity/1024/1024/1024,2)Avail_Virtual_GB,truncate(D.availablePhysicalCapacity/1024/1024/1024,2)Avail_Physical_GB from PrimaryStorageVO as A,PrimaryStorageCapacityVO as D where  A.uuid=D.uuid;"

	Cluster_PS_Info_Sql="select C.name Cluster,A.name PS, A.url,A.type,A.mountPath,A.status PSstatus from PrimaryStorageVO as A,PrimaryStorageClusterRefVO as B,ClusterVO as C where A.uuid=B.primaryStorageUuid AND C.uuid=B.clusterUuid order by C.name;"
	#SnapShot_Size_Sql="select B.name Volume_Name,C.name VM_Name,truncate(A.size/1024/1024/1024,2) Snapshot_Size_GB, truncate(B.size/1024/1024/1024,2) Volume_Size_GB, A.name Snapshot_Name from VolumeSnapshotVO as A, VolumeVO as B,VmInstanceVO as C where A.volumeUuid=B.uuid AND C.uuid=B.vmInstanceUuid Order by A.size desc ;"
	SnapShot_Size_Sql="select B.name Volume_Name,C.name VM_Name,truncate(A.size/1024/1024/1024,2) Snapshot_Size_GB,truncate(B.size/1024/1024/1024,2) Volume_Virtual_Size_GB,truncate(B.actualSize/1024/1024/1024,2) Volume_Actual_Size_GB,left(A.name,16) Snapshot_Name from VolumeSnapshotVO as A, VolumeVO as B,VmInstanceVO as C where A.volumeUuid=B.uuid AND C.uuid=B.vmInstanceUuid Order by A.size desc  limit 20;"
	SnapShot_Num_Sql="select B.name Volume_name,count(B.name) SnapShot_Num,C.name VM_Name,truncate(A.size/1024/1024/1024,2) Snapshot_Size_GB,truncate(B.size/1024/1024/1024,2) Volume_Virtual_Size_GB,truncate(B.actualSize/1024/1024/1024,2) Volume_Actual_Size_GB,left(A.name,16) Snapshot_Name from VolumeSnapshotVO as A, VolumeVO as B,VmInstanceVO as C where A.volumeUuid=B.uuid AND C.uuid=B.vmInstanceUuid group by B.name Order by count(B.name)  desc  limit 20;"
	Volume_Size_Sql="select B.name Volume_name, truncate(B.size/1024/1024/1024,2) Volume_Virtual_Size_GB,truncate(B.actualSize/1024/1024/1024,2) Volume_Actual_Size_GB from  VolumeVO as B Order by B.actualSize desc  limit 20;"

	zs_properties=`zstack-ctl status|grep [z]stack.properties|awk '{print $2}'`
	DB_IP=`cat $zs_properties|awk -F ":" '/DB.url /{print $3}'`
	DB_IP=`echo ${DB_IP#*//}`
	DB_Port=`cat  $zs_properties|awk -F ":" '/DB.url /{print $4}'`
	DB_User=`cat  $zs_properties|awk  '/DB.user /{print $3}'`
	DB_Password=${zs_sql_pwd}
	SQL_Access="mysql -u $DB_User -p$DB_Password zstack -h $DB_IP -P $DB_Port"

	Ceph_MON_IP=`echo "$Ceph_MON_IP_Sql"|$SQL_Access|sed '1d'`
	Image_Store_IP=`echo "$Image_Store_IP_Sql"|$SQL_Access|sed '1d'`
	MN_IP=`echo "$MN_IP_Sql"|$SQL_Access|sed '1d'`
	Host_IP=`echo "$Host_IP_Sql"|$SQL_Access|sed '1d'`
	MN_Host_IP=`echo "$MN_Host_IP_Sql"|$SQL_Access|sed '1d'`
	MN_Image_Store=`echo "$MN_Image_Store_Sql"|$SQL_Access|sed '1d'`
	Image_Store_Host=`echo "$Image_Store_Host_Sql"|$SQL_Access|sed '1d'`
	MN_MON_IP=`echo "$MN_MON_IP_Sql"|$SQL_Access|sed '1d'`
	Image_Server_Capacity=`echo "$Image_Server_Capacity_Sql"|$SQL_Access`
	Ceph_Image_Serveri_Capatity=`echo "$Ceph_Image_Serveri_Capatity_Sql"|$SQL_Access`
	Cluster_PS_Info=`echo "$Cluster_PS_Info_Sql"|$SQL_Access`

	echo "Ceph 存储Mon节点信息:"
	echo $Ceph_MON_IP
	echo
	sleep 1
	echo "镜像仓库节点信息:"
	echo $Image_Store_IP
	echo

	echo "管理节点信息:"
	echo $MN_IP
	echo

	echo "管理节点与物理机共用的节点信息:"
	echo $MN_Host_IP
	echo

	echo "管理节点与镜像仓库共用的节点信息:"
	echo $MN_Image_Store
	echo

	echo "镜像仓库与物理机共用的节点信息:"
	echo $Image_Store_Host
	echo

	echo "管理节点与Ceph存储Mon共用的节点信息:"
	echo $MN_MON_IP
	echo

	echo "物理机的管理网络IP地址信息:"
	echo "$Host_IP_Sql"|$SQL_Access
	echo

	echo "镜像服务器容量:"
	echo "$Image_Server_Capacity_Sql"|$SQL_Access|column -t
	echo

	echo "Ceph镜像服务器容量:"
	echo "$Ceph_Image_Serveri_Capatity_Sql"|$SQL_Access|column -t
	echo

	echo "主存储容量:"
	echo "$PS_Capacity_Sql"|$SQL_Access|column -t
	echo

	echo "集群与主存储的挂载关系列表:"
	echo "$Cluster_PS_Info_Sql"|$SQL_Access|column -t
	echo


	echo "快照大小与云主机云盘关系列表:(容量排序前20)"
	echo "$SnapShot_Size_Sql"|$SQL_Access|column -t
	echo

	echo "快照数量与云主机云盘关系列表:(数量排序前20)"
	echo "$SnapShot_Num_Sql"|$SQL_Access|column -t
	echo

	echo "云盘容量排行:(真实容量排序前20)"
	echo "$Volume_Size_Sql"|$SQL_Access|column -t
	echo
	# 2.物理机概览
	#if [ -e /root/trestds ]; then
	echo "物理机上MON节点系统盘类型:"
	grep "system disk sd"  $Total_Host_Log -ir|awk -F "/|:" '{print $7":"$5,$8}'
	echo

	echo "物理机的主机名信息:"
	grep "主机名" $Total_Host_Log -ir| awk -F "/|:" '{print $5,$7}'
	echo

        echo "物理机CPU C State信息:"
        grep "CPU C state"  $Total_Host_Log -r | awk -F "/|:" '{print $7":"$8}'
        echo

        echo "物理机CPU的温度信息:"
        grep "CPU temperature"  $Total_Host_Log -r | awk -F "/|:" '{print $5":"$8}'
        echo

	echo "物理机的CPU核心数:"
	grep "CPU核心数: "  $Total_Host_Log -ir|awk -F "/|:" '{print $5,$7,$8}'
	echo

	echo "物理机已开机运行时间:"
	grep "运行时间" $Total_Host_Log -ir| awk -F "/|:" '{print $5,$7}'
	echo

	echo "物理机上的进程数量信息:"
	grep "进程数量" $Total_Host_Log -ir| awk -F "/|:" '{print $5,$7}'
	echo

	echo "物理机上系统负载信息:"
	grep "系统负载: " $Total_Host_Log -ir| awk -F "/|:" '{print $5,$7,$8}'
	echo

	echo "物理机上已用内存信息:"
	grep "已用内存"  $Total_Host_Log -ir|awk -F "/|:" '{print $5,$7,$8,$9,$10}'
	echo

	echo "物理机上SWAP信息,针对Ceph存储请确保关闭SWAP分区:"
	grep "已用Swap"  $Total_Host_Log -ir|awk -F "/|:" '{print $5,$7,$8,$9,$10}' | awk '{if($4>'1'){print "Urgent：该物理机没有关闭swap分区 "$0} else print $1":该物理机swap分区已关闭"}'
	echo

	echo "物理机上系统盘使用信息:"
	grep "系统盘使用"  $Total_Host_Log -ir|awk -F "/|:" '{print $5,$7,$8,$9,$10}'
	echo

	echo "物理机硬件信息汇总:"
	grep "^Summary"  $Total_Host_Log -ir|awk -F "/|:" '{print $5,$8}'
	echo

	echo "物理机上硬盘信息汇总:"
	grep "^Disk:"  $Total_Host_Log -ir|awk -F "/|:" '{print $5,$8,$9}'
	echo

	echo "物理机上磁盘控制器信息汇总:"
	grep "^Disk-Control:"  $Total_Host_Log -ir|awk -F "/|:" '{print $5,$7,$8,$9,$10}'
	echo

	echo "物理机上网卡信息汇总:"
	grep "^Network:"  $Total_Host_Log -ir|awk -F "/|:" '{print $5,$7,$8,$9,$10}'
	echo

	echo "物理机上CPU信息汇总:"
	grep "CPU型号:"  $Total_Host_Log -ir|awk -F "/|:" '{print $5,$7,$8,$9,$10}'
	echo

	echo "物理机上内存RSS使用信息:"
	grep "System Memory RSS Info:" $Total_Host_Log -ir|awk -F "/|:" '{print $5,$7,$8}'
	echo

	echo "物理机上时间同步信息汇总:"
	echo "Chrony Server Conf 第一列为时间客户端, 第二列为时间源服务器"
	grep "^server" $Total_Host_Log -r |grep iburst$|awk '{gsub(/\/HostDailyCheck-[^|]*txt-/," " ); print}'|awk -F "/| " '{print $5,$7}'
	echo

	#fi
	echo "物理机上使用量超过30%的磁盘信息列表:"
	grep "磁盘检查" $Total_Host_Log -ir -A 50|grep  "|"|grep -v Mounted |awk -F '[ %]+' '{ if ($7>=30) print}'|awk '{print $1, $4,$5,$7,$NF}'|awk '{gsub(/\/tmp\/xunjianlog-[^|]*log\//,"" ); print}'|awk '{gsub(/\/HostDailyCheck-[^|]*txt-/," " ); print}'
	echo

	echo "物理机上警告信息列表:"
	grep "Important：" $Total_Host_Log -ir |awk -F "/|:" '{print $2, $4,$5,$6}'
	echo

	echo "物理机上网卡Bond信息:"
	#grep "Bonding Mode Slave Info:" $Total_Host_Log -ir -A 20|grep Bond_Info|awk '{gsub(/\/HostDailyCheck-[^|]*txt-/," " ); print}'|sed 's/log\///g'|sed 's/Bond_Info|//g'
	grep "Bonding Mode Slave Info:" $Total_Host_Log -ir -A 20|grep Bond_Info|awk '{gsub(/\/HostDailyCheck-[^|]*txt-/," " ); print}'|awk '{gsub(/\/tmp\/xunjianlog-[^|]*\//,"" ); print}'|sed 's/log\///g'|sed 's/Bond_Info|//g'
	echo

	echo "物理机上网卡、网卡是否链接、网卡驱动、网卡带宽、网卡设备型号信息，请仔细确认核对:"
	grep "device  link_status  driver  speed  vendor_device" $Total_Host_Log -A 50 -ir|egrep "Ethernet|bonding"|awk '{gsub(/\/tmp\/xunjianlog-[^|]*log\//,"" ); print}'|awk '{gsub(/\/HostDailyCheck-[^|]*txt-/," " ); print}'
	echo

	echo "内存占用超过16G 以上进程列表:"
	echo "Host-PID     %MEM  RSS(GB)  COMMAND"|column -t
	grep "内存占用TOP20" $Total_Host_Log -ir -A 22|grep -v COMMAND |awk  '{ if ($3>=16) print}'|awk '{gsub(/\/HostDailyCheck-[^|]*txt-/," " ); print}'|sed 's/log\///g'|column -t
	echo

	echo "CPU占用超过200%以上进程列表:"
	echo "Host-PID     USER  PR  NI  VIRT     RES     SHR    S  %CPU   %MEM  TIME+      COMMAND"|column -t
	grep "CPU占用TOP20" $Total_Host_Log -ir -A 22|grep -v COMMAND |awk  '{ if ($9>=200) print}'|awk '{gsub(/\/HostDailyCheck-[^|]*txt-/," " ); print}'|sed 's/log\///g'|column -t
	echo
	#sleep 5

        echo "检查SELinux:"
	SELinux_Disable_Num=`grep "SELinux：disabled"  $Total_Host_Log -ir|wc -l`
		if [ X$SELinux_Disable_Num == X$Total_Host_Num ];then
			echo "All hosts SELinux config disabled "
		else
			echo "All hosts SELinux config aren't all disabled "
		fi

        echo "检查语言编码:"
	LANG_NUM=`grep "语言/编码：en_US.UTF-8"  $Total_Host_Log -ir| wc -l`
		if [ X$LANG_NUM == X$Total_Host_Num ];then
			echo "All hosts LANG setting en_US.UTF-8"
		else
			echo "All hosts LANG setting aren't all disabled "
		fi

        echo "检查EFI分区:"
        EFI_NUM=`grep "/boot/efi" $Total_Host_Log -ir |grep uuid -i|wc -l`
        if [ X$EFI_NUM != X$Total_Host_Num ] && [ $EFI_NUM -ne 0 ];then
            echo "There are $EFI_NUM Host using EFI partition, not all Host, Please Check"
        elif [ X$EFI_NUM == X$Total_Host_Num ];then
            echo "All hosts are using EFI partition"
        elif [ $EFI_NUM -eq 0 ];then
            echo "There are $EFI_NUM Host using EFI partition"
        fi
        echo ""
}


function OS_Check(){
    echo "############################### OS check ####################################"
    CT72_NUM=`grep  "CentOS Linux release 7.2.1511 (Core)" $Total_Host_Log -ir |grep "发行版本：" |awk -F : '{print $2}'|wc -l`
    CT73_NUM=`grep  "CentOS Linux release 7.3.1611 (Core)" $Total_Host_Log -ir |grep "发行版本：" |awk -F : '{print $2}'|wc -l`
    CT74_NUM=`grep  "CentOS Linux release 7.4.1708 (Core)" $Total_Host_Log -ir |grep "发行版本：" |awk -F : '{print $2}'|wc -l`
    CT75_NUM=`grep  "CentOS Linux release 7.5.1804 (Core)" $Total_Host_Log -ir |grep "发行版本：" |awk -F : '{print $2}'|wc -l`
    CT76_NUM=`grep  "CentOS Linux release 7.6.1810 (Core)" $Total_Host_Log -ir |grep "发行版本：" |awk -F : '{print $2}'|wc -l`
    if [ $CT73_NUM -ne 0 ] || [ $CT75_NUM -ne 0 ] || [ $CT72_NUM -ne 0 ] ;then
        echo "Warning: There are hosts using the System not supported by ZStack!"
    elif [ X$CT74_NUM != X$Total_Host_Num ] && [ $CT74_NUM -ne 0 ];then
        echo "Warning: There aren't all hosts using the same system!"
    elif [ X$CT76_NUM != X$Total_Host_Num ] && [ $CT76_NUM -ne 0 ];then
        echo "Warning: There aren't all hosts using the same system!"
    fi

    echo "There are $CT72_NUM Host using CentOS 7.2"
    echo "There are $CT73_NUM Host using CentOS 7.3"
    echo "There are $CT74_NUM Host using CentOS 7.4"
    echo "There are $CT75_NUM Host using CentOS 7.5"
    echo "There are $CT76_NUM Host using CentOS 7.6"

    if [ X$CT74_NUM == X$Total_Host_Num ];then
        echo "All hosts using the same system CentOS 7.4.1708"
    elif [ X$CT76_NUM == X$Total_Host_Num ];then
        echo "All hosts using the same system CentOS 7.6.1810"
    fi
}

function Kernel_Check(){
    echo "############################### kernel check ####################################"
    CT72_Kernel_NUM=`grep  "3.10.0-327" $Total_Host_Log -ir |awk '/内核/ {print $2}'|wc -l`
    CT73_Kernel_NUM=`grep  "3.10.0-514" $Total_Host_Log -ir |awk '/内核/ {print $2}'|wc -l`
    CT74_Kernel_NUM=`grep  "3.10.0-693" $Total_Host_Log -ir |awk '/内核/ {print $2}'|wc -l`
    CT75_Kernel_NUM=`grep  "3.10.0-862" $Total_Host_Log -ir |awk '/内核/ {print $2}'|wc -l`
    CT76_Kernel_NUM=`grep  "3.10.0-957" $Total_Host_Log -ir |awk '/内核/ {print $2}'|wc -l`
    if [ $CT73_Kernel_NUM -ne 0 ] || [ $CT75_Kernel_NUM -ne 0 ] || [ $CT72_Kernel_NUM -ne 0 ] ;then
        echo "Warning: There are hosts using the Kernel not supported by ZStack!"
    elif [ X$CT74_Kernel_NUM != X$Total_Host_Num ] && [ $CT74_Kernel_NUM -ne 0 ];then
        echo "Warning: There aren't all hosts using the same system!"
    elif [ X$CT76_Kernel_NUM != X$Total_Host_Num ] && [ $CT76_Kernel_NUM -ne 0 ];then
        echo "Warning: There aren't all hosts using the same system!"
    fi

    echo "There are $CT72_Kernel_NUM Host using CentOS 7.2.1511 3.10.0-327"
    echo "There are $CT73_Kernel_NUM Host using CentOS 7.3.1611 3.10.0-514"
    echo "There are $CT74_Kernel_NUM Host using CentOS 7.4.1708 3.10.0-693"
    echo "There are $CT75_Kernel_NUM Host using CentOS 7.5.1804 3.10.0-862"
    echo "There are $CT76_Kernel_NUM Host using CentOS 7.6.1810 3.10.0-957"

    if [ X$CT74_Kernel_NUM == X$Total_Host_Num ];then
        echo "All hosts using the same Kernel CentOS 7.4.1708 3.10.0-693"
    elif [ X$CT76_Kernel_NUM == X$Total_Host_Num ];then
        echo "All hosts using the same Kernel CentOS 7.6.1810 3.10.0-957"
    fi
}



ZS_Overview
OS_Check
Kernel_Check
#Hostname_Check
