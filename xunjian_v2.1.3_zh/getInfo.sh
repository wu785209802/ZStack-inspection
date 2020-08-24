#!/bin/bash
# Author: bo.zhang
# V1.8.0
# 2018-12-07
# 2019-02-19
# 2019-05-30

dd=$(date '+%Y-%m-%d')
log_dir=/tmp/xunjianlog-"$dd"
. ./.env
result=$log_dir/log/platform_info.csv
#user_password='zstackts'
#zstack-cli LogInByAccount accountName=admin password=$user_password >/dev/null 2>&1
cat ./template.txt |awk '{print $1"\t""template"}'  >> $result

function GetLicenseType(){
# 1 已购买license类型（hybrid，Paid）
  license_type1=$(zstack-cli GetLicenseInfo | grep licenseType | awk -F '"' '{print $4}')
  #echo $license_type1>>$result
  sed  -i "/已购买license类型/s/template/$license_type1/g" /$result
# 2 试用版（test）/永久(prepaid)
  issuedDate=$(zstack-cli GetLicenseInfo | grep 'issuedDate' | awk -F '"' '{print $4}' | sed '1,$s/T/ /g')
  expiredDate=$(zstack-cli GetLicenseInfo | grep 'expiredDate' | awk -F '"' '{print $4}' | sed '1,$s/T/ /g')
#  echo ${expiredDate}' '${issuedDate}
  avaliableDays=$(($(date +%s -d "${expiredDate}")-$(date +%s -d "${issuedDate}")))
  avaliableDay=$(echo $avaliableDays | awk '{print $1/86400}')
# 有效期小于30天则判定为试用用户
  echo $avaliableDay | awk '{if($1<30) print 'test';else print 'prepaid'}'
  if [ "$avaliableDay" -le 30 ];then
    #echo 'test'>>$result
    sed  -i "/试用版/s/template/test/g" $result
  else
    #echo 'prepaid'>>$result
    sed  -i "/试用版/s/template/prepai/g" $result
  fi
}
# 3 版本号
function GetZstackVersion(){
        zs_version=$(zstack-cli GetVersion | grep version | awk -F '"' '{print $4}')
        #echo $zs_version>>$result
        sed  -i "/版本号/s/template/$zs_version/g" $result
        }

# 4 是否超融合部署
function QueryIfFuse(){
	com_ip=$(zstack-cli QueryHost hypervisorType=KVM fields=managementIp status=Connected | grep managementIp | awk -F '"' '{print $4}' | head -1)
	ssh $com_ip -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa ceph -s >>/dev/null 2>&1
	if [ $? -ne 0 ];then
		#echo 'N'>>$result
    sed  -i "/是否超融合部署/s/template/N/g" $result
	else
		#echo 'Y'>>$result
    sed  -i "/是否超融合部署/s/template/Y/g" $result
	fi
}
# 5 管理节点是否独立部署
function QueryIfAlone(){
	ifVM=$(dmidecode -t system | grep Manufacturer | awk '{print $2$3}')
	if [ "$ifVM" == "RedHat" ]
	then
		#echo "N">>$result
    sed  -i "/管理节点是否独立部署/s/template/N/g" $result
	else
		/etc/init.d/zstack-kvmagent status >> /dev/null 2>&1
		if [ $? -eq 0 ];then
			#echo "N">>$result
      sed  -i "/管理节点是否独立部署/s/template/N/g" $result
		else
			#echo "Y">>$result
      sed  -i "/管理节点是否独立部署/s/template/Y/g" $result
		fi
	fi
}
# 6 管理节点是否双节点使用高可用（zsha2）
# 以管理节点个数来做判断，只有1个，非zsha2；2个，zsha2；其他，NULL
function IfInstallZSHA2(){
	mn_count=$(zstack-cli QueryManagementNode count=true | grep -oE '[0-9]+')
	if [ $mn_count -eq 1 ];then
		#echo "N">>$result
    sed  -i "/管理节点是否双节点使用高可用/s/template/N/g" $result
        elif [ $mn_count -eq 2 ];then
                #echo "Y">>$result
                sed  -i "/管理节点是否双节点使用高可用/s/template/Y/g" $result
	else
		#echo "NULL">>$result
    sed  -i "/管理节点是否双节点使用高可用/s/template/NULL/g" $result
        fi

	}
# 7 物理机数量
# KVM 物理机的数量
function QueryHostNum(){
  host_num=$(zstack-cli QueryHost hypervisorType=KVM count=true | grep total |awk  '{print $2}')
  #echo $host_num>>$result
  sed  -i "/物理机数量/s/template/$host_num/g" $result
}

# 8 local主存储类型
# zstack-cli QueryPrimaryStorage type=LocalStorage count=true | grep -oE '[0-9]+'
function QueryLocalStorageType(){
  local_storage_num=$(zstack-cli QueryPrimaryStorage type=LocalStorage count=true | grep -oE '[0-9]+')
  if [ $local_storage_num -gt 0 ];then
    #echo 'Y'>>$result
    sed  -i "/local主存储类型/s/template/Y/g" $result
  else
    #echo 'N'>>$result
    sed  -i "/local主存储类型/s/template/N/g" $result
  fi
}
# 9 sblk主存储类型
# zstack-cli QueryPrimaryStorage type=LocalStorage count=true | grep -oE '[0-9]+'
function QuerySblkStorageType(){
  sblk_storage_num=$(zstack-cli QueryPrimaryStorage type=SharedBlock count=true | grep -oE '[0-9]+')
  if [ $sblk_storage_num -gt 0 ];then
    #echo 'Y'>>$result
    sed  -i "/sblk主存储类型/s/template/Y/g" $result
  else
    #echo 'N'>>$result
    sed  -i "/sblk主存储类型/s/template/N/g" $result
  fi
  #echo $sblk_storage_num",">>$result
}

# 10 NFS主存储类型
# zstack-cli QueryPrimaryStorage type=LocalStorage count=true | grep -oE '[0-9]+'
function QueryNfsStorageType(){
  nfs_storage_num=$(zstack-cli QueryPrimaryStorage type=NFS count=true | grep -oE '[0-9]+')
  if [ $nfs_storage_num -gt 0 ];then
    #echo 'Y'>>$result
    sed  -i "/NFS主存储类型/s/template/Y/g" $result
  else
    #echo 'N'>>$result
    sed  -i "/NFS主存储类型/s/template/N/g" $result
  fi
  #echo $nfs_storage_num",">>$result
}

# 11 Ceph主存储类型
# zstack-cli QueryPrimaryStorage type=LocalStorage count=true | grep -oE '[0-9]+'
function QueryCephStorageType(){
  ceph_storage_num=$(zstack-cli QueryPrimaryStorage type=Ceph count=true | grep -oE '[0-9]+')
  if [ $ceph_storage_num -gt 0 ];then
    #echo 'Y'>>$result;
    sed  -i "/Ceph主存储类型/s/template/Y/g" $result
  else
    #echo 'N'>>$result;
    sed  -i "/Ceph主存储类型/s/template/N/g" $result
  fi
  #echo $ceph_storage_num",">>$result
}

# 12 SMP主存储类型
# zstack-cli QueryPrimaryStorage type=LocalStorage count=true | grep -oE '[0-9]+'
function QuerySMPStorageType(){
  SMP_storage_num=$(zstack-cli QueryPrimaryStorage type=SharedMountPoint count=true | grep -oE '[0-9]+')
  if [ $SMP_storage_num -gt 0 ];then
    #echo 'Y'>>$result
    sed  -i "/smp主存储/s/template/Y/g" $result
  else
    #echo 'N'>>$result
    sed  -i "/smp主存储/s/template/N/g" $result
  fi
  #echo $SMP_storage_num",">>$result
}



# 13 一个集群有加载 单主存储（0）local+nfs(1)local+sblk(2)多local(3)多NFS(4)  QueryPrimaryStorage fields=type attachedClusterUuids=
function attachedClusterPS(){
	ps_categories=$($mysql_cmd "
	use zstack;
  SELECT
	(
	CASE
			pss
			WHEN '1' THEN
			'0'
			WHEN '2' THEN
			'0'
			WHEN '4' THEN
			'0'
			WHEN '8' THEN
			'0'
			WHEN '16' THEN
			'0'
			WHEN '3' THEN
			'1'
			WHEN '17' THEN
			'2'
			WHEN '5' THEN
			'3' ELSE '99'
		END
		) categories
	FROM
		(
		SELECT
			sum( ps_Type ) pss
		FROM
			(
			SELECT
				cv.uuid,
				cv.NAME,
				( CASE ps.type WHEN 'LocalStorage' THEN '1' WHEN 'NFS' THEN '2' WHEN 'SharedMountPoint' THEN '4' WHEN 'Ceph' THEN '8' WHEN 'SharedBlock' THEN '16' ELSE '99' END ) AS ps_Type
			FROM
				ClusterVO cv,
				PrimaryStorageClusterRefVO psv,
				PrimaryStorageVO ps
			WHERE
				cv.uuid = psv.clusterUuid
				AND ps.uuid = psv.primaryStorageUuid
				AND ps.type != 'VCenter'
			ORDER BY
				cv.uuid
			) t1
		GROUP BY
		t1.uuid
	) t2;
	quit" | grep -v categories | xargs | sed 's/ /;/g')
	#echo $ps_categories>>$result
  sed  -i "/一个集群有加载单主存储/s/template/$ps_categories/g" $result
}

# 14 镜像服务器类型 Ceph(1) imagestore(2) 混合（3）

function QueryBackupStorageType(){

	backup_storage_type=$(zstack-cli QueryBackupStorage type!=VCenter fields=type | grep type | awk -F '"' '{print $4}' | sort | uniq )
	if [ "$backup_storage_type" == "Ceph" ];then
		#echo '1'>>$result
    sed  -i "/镜像服务器类型Ceph/s/template/1/g" $result
	elif [ "$backup_storage_type" == "ImageStoreBackupStorage" ];then
		#echo '2'>>$result
    sed  -i "/镜像服务器类型Ceph/s/template/2/g" $result
	else
		#echo '3'>>$result
    sed  -i "/镜像服务器类型Ceph/s/template/3/g" $result
	fi
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
  sed  -i "/主存储总物理容量/s/template/$ps_info_1/g" $result
# 16 主存储已用物理容量百分比(0.00)
	#echo $(echo $ps_info | awk '{print $2}')>>$result
	ps_info_2=$(echo $ps_info | awk '{print $2}')
  sed  -i "/主存储已用物理容量百分比/s/template/$ps_info_2/g" $result
# 15-1 主存储总容量(GB)
	#echo $(echo $ps_info | awk '{print $3}')>>$result
	ps_info_3=$(echo $ps_info | awk '{print $3}')
  sed  -i "/主存储总容量/s/template/$ps_info_3/g" $result
# 16 主存储已用容量百分比(0.00)
	#echo $(echo $ps_info | awk '{print $4}')>>$result
	ps_info_4=$(echo $ps_info | awk '{print $4}')
  sed  -i "/主存储已用容量百分比/s/template/$ps_info_4/g" $result
}

function QueryBackupStorageInfo(){
  bs_info=$($mysql_cmd "
  use zstack;
  SELECT
	SUM( ROUND( bs.totalCapacity / 1024 / 1024 / 1024 ) ) AS totalCap,
	SUM( ROUND( ( bs.totalCapacity - bs.availableCapacity ) / bs.totalCapacity, 2 ) ) AS usedPer
FROM
	BackupStorageVO bs
WHERE
	bs.type != 'VCenter'
	AND bs.uuid NOT IN ( SELECT resourceUuid FROM SystemTagVO WHERE tag = 'onlybackup' );
  quit" | grep -v 'usedPer')

# 17 备份存储总容量(GB)
	#echo $(echo $bs_info | awk '{print $1}')>>$result
	bs_info_1=$(echo $bs_info | awk '{print $1}')
  sed  -i "/备份存储总容量/s/template/$bs_info_1/g" $result
# 18 备份存储  已用190307(0.00)
	#echo $(echo $bs_info | awk '{print $2}')>>$result
	bs_info_2=$(echo $bs_info | awk '{print $2}')
  sed  -i "/备份存储可用容量百分比/s/template/$bs_info_2/g" $result
}

# 19 区域数量
function QueryZoneNum(){
	zone_num=$(zstack-cli QueryZone count=true  | grep total | sed '1,$s/\,//g' | sed '1,$s/ //g' | awk -F ':' '{print $2}')
	#echo $zone_num>>$result
  sed  -i "/区域数量/s/template/$zone_num/g" $result
	}


# 20 集群数量
function QueryClusterNum(){
	cluster_num=$(zstack-cli QueryCluster type=zstack count=true  | grep total | sed '1,$s/\,//g' | sed '1,$s/ //g' | awk -F ':' '{print $2}')
	#echo $cluster_num>>$result
  sed  -i "/集群数量/s/template/$cluster_num/g" $result
	}


function QueryL3NetworkType(){

# 21 扁平网络数量
	flat_num=$(zstack-cli QueryL3Network system=false category=Private count=true type!=L3VpcNetwork | grep total | awk '{print $2}')
	#echo $flat_num>>$result
  sed  -i "/扁平网络数量/s/template/$flat_num/g" $result


# 22 云路由网络
	vr_net=$(zstack-cli QueryVirtualRouterVm applianceVmType?=vrouter,VirtualRouter count=true status=Connected | grep total | awk '{print $2}')
  #echo "$vr_net">>$result
  sed  -i "/云路由网络/s/template/$vr_net/g" $result
# 23 VPC网络
	vpc_net=$(zstack-cli QueryL3Network l2Network.cluster.type!=vmware type=L3VpcNetwork count=true | grep total | awk '{print $2}')
  sed  -i "/VPC网络/s/template/$vpc_net/g" $result
  #echo "$vpc_net">>$result
# 24 混合网络（0/1）
	if [[ $flat_num -gt 0 ]] && [[ $vr_net -gt 0 ]];then
  sed  -i "/混合网络/s/template/Y/g" $result
	        #echo "Y">>$result
	elif [[ $flat_num -gt 0 ]] && [[ $vpc_net -gt 0 ]];then
  sed  -i "/混合网络/s/template/Y/g" $result
	        #echo "Y">>$result
	elif [[ $vr_net -gt 0 ]] && [[ $vpc_net -gt 0 ]];then
  sed  -i "/混合网络/s/template/Y/g" $result
	        #echo "Y">>$result
	else
  sed  -i "/混合网络/s/template/N/g" $result
        	#echo "N">>$result
	fi

}


# 25 负载均衡器数量
function QueryLoadBalancerNum(){
	lb_num=$(zstack-cli QueryLoadBalancer count=true | grep total | awk '{print $2}')
  sed  -i "/负载均衡器数量/s/template/$lb_num/g" $result
	#echo $lb_num>>$result
	}
# 26 监听器数量

function QueryLoadBalancerListenerNum(){
	lbListener_num=$(zstack-cli QueryLoadBalancerListener count=true | grep total | awk '{print $2}')
  sed  -i "/监听器数量/s/template/$lbListener_num/g" $result
	#echo $lbListener_num>>$result
	}

# 27 是否使用IPv6
function QueryL3NetworkIPV6(){
	ipv6_count=$(zstack-cli QueryL3Network ipVersion=6 count=true | grep -oE '[0-9]+')
	if [ $ipv6_count -gt 0 ];then
    sed  -i "/是否使用IPv6/s/template/Y/g" $result
		#echo 'Y'>>$result
	else
    sed  -i "/是否使用IPv6/s/template/N/g" $result
		#echo 'N'>>$result
	fi
}

# 28 EIP数量
function QueryEipNum(){
	EIP_num=$(zstack-cli QueryEip count=true | grep total | awk '{print $2}')
  sed  -i "/EIP数量/s/template/$EIP_num/g" $result
	#echo $EIP_num>>$result
}
# 29 VIP数量
function QueryVipNum(){
        VIP_num=$(zstack-cli QueryVip count=true | grep total | awk '{print $2}')
        sed  -i "/VIP数量/s/template/$VIP_num/g" $result
        #echo $VIP_num>>$result
}

# 30 安全组数量
function QuerySecurityGroupNum(){
        SCG_num=$(zstack-cli QuerySecurityGroup count=true | grep total | awk '{print $2}')
        sed  -i "/安全组数量/s/template/$SCG_num/g" $result
        #echo $SCG_num>>$result
}

# 31 端口转发数量
function QueryPortForwardingRuleNum(){
        PF_num=$(zstack-cli QueryPortForwardingRule count=true | grep total | awk '{print $2}')
        sed  -i "/端口转发数量/s/template/$PF_num/g" $result
        #echo $PF_num>>$result
}


# 32 报警资源类型
function QueryAlarmType(){
	al_type=$(zstack-cli QueryAlarm fields=namespace | grep namespace | awk -F '"' '{print $4}' | awk -F '/' '{print $2}' | sort | uniq | xargs | sed '1,$s/ /;/g')
  sed  -i "/报警资源类型/s/template/$al_type/g" $result
	#echo $al_type>>$result
}

# 33 账户个数
function QueryAccountNum(){
	account_num=$(zstack-cli QueryAccount count=true | grep total | awk '{print $2}')
  sed  -i "/账户个数/s/template/$account_num/g" $result
	#echo $account_num>>$result
}

# 34 ldap绑定账户数量
function QueryLdapServerNum(){
	ldap_server_num=$(zstack-cli QueryLdapServer count=true | grep total | awk '{print $2}')
  if [ "$ldap_server_num" -gt 0 ];then
    sed  -i "/ldap绑定账户数量/s/template/1/g" $result
		#echo '1'>>$result
	else
    sed  -i "/ldap绑定账户数量/s/template/0/g" $result
		#echo '0'>>$result
	fi
}
# 35 numa是否开启
function IfOpneNuma(){
	zstack-cli QueryGlobalConfig name=numa fields=value | grep value | grep true >/dev/null 2>&1
	if [ $? -eq 0 ];then
		#echo 'Y'>>$result
    sed  -i "/numa是否开启/s/template/Y/g" $result
  else
    #echo 'N'>>$result
    sed  -i "/numa是否开启/s/template/N/g" $result
	fi
}
# 36 云主机数量
function QueryVmInstanceNum(){
	vm_num=$(zstack-cli QueryVmInstance count=true | grep total | awk '{print $2}')
  sed  -i "/云主机数量/s/template/$vm_num/g" $result
	#echo $vm_num>>$result
	}
# 37 云主机设置高可用数量
function GetVmInstanceHaLevelNum(){
  nev_count=$($mysql_cmd "
  use zstack;
  SELECT
	COUNT( * ) AS nev_count
FROM
	SystemTagVO st,
	VmInstanceVO vm
WHERE
	st.resourceUuid = vm.uuid
	AND vm.hypervisorType = 'KVM'
	AND tag = 'ha::NeverStop';
  quit" | grep -v nev_count)
  #echo $nev_count>>$result
  sed  -i "/云主机设置高可用数量/s/template/$nev_count/g" $result
	}

function QueryVolumeInfo(){
	vol_num=$(zstack-cli QueryVolume type=Data count=true | grep -oE '[0-9]+')
	if [ $vol_num -gt 0 ];then
		vol_info=$(zstack-cli QueryVolume fields=size type=Data| grep -oE [0-9]+ |awk '{sum+=$1}END{print NR,sum/(1024*1024*1024),sum/(1024*1024*1024)/NR}')
		vol_num=$(echo $vol_info | awk '{print $1}')
		vol_avg_size=$(echo $vol_info | awk '{print $3}')
	else
		vol_avg_size=0
	fi
# 38 云盘数量
  sed  -i "/云硬盘数量/s/template/$vol_num/g" $result
	#echo $vol_num>>$result
# 39 云盘平均容量(GB)
	#echo $vol_avg_size>>$result
  sed  -i "/云盘平均容量/s/template/$vol_avg_size/g" $result
	}
function QueryVmInHost(){
	vm_count=$($mysql_cmd "
	use zstack;
  SELECT
	IFNULL( min( vm_count ), 0 ),
	IFNULL( max( vm_count ), 0 ),
	IFNULL( round( avg( vm_count ), 2 ), 0 )
FROM
	(
SELECT
	t.hostUuid AS HUUID,
	count( t.uuid ) AS vm_count
FROM
	VmInstanceVO t
WHERE
	t.hostUuid IS NOT NULL
	AND t.state = 'Running'
GROUP BY
	t.hostUuid
	) AS t1;
	quit" -N
	)
	vm_min_count=$(echo $vm_count | awk '{print $1}')
	vm_max_count=$(echo $vm_count | awk '{print $2}')
	vm_avg_count=$(echo $vm_count | awk '{print $3}')
# 40 物理机上最少虚拟机数量
	#echo $vm_min_count>>$result
  sed  -i "/物理机上最少虚拟机数量/s/template/$vm_min_count/g" $result
# 41 物理机上最多虚拟机数量
	#echo $vm_max_count>>$result
  sed  -i "/物理机上最多虚拟机数量/s/template/$vm_max_count/g" $result
# 42 物理机上平均虚拟机数量
	#echo $vm_avg_count>>$result
  sed  -i "/物理机上平均虚拟机数量/s/template/$vm_avg_count/g" $result
}
# 43 共享云盘数量
function QueryVolumeSharedInfo(){
#	#vol_uuids=$(zstack-cli QueryVolume fields=uuid | grep uuid | awk -F '"' '{print $4}')
#	#count=0
#	#shareable_vol_size=0
#	for uuid in $vol_uuids
#	do
#	# Shareable Volume type.
#	    shareable_tag=$(zstack-cli QueryVolume uuid=$uuid | egrep 'isShareable|size' | awk '{if(NR%3==0){printf $0 "\n"}else{printf "%s",$0}}' | grep true)
#	    if [ "$shareable_tag" ]
#	    then
#	        vol_size=$(echo $shareable_tag | grep -oE [0-9]+ | awk '{print $0/(1024*1024*1024)}' | awk -F '.' '{print $1}')
#	        count=$(($count+1))
#	        shareable_vol_size=$(($vol_size+$shareable_vol_size))
#	    fi
#	done
	count=$(zstack-cli QueryVolume type=Data isShareable=true count=true | grep -oE [0-9]+)
  sed  -i "/共享云盘数量/s/template/$count/g" $result
	#echo $count>>$result
	}
# 44 iscsi云盘数量
function QueryVolumeISCSIVolinfo(){
  sum_scsi_vol=$($mysql_cmd "
  use zstack;
  SELECT
	COUNT( * ) AS sum_scsi_vol
FROM
	VolumeVO vo,
	SystemTagVO st
WHERE
	vo.uuid = st.resourceUuid
	AND vo.type = 'Data'
	AND vo.format != 'vmtx'
	AND st.tag = 'capability::virtio-scsi';
  quit" |grep -v sum_scsi_vol)
  #echo $sum_scsi_vol>>$result
  sed  -i "/iscsi云云盘数量/s/template/$sum_scsi_vol/g" $result
	}
# 45 AddOn lic
function chkAddonLics(){
  licInfo=$(zstack-cli GetLicenseAddOns | egrep 'expiredDate|service-7x24|project-management|disaster-recovery|baremetal|arm64|vmware|v2v' | sed 's/ //g' | xargs -n2 | awk -F ':|T| |,' '{print $NF,$2}' | grep -v '^ ' | sed 's/ /,/g')
  for i in $licInfo;do
    licName=$(echo $i | awk -F ',' '{print $1}')
    expiredDate=$(echo $i | awk -F ',' '{print $2}')
    avaliableTime=$(($(date +%s -d "${expiredDate}")-$(date +%s)))
    avaliableDays=$(echo $avaliableTime | awk '{print $1/86400}')
    echo $licName" "$avaliableDays | awk '{if($2>90)print $1":1";else print $1":0"}'
  done
}

function chkAddon(){
  chkAddonLic=$(chkAddonLics)
  ifService724=$(echo $chkAddonLic | sed 's/ /\n/g' | grep 'service-7x24' | awk -F ':' '{print $2}')
  ifProjectManagement=$(echo $chkAddonLic | sed 's/ /\n/g' | grep 'project-management' | awk -F ':' '{print $2}')
  ifDisasterRecovery=$(echo $chkAddonLic | sed 's/ /\n/g' | grep 'disaster-recovery' | awk -F ':' '{print $2}')
  ifBaremetal=$(echo $chkAddonLic | sed 's/ /\n/g' | grep 'baremetal' | awk -F ':' '{print $2}')
  ifArm64=$(echo $chkAddonLic | sed 's/ /\n/g' | grep 'arm64' | awk -F ':' '{print $2}')
  ifVmware=$(echo $chkAddonLic | sed 's/ /\n/g' | grep 'vmware' | awk -F ':' '{print $2}')
  ifV2v=$(echo $chkAddonLic | sed 's/ /\n/g' | grep 'v2v' | awk -F ':' '{print $2}')

  if [ $ifVmware ];then
  	usedVC=$($mysql_cmd " use zstack;SELECT CASE WHEN COUNT(*) > 0 THEN '1' ELSE '0' END FROM VCenterVO;" -N)
  	ifVmware_usedVC="$ifVmware:$usedVC"
    sed  -i "/vCenter模块/s/template/$ifVmware_usedVC/g" $result
  else
  	#echo '-1:0'>>$result
    sed  -i "/vCenter模块/s/template/-1:0/g" $result
  fi

  if [ $ifProjectManagement ];then
    usedPM=$($mysql_cmd " use zstack;SELECT CASE WHEN COUNT(*) > 0 THEN '1' ELSE '0' END FROM IAM2ProjectVO;" -N)
    ifProjectManagement_usedPM="$ifProjectManagement:$usedPM"
    #echo "$ifProjectManagement:$usedPM">>$result
    sed  -i "/企业管理模块/s/template/$ifProjectManagement_usedPM/g" $result
  else
    #echo '-1:0'>>$result
    sed  -i "/企业管理模块/s/template/-1:0/g" $result
  fi

  if [ $ifDisasterRecovery ];then
    usedDR=$($mysql_cmd " use zstack;SELECT CASE WHEN COUNT(*) > 0 THEN '1' ELSE '0' END FROM SchedulerJobVO WHERE jobClassName in ('org.zstack.storage.backup.CreateVolumeBackupJob','org.zstack.storage.backup.CreateVmBackupJob','org.zstack.storage.backup.CreateDatabaseBackupJob');" -N)
    ifDisasterRecovery_usedDR="$ifDisasterRecovery:$usedDR"
    #echo "$ifDisasterRecovery:$usedDR">>$result
    sed  -i "/灾备模块/s/template/$ifDisasterRecovery_usedDR/g" $result
  else
    #echo '-1:0'>>$result
    sed  -i "/灾备模块/s/template/-1:0/g" $result
  fi

  if [ $ifV2v ];then
    usedV2V=$($mysql_cmd " use zstack;SELECT CASE WHEN COUNT(*) > 0 THEN '1' ELSE '0' END FROM V2VConversionHostVO;" -N)
    ifV2v_usedV2="$ifV2v:$usedV2V"
    #echo "$ifV2v:$usedV2V">>$result
    sed  -i "/v2v模块/s/template/$ifV2v_usedV2/g" $result
  else
    #echo '-1:0'>>$result
    sed  -i "/v2v模块/s/template/-1:0/g" $result
  fi

  if [ $ifBaremetal ];then
    usedBM=$($mysql_cmd " use zstack;SELECT CASE WHEN COUNT(*) > 0 THEN '1' ELSE '0' END FROM ClusterVO cv WHERE cv.type = 'baremetal';" -N)
    ifBaremetal_usedB="$ifBaremetal:$usedBM"
    #echo "$ifBaremetal:$usedBM">>$result
    sed  -i "/裸金属模块/s/template/$ifBaremetal_usedB/g" $result
  else
    #echo '-1:0'>>$result
    sed  -i "/裸金属模块/s/template/-1:0/g" $result
  fi

  if [ $ifArm64 ];then
    usedARM=$($mysql_cmd " use zstack;SELECT CASE WHEN COUNT(*) > 0 THEN '1' ELSE '0' END FROM SystemTagVO WHERE resourceUuid IN (SELECT uuid FROM HostVO) AND tag = 'hostCpuModelName::aarch64';" -N)
    ifArm64_usedARM="$ifArm64:$usedARM"
    #echo "$ifArm64:$usedARM">>$result
    sed  -i "/ARM模块/s/template/$ifArm64_usedARM/g" $result
  else
    #echo '-1:0'>>$result
    sed  -i "/ARM模块/s/template/-1:0/g" $result
  fi

  if [ $ifService724 ];then
    ifService724_1="$ifService724:1"
    #echo "$ifService724:1">>$result
    sed  -i "/7X24/s/template/$ifService724_1/g" $result
  else
    #echo '-1:0'>>$result
    sed  -i "/7X24/s/template/-1:0/g" $result
  fi

}
# 46 接收端类型及个数，邮箱、钉钉、HTTP
function chkEndpoint(){
	endPoints=$($mysql_cmd " use zstack;SELECT CONCAT(type,':',COUNT(*)) FROM SNSApplicationEndpointVO WHERE state = 'Enabled' AND ownerType IS NULL AND name != 'system-alarm-endpoint' GROUP BY type;" -N)
	DingTalkNum=$(echo $endPoints | sed 's/ /\n/g' | grep DingTalk | awk -F ':' '{print $2}')
	EmailNum=$(echo $endPoints | sed 's/ /\n/g' | grep Email | awk -F ':' '{print $2}')
	HTTPNum=$(echo $endPoints | sed 's/ /\n/g' | grep HTTP | awk -F ':' '{print $2}')
	#echo $DingTalkNum | awk '{if($1>0)print $1;else print "0"}'>>$result
	var_DingTalkNum=`echo $DingTalkNum | awk '{if($1>0)print $1;else print "0"}'`
  sed  -i "/钉钉接收端个数/s/template/$var_DingTalkNum/g" $result
	#echo $EmailNum | awk '{if($1>0)print $1;else print "0"}'>>$result
	var_EmailNum=`echo $EmailNum | awk '{if($1>0)print $1;else print "0"}'`
  sed  -i "/邮件接收端个数/s/template/$var_EmailNum/g" $result
	#echo $HTTPNum | awk '{if($1>0)print $1;else print "0"}'>>$result
	var_HTTPNum=`echo $HTTPNum | awk '{if($1>0)print $1;else print "0"}'`
  sed  -i "/HTTP接收端个数/s/template/$var_HTTPNum/g" $result
}
# 47 需要0-250,250-500,500-1000,1000以上   各规格云盘的数量
function chkVolRange(){
volRange=$($mysql_cmd " use zstack;
	SELECT
		COUNT(CASE WHEN volSize <= 250 THEN volSize END) AS volL250,
		COUNT(CASE WHEN volSize > 250 AND volSize <= 500 THEN volSize END) AS volL500,
		COUNT(CASE WHEN volSize > 500 AND volSize <= 1000 THEN volSize END) AS volL100,
		COUNT(CASE WHEN volSize > 1000 THEN volSize END) AS volG1000
	FROM
		(SELECT ROUND(vv.size/1024/1024/1024) AS volSize FROM VolumeVO vv WHERE type = 'Data' AND status = 'Ready' AND format IN('qcow2','raw')) t;" -N)
	#echo $volRange | sed 's/ /:/g'>>$result
	vol_Range=`echo $volRange | sed 's/ /:/g'`
  sed  -i "/云盘范围区间/s/template/$vol_Range/g" $result
}
# 48 共享云盘使用查询
function chkShareableVol(){
	shareAbleVols=$($mysql_cmd " use zstack;SELECT t1.VolName ,vv.name  FROM VmInstanceVO vv,
	(SELECT CONCAT(vv.name,'、',ROUND(vv.size/1024/1024/1024),'GB') AS 'VolName',svr.vmInstanceUuid FROM VolumeVO vv LEFT JOIN ShareableVolumeVmInstanceRefVO svr ON vv.uuid = svr.volumeUuid WHERE vv.isShareable = '1') t1
	WHERE vv.uuid = t1.vmInstanceUuid;" -N | awk '{seq[$1]=seq[$1]("、"$2)}END{for(i in seq)print i""seq[i]}')

	#echo $shareAbleVols | sed 's/ /;/g'>>$result
	shareAble_Vols=`echo $shareAbleVols | sed 's/ /;/g'`
  sed  -i "/共享云盘使用情况/s/template/$shareAble_Vols/g" $result
}
GetLicenseType
GetZstackVersion
QueryIfFuse
QueryIfAlone
IfInstallZSHA2
QueryHostNum
QueryLocalStorageType
QuerySblkStorageType
QueryNfsStorageType
QueryCephStorageType
QuerySMPStorageType
attachedClusterPS
QueryBackupStorageType
QueryPrimaryStorageInfo
QueryBackupStorageInfo
QueryZoneNum
QueryClusterNum
QueryL3NetworkType
QueryLoadBalancerNum
QueryLoadBalancerListenerNum
QueryL3NetworkIPV6
QueryEipNum
QueryVipNum
QuerySecurityGroupNum
QueryPortForwardingRuleNum
QueryAlarmType
QueryAccountNum
QueryLdapServerNum
IfOpneNuma
QueryVmInstanceNum
GetVmInstanceHaLevelNum
QueryVolumeInfo
QueryVmInHost
QueryVolumeSharedInfo
QueryVolumeISCSIVolinfo
chkAddon
chkEndpoint
chkVolRange
chkShareableVol
