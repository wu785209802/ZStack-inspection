#!/bin/bash
PARSE_JSON="./json.sh -l -p -b"

function check_pool_size(){
  echo "############################### 检查pool的容量 ####################################"
  echo -e "pool_name\t总容量(T)\t使用容量(T)\t可用容量(T)\t使用率"
  body=`zstack-cli QueryPrimaryStorage type!=VCenter | $PARSE_JSON`
  count=`echo $body | grep '"pools",[0-9],"poolName"'| awk -F " " '{print $2}' | sort -u | wc -l`
  for i in ${count[@]}
  do
  poolName=`echo "$body" | grep "\"pools\"\,$i\,\"poolName\"" | awk -F '"' '{print $8}'`
  totalCapacity=`echo "$body" | grep "\"pools\"\,$i\,\"totalCapacity\"" | awk -F " " '{print $2}' |awk '{print $0/1024/1024/1024/1024}'`
  usedCapacity=`echo "$body" | grep "\"pools\"\,$i\,\"usedCapacity\"" | awk -F " " '{print $2}' |awk '{print $0/1024/1024/1024/1024}'`
  availableCapacity=`echo "$body" | grep "\"pools\"\,$i\,\"availableCapacity\"" | awk -F " " '{print $2}' |awk '{print $0/1024/1024/1024/1024}'`
  UtilizationRate=`awk "BEGIN {print $usedCapacity/$totalCapacity}"` 
  echo -e "$poolName\t$totalCapacity\t$usedCapacity\t$availableCapacity\t$UtilizationRate"
  done
}

check_pool_size
