#!/bin/bash

Passwd_Path="./UnSecurity_Passwd.txt"

DB_User_1="root"
DB_User_2="zstack"
DB_Passwd_1="zstack.mysql.password"
DB_Passwd_2="zstack.password"
zs_properties=`zstack-ctl status|grep [z]stack.properties|awk '{print $2}'`
DB_IP=`cat $zs_properties|awk -F ":" '/DB.url /{print $3}'`
DB_IP=`echo ${DB_IP#*//}`
DB_Port=`cat  $zs_properties|awk -F ":" '/DB.url /{print $4}'`
SQL_Access="mysql -u $DB_User -p$DB_Password zstack -h $DB_IP -P $DB_Port"

UnSecurity_Passwd=$(cat $Passwd_Path)
Passwd_List=$(mysql -u $DB_User_1 -p$DB_Passwd_1 zstack -h $DB_IP -P $DB_Port -e "select * from KVMHostVO;" | grep "$DB_User_1" | awk -F " " '{print $3}')

function Check_UnSecurity_Passwd(){
Passwd_List=$(mysql -u $DB_User_1 -p$DB_Passwd_1 zstack -h $DB_IP -P $DB_Port -e "select * from KVMHostVO;" | grep "$DB_User_1" | awk -F " " '{print $3}')
flag_1=0
for passwd in ${Passwd_List[@]}
do
  for pwd in ${UnSecurity_Passwd[@]}
  do
    if [[ $pwd == $passwd ]];then
      HOST_IP[$flag_1]=`mysql -u $DB_User_1 -p$DB_Passwd_1 zstack -h $DB_IP -P $DB_Port -e "select KVMHostVO.password,KVMHostVO.username,HostVO.managementIp from KVMHostVO,HostVO where KVMHostVO.uuid=HostVO.uuid and KVMHostVO.password in ('$pwd');" | awk -F " " '{print $3}' | sed "1d"`
    fi  
  ((flag_1++))
  done
done

for ip_1 in ${HOST_IP[@]}
do
  echo $ip_1 >> tmp_1.log
done

if [[ -f tmp_1.log  ]];then
  sort tmp_1.log | uniq >> ip_1.log
  ip_list=$(cat ./ip_1.log)
fi

for ip_2 in ${ip_list[@]}; 
do
  echo "The password of host($ip_2) is too simple !"
done
if [[ -f tmp_1.log && ip_1.log ]];then
  rm -rf tmp_1.log && rm -rf ip_1.log
fi
}

function Check_Passwd_Len(){
flag_2=0
for passwd in ${Passwd_List[@]}
do
  Passwd_LEN=${#passwd}
  if [[ $Passwd_LEN -lt 9 ]];then
    HOST_IP[$flag_2]=`mysql -u $DB_User_1 -p$DB_Passwd_1 zstack -h $DB_IP -P $DB_Port -e "select KVMHostVO.password,KVMHostVO.username,HostVO.managementIp from KVMHostVO,HostVO where KVMHostVO.uuid=HostVO.uuid and KVMHostVO.password in ('$passwd');" | awk -F " " '{print $3}' | sed "1d"`
  fi
  ((flag_2++))
done

for ip_3 in ${HOST_IP[@]}
do
  echo $ip_3 >> tmp_2.log
done

if [[ -f tmp_2.log ]];then
  sort tmp_2.log | uniq >> ip_2.log
  ip_list=$(cat ./ip_2.log)
fi

for ip_4 in ${ip_list[@]}
do
  echo "The password length of host($ip_4) is too short !"
done

if [[ -f tmp_2.log && ip_2.log ]];then
  rm -rf tmp_2.log && rm -rf ip_2.log 
fi
}

function Check_SQL(){
DB_User=$1
DB_Password=$2
DB_IP=$3
DB_Port=$4
SQL_Result=`mysql -u $DB_User -p$DB_Password zstack -h $DB_IP -P $DB_Port -e quit 2>&1`
SQL_Result_Len=${#SQL_Result}  
if [[ ${SQL_Result_Len} -eq 0 ]];then
  echo "Please change password of database user $1 !"  
else  
  echo "Wrong Password !"  
fi
}

#function Check_bond(){
#`ifconfig | grep bond |sed 's/[ ]*//g' >> tmp_3.log`
#Bond_Str=`cat ./tmp_3.log`
#for str in ${Bond_Str[@]}
#do
#  bond_name=`echo $str | awk -F ":" '{print $1}'`
#  if [[ "$str" =~ "UP" ]];then
#    echo "$bond_name UP"
#  elif [[ "$str" =~ "DOWN" ]];then
#    echo "$bond_name DOWN"
#  fi
#done
#rm -rf tmp_3.log
#}

main()
{
  echo ""
  echo "############################## 检查物理机用户密码是否为弱密码 ##############################"
  Check_UnSecurity_Passwd
  echo ""
  echo "############################## 检查物理机用户密码长度是否小于9 ##############################"
  Check_Passwd_Len
  echo ""
  echo "##############################检查数据库用户密码是否正确 ##############################"
  Check_SQL $DB_User_1 $DB_Passwd_1 $DB_IP $DB_Port
  Check_SQL $DB_User_2 $DB_Passwd_2 $DB_IP $DB_Port
  echo ""
}

main
