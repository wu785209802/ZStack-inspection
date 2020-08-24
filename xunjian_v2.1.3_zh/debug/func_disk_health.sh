#!/bin/bash

#function check_disk(){
#  xms-cli --user  admin --password password disk list > disk_table
#  disk_list=`cat ./disk_table | awk -F " " '{print $2}' | sed 's/ID//g'| tr -s "\n"`
#  awk -F "|" '{print $2 $3 $4 $5 $6 $7 $8 $12 }' ./disk_table > ./disk_table.tmp && sed -i '/^$/d' ./disk_table.tmp 
#  awk '{print $0 "HEALTH"}' ./disk_table.tmp > ./table.tmp
#  for i in ${disk_list[@]}
#  do
#  health_val=`xms-cli --user  admin --password password -f json disk show $i | grep ssd_life_left  | awk -F " " '{print $2}'| awk -F "," '{print $1}'`
#  sed  -i "/\<${i}\>/s/HEALTH/${health_val}/g" ./table.tmp
#  done
#  cat ./table.tmp | awk '$NF<50 {printf "%s\t%s\n",$0,"Urgent:硬盘寿命低于50%";} $NF>=50 {print $0 }'
#  rm -rf ./disk_table && rm -rf ./disk_table.tmp && rm -rf ./table.tmp
#}

xms_cli_prefix="xms-cli --user admin --password zstackts"

function check_disk(){
  echo "硬盘寿命检查"
  $xms_cli_prefix disk list > disk_table
  disk_list=`cat ./disk_table | awk -F " " '{print $2}' | sed 's/ID//g'| tr -s "\n"`
  awk -F "|" '{print $2 $3 $4 $5 $6 $7 $8 $12 }' ./disk_table > ./disk_table.tmp && sed -i '/^$/d' ./disk_table.tmp
  awk '{print $0 "HEALTH"}' ./disk_table.tmp > ./table.tmp
  for i in ${disk_list[@]}
  do
  health_val=`$xms_cli_prefix -f json disk show $i | grep ssd_life_left  | awk -F " " '{print $2}'| awk -F "," '{print $1}'`
  sed  -i "/\<${i}\>/s/HEALTH/${health_val}/g" ./table.tmp
  done
  cat ./table.tmp | awk '$NF<50 {printf "%s\t%s\n",$0,"Urgent:硬盘寿命低于50%";} $NF>=50 {print $0 }'
  rm -rf ./disk_table && rm -rf ./disk_table.tmp && rm -rf ./table.tmp
}

check_disk
