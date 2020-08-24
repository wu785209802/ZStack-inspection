#!/bin/bash
. ./.env
# Add zs_overview. Use zstack-cli.
function zs_version(){
  # 版本及运行状态
  zstack_status=$(zstack-ctl status | grep status | awk  '{print $3}' | uniq |sed -r 's:\x1B\[[0-9;]*[mK]::g')
  zstack_version=$(zstack-ctl status | grep version)
  os_version=$(cat /etc/redhat-release && uname -r)
  echo "ZStack版本：${zstack_version}"
  echo "管理节点OS版本：${os_version}" | xargs
  if [ "$zstack_status" == "Running" ];then
    echo "ZStack服务运行中，状态为：${zstack_status}"
  else
    echo "ZStack服务未运行，状态为：${zstack_status}"
  fi
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
}
function zs_overview(){
  IPAvailableCapacity=$(zstack-cli GetIpAddressCapacity all=true | grep availableCapacity | grep -oE [0-9]+)
  IPTotalCapacity=$(zstack-cli GetIpAddressCapacity all=true | grep totalCapacity | grep -oE [0-9]+)
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


  echo "物理机数量:${hostTotal}"
  echo "云主机数量:${vmTotal}"
  echo "运行中云主机数量:${vmRunningTotal}"
  echo "主存储数量:${psTotal}"
  echo "镜像服务器数量:${bsTotal}"
  echo "IP地址总量:${IPTotalCapacity}"
  echo "可用IP地址量:${IPAvailableCapacity}"
}
#zs_version
zs_overview

function os_version(){
echo '############################集群物理机系统版本############################'
$mysql_cmd "
use zstack;
SELECT
  CVO.name AS '集群名称',
	HVO.managementIp AS '物理机IP',
	CASE STVO.tag
	WHEN 'os::version::7.6.1810' THEN
		'centos7.6'
	WHEN 'os::version::7.4.1708' THEN
		'centos7.4'
	WHEN 'os::version::7.2.1511' THEN
    'centos7.2'
	ELSE
		'Important，不匹配的OS版本'
END AS 系统版本

FROM
	SystemTagVO STVO,
	HostVO HVO,
	ClusterVO CVO
	WHERE STVO.tag LIKE '%os::version::%'
	AND STVO.resourceUuid=HVO.uuid
	AND HVO.clusterUuid=CVO.uuid
	ORDER BY CVO.name;
  quit"
}
#
# execute sql stat

# 2019-05-31
	vmVol_info=$($mysql_cmd "
	use zstack;
	SELECT ROUND(SUM(vv.size/1024/1024/1024)) AS 'volCap(GB)'
	FROM VolumeVO vv
	WHERE vv.type = 'Root'
	AND vv.format != 'vmtx';
	quit"  | grep -v volCap)
	echo "云主机系统盘容量总和(GB):$vmVol_info"
	dataVol_info=$($mysql_cmd "
	use zstack;
	SELECT COUNT(*) AS volNum, ROUND(SUM(vv.size/1024/1024/1024)) AS 'volCap(GB)'
	FROM VolumeVO vv
	WHERE vv.type = 'Data'
	AND vv.format != 'vmtx';
	quit"  | grep -v volNum)
	echo "数据云盘数量:"$(echo $dataVol_info | awk '{print $1}')
	echo "数据云盘总容量(GB):"$(echo $dataVol_info | awk '{print $2}')
# 2019-05-31

echo '############################集群阈值设置############################'
$mysql_cmd "
use zstack;
SELECT cs.name,cs.uuid,
CASE
WHEN rc.name = 'reservedMemory' THEN '保留内存'
WHEN rc.name = 'cpu.overProvisioning.ratio' THEN 'CPU超分率'
WHEN rc.name = 'overProvisioning.memory' THEN '内存超分率'
ELSE ''
END AS 'configName',rc.category,REPLACE(gv.defaultValue,'G','') AS defaultValue,REPLACE(rc.value,'G','') AS value,
CASE
  WHEN rc.category = 'mevoco' AND rc.name = 'overProvisioning.memory' AND rc.value > 1.5 THEN 'Urgent：集群内存超分率过高！'
  WHEN rc.category = 'mevoco' AND rc.name = 'overProvisioning.memory' AND rc.value > 1.2 THEN 'Important：集群内存超分率过高！'
  WHEN rc.category = 'mevoco' AND rc.name = 'overProvisioning.memory' AND rc.value > 1 THEN 'Warninig：集群内存超分率过高！'
  WHEN rc.category = 'host' AND rc.name = 'cpu.overProvisioning.ratio' AND rc.value > 11 THEN 'Important：集群CPU超分率过高！'
  WHEN rc.category = 'host' AND rc.name = 'cpu.overProvisioning.ratio' AND rc.value > 5 THEN 'Warninig：集群CPU超分率过高！'
  WHEN rc.category = 'kvm' AND rc.name = 'reservedMemory' AND rc.value < 1 THEN 'Important：集群内存保留设置过低！'
  WHEN rc.category = 'kvm' AND rc.name = 'reservedMemory' AND rc.value < 16 THEN 'Warninig：集群内存保留设置过低！'
  ELSE	'' END AS 'COMMENT'
FROM ClusterVO cs,ResourceConfigVO rc,GlobalConfigVO gv
WHERE cs.uuid = rc.resourceUuid
AND rc.category = gv.category
AND rc.name = gv.name;
quit"

echo '############################运行中的云主机概览############################'
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

echo '############################暂停中的云主机概览############################'
$mysql_cmd "
use zstack;
SELECT
	t.NAME,
	t.uuid,
	t.hostUuid,
CASE
		t.state
		WHEN 'Paused' THEN
		'Urgent，存在暂停的云主机'
	ELSE ''
	END AS 'comment'
FROM
	VmInstanceVO t
WHERE
	t.state = 'Paused';
quit"

echo '############################主存储概览############################'
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
			WHEN (t3.totalPhysicalCapacity - t3.availablePhysicalCapacity)/t3.totalPhysicalCapacity > 0.65 THEN 'Important：主存储已用物理容量超过65%，请尽快扩容'
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
echo '############################主存储保留容量############################'
$mysql_cmd "
use zstack;
	SELECT name,category,defaultValue,value,
	 CASE
		WHEN UPPER(SUBSTR(value,(LENGTH(value)),LENGTH(value))) LIKE 'G'
			THEN (CASE WHEN SUBSTR(value,1,(LENGTH(value)-1))*1 < 200 THEN 'Important：主存储保留容量过低，建议设置200GB及以上' ELSE '' END)
		WHEN UPPER(SUBSTR(value,(LENGTH(value)),LENGTH(value))) LIKE 'M'
			THEN (CASE WHEN SUBSTR(value,1,(LENGTH(value)-1))/1024 < 200 THEN 'Important：主存储保留容量过低，建议设置200GB及以上' ELSE '' END)
		WHEN UPPER(SUBSTR(value,(LENGTH(value)),LENGTH(value))) LIKE 'K'
			THEN (CASE WHEN SUBSTR(value,1,(LENGTH(value)-1))/1024/1024 < 200 THEN 'Important：主存储保留容量过低，建议设置200GB及以上' ELSE '' END)
		WHEN UPPER(SUBSTR(value,(LENGTH(value)),LENGTH(value))) LIKE 'B'
			THEN (CASE WHEN SUBSTR(value,1,(LENGTH(value)-1))/1024/1024/1024 < 200 THEN 'Important：主存储保留容量过低，建议设置200GB及以上' ELSE '' END)
		WHEN UPPER(SUBSTR(value,(LENGTH(value)),LENGTH(value))) LIKE 'T'
			THEN (CASE WHEN SUBSTR(value,1,(LENGTH(value)-1))*1024 < 200 THEN 'Important：主存储保留容量过低，建议设置200GB及以上' ELSE '' END)
		ELSE 'NULL'
		END AS 'comment'
	FROM GlobalConfigVO WHERE name ='reservedCapacity' AND category = 'primaryStorage';
quit"
echo '############################主存储阈值设置############################'
$mysql_cmd "
use zstack;
	SELECT name,category,defaultValue,value,
		CASE
		WHEN value > 0.9 THEN 'Important：主存储使用阈值设置过大，建议设置小于等于0.9'
		ELSE ''
	END AS 'comment'

	FROM GlobalConfigVO
	WHERE name = 'Threshold.primaryStorage.physicalCapacity';
quit"

echo '############################镜像服务器概览############################'
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

os_version

echo '###########################灾备信息查询############################'
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

echo '############################灾备服务器概览############################'
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
		WHEN 1 - bs.availableCapacity / bs.totalCapacity >= 0.9 THEN	'Urgent：备份镜像服务器使用率过高！'
		WHEN 1 - bs.availableCapacity / bs.totalCapacity > 0.7 AND 1 - bs.availableCapacity / bs.totalCapacity <= 0.8 THEN	'Important：备份镜像服务器使用率过高！'
		WHEN 1 - bs.availableCapacity / bs.totalCapacity > 0.6 AND 1 - bs.availableCapacity / bs.totalCapacity <= 0.7 THEN	'Warning：备份镜像服务器使用率过高！'
		ELSE ''
END AS 'COMMENT'
FROM
	BackupStorageVO bs,
	SystemTagVO st
WHERE
	bs.uuid = st.resourceUuid
	AND st.tag IN ( 'allowbackup', 'onlybackup', 'remotebackup' );
quit"
echo '############################灾备任务概览############################'
$mysql_cmd "
use zstack;
SELECT
t.name AS '任务名称',
t.schedulerJobGroupUuid AS '任务uuid',
t.startTime AS '执行时间',
t.success AS '上次执行结果',
CASE t.success
	WHEN 0 THEN
		'Urgent，最后一次灾备任务执行失败，请检查'
	ELSE
		''
END AS 'comment'
 FROM (SELECT sh.schedulerJobGroupUuid,sv.name,MAX(sh.startTime) AS 'startTime',
SUBSTR(MAX(CONCAT(sh.startTime,':',sh.success)),LENGTH(MAX(CONCAT(sh.startTime,':',sh.success)))) AS 'success'
FROM SchedulerJobHistoryVO sh,SchedulerJobGroupVO sv WHERE sh.schedulerJobGroupUuid = sv.uuid GROUP BY sh.schedulerJobGroupUuid)t;
quit" 2>/dev/null

echo '############################管理节点消息队列查询############################'
$mysql_cmd "
use zstack;
SELECT
	COUNT( * ) AS queueNum,
CASE
		WHEN COUNT( * ) > 100 THEN
		'Important：管理节点消息队列超过100 ' ELSE ''
END AS COMMENT
FROM
	JobQueueVO;
quit"

echo '############################物理机上的虚拟机虚拟机规格############################'
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
echo '############################物理机上云主机的数量 和使用的虚拟CPU数量总和############################'
$mysql_cmd "
use zstack;
#  SELECT
#    t3.name AS clusterName,
#    t2. NAME AS HostName,
#    t2.managementIp AS HostIP,
#    count(t1.uuid) AS VmNumber,
#    SUM(t1.cpuNum) AS 'CpuTotalNum',
#    CASE
#      WHEN count(t1.uuid) >=20 THEN 'Warning：该物理机上的云主机数量超过20个'
#    ELSE ''
#    END AS 'comment'
#  FROM
#    VmInstanceVO t1,
#    HostVO t2,
#    ClusterVO t3
#  WHERE t1.hostUuid = t2.uuid
#  AND t2.clusterUuid = t3.uuid
#  GROUP BY
#    t1.hostUuid,
#    t1.state
#  ORDER BY t3.name,t2.name;
#
SELECT
	t3.NAME AS clusterName,
	t2.NAME AS HostName,
	t2.managementIp AS HostIP,
	count( t1.uuid ) AS VmNumber,
	SUM( t1.cpuNum ) AS 'CpuTotalNum',
CASE

		WHEN count( t1.uuid ) >= 20 THEN
		'Warning：该物理机上的云主机数量超过20个' ELSE ''
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
#echo '############################全局设置############################'
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

quit" > ${LOG_PATH}/log/GlobalConfig.cfg 2>&1


echo '############################硬件设施-物理机############################'
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
echo '############################集群主存储类型及物理机数量############################'
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
echo '############################物理机保留内存检查############################'
$mysql_cmd "
use zstack;
		SELECT name,category,defaultValue,value,
		 CASE
						WHEN UPPER(SUBSTR(value,(LENGTH(value)),LENGTH(value))) LIKE 'G'
							THEN (CASE WHEN SUBSTR(value,1,(LENGTH(value)-1))*1 < 16 THEN 'Important：物理机保留内存过低' ELSE '' END)
						WHEN UPPER(SUBSTR(value,(LENGTH(value)),LENGTH(value))) LIKE 'M'
							THEN (CASE WHEN SUBSTR(value,1,(LENGTH(value)-1))/1024 < 16 THEN 'Important：物理机保留内存过低' ELSE '' END)
						WHEN UPPER(SUBSTR(value,(LENGTH(value)),LENGTH(value))) LIKE 'K'
							THEN (CASE WHEN SUBSTR(value,1,(LENGTH(value)-1))/1024/1024 < 16 THEN 'Important：物理机保留内存过低' ELSE '' END)
						WHEN UPPER(SUBSTR(value,(LENGTH(value)),LENGTH(value))) LIKE 'B'
							THEN (CASE WHEN SUBSTR(value,1,(LENGTH(value)-1))/1024/1024/1024 < 16 THEN 'Important：物理机保留内存过低' ELSE '' END)
						WHEN UPPER(SUBSTR(value,(LENGTH(value)),LENGTH(value))) LIKE 'T'
							THEN (CASE WHEN SUBSTR(value,1,(LENGTH(value)-1))*1024 < 16 THEN 'Important：物理机保留内存过低' ELSE '' END)
						ELSE 'NULL'
						END AS 'comment'

		FROM GlobalConfigVO WHERE name = 'ReservedMemory';
quit"
echo '############################物理机上CPU-内存 超线程后总量############################'
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
echo '############################迁移服务器############################'
$mysql_cmd "
use zstack;
SELECT
	*
FROM
	V2VConversionHostVO;
quit"
echo '############################迁移任务############################'
$mysql_cmd "
use zstack;
SELECT
	*
FROM
	V2VConversionCacheVO;
quit"
echo '############################裸金属设备############################'
$mysql_cmd "
use zstack;
SELECT
	*
FROM
	BaremetalChassisVO;
quit"
echo '############################裸金属主机############################'
$mysql_cmd "
use zstack;
SELECT
	*
FROM
	BaremetalInstanceVO;
quit"

echo '############################Lun透传检查############################'
$mysql_cmd "
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
quit"

echo '############################USB设备检查############################'
$mysql_cmd "
use zstack;
SELECT hv.managementIp,ud.name,ud.iManufacturer,ud.iProduct,ud.iSerial,ud.usbVersion,ud.state,ud.vmInstanceUuid
FROM HostVO hv,UsbDeviceVO ud
WHERE hv.hypervisorType='KVM'
AND hv.uuid=ud.hostUuid
AND ud.iManufacturer <> 'QEMU';
quit"

echo '############################GPU设备检查############################'
$mysql_cmd "
use zstack;
SELECT hv.managementIp,pd.* FROM PciDeviceVO pd,HostVO hv WHERE hv.uuid=pd.hostUuid AND hv.hypervisorType='KVM' AND pd.type LIKE '%GPU%';
SELECT * FROM FiberChannelStorageVO;
quit"

echo '############################云主机云盘及快照检查############################'
$mysql_cmd "
use zstack;
	SELECT t1.*,
		CASE
		WHEN t1.volumeSanpshotNum > 10 THEN 'Warning：云盘快照数量大于10个'
		ELSE
			''
	END AS 'Comment'

	FROM
		(SELECT
			t1.vmInstanceUuid,
			t3.type,
			t1.type AS 'volumeType',
			COUNT(DISTINCT t1.uuid) AS 'volumnNum',
			COUNT(t2.uuid) AS 'volumeSanpshotNum'
		FROM
			VolumeEO t1
		LEFT JOIN VolumeSnapshotEO t2 ON t1.uuid = t2.volumeUuid
		RIGHT JOIN PrimaryStorageVO t3 on t1.primaryStorageUuid=t3.uuid
		WHERE t1.vmInstanceUuid IS NOT NULL
		AND	t1.status='Ready'
		GROUP BY
			t1.vmInstanceUuid,
			t1.type
	) t1
	WHERE t1.volumeSanpshotNum > 0
	ORDER BY volumeSanpshotNum DESC;
quit"
echo '############################网络规划查询############################'
$mysql_cmd "
use zstack;
	SELECT
					ll2. NAME AS '二层网络名称',
					ll2.physicalInterface '网卡',
					ll2.vlan AS 'VLAN_ID',
					ll2.type AS '二层网络类型',
					l3. NAME AS '三层网络名称',
					l3.category AS '三层网络分类',
					l3.type AS '三层网络类型',
					ipr.startIp AS '起始IP',
					ipr.endIp AS '结束IP',
					ipr.networkCidr AS 'IP(CIDR)'
	FROM
					L3NetworkVO l3,
					IpRangeVO ipr,
					(
									SELECT
													l2.uuid,
													l2. NAME,
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

echo '############################加载网卡数量大于1的云主机查询############################'
$mysql_cmd "
use zstack;
SELECT
	COUNT( * ) AS '网卡数大于1的云主机数量'
FROM
	(
	SELECT
		COUNT( VNVO.vmInstanceUuid ) AS vmnic
	FROM
		VmInstanceVO VIVO,
		VmNicVO VNVO
	WHERE
		VNVO.vmInstanceUuid = VIVO.uuid
	GROUP BY
		VIVO.uuid
	HAVING
	vmnic > 1 ) t1;
  quit"

# echo '############################审计信息查询############################'
mysql -uzstack_ui -pzstack.ui.password -e "
use zstack_ui;
SELECT
	*
FROM
	event ent
WHERE
	ent.create_time > DATE_SUB(
		CURRENT_DATE (),
		INTERVAL 30 DAY
	)
ORDER BY
	ent.create_time DESC;
quit" > ${LOG_PATH}/log/audit_30day.log 2>&1
# 2019-05-31
echo '############################弹性IP查询############################'
# 均为已加载云主机的弹性IP信息
$mysql_cmd "
use zstack;
	SELECT CONCAT('扁平网络EIP个数 ',COUNT(ev.uuid)) AS EipInfo FROM EipVO ev,L3NetworkVO lv,VmNicVO vv
	WHERE ev.vmNicUuid = vv.uuid
	AND vv.l3NetworkUuid = lv.uuid
	AND lv.type = 'L3BasicNetwork'
	AND lv.category = 'Private'
	AND lv.uuid NOT IN (SELECT nv.l3NetworkUuid FROM NetworkServiceL3NetworkRefVO nv WHERE nv.networkServiceType = 'LoadBalancer')
	UNION
	SELECT CONCAT('EIP总数 ',COUNT(*)) FROM EipVO WHERE vmNicUuid IS NOT NULL;
quit"
# 2019-05-31
echo '############################云主机平台类型查询############################'
$mysql_cmd "
use zstack;
	SELECT vv.platform AS '云主机平台',COUNT(vv.uuid) AS '云主机个数'FROM VmInstanceVO vv
	WHERE vv.hypervisorType = 'KVM'
	GROUP BY vv.platform;
quit"
echo '############################NeverStop云主机资源占用查询############################'
$mysql_cmd "
use zstack;
        SELECT COUNT(vm.name) AS '高可用数量',SUM(vm.cpuNum) AS totalCPU,ROUND(SUM(memorySize/1024/1024/1024)) AS totalMem FROM SystemTagVO st,VmInstanceVO vm
        WHERE st.resourceUuid = vm.uuid
        AND vm.hypervisorType = 'KVM'
        AND tag='ha::NeverStop';
quit"

echo '############################云主机规格TOP10查询############################'
$mysql_cmd "
use zstack;
	SELECT vm.name,vm.uuid,vm.cpuNum,ROUND(vm.memorySize/1024/1024/1024) AS 'memSize(GB)'
	FROM VmInstanceVO vm
	WHERE vm.hypervisorType = 'KVM' AND vm.state = 'Running'
	ORDER BY vm.cpuNum DESC, vm.memorySize DESC
	LIMIT 10;

quit"

echo '############################云主机镜像名称############################'
$mysql_cmd "
use zstack;
SELECT vv.name AS vmName,vv.platform,iv.name AS imageNmae
FROM VmInstanceVO vv,ImageVO iv
WHERE vv.imageUuid = iv.uuid
ORDER BY vv.platform,iv.name;
quit"

echo '############################资源标签数查询############################'
$mysql_cmd "
use zstack;
	SELECT ut.resourceType,COUNT(*) AS tagCount
	FROM UserTagVO ut,TagPatternVO tv
	WHERE ut.tagPatternUuid = tv.uuid
	GROUP BY ut.resourceType;

quit"
echo '############################亲和组数量查询############################'
$mysql_cmd "
use zstack;
SELECT
	AGVO.NAME AS '亲和组名称',
	CASE
		WHEN AGVO.policy = 'ANTIHARD' THEN
		'强制' ELSE '非强制' END AS 'policy',
	VIVO.NAME AS '云主机名称',
	IOVO.cpuNum,
	ROUND(IOVO.memorySize / 1024 / 1024 / 1024) AS '内存'
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
quit"

echo '############################全局设置自定义内容############################'
$mysql_cmd "
use zstack;
	select name,category,defaultValue,value from GlobalConfigVO where value!=defaultValue;
quit"

echo '############################集群自定义设置############################'
$mysql_cmd "
use zstack;
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
quit"

echo '############################集群Prometheus设置############################'
$mysql_cmd "
use zstack;
SELECT
CASE name
	WHEN 'storage.local.retention.size' THEN '监控数据保留大小'
	WHEN 'storage.local.retention' THEN '监控数据保留周期'
END AS '名称',
defaultValue AS '默认值',
value AS '设置值'
FROM GlobalConfigVO WHERE category='Prometheus';
SELECT type,COUNT(type) AS '云主机类型' FROM VmInstanceVO GROUP BY type;
quit"

echo '############################安全组数量查询############################'
$mysql_cmd "
use zstack;
	SELECT COUNT(*) AS '安全组总数量' FROM SecurityGroupVO sv;
	SELECT sgr.vmInstanceUuid AS '云主机UUID',COUNT(sgr.vmInstanceUuid) AS '安全组数量'
	FROM VmNicSecurityGroupRefVO sgr
	GROUP BY sgr.vmNicUuid
	ORDER BY COUNT(sgr.vmInstanceUuid) DESC
	LIMIT 10;
quit"

echo '###########################网络服务统计############################'
$mysql_cmd "
use zstack;
SELECT COUNT(name) AS 'EIP数量' FROM EipVO;
SELECT COUNT(*) AS '端口转发' FROM (SELECT COUNT(name) FROM PortForwardingRuleVO GROUP BY name)t1;
SELECT COUNT(uuid) AS '负载均衡器' FROM LoadBalancerVO;
SELECT COUNT(uuid) AS 'IPSEC数量' FROM IPsecConnectionVO;
quit"


echo '###########################负载均衡器数量查询############################'
$mysql_cmd "
use zstack;
		SELECT COUNT(*) AS '负载均衡器总数量' FROM  LoadBalancerVO;

		SELECT lbv.loadBalancerUuid AS '负载均衡器UUID',COUNT(lbv.uuid) AS '监听器数量' FROM LoadBalancerListenerVO lbv
		GROUP BY lbv.loadBalancerUuid
		ORDER BY COUNT(lbv.uuid) DESC
		LIMIT 10;
quit"
echo '###########################路由器数量规格查询############################'
$mysql_cmd "
use zstack;
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

echo '###########################OSPF查询############################'
$mysql_cmd "
use zstack;
		SELECT CASE  ospfCount
  	WHEN 0 THEN '没有使用OSPF'
  	ELSE
    	'已使用OSPF'
		END AS 'OSPF使用情况'
 		FROM (SELECT COUNT(*) AS ospfCount FROM RouterAreaVO) t;
quit"

echo '############################已触发报警查询############################'
$mysql_cmd "
use zstack;
	SELECT av.name,av.metricName,av.comparisonOperator,av.threshold,av.namespace,av.state
	FROM AlarmVO av WHERE av.status = 'Alarm' ;
quit"


echo '############################镜像类型查询############################'
# 含云路由镜像，不含VCenter镜像
$mysql_cmd "
use zstack;
	SELECT iv.format,COUNT(*) AS 'ImageNum'
	FROM ImageVO iv
	WHERE iv.format != 'vmtx'
	GROUP BY iv.format;
quit"

echo '############################VCenter信息查询############################'
$mysql_cmd "
use zstack;
	SELECT COUNT(*) AS 'VCenter数量' FROM VCenterVO;
	SELECT ps.name,ps.type,ps.state,ps.status,
		ROUND(psc.totalCapacity/1024/1024/1024,4) AS 'totalCapacity(GB)',
		ROUND(psc.availableCapacity/1024/1024/1024,4) AS 'availableCapacity(GB)',
		ROUND(psc.totalPhysicalCapacity/1024/1024/1024,4) AS 'totalPhysicalCapacity(GB)',
		ROUND(psc.availablePhysicalCapacity/1024/1024/1024,4) AS 'availablePhysicalCapacity(GB)'
	FROM PrimaryStorageVO ps,PrimaryStorageCapacityVO psc
	WHERE ps.uuid = psc.uuid
	AND ps.type = 'VCenter';
	SELECT vm.zoneUuid,vm.clusterUuid,COUNT(vm.uuid) AS '云主机数量'
	FROM VmInstanceVO vm WHERE hypervisorType = 'ESX' GROUP BY vm.zoneUuid,vm.clusterUuid;
quit"

echo '############################混合云信息查询############################'
$mysql_cmd "
use zstack;
select * from DataCenterVO;
select * from IdentityZoneVO;
quit"


echo '############################计费单价查询############################'
$mysql_cmd "
use zstack;
	SELECT pv.resourceName,pv.timeUnit,pv.resourceUnit,pv.price FROM PriceVO pv;
quit"


echo '############################企业管理查询############################'
$mysql_cmd "
use zstack;
	SELECT COUNT(DISTINCT ipv.uuid) AS '项目数量',COUNT(DISTINCT ivid.uuid) AS '用户数量(含平台管理员)'
	FROM IAM2ProjectVO ipv,IAM2VirtualIDVO ivid;
quit"


echo '############################裸金属主机数量查询############################'
$mysql_cmd "
use zstack;
	SELECT COUNT(*) FROM BaremetalInstanceVO;
quit"



#echo '###########################邮箱接收端查询############################'
#$mysql_cmd "
#use zstack;
#	SELECT * FROM SNSEmailEndpointVO;
#quit"
#echo '###########################HTTP接收端查询############################'
#$mysql_cmd "
#use zstack;
#	SELECT * FROM SNSHttpEndpointVO;
#quit"
#echo '###########################钉钉接收端查询############################'
#$mysql_cmd "
#use zstack;
#	SELECT * FROM SNSDingTalkEndpointVO;
#quit"
#echo '###########################邮箱服务器查询############################'
#$mysql_cmd "
#use zstack;
#	SELECT COUNT(uuid)  AS '邮箱服务器个数' FROM EmailMediaVO;
#	SELECT COUNT(uuid) AS '邮箱接收端个数' FROM SNSEmailEndpointVO;
#	SELECT SUM(num) AS '接收端总数',
#		CASE
#			WHEN SUM(num) <= 0 THEN 'Important：未配置接收端，建议配置邮箱接收端、报警器，实时报告异常信息'
#		ELSE ''
#		END AS 'comment'
#	FROM
#		(SELECT COUNT(*) AS 'num' FROM SNSEmailEndpointVO UNION
#		SELECT COUNT(*) AS 'num' FROM SNSDingTalkEndpointVO UNION
#		SELECT COUNT(*) AS 'num' FROM SNSHttpEndpointVO WHERE url != 'http://localhost:5000/zwatch/webhook')t1;
#quit"
function endPointChk(){
    echo '############################接收端检查############################'
    $mysql_cmd "
    use zstack;
    SELECT name,CASE
    WHEN endPointNum = 0 AND name = 'Email' THEN 'Warning:未配置邮箱接收端！'
    ELSE endPointNum
    END AS 'endPointNum'
    FROM (SELECT 'DingTalk' AS 'name',COUNT(*) AS 'endPointNum' FROM SNSDingTalkEndpointVO UNION
    SELECT 'Http' AS 'name',COUNT(*) AS 'endPointNum' FROM SNSHttpEndpointVO UNION
    SELECT 'Email' AS 'name',COUNT(*) AS 'endPointNum' FROM SNSEmailEndpointVO) t1;
    quit"
}
endPointChk

echo '############################置备方式查询############################'
$mysql_cmd "
use zstack;
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
SELECT VolumeVO.name,ROUND(VolumeVO.size/1024/1024/1024) AS '云盘大小',CASE SystemTagVO.tag
	WHEN 'volumeProvisioningStrategy::ThinProvisioning' THEN '精简置备'
	WHEN 'volumeProvisioningStrategy::ThickProvisioning' THEN '厚置备'
END AS '置备方式'
 FROM SystemTagVO,VolumeVO WHERE VolumeVO.uuid = SystemTagVO.resourceUuid AND SystemTagVO.tag LIKE '%volumeProvisioningStrategy%';
quit"

echo '############################存储心跳网络查询############################'
$mysql_cmd "
use zstack;
	SELECT t2.*,
		CASE
			WHEN t2.type = 'SharedBlock' AND t2.heartBeatCidr IS NULL THEN 'Urgent：未设置存储心跳网络（若为存储为FCSAN，请忽略）'
			WHEN t2.type != 'LocalStorage' AND t2.heartBeatCidr IS NULL THEN 'Urgent：未设置存储心跳网络，请检查'
			ELSE ''
		END AS 'comment'
	FROM
		(SELECT ps.name,ps.type,ps.uuid,t1.tag,SUBSTR(t1.tag,32,LENGTH(tag)) AS 'heartBeatCidr'
		FROM PrimaryStorageVO ps
			LEFT OUTER JOIN
		(SELECT * FROM SystemTagVO st WHERE st.resourceType='PrimaryStorageVO'
			AND st.tag LIKE 'primaryStorage::gateway::cidr::%') t1
		ON ps.uuid = t1.resourceUuid) t2
		WHERE t2.type != 'VCenter'
	;
quit"


echo '############################迁移网络查询############################'
$mysql_cmd "
use zstack;
	SELECT t2.name,t2.uuid,t2.tag,
		CASE
		WHEN t2.tag IS NOT NULL THEN SUBSTR(t2.tag,34,LENGTH(t2.tag))
		ELSE ''
	END AS 'migrateCidr'
	FROM
		(SELECT * FROM ClusterVO cv
		LEFT OUTER JOIN
		(SELECT st.tag,st.resourceUuid
		FROM SystemTagVO st
		WHERE st.resourceType = 'ClusterVO'
		AND st.tag LIKE 'cluster::migrate::network::cidr::%') t1
		ON cv.uuid = t1.resourceUuid) t2
	WHERE t2.hypervisorType = 'KVM'
	;
quit"
