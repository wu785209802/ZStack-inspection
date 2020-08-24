#########################################################################
# File Name: check_host.sh
# Author: wuqiuyang
# mail: qiuyang.wu@zstack.io
# Created Time: 2020-07-04
#########################################################################
#!/bin/bash
export PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/root/bin
source /etc/profile
PROGPATH=`echo $0 | sed -e 's,[\\/][^\\/][^\\/]*$,,'`
[ -f $PROGPATH ] && PROGPATH="."
LOGPATH="$PROGPATH/log"
[ -e $LOGPATH ] || mkdir $LOGPATH
RESULTFILE="$LOGPATH/HostDailyCheck-`hostname`-`date +%Y%m%d`.txt"

function check_kvmagent(){
  echo "************** check zstack-kvmagent.service status **************"
  kvmagent_str=`systemctl status zstack-kvmagent`
  kvmagent_status=`echo "$kvmagent_str" | grep "Active" | awk -F  " " '{print $2}'`
  echo "zstack-kvmagent.service:" "$kvmagent_status"
  echo ""
}

function check_libvirtd(){
  echo "****************** check libvirtd.service status *****************"
  libvirtd_str=`systemctl status libvirtd`
  libvirtd_status=`echo "$libvirtd_str" | grep "Active" | awk -F  " " '{print $2}'`
  echo "libvirtd.service:" "$libvirtd_status"
  echo ""
}

function check_chronyc(){
  echo "************************* check chronyc **************************"
  if [ `pgrep chronyd` ];then
    echo ""
    chronyc sources -v
    echo ""
    echo "Chrony服务配置:"
    cat /etc/chrony.conf|grep -v "^#"|tr -s '\n'
  	chronyc sources -v | grep ? | grep -v unreachable
	  if [ $? -eq 0 ];then echo Chrony_server_is_unreachable_please_check;fi
  elif [ `pgrep ntp` ];then
    echo ""
    ntpq -np
    echo ""
    echo "NTP服务配置:"
    cat /etc/ntp.conf|grep -v ^# |tr -s '\n'
  fi
  echo ""
  echo '系统时间:'
  timedatectl
  hwclock
  echo ""
}

main(){
  check_kvmagent 
  check_libvirtd 
  check_chronyc 
	echo "检查结果：$RESULTFILE"
}

main > $RESULTFILE
