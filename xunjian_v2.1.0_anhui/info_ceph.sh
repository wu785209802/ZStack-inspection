#########################################################################
# File Name: info_ceph.sh
# Author: wuqiuyang
# mail: qiuyang.wu@zstack.io
# Created Time: 2020-07-04
#########################################################################
#!/bin/bash

PARSE_JSON="/tmp/json.sh -l -p -b"
user=$1
password=$2
xms_cli_prefix="xms-cli --user ${user} --password ${password}"

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

function check_pool_type(){
  xms_cli_prefix="xms-cli --user ${user} --password ${password}"
  body=`$xms_cli_prefix -f json pool list`
  id=`echo $body | $PARSE_JSON | grep '"pools",[0-9],"id"' | awk -F '\t' '{print $2}'`
  echo "" > /tmp/log/pool_type
  for i in ${id[@]}
  do
  xms_str=`$xms_cli_prefix -f json pool show $i | grep -E "pool_name|device_type"`
  device_type=`echo "$xms_str" | grep "device_type" | awk -F '"' '{print $4}'`
  pool_name=`echo "$xms_str" | grep "pool_name" | awk -F '"' '{print $4}'`
  echo -e "${pool_name}\t${device_type}" >> /tmp/log/pool_type
  done
}

main(){
  cp ./json.sh /tmp/json.sh
  check_pool_type && touch /tmp/log/finished &
  while true
  do
  if [ ! -f /tmp/log/finished ];then
    echo ""
    echo -n "    正在收集信息，请稍后...." && progress
  else
    cd /tmp/log/ && rm -rf finished && break
  fi
  done  
  rm -rf /tmp/json.sh
}

main
