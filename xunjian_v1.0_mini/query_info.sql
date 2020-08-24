#!/bin/bash
. ./.env
# Add zs_overview. Use zstack-cli.

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

echo '############################USB设备检查############################'
$mysql_cmd "
use zstack;
SELECT hv.managementIp,ud.name,ud.iManufacturer,ud.iProduct,ud.iSerial,ud.usbVersion,ud.state,ud.vmInstanceUuid
FROM HostVO hv,UsbDeviceVO ud
WHERE hv.hypervisorType='KVM'
AND hv.uuid=ud.hostUuid
AND ud.iManufacturer <> 'QEMU';
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

echo '############################云主机镜像名称############################'
$mysql_cmd "
use zstack;
SELECT vv.name AS vmName,vv.platform,iv.name AS imageNmae
FROM VmInstanceVO vv,ImageVO iv
WHERE vv.imageUuid = iv.uuid
ORDER BY vv.platform,iv.name;
quit"

echo '############################全局设置自定义内容############################'
$mysql_cmd "
use zstack;
	select name,category,defaultValue,value from GlobalConfigVO where value!=defaultValue;
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
