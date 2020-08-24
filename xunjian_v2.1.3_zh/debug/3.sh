#!/bin/bash

 function auto_mount_check(){
 	# 镜像服务器是否单独挂载
 	echo '############################镜像服务器是否单独挂载检查############################'
	im_bs_mount_info=$(zstack-cli QueryImageStoreBackupStorage fields=hostname,url | egrep 'hostname|url' | awk -F '"' '{print $4}' |sed -n '{N;s/\n/ /p}' |sed 's/ /,/g')
	if [ -n "${im_bs_mount_info}" ];then
		for bs_info in $(echo $im_bs_mount_info | sed 's/ /\n/g');do
			host_IP=$(echo $bs_info | awk -F ',' '{print $1}')
			mount_point=$(echo $bs_info | awk -F ',' '{print $2}')
			ssh $host_IP -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa grep $mount_point /etc/rc.local >> /dev/null 2>&1
			if [ $? -ne 0 ];then
				echo "镜像服务器:${host_IP}上${mount_point}与 / 共用"
				# echo "镜像服务器:${host_IP}上${mount_point}未单独挂载(若与/共用，请忽略该消息)"
			else
				ssh $host_IP -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa df -Th 2> /dev/null | grep $mount_point > /dev/null 2>&1
				if [ $? -ne 0 ];then
					echo "Urgent: 镜像服务器:${host_IP}上${mount_point}未单独挂载，请检查！"
				else
					echo "镜像服务器:${host_IP}上${mount_point}已单独挂载"
				fi
			fi
		done
	else
		echo '未使用镜像服务器'
	fi
}
auto_mount_check
