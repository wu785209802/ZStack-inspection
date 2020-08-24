#!/bin/bash

zs_sql_pwd_encrypt=$(grep DB.password /usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/zstack.properties | awk '{print $3}')
export zs_sql_pwd=`python ./aes.py $zs_sql_pwd_encrypt`
echo $zs_sql_pwd
