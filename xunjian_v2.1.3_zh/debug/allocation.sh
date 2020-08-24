#!/bin/bash

function Pre_allocation(){
    Body=`zstack-cli QueryPrimaryStorage`
    if [[ $Body =~ "LocalStorage" ]];then
       allocation_str=$($mysql_cmd "use zstack;SELECT GlobalConfigVO.NAME,GlobalConfigVO.VALUE FROM GlobalConfigVO WHERE category='localStoragePrimaryStorage' AND description='qcow2 allocation policy, can be none, metadata, falloc, full';" 
| grep -v "NAME" | sed 's/\t/,/g')
       allocation=`echo $allocation_str | awk -F "," '{print $2}'`
       if [[ "$allocation_str" =~ "falloc" ]];then
           echo "Normal: 本地存储的云盘预分配策略为falloc"
       else
           echo "Urgent: 本地存储的云盘的预分配策略为$allocation"
       fi
    fi
}

Pre_allocation
