# Ceph登录信息
# set -x
# 定义相关变量
dd=$(date '+%Y-%m-%d')
CEPH_LOG_PATH=/tmp/CephCheck.${dd}
ceph_check_log=${CEPH_LOG_PATH}/log/ceph_check.log
report_log=${CEPH_LOG_PATH}/log/ceph_check.csv
# 检查是否是企业版Ceph
ceph -s >> /dev/null 2>&1
if [ $? -ne 0 ];then echo '非Ceph环境，请检查后再试' && exit 93;fi
rpm -qa | grep xdc >> /dev/null 2>&1
if [ $? -ne 0 ];then echo '非企业版Ceph，请手动进行巡检' && exit 91;fi
ps -ef | grep ceph-mon >> /dev/null 2>&1
if [ $? -ne 0 ];then echo "非MON节点，请拷贝 $0 到Ceph MON节点进行巡检" & exit 92;fi
while true;do
	xms-cli --user $1 --password $2 pool list >> /dev/null 2>&1
	if [ $? -ne 0 ];then
		echo 'Wrong username or password' && echo "Usage: $0 <Ceph UI Username> <Ceph UI Password> " && exit 2
	else
		break
	fi
done
user=$1
password=$2
xms_cli_prefix="xms-cli --user ${user} --password ${password}"
# 报告信息
# 如果，没有日志没录，则自动创建该目录
if [ ! -d "${CEPH_LOG_PATH}/log" ];then mkdir -p ${CEPH_LOG_PATH}/log;fi
if [ -f ${report_log} ];then cp ${report_log} ${report_log}.${dd};fi
echo 'Ceph巡检报告'> ${report_log}

# 临时文件
#
function progress(){
        num=0;
        label=("|" "/"  "-" "\\" "|" "+")
        while [ $num -ne 20 ]
        do
            ((color=30+num%8))
            echo -en "\e[1;"$color"m"
            printf "[%c]\r" "${label[num%6]}"
            let num++
            sleep 0.2
        done
        echo -en "\e[1;30;m"
}

#ceph Version信息
function cephVersion(){
		cephVersion=$(rpm -qa |grep xdc | awk -F "-" '{print$2}')
		echo "当前ceph版本为:$cephVersion"
		echo ""
}
# 产品license信息
function report(){
	# 定义输出报表信息
	# 格式为：巡检项目(key),巡检结果(value),参考值(referenceValue),是否正常(result,正常/异常),均不能为空

	# 参数检查
	#if [ $# -lt 4 ];then
	#	echo '参数不足，请检查后重试' && echo "Usage:$0 <巡检项目(key)> <巡检结果(value)> <参考值(referenceValue)> <是否正常(result,正常/异常)>" && exit 1
	#fi
	# 去除值中的','，防止影响结果
	key=$(echo $1 | sed 's/,/ /g')
	value=$(echo $2 | sed 's/,/ /g')
	referenceValue=$(echo $3 | sed 's/,/ /g')
	result=$(echo $4 | sed 's/,/ /g')
	# 记录结果
	echo "$key,$value,$referenceValue,$result" >> $report_log


}
function licenseList(){
	echo "产品license信息:"
	$xms_cli_prefix time show | grep server_time
	$xms_cli_prefix license show
	expired_date=$($xms_cli_prefix license show | grep expired_time | grep -oE [0-9]{4}-[0-9]{2}-[0-9]{2})
	current_date=$(date "+%Y-%m-%d")
	if [ "$expired_date" > "$current_date" ];then
		report 产品license有效期 $expired_date 无 正常
	else
		report 产品license有效期 $expired_date 无 异常
	fi
	endDate=`date -d "$expired_date" +%s`
	nowDate=`date -d "$current_date" +%s`
	stampDiff=`expr $endDate - $nowDate`
	dayDiff=`expr $stampDiff / 86400`
	if [[ $dayDiff -le 0 ]];then
			echo "Important：存储license已过期，请及时联系技术支持工程师";
	elif [[ $dayDiff -le 7 ]];then
			echo "Important：存储license据过期时间仅剩$dayDiff天，请及时联系技术支持工程师";
	fi
echo ""
}

# IP规划
function hostList(){
	echo "IP规划:"
	$xms_cli_prefix host list
	$xms_cli_prefix network-address list
	echo ""
}
# 带宽 IOPS 延迟 OSD信息
function bandwidthIOPS(){
	echo "OSD信息:"
	ceph -s | grep osd:
	echo ""
	echo "带宽 IOPS"
	ceph -s | grep client
	echo ""
	echo "延迟"
	ceph osd perf
	echo ""
}
# 存储池信息
function poolList(){
	echo "存储池信息:"
	$xms_cli_prefix pool list
	echo ""
}
# 磁盘信息
function diskList(){

	echo "磁盘信息:"
	$xms_cli_prefix disk list
	echo ""
	echo "OSD使用信息:"
	ceph osd df
	echo ""

}
# OSD使用信息
function osdList(){
	echo "OSD使用信息:"
	$xms_cli_prefix osd list
	osd_used_info=$(ceph osd df |egrep -v 'ID|STDDEV|TOTAL'| awk '{if($7>50){printf "%s|%0.2f\n",$1,$7}else{printf "%s|%0.2f\n",$1,$7}}')
	for used in $osd_used_info
	do

		ID=$(echo $used | cut -d '|' -f 1)
		used1=$(echo $used | cut -d '|' -f 2)
		used100=$(echo $used | cut -d '|' -f 2 | awk '{print $1 * 100}')

		if [ $used100 -lt 5000 ];then
			report OSD_ID:$ID已用百分比 $used1 50% 正常
		else
			report OSD_ID:$ID已用百分比 $used1 50% 异常
		fi
	done
	echo ""
}
# 缓存盘信息
function cacheInfo(){
	echo "缓存盘信息:"
	SSD_IDs=$($xms_cli_prefix disk list | grep SSD | awk '{print $2}')
	echo '+----+--------------------------------------+-----------+-----------+---------+-------------+-----------------------------+'
	echo '| ID |                 UUID                 |   SIZE    |   PATH    | DISK ID | DISK DEVICE |           CREATE            |'
	echo '+----+--------------------------------------+-----------+-----------+---------+-------------+-----------------------------+'
	for SSD_ID in ${SSD_IDs};do
			$xms_cli_prefix partition list  --disk ${SSD_ID} | egrep -v '+---|UUID'

	done
	echo '+----+--------------------------------------+-----------+-----------+---------+-------------+-----------------------------+'
	echo ""
}
# 缓存盘使用信息

# 服务运行状态
function serviceList(){
	echo "服务运行状态:"
	$xms_cli_prefix service list

	service_status_list=$($xms_cli_prefix service list | egrep -v 'ID|+--' | awk '{print $14,$6,$8}' | sort| sed 's/ /|/g')
	for service_status in $service_status_list;do
		host=$(echo $service_status | cut -d '|' -f 1)
		service_name=$(echo $service_status | cut -d '|' -f 2)
		status=$(echo $service_status | cut -d '|' -f 3)
		if [ "$status" == "active" ];then
			report 服务运行状态检查 ${host}_${service_name}_${status} active 正常
		else
			report 服务运行状态检查 ${host}_${service_name}_${status} active 异常
		fi

	done
	echo ""
}
#ES服务查询
function ESlist(){
	echo "检查ES服务运行状态:"
	ES_service_status=$($xms_cli_prefix -l cluster show elasticsearch |egrep -v 'ID|+--' | grep -w 'elasticsearch_enabled'|awk -F "|" '{print$3}' |sed 's/ //g')
	if [ "$ES_service_status" == "true" ];then
		echo 'Urgent: ES服务处于开启状态，请联系技术支持关闭ES服务'
  else
    echo 'Normal: ES服务处于关闭状态'
  fi
	echo ""
}

# 数据库信息
function dbList(){
	echo "数据库信息:"
	xms-manage db list
	echo ""
}

#Ceph计算节点的virsh secret-list
function secretlist(){
	echo "secret-list信息查询:"
	for ip in `xms-cli --user admin --password ${password} service list | egrep -v 'ID|+--' | awk '{print $14}' | sort|uniq`
			do echo $ip ;ssh -o StrictHostKeyChecking=no $ip virsh secret-list
	done
	echo ""
}
# 配置信息
function confList(){
	echo "配置信息:"
	$xms_cli_prefix conf list
	echo ""
}
function cephHealth(){
        echo "Ceph health check:"
        ceph status

        echo
        echo "Ceph mon stat:"
        ceph mon stat

        echo
        echo "Ceph df stat:"
        ceph df detail
	ceph_df_use=`ceph df detail |sed -n 3p |awk -F " " '{print$4}'|awk -F "." '{print$1}'`
	if [[ "$ceph_osd_use" -gt 75 ]];then
            echo 'Urgent:存储使用率大于 75 %,请联系技术支持工程师获取帮助'
        elif [[ "$ceph_osd_use" -gt 70 ]];then
            echo 'Important:存储使用率大于 70 %,请联系技术支持工程师获取帮助'
        fi
        echo
        echo "Ceph osd df:"
        ceph osd df
				ceph_osd_use=`ceph osd df | sed -n '2,$p' |awk -F " " '{print$7}'|sort -nr |sed -n 1p|awk -F "." '{print$1}'`
        if [[ "$ceph_osd_use" -gt 80 ]];then
					echo 'Urgent:osd使用率大于 80 %,请联系技术支持工程师获取帮助'
	      elif [[ "$ceph_osd_use" -gt 70 ]];then
					echo 'Important:osd使用率大于 70 %,请联系技术支持工程师获取帮助'
	      fi
        ceph osd df | sed -n '2,$p' |awk -F " " '{print$2 ":" $7}' | sed '$d' | sed '$d' | grep "^0" -v | awk -F ":" '{print $2}' >> temp_osd_df.log
				#计算方差
        SD=$(awk '{x[NR]=$0; s+=$0; n++} END{a=s/n; for (i in x){ss += (x[i]-a)^2} sd = sqrt(ss/n); print "SD = "sd}' temp_osd_df.log | awk -F ' = ' '{print$2}' | awk -F '.' '{print $1}')
        if [[ $SD -gt 7 ]]; then
          echo "Urgent:osd分配不均匀,请联系技术支持工程师获取帮助"
        else
          echo "Normal:osd分配均匀"
	      fi
        rm -rf temp_osd_df.log
				echo ""
        ceph osd df tree

        echo
        echo "Ceph osd tree:"
        ceph osd tree
	      echo

        echo "Ceph osd perf:"
        ceph osd perf
        echo

        echo "Ceph pool list:"
        ceph osd pool ls
	      ceph osd pool ls detail

        echo
        echo "Ceph osd dump:"
        ceph osd dump
	      echo

        echo "Ceph pg stat:"
        ceph pg stat
        echo

        echo "Ceph pg dump:"
        ceph pg dump|sed  -n  '/sum/,${//!p};$p'
        echo

        echo "Ceph pg check, expected OK"
        ceph pg dump_stuck stale
        ceph pg dump_stuck inactive
        ceph pg dump_stuck unclean

        echo
        echo "Ceph auth ls:"
        ceph auth ls

        echo
        echo "Ceph version:"
        ceph -v

        echo
        echo "Ceph fsid:"
        ceph fsid

        echo
				echo "Ceph log last:"
        ceph log last

        echo
        echo "Ceph crush dump:"
        ceph osd crush dump

	      echo
	      echo "Ceph crush tree:"
	      ceph osd crush tree

        echo
        echo "Ceph osd blacklist:"
	      ceph osd blacklist ls

        echo
        echo "Ceph quorum status:"
        ceph quorum_status -f json-pretty

        echo
				echo "Ceph mon feature ls:"
        ceph mon feature ls
        echo
}
function ceph_status(){
		echo "ceph健康信息查询:"
		cephstatus=$(ceph -s |grep HEALTH |awk -F "_" '{print$2}')
		if [ "$cephstatus" != "OK" ];then
    		echo "Urgent:存储状态为$cephstatus，请及时联系技术支持工程师"
		else
	      echo "Normal:ceph 状态为 $cephstatus ,无异常"
		fi
		echo ""
}

function check(){
	cephVersion
	ceph_status
	licenseList
	hostList
	bandwidthIOPS
	poolList
	diskList
	osdList
	cacheInfo
	serviceList
	ESlist
	dbList
	secretlist
	confList
	cephHealth
}
check > ${ceph_check_log} 2>&1 && touch ${CEPH_LOG_PATH}/log/finished &
        while true;do
                if [ ! -f ${CEPH_LOG_PATH}/log/finished ];then
                        echo -en '     正在巡检中,请稍候            ' && progress
                else
                        cd ${CEPH_LOG_PATH}/log/ && rm -f finished && break
                fi
        done
iconv -f UTF8 -t GBK $report_log -o $report_log
cd ${CEPH_LOG_PATH} && sudo tar -czf ceph_check.${dd}.tar.gz log > tardetail && sudo rm -rf tardetail && rm -rf log &

echo "Ceph存储巡检结束，日志存放于：${CEPH_LOG_PATH}/ceph_check.${dd}.tar.gz"
