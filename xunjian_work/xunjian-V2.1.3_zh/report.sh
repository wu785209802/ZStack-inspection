# cpu负载率
cpu_load=$(zstack-cli GetMetricData metricName='CPUAllUsedUtilization' offsetAheadOfCurrentTime=310 period=10 namespace=ZStack/Host | grep value | awk -F ' ' '{sum+=$2}END{print sum/NR}')
# 内存负载率
mem_load=$(zstack-cli GetMetricData metricName='MemoryUsedInPercent' offsetAheadOfCurrentTime=310 period=10 namespace=ZStack/Host | grep value | awk -F ' ' '{sum+=$2}END{print sum/NR}')
# 网络吞吐量--发送
net_load_out=$(zstack-cli GetMetricData metricName='NetworkAllOutBytes' offsetAheadOfCurrentTime=310 period=10 namespace=ZStack/Host | grep value | awk -F ' ' '{sum+=$2}END{print sum/NR/1024}')
# 网络吞吐量--接收
net_load_in=$(zstack-cli GetMetricData metricName='NetworkAllInBytes' offsetAheadOfCurrentTime=310 period=10 namespace=ZStack/Host | grep value | awk -F ' ' '{sum+=$2}END{print sum/NR/1024}')
# 磁盘IO
disk_load_write=$(zstack-cli GetMetricData metricName='DiskAllWriteBytes' offsetAheadOfCurrentTime=310 period=10 namespace=ZStack/Host  | grep value | awk -F ' ' '{sum+=$2}END{print sum/NR/1024}')
# 磁盘IO
disk_load_read=$(zstack-cli GetMetricData metricName='DiskAllReadBytes' offsetAheadOfCurrentTime=310 period=10 namespace=ZStack/Host  | grep value | awk -F ' ' '{sum+=$2}END{print sum/NR/1024}')
echo "cpu负载率:$cpu_load %"  
echo "内存负载率:$mem_load %"  
echo "网络吞吐量--发送:$net_load_out KB"  
echo "网络吞吐量--接收:$net_load_in KB" 
echo "磁盘IO--写:$disk_load_write KB"  
echo "磁盘IO--读:$disk_load_read KB" 

