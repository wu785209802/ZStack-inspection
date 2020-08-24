#########################################################################
# File Name: info_collect.sh
# Author: wuqiuyang
# mail: qiuyang.wu@zstack.io
# Created Time: 2020-07-04
#########################################################################
#!/bin/bash

clear
echo -n "输入云平台用户名:"
read  cloud_username
echo -n "输入云平台密码:"
read -s cloud_password
echo ""
DATE=$(date +%Y%m%d)
USER=$cloud_username
PASSWD=$cloud_password

export zs_sql_pwd=$(grep DB.password /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/zstack.properties | awk '{print $3}')
echo "show databases" |mysql -uzstack -p${zs_sql_pwd} > /dev/null 2>&1
if [ $? -ne 0 ];then
  export zs_sql_pwd=zstack.password
fi
export mysql_cmd=$(echo "mysql -uzstack -p${zs_sql_pwd} -e")

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

function chkLogin(){
 echo '----------------------------------------------------------------------------------'
 echo '1. 检查登录状态'
 echo '----------------------------------------------------------------------------------'
 zstack-cli LogInByAccount accountName=$USER password=$PASSWD > ./session.log 3>&1
 if [ $? -ne 0 ];then
   echo "密码错误，请检查!" && exit 11
 else
   echo "密码正确!"
 fi
}

function chkCeph(){
  monAddrs=$(zstack-cli QueryCephPrimaryStorage | grep monAddr | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}')
  if [ -n "${monAddrs}" ];then
    my_ips=$(hostname -I)
    tag=0
    for monIP in $monAddrs;do
      for my_ip in $my_ips;do
        if [ "$monIP" == "$my_ip" ];then
          while true;do
            echo "检测到本机为Ceph的MON节点,是否需要立即进行巡检?(请输入yes或no)"
            read ifCheck
            if [ "$ifCheck" == "yes" ];then
              tag=1
              echo -n "请输入企业版Ceph的用户名:"
              read username
              echo -n "请输入企业版Ceph的密码:"
              read -s password
              bash ./info_ceph.sh $username $password &&sleep 3 && return
            elif [ "$ifCheck" == "no" ];then
              tag=2
              return
            else
              continue
            fi
          done
        fi
      done
    done
    if [ $tag -eq 0 ];then
      AvailablemonAddr=$($mysql_cmd "use zstack;SELECT CephPrimaryStorageMonVO.hostname FROM PrimaryStorageVO,CephPrimaryStorageMonVO WHERE primaryStorageUuid = PrimaryStorageVO.uuid AND CephPrimaryStorageMonVO.STATUS = 'Connected';" -N )
      echo "当前为非MON节点，自动拷贝check-ceph.sh到Ceph MON节点执行"
      mon_num=`echo $AvailablemonAddr |sed 's/ /\n/g'|wc -l`
      selectmon=`echo $[$RANDOM%$mon_num+1]`
      selectmonip=`echo $AvailablemonAddr | sed 's/ /\n/g'|sed -n "$selectmon"p`
      while true;do
      echo "是否需要立即进行巡检?(请输入yes或no)"
      read ifCheck
      if [ "$ifCheck" == "yes" ];then
      	echo -n "请输入企业版Ceph的用户名:"
      	read username
      	echo -n "请输入企业版Ceph的密码:"
      	read -s password
      	scp -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa ./json.sh $selectmonip:/tmp/ >>/dev/null 2>&1
      	ssh -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa $selectmonip bash -s < info_ceph.sh $username $password
      	ssh -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa $selectmonip "rm -rf /tmp/json.sh"
      	scp -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa $selectmonip:/tmp/log/pool_type /tmp/log >>/dev/null 2>&1
      	return
      elif [ "$ifCheck" == "no" ];then
      	return
      else
      	continue
      fi
      done
    fi
  fi
}

function chkMn(){
  echo '----------------------------------------------------------------------------------'
  echo '3. 管理节点信息收集'
  echo '----------------------------------------------------------------------------------'
  . ./.env
  sudo bash info_mn.sh  >>/dev/null 2>&1 &
  while true;do
  ps -ef | egrep 'info_mn'  | grep -v grep > /dev/null 2>&1
  if [ $? -eq 0 ];then
    progress
  else
    break
  fi
  done
  chkCeph
  echo ""
  if [[ `cat /tmp/log/pool_type` =~ "SSD" ]];then
    SSD_pool_id=`cat /tmp/log/pool_type | grep "SSD" | awk -F "\t"  '{print $1}'`
    flag_ssd=0
    for ssd in ${SSD_pool_id[@]}
    do
      ssd_list[$flag_ssd]=$ssd
      ((flag_ssd++))
    done
    ssd_num=${#ssd_list[@]}
    ssd_num=$((ssd_num-1))
  fi
  if [[ `cat /tmp/log/pool_type` =~ "HDD" ]];then
    HDD_pool_id=`cat /tmp/log/pool_type | grep "HDD" | awk -F "\t"  '{print $1}'`
    flag_hdd=0
    for hdd in ${HDD_pool_id[@]}
    do
      hdd_list[$flag_hdd]=$hdd
      ((flag_hdd++))
    done
    hdd_num=${#hdd_list[@]}
    hdd_num=$((hdd_num-1))
  fi
  if [[ `cat /tmp/log/pool_type` =~ "Hybrid" ]];then
    Hybrid_pool_id=`cat /tmp/log/pool_type | grep "Hybrid" | awk -F "\t"  '{print $1}'`
    flag_hybrid=0
    for hybrid in ${Hybrid_pool_id[@]}
    do
      hybrid_list[$flag_hybrid]=$hybrid
      ((flag_hybrid++))
    done
    hybrid_num=${#hybrid_list[@]}
    hybrid_num=$((hybrid_num-1))
  fi
  for i in `seq 0 $ssd_num`
  do
    if [[ `cat /tmp/log/volume_info` =~ "${ssd_list[i]}" ]];then
      sed  -i "/${ssd_list[i]}/s/template/SSD/g" /tmp/log/volume_info
    fi
  done

  for j in `seq 0 $hdd_num`
  do
    if [[ `cat /tmp/log/volume_info` =~ "${hdd_list[j]}" ]];then
      sed  -i "/${hdd_list[j]}/s/template/HDD/g" /tmp/log/volume_info
    fi
  done

  for k in `seq 0 $hybrid_num`
  do
    if [[ `cat /tmp/log/volume_info` =~ "${hybrid_list[k]}" ]];then
      sed  -i "/${hybrid_list[k]}/s/template/Hybrid/g" /tmp/log/volume_info
    fi
  done
}

function chkHost(){
  echo '----------------------------------------------------------------------------------'
  echo '2. 物理机信息收集'
  echo '----------------------------------------------------------------------------------'
  DATE_START=$(date +%s)
  if [ ! -f '~/.ssh/config' ];then
    echo 'StrictHostKeyChecking=no' > ~/.ssh/config
  fi
  sudo python ssh_info.py > /dev/null 2>&1 && sudo ansible-playbook info_host.yaml -i ./ansible.conf | grep fatal | tee -a /tmp/log/check_err.log > /dev/null 2>&1 &
  while true;do
  ps -ef | egrep 'ssh_info.py|ansible-playbook|info_host.yaml'  | grep -v grep > /dev/null 2>&1
  if [ $? -eq 0 ];then
    progress
    DATE_FINISH=$(date +%s)
    RUN_TIME=$(($DATE_FINISH-$DATE_START))
    if [ $RUN_TIME -gt 1500 ];then
      ans_pro=$(ps -ef | grep '[a]nsible-playbook info_host.yaml' | awk '{print $2}')
      if [ "$ans_pro" ];then kill $ans_pro && echo '物理机信息收集失败，请检查' && exit 80;fi
    fi
  else
    ls /tmp/log 2>/dev/null| grep -oE "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}" >> /dev/null 2>&1
    break
  fi
  done
}

function tar(){
  cd /tmp/ && sudo tar czvf collect_info-${DATE}.tar.gz log && sudo rm -rf /tmp/log
}


main(){
  cp ./json.sh /tmp/json.sh
  case_names=(chkLogin chkHost chkMn)
  for i in ${case_names[@]}
  do
  start_date=$(date +%s)
  $i
  if [ $? == 0 ];then
    end_date=$(date +%s)
    run_time=$(($end_date-$start_date))
    echo "执行结果:    成功！用时:${run_time}秒"
  else
    end_date=$(date +%s)
    run_time=$(($end_date-$start_date))
    echo "执行结果:   成功！用时:${run_time}秒"
    echo "发现有部分异常，请检查！"
  fi
  sleep 1
  done
  echo "************** check zstack-kvmagent.service status **************" >> /tmp/log/service_info
  grep "zstack-kvmagent.service:" `find /tmp/log/ -name HostDailyCheck-*txt` -ir | awk -F "/|:" '{print $4"\t"$6"\t"$7}' >> /tmp/log/service_info
  echo "" >> /tmp/log/service_info
  echo "****************** check libvirtd.service status *****************" >> /tmp/log/service_info
  grep "libvirtd.service:" `find /tmp/log/ -name HostDailyCheck-*txt` -ir| awk -F "/|:" '{print $4"\t"$6"\t"$7}' >> /tmp/log/service_info 
  echo "" >> /tmp/log/service_info
  echo "************************* check chronyc **************************" >> /tmp/log/service_info
  grep "\^\*\ " `find /tmp/log/ -name HostDailyCheck-*txt` -ir | awk -F "/|:" '{print $4"\t"$6}' >> /tmp/log/service_info 
     
  tar >>/dev/null 2>&1
  zstack-cli LogOut sessionUuid=$session_uuid >>/dev/null 2>&1
  rm -rf /tmp/json.sh

  echo -e "\n收集结束, 结果存放于:/tmp/collect_info-${DATE}.tar.gz"
}

main
