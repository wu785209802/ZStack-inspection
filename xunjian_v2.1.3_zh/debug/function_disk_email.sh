#!/bin/bash
PARSE_JSON="./json.sh -l -p -b"
user=$1
password=$2


function check_cephEmail(){
    mon_ip=`xms-cli --user $user --password $password host list | grep "monitor" | awk -F " " '{print $14}'`
    mon_num=`echo $mon_ip | wc -l`
    select_mon=`echo $[$RANDOM%$mon_num+1]`
    IP=`echo "$mon_ip" | sed 's/ /\n/g' |sed -n "$select_mon"p`
    NAME=$user
    PASSWORD=$password
    token_id=`curl -s POST "http://$IP:8056/v1/auth/tokens" -H "accept: application/json" -H "Content-Type: application/json" -d "{\"auth\":{\"identity\":{\"token\":{\"uuid\":\"string\"},\"password\":{\"user\":{\"id\":0,\"password\":\"${PASSWORD}\",\"email\":\"string\",\"name\":\"${NAME}\"}}}}}" | ./json.sh -l -p -b | grep -E "token\"\,\"uuid" | awk -F '"' '{print $6}'`
    status_str=`curl -s GET "http://$IP:8056/v1/emails/config" -H "accept: application/json" -H "Xms-Auth-Token:$token_id" | ./json.sh -l -b -p`
    status=`echo "$status_str" | grep -E "email_config\"\,\"enabled" | awk -F " " '{print $2}'`
    if [[ "$status" == "true" ]];then
        echo "Normal:存储配置了邮箱服务器"
    elif [[ "$status" == "false" ]] || [[ "$status_str" =~ "null" ]];then
        echo "Urgent:存储没有配置邮箱服务器"
    fi
    echo ""
}


check_cephEmail
