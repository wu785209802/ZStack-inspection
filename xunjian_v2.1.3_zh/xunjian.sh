#!/bin/sh
. ./.env
DATE=$(date +%Y%m%d)
DATE_START=$(date +%s)
check_date=`date +%Y%m%d%H%M%S`
case_names=(check_host check_MN get_warn_info)
#num=${#case_names[*]}

usage(){
	echo "Usage: bash $0 -p [MN_admin_password]"
	echo "Usage: bash $0 -s [Two-factorverificationcode] -p [MN_admin_password]"
}
# 进度条展示
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
        echo -en "\e[1;0;m"
}

# 检查登录状态
 echo '----------------------------------------------------------------------------------'
 echo '1. 检查登录状态'
 echo '----------------------------------------------------------------------------------'
 if [ $# -eq 0 ];then
    usage && exit 10
 elif [ $# -eq 2 -o $# -eq 4 ];then
    while getopts ":s:p:a:" opt;
    do
        case $opt in
        s )
		authenticate="systemTags=twofatoken::${OPTARG}"
	;;
	p )
             #sudo sed -i "s/^user_password=.*/user_password=\'$OPTARG\'/g" getInfo.sh
             zstack-cli LogInByAccount accountName=admin password=${OPTARG} $authenticate > ./session.log 3>&1
             if [ $? -ne 0 ];then
                	error_code=0
			cat session.log |awk -F "details" '{print$2}'|grep "wrong account name or password" >/dev/null 2>&1 && error_code=1
			cat session.log |awk -F "details" '{print$2}'|grep "附加认证失败" >/dev/null 2>&1 && error_code=2
			cat session.log |awk -F "details" '{print$2}'|grep "Login sessions hit limit of max allowed concurrent login sessions" >/dev/null 2>&1 && error_code=3
			if [ $error_code -eq 1 ];then
				echo "密码错误，请检查!" && exit 11
			elif  [ $error_code -eq 2 ];then
				echo "双因子验证失败，请检查登陆参数!" && exit 11
			elif [ $error_code -eq 3 ];then
				echo "登陆失败，已超过admin最大登录会话数!" && exit 11
			else
				echo "登陆error_code未收录，请使用cat ./session.log查看错误原因" && exit 11
			fi
	     else
		session_uuid=$(grep uuid ./session.log | awk -F '"' '{print $4}')
		echo "session_uuid=${session_uuid}" >> ./.env
		rm -f ./session.log >> /dev/null 2>&1
             fi
	     #rm -f ./session.log >> /dev/null 2>&1
             ;;

         c )
             sudo python ./ssh_info.py $OPTARG
             ;;

          ? )
             usage && exit 13
             ;;
        esac
    done
 else
    usage && exit 12
 fi
# 同步zstack密码到脚本-->物理机巡检/管理节点巡检
# sed -i "s/zstack.password/${zs_sql_pwd}/" ./query_info.sql
 sed -i "s/zstack.password/${zs_sql_pwd}/" ./ssh_info.py
 sed -i "s/zstack.password/${zs_sql_pwd}/" ./getInfo.sh
 sed -i "s/zstack.password/${zs_sql_pwd}/" ./xunjian.sh
# 检查会话数
 session_nums=$(zstack-cli QueryGlobalConfig name=session.maxConcurrent fields=value | grep -oE '[0-9]+')
 used_session_nums=$(echo "SELECT COUNT(*) FROM SessionVO WHERE accountUuid=(SELECT uuid FROM AccountVO WHERE name='admin');"|mysql -uzstack -pzstack.password zstack | sed -n '2p')
 available_session_nums=$(($session_nums-$used_session_nums))
 if [ "$available_session_nums" -lt "10" ];then
    echo '无足够的会话数，请稍后再试'
    exit 2
 fi


# 检查日志目录
if [ -d "$LOG_PATH/log" ];then
	ls $LOG_PATH/log/* >> /dev/null 2>&1
	if [ "$?" = "0" ];then
		backup_dir=$(cat /proc/sys/kernel/random/uuid)
		mkdir -p /tmp/$backup_dir
		mv $LOG_PATH/log/* /tmp/$backup_dir
		echo "${LOG_PATH}/log 文件已备份到/tmp/${backup_dir}" >> $LOG_PATH/log/zs_check.log 2>&1
	fi
else
	mkdir -p $LOG_PATH/log
fi
echo "执行结果:    成功！用时：$(($(date +%s)-$DATE_START))秒"
# 物理机巡检
function check_host(){
 echo '----------------------------------------------------------------------------------'
	echo '2. 物理机巡检'
 echo '----------------------------------------------------------------------------------'
	DATE_START=$(date +%s)
  # 传入本地存储url
  localPsPath=$($mysql_cmd "use zstack;SELECT CONCAT(hv.managementIp,':',ps.url) FROM PrimaryStorageVO ps,PrimaryStorageClusterRefVO psc,HostVO hv WHERE ps.uuid = psc.primaryStorageUuid AND psc.clusterUuid = hv.clusterUuid AND ps.type = 'LocalStorage' ORDER BY hv.managementIp;" -N | xargs | sed 's/\//,/g')
  sed -i "s/^localPsPath=.*/localPsPath=\'$localPsPath\'/g" ./check-host.sh
# 修改ssh参数
	if [ ! -f '~/.ssh/config' ];then
		echo 'StrictHostKeyChecking=no' > ~/.ssh/config
	fi
	sudo python ssh_info.py > /dev/null 2>&1 && sudo ansible-playbook check-host.yaml -i ./ansible.conf | grep fatal | tee -a $LOG_PATH/log/check_err.log > /dev/null 2>&1 &
	while true;do
		ps -ef | egrep 'ssh_info.py|ansible-playbook|check-host.yaml'  | grep -v grep > /dev/null 2>&1
		if [ $? -eq 0 ];then
			progress
		        DATE_FINISH=$(date +%s)
		        RUN_TIME=$(($DATE_FINISH-$DATE_START))
			if [ $RUN_TIME -gt 1500 ];then
				ans_pro=$(ps -ef | grep '[a]nsible-playbook check-host.yaml' | awk '{print $2}')
				if [ "$ans_pro" ];then kill $ans_pro && echo '物理机巡检失败，请检查' && exit 80;fi
			fi
		else
			ls /tmp/log 2>/dev/null| grep -oE "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}" >> /dev/null 2>&1
			if [ $? -eq 0 ];then
				cd /tmp/log && mv -n `ls | grep -oE "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}"` $LOG_PATH/log && cd - > /dev/null 2>&1
			fi
			break
		fi
	done
sed -i "s/^localPsPath=.*/localPsPath=\'\'/g" ./check-host.sh
}
# 如果有Ceph环境，则提示进行巡检。若MON节点与管理节点共用，可直接进行巡检；否则，需拷贝Ceph巡检脚本到企业版Ceph的MON节点进行巡检
function chkCeph(){
        monAddrs=$(zstack-cli QueryCephPrimaryStorage | grep monAddr | grep -oE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}')
        if [ -n "${monAddrs}" ];then
#                echo '检测到平台使用了Ceph类型的主存储,请使用check-ceph.sh脚本进行巡检' && sleep 5
#               若MON节点与管理节点共用，且使用了Ceph主存储，则提示是否同时进行Ceph巡检
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
							echo -e "请输入企业版Ceph的用户名:"
							read username
							echo -e "请输入企业版Ceph的密码:"
							read password
                                                        bash ./check-ceph.sh $username $password &&sleep 3 &&cp ${CEPH_LOG_PATH}/ceph_check.${dd}.tar.gz $LOG_PATH/log && return
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
													echo -e "请输入企业版Ceph的用户名:"
													read username
													echo -e "请输入企业版Ceph的密码:"
													read password
													ssh -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa $selectmonip bash -s < check-ceph.sh $username $password
													scp -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa $selectmonip:${CEPH_LOG_PATH}/ceph_check.${dd}.tar.gz  $LOG_PATH/log >>/dev/null 2>&1
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

# 管理节点巡检
function check_MN(){
 echo '----------------------------------------------------------------------------------'
 echo '3. 管理节点巡检'
 echo '----------------------------------------------------------------------------------'
#	echo '[remote_hosts]' > ./remote_hosts.cfg 2>&1
	. ./.env

#	mysql -uzstack  -pzstack.password zstack -e 'select hostName from ManagementNodeVO where hostName not in (select managementIp from HostVO)' | grep -v hostName >> ./remote_hosts.cfg 2>&1
#	ansible-playbook check-host.yaml -i ./remote_hosts.cfg > /dev/null 2>&1 &
	sudo bash check-mn.sh | tee -a /$LOG_PATH/log/management.log >>/dev/null 2>&1 &
	#sudo bash check_password.sh | tee -a /$LOG_PATH/log/management.log >>/dev/null 2>&1 &
	sudo bash getInfo.sh >>/dev/null 2>&1 &
	sudo bash mn_report.sh >>/dev/null 2>&1 &
	while true;do
		ps -ef | egrep 'check-mn|getInfo|mn_report'  | grep -v grep > /dev/null 2>&1
		if [ $? -eq 0 ];then
			progress
		else
#			ls /tmp/log | grep -oE "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}" >> /dev/null 2>&1
#			if [ $? -eq 0 ];then
#				cd /tmp/log && mv -n `ls | grep -oE "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}"` $LOG_PATH/log && cd - > /dev/null 2>&1
#                        fi
#			rm -f ./remote_hosts.cfg
			break
		fi
	done
	chkCeph
#
}

# 获取告警信息
function get_warn_info(){
 echo '----------------------------------------------------------------------------------'
 echo '4. 收集巡检信息'
 echo '----------------------------------------------------------------------------------'
	# 生成管理节点巡检报告
	. ./.env

    #    cp $LOG_PATH/log/management.log $LOG_PATH/log/management.log.bak
     #   cat $LOG_PATH/log/management.log | sed 's/ /,/g' | sed 's/\t/,/g' | sed 's/:/,/g' | sed 's/,,*/,/g' | sed 's/############################/,/g' > $management_report
      #  sed -i 's/9527/ /g' $management_report
	# 物理机报告合并
#	find $LOG_PATH/log/ -name HostReport*.csv | xargs cat >> $management_report
#	iconv -f UTF8 -t GBK $management_report -o $management_report

	sudo cd $LOG_PATH/log/
	sudo bash analyze.sh $LOG_PATH/log >> $LOG_PATH/log/management.log  2>&1 &
	DATE_FINISH=$(date +%s)
	RUN_TIME=$(($DATE_FINISH-$DATE_START))
	# 9527为空格标记符号
        echo "##################################备份任务检查####################################" >> $LOG_PATH/log/management.log
	echo -e "管理节点备份任务:\n$(sudo crontab -l | grep "dump_mysql" | grep "zstack-ctl")"  >> $LOG_PATH/log/management.log
	if [ -f /etc/zsha2.conf ];then 
          echo '管理节点备份任务(Peer):'
          peer_ip=`cat /etc/zsha2.conf | grep peer | awk -F '"' '{print $4}'` 
          ssh -i /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa ${peer_ip} "crontab -l" | grep "dump_mysql" | grep "zstack-ctl" >> $LOG_PATH/log/management.log 
        fi

        #echo -e "\n############################ 物理机严重警告信息 ############################\n $(grep Urgent $LOG_PATH/log/ -ir|grep -v "物理机警告信息"|awk -F 'management.log:' '{print$2}')"
        echo -e "\n################################## 物理机严重警告信息 ############################ \n$(grep Urgent $LOG_PATH/log/management.log -ir)"
	if [ -f "$LOG_PATH/log/ceph_check.${dd}.tar.gz" ];then
			echo -e "\n############################# ceph企业版存储严重警告信息 ######################### \n$(zgrep -a Urgent $LOG_PATH/log/ceph_check.${dd}.tar.gz 2>/dev/null)"
	fi
	echo -e "\n################################### 物理机警告信息 ############################### \n$(cat $LOG_PATH/log/management.log |grep Urgent |grep -Ev "物理机上警告信息|xunjianlog")"|tee -a $LOG_PATH/log/management.log >>/dev/null
	find $LOG_PATH/log -name HostD* | xargs grep Important | awk -F '/log/' '{print $2}' | awk -F '/HostDailyCheck|.txt:' '{print $1,$NF}' | sort -k 2,2| uniq |tee -a $LOG_PATH/log/management.log >>/dev/null

	sudo echo -e "\n本次巡检用时"$RUN_TIME"秒" >> $LOG_PATH/log/management.log
	#cd $LOG_PATH/ && sudo tar -zcvf xunjianlog-${DATE}.tar.gz log > tardetail && sudo rm -rf tardetail && sudo rm -rf log &
	while true;do
                ps -ef | egrep 'analyze.sh'  | grep -v grep > /dev/null 2>&1
                if [ $? -eq 0 ];then
                        progress
                else
                        break
                fi
        done
}



# main
for i in ${case_names[@]};do
	start_date=$(date +%s)
	$i
	if [ $? == 0 ];then
		end_date=$(date +%s)
		run_time=$(($end_date-$start_date))
		echo "执行结果:    成功！用时: ${run_time}秒"
	else
		end_date=$(date +%s)
		run_time=$(($end_date-$start_date))
		echo "执行结果:    成功！用时: ${run_time}秒"
		echo "发现有部分异常，请检查巡检日志是否有错误！"
	fi
	sleep 1
done
#

# 登出当前session
function tar(){
Old_Pwd=$PWD
#cd $LOG_PATH/log && sudo tar czvf - * |openssl des3 -salt -k zstack.io | dd of=../xunjianlog-${DATE}.tar.gz > tardetail && sudo rm -rf tardetail && cd $LOG_PATH && sudo rm -rf log && cd $Old_Pwd
cd $LOG_PATH/log && sudo tar czvf - * |openssl des3 -salt -k zstack.io | dd of=../xunjianlog-${DATE}.tar.gz > tardetail && sudo rm -rf tardetail && cd $LOG_PATH && cd $Old_Pwd
}
tar >>/dev/null 2>&1
zstack-cli LogOut sessionUuid=$session_uuid >>/dev/null 2>&1
# 恢复脚本默认密码
# sed -i "s/${zs_sql_pwd}/zstack.password/" ./query_info.sql
sed -i "s/${zs_sql_pwd}/zstack.password/" ./ssh_info.py
sed -i "s/${zs_sql_pwd}/zstack.password/" ./getInfo.sh
sed -i "s/${zs_sql_pwd}/zstack.password/" ./xunjian.sh

echo -e "\n巡检结束, 巡检结果存放于:$LOG_PATH/xunjianlog-${DATE}.tar.gz"
