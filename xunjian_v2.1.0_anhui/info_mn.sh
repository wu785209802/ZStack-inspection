#########################################################################
# File Name: info_mn.sh
# Author: wuqiuyang
# mail: qiuyang.wu@zstack.io
# Created Time: 2020-07-04
#########################################################################
#!/bin/bash

. ./.env
PARSE_JSON="/tmp/json.sh -l -p -b"

zs_properties=`zstack-ctl status|grep [z]stack.properties|awk '{print $2}'`
DB_IP=`cat $zs_properties|awk -F ":" '/DB.url /{print $3}'`
DB_IP=`echo ${DB_IP#*//}`
DB_Port=`cat  $zs_properties|awk -F ":" '/DB.url /{print $4}'`

export zs_sql_pwd=$(grep DB.password /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/zstack.properties | awk '{print $3}')

echo "show databases" |mysql -uzstack -p${zs_sql_pwd} > /dev/null 2>&1
if [ $? -ne 0 ];then
  export zs_sql_pwd=zstack.password
fi
export mysql_cmd=$(echo "mysql -uzstack -p${zs_sql_pwd} -e")

function init(){
  echo "" > /tmp/log/service_info
  #echo "" > /tmp/log/vm_info
  echo "" > /tmp/log/vip_info
  echo "" > /tmp/log/volume_info
}

#查询云主机信息
#function query_vm(){
#  #echo "#################### 查询云主机信息 ####################"
#  $mysql_cmd "
#  use zstack;
#  SELECT VmInstanceVO.uuid,
#        VmInstanceVO.NAME,
#        VmInstanceVO.cpuNum,
#        VmInstanceVO.memorySize,
#        VmInstanceVO.description,
#        VmInstanceVO.createDate,
#        UserTagVO.tag
#        FROM VmInstanceVO LEFT JOIN UserTagVO ON VmInstanceVO.uuid=UserTagVO.resourceUuid;
#  quit"
#}
#
#function query_vip(){
#  #echo "#################### 查询vip信息 ####################"
#  $mysql_cmd "
#  USE zstack;
#  SELECT
#    c.VipVO_uuid,
#    c.NAME AS vip_name,
#    c.ip,
#    c.useFor AS ip_use_for,
#    VmInstanceVO.NAME AS vm_name,
#    c.vmInstanceUuid,
#    c.inboundBandwidth,
#    c.outboundBandwidth
#  FROM
#    (
#    SELECT
#      b.*,
#      VmNicVO.uuid AS VmNicVO_uuid,
#      VmNicVO.vmInstanceUuid
#    FROM
#      (
#      SELECT
#        a.*,
#        UsedIpVO.vmNicUuid
#      FROM
#        (
#        SELECT
#          VipVO.uuid AS VipVO_uuid,
#          VipVO.ip,
#          VipVO.NAME,
#          VipVO.useFor,
#          VipQosVO.inboundBandwidth,
#          VipQosVO.outboundBandwidth,
#          VipVO.usedIpUuid
#        FROM
#          VipVO
#          LEFT JOIN VipQosVO ON VipVO.uuid = VipQosVO.vipUuid
#        ) AS a
#        LEFT JOIN UsedIpVO ON a.usedIpUuid = UsedIpVO.uuid
#      ) AS b
#      LEFT JOIN VmNicVO ON b.vmNicUuid = VmNicVO.uuid
#    ) AS c
#    LEFT JOIN VmInstanceVO ON c.vmInstanceUuid = VmInstanceVO.uuid;
#  quit"
#}
function query_vm_vip(){
  #echo "#################### 查询vip信息 ####################"
  $mysql_cmd "
  use zstack;
  SELECT
  	e.NAME AS Vm_Name,
  	e.uuid AS Vm_Uuid,
  	e.cpuNum AS Vm_Cpu_Num,
  	(e.memorySize/1024/1024/1024) AS 'Vm_Mem_Size(G)',
  	e.description AS Vm_Description,
  	e.createDate AS Vm_Create_Date,
  	e.tag AS Vm_Tag,
  	d.VipVO_uuid AS Vip_Uuid,
  	d.vip_name AS Vip_Name,
  	d.ip AS Ip,
  	d.ip_use_for AS Ip_Used_For,
  	d.inboundBandwidth AS Inbound_Bandwidth,
  	d.outboundBandwidth AS Outbound_Bandwidth
  FROM
  	(
  		(
  		SELECT
  			c.VipVO_uuid,
  			c.NAME AS vip_name,
  			c.ip,
  			c.useFor AS ip_use_for,
  			VmInstanceVO.NAME AS vm_name,
  			c.vmInstanceUuid,
  			c.inboundBandwidth,
  			c.outboundBandwidth
  		FROM
  			(
  			SELECT
  				b.*,
  				VmNicVO.uuid AS VmNicVO_uuid,
  				VmNicVO.vmInstanceUuid
  			FROM
  				(
  				SELECT
  					a.*,
  					UsedIpVO.vmNicUuid
  				FROM
  					(
  					SELECT
  						VipVO.uuid AS VipVO_uuid,
  						VipVO.ip,
  						VipVO.NAME,
  						VipVO.useFor,
  						VipQosVO.inboundBandwidth,
  						VipQosVO.outboundBandwidth,
  						VipVO.usedIpUuid
  					FROM
  						VipVO
  						LEFT JOIN VipQosVO ON VipVO.uuid = VipQosVO.vipUuid
  					) AS a
  					LEFT JOIN UsedIpVO ON a.usedIpUuid = UsedIpVO.uuid
  				) AS b
  				LEFT JOIN VmNicVO ON b.vmNicUuid = VmNicVO.uuid
  			) AS c
  			LEFT JOIN VmInstanceVO ON c.vmInstanceUuid = VmInstanceVO.uuid
  		) AS d
  	)
  	RIGHT JOIN (
  		(
  		SELECT
  			VmInstanceVO.uuid,
  			VmInstanceVO.NAME,
  			VmInstanceVO.cpuNum,
  			VmInstanceVO.memorySize,
  			VmInstanceVO.description,
  			VmInstanceVO.createDate,
  			UserTagVO.tag
  		FROM
  			VmInstanceVO
  			LEFT JOIN UserTagVO ON VmInstanceVO.uuid = UserTagVO.resourceUuid
  		) AS e
  	) ON d.vmInstanceUuid = e.uuid UNION
  SELECT
  	e.NAME AS Vm_Name,
  	e.uuid AS Vm_Uuid,
  	e.cpuNum AS Cpu_Num,
  	(e.memorySize/1024/1024/1024) AS 'Vm_Mem_Size(G)',
  	e.description AS Vm_Description,
  	e.createDate AS Create_Date,
  	e.tag AS Vm_Tag,
  	d.VipVO_uuid AS Vip_Uuid,
  	d.vip_name AS Vip_Name,
  	d.ip AS Ip,
  	d.ip_use_for AS Ip_Used_For,
  	d.inboundBandwidth AS Inbound_Bandwidth,
  	d.outboundBandwidth AS Outbound_Bandwidth
  FROM
  	(
  		(
  		SELECT
  			c.VipVO_uuid,
  			c.NAME AS vip_name,
  			c.ip,
  			c.useFor AS ip_use_for,
  			VmInstanceVO.NAME AS vm_name,
  			c.vmInstanceUuid,
  			c.inboundBandwidth,
  			c.outboundBandwidth
  		FROM
  			(
  			SELECT
  				b.*,
  				VmNicVO.uuid AS VmNicVO_uuid,
  				VmNicVO.vmInstanceUuid
  			FROM
  				(
  				SELECT
  					a.*,
  					UsedIpVO.vmNicUuid
  				FROM
  					(
  					SELECT
  						VipVO.uuid AS VipVO_uuid,
  						VipVO.ip,
  						VipVO.NAME,
  						VipVO.useFor,
  						VipQosVO.inboundBandwidth,
  						VipQosVO.outboundBandwidth,
  						VipVO.usedIpUuid
  					FROM
  						VipVO
  						LEFT JOIN VipQosVO ON VipVO.uuid = VipQosVO.vipUuid
  					) AS a
  					LEFT JOIN UsedIpVO ON a.usedIpUuid = UsedIpVO.uuid
  				) AS b
  				LEFT JOIN VmNicVO ON b.vmNicUuid = VmNicVO.uuid
  			) AS c
  			LEFT JOIN VmInstanceVO ON c.vmInstanceUuid = VmInstanceVO.uuid
  		) AS d
  	)
  	LEFT JOIN (
  		(
  		SELECT
  			VmInstanceVO.uuid,
  			VmInstanceVO.NAME,
  			VmInstanceVO.cpuNum,
  			VmInstanceVO.memorySize,
  			VmInstanceVO.description,
  			VmInstanceVO.createDate,
  			UserTagVO.tag
  		FROM
  			VmInstanceVO
  			LEFT JOIN UserTagVO ON VmInstanceVO.uuid = UserTagVO.resourceUuid
  		) AS e
  	) ON d.vmInstanceUuid = e.uuid;
    quit"
}

function query_volume(){
  #echo "#################### 查询volume信息 ####################"
  $mysql_cmd "
  use zstack;
  SELECT
        VolumeEO.uuid,
        VolumeEO.NAME as 'Volume_Name',
        VolumeEO.installPath,
        VolumeEO.type,
        VolumeEO.size,
        VolumeEO.actualSize,
        VolumeEO.STATUS,
        VmInstanceVO.name as 'Vm_Name'
  FROM
        VolumeEO,
        VmInstanceVO 
  WHERE
        VolumeEO.STATUS = 'Ready' AND VolumeEO.vmInstanceUuid = VmInstanceVO.uuid;
  quit"
}

function check_zsha2(){
  echo "************************ check zsha2 status **********************"
  zsha2_str=`/usr/local/bin/zsha2 status -json 2>&1`
  systemctl is-enabled zstack-ha  >/dev/null 2>&1
  result=`echo $?`
  if [[ $result -eq 0 ]];then
    echo "$zsha2_str"
  else
    echo "This is not dual management node high availability"
  fi
  echo ""
}

main(){
  init
  check_zsha2  >> /tmp/log/service_info
  #query_vm | sed '1d' | awk -F "\t" 'BEGIN{print "uuid\tname\tcpuNum\tmemorySize(G)\tdescription\tcreateDate\ttag"} {print $1"\t"$2"\t"$3"\t"$4/1024/1024/1024"\t"$5"\t"$6"\t"$7}' >> /tmp/log/vm_info
  query_vm_vip >> /tmp/log/vip_info
  query_volume | sed '1d' |  awk -F "\t|/" '{print $1"\t"$2"\t"$5"\t"$7"\t"$8"\t"$9"\t"$10"\t"$11}' | awk -F "\t" '{print $1"\t"$2"\t"$8"\t"$3"\t""template""\t"$4"\t"$5"\t"$6"\t"$7"\t"}' | awk -F "\t" 'BEGIN {print "uuid\tvolume_name\tvm_name\tpool_id\tpool_type\ttype\tsize(G)\tactualSize(G)\tSTATUS"} {printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n",$1,$2,$3,$4,$5,$6,$7/1024/1024/1024,$8/1024/1024/1024,$9}' >> /tmp/log/volume_info
}
main
