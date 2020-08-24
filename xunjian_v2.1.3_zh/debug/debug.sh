#!/bin/bash
zs_sql_pwd=zstack.password
mysql_cmd=$(echo "mysql -uzstack -p${zs_sql_pwd} -e")
IPs=$($mysql_cmd "use zstack;SELECT hostName FROM ManagementNodeVO;" -N)
function logmonitor_check(){
echo "############################ 管理节点Prometheus版本查询 ############################"
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
	echo $CPUOverProvisioningRatio | awk '{if($0>10){print "Important：CPU超分率设置过高，当前为：$0"}}'
	echo $ReservedMemory | awk '{if($0<1){print "Important：物理机保留内存设置过小，当前为："$0"GB"}}'
	echo $MemOverProvisioning | awk '{if($0>1.2){print "Important：内存超分率设置过高，当前为："$0}}'
	echo $psOverProvisioning | awk '{if($0>1.2){print "Important：主存储超分率设置过高，当前为："$0}}'
	echo $psThreshold | awk '{if($0>0.85){print "Important：主存储使用阈值设置过高，当前为："$0}}'
}
warnning
#logmonitor_check
