#!/bin/bash
user=$1
password=$2
xms_cli_prefix="xms-cli --user ${user} --password ${password}"

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
	echo "$key,$value,$referenceValue,$result"
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

licenseList
