#!/bin/bash

function check_disk_ssd(){
  echo "###########################MON节点系统盘类型检查############################"
 `ceph mon stat >/dev/null 2>&1`
  result_vlaue=`echo $?`
  #monip_list=`echo "$mon_stat" | awk -F "{|}" '{print $2}' | sed "s/,/\n/g" | awk -F "=|:" '{print $2}'`
  boot_disk=`lsblk | grep boot | awk -F "├─| " '{print $2}' | awk -F "[0-9$]" '{print $1}'`
  disk_value=`grep ^ /sys/block/${boot_disk}/queue/rotational`
  if [[ $result_vlaue -eq 0 ]];then
    container_num=`docker ps -a -q | wc -l`
    if [[ $container_num -gt 3 ]];then
      if [[ $disk_value -eq 0  ]];then
        echo "Normal: system disk ${boot_disk} type is SSD"
      elif [[ $disk_value -eq 1 ]];then
        echo "Urgent: system disk ${boot_disk} type is HDD"
      fi
    else
      break
    fi
  else
    break
  fi
  echo ""
}
check_disk_ssd
