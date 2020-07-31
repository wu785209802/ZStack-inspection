#!/bin/bash
zstack-cli LogInByAccount accountName=admin password=zstackts
export mysql_cmd=$(echo "mysql -uzstack -pzstack.password -e")
