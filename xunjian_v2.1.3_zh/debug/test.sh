#!/bin/bash


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
  	echo "$ifVmware:$usedVC"

  else
  	echo '-1:0'
  fi

  if [ $ifProjectManagement ];then
    usedPM=$($mysql_cmd " use zstack;SELECT CASE WHEN COUNT(*) > 0 THEN '1' ELSE '0' END FROM IAM2ProjectVO;" -N)
    echo "$ifProjectManagement:$usedPM"
  else
    echo '-1:0'
  fi

  if [ $ifDisasterRecovery ];then
    usedDR=$($mysql_cmd " use zstack;SELECT CASE WHEN COUNT(*) > 0 THEN '1' ELSE '0' END FROM SchedulerJobVO WHERE jobClassName in ('org.zstack.storage.backup.CreateVolumeBackupJob','org.zstack.storage.backup.CreateVmBackupJob','org.zstack.storage.backup.CreateDatabaseBackupJob');" -N)
    echo "$ifDisasterRecovery:$usedDR"
  else
    echo '-1:0'
  fi

  if [ $ifV2v ];then
    usedV2V=$($mysql_cmd " use zstack;SELECT CASE WHEN COUNT(*) > 0 THEN '1' ELSE '0' END FROM V2VConversionHostVO;" -N)
    echo "$ifV2v:$usedV2V"
  else
    echo '-1:0'
  fi

  if [ $ifBaremetal ];then
    usedBM=$($mysql_cmd " use zstack;SELECT CASE WHEN COUNT(*) > 0 THEN '1' ELSE '0' END FROM ClusterVO cv WHERE cv.type = 'baremetal';" -N)
    echo "$ifBaremetal:$usedBM"
  else
    echo '-1:0'
  fi

  if [ $ifArm64 ];then
    usedARM=$($mysql_cmd " use zstack;SELECT CASE WHEN COUNT(*) > 0 THEN '1' ELSE '0' END FROM SystemTagVO WHERE resourceUuid IN (SELECT uuid FROM HostVO) AND tag = 'hostCpuModelName::aarch64';" -N)
    echo "$ifArm64:$usedARM"
  else
    echo '-1:0'
  fi

  if [ $ifService724 ];then
    echo "$ifService724:1"
  else
    echo '-1:0'
  fi

}
# 46 接收端类型及个数，邮箱、钉钉、HTTP
function chkEndpoint(){
	endPoints=$($mysql_cmd " use zstack;SELECT CONCAT(type,':',COUNT(*)) FROM SNSApplicationEndpointVO WHERE state = 'Enabled' AND ownerType IS NULL AND name != 'system-alarm-endpoint' GROUP BY type;" -N)
	DingTalkNum=$(echo $endPoints | sed 's/ /\n/g' | grep DingTalk | awk -F ':' '{print $2}')
	EmailNum=$(echo $endPoints | sed 's/ /\n/g' | grep Email | awk -F ':' '{print $2}')
	HTTPNum=$(echo $endPoints | sed 's/ /\n/g' | grep HTTP | awk -F ':' '{print $2}')
	echo $DingTalkNum | awk '{if($1>0)print $1;else print "0"}'
	echo $EmailNum | awk '{if($1>0)print $1;else print "0"}'
	echo $HTTPNum | awk '{if($1>0)print $1;else print "0"}'
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
	echo $volRange | sed 's/ /:/g'
}
# 48 共享云盘使用查询
function chkShareableVol(){
	shareAbleVols=$($mysql_cmd " use zstack;SELECT t1.VolName ,vv.name  FROM VmInstanceVO vv,
	(SELECT CONCAT(vv.name,'、',ROUND(vv.size/1024/1024/1024),'GB') AS 'VolName',svr.vmInstanceUuid FROM VolumeVO vv LEFT JOIN ShareableVolumeVmInstanceRefVO svr ON vv.uuid = svr.volumeUuid WHERE vv.isShareable = '1') t1
	WHERE vv.uuid = t1.vmInstanceUuid;" -N | awk '{seq[$1]=seq[$1]("、"$2)}END{for(i in seq)print i""seq[i]}')

	echo $shareAbleVols | sed 's/ /;/g'
}
chkAddon
echo "***************"
chkEndpoint
echo "***************"
chkVolRange
echo "***************"
chkShareableVol
echo "***************"
