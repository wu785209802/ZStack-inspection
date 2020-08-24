#!/bin/bash

zstack-cli LogInByAccount accountName=admin password=$1

export mysql_cmd=$(echo "mysql -uzstack -p${zs_sql_pwd} -e")
