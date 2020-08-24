import os,sys
import logging

def ssh_info_generate(cluster_uuid_list=[]):
	query1 = 'echo "select managementIp from HostVO where hypervisorType = \'KVM\' AND status=\'Connected\' '
	query2 = ';"| mysql -u zstack -pzstack.password zstack|grep -v managementIp'
	query = query1 + query2
	#mysql select statement
	if len(cluster_uuid_list):
		insert = ' and clusterUuid = \'' + cluster_uuid_list[0] + '\''
	if len(cluster_uuid_list) == 1 and cluster_uuid_list != 'all':
		query = query1 + insert + query2
	if len(cluster_uuid_list) > 1:		
		for index in range(1,len(cluster_uuid_list)):
			insert = insert + ' or clusterUuid = \'' + cluster_uuid_list[index] + '\''
		query = query1 + insert + query2
	
	#get_host_ips_str
	#host_ip_list = os.popen('echo "select managementIp from HostVO where hypervisorType = \'KVM\';"| mysql -u zstack -pzstack.password zstack|grep -v managementIp').read()
	host_ip_list = os.popen(query).read()
	host_ips = host_ip_list.split("\n")[:-1]

	#get_host_usernames_str
	host_username_list = os.popen('echo "select username,password,port from KVMHostVO;"| mysql -u zstack -pzstack.password zstack|grep -v username').read()
	host_usernames_list = host_username_list.split("\n")
	host_usernames = []
	for host_username in host_usernames_list:
		host_usernames.append(host_username.split("\t"))
	host_usernames = host_usernames[:-1]
	#same_len
	if len(host_usernames) < len(host_ips):
		Dvalue = len(host_ips) - len(host_usernames)
		while Dvalue > 0:
			host_usernames.append(["",""])
			Dvalue -= 1

	#create_kv_username_password
	count = 0
	userpassword_kvs = []
	while count < len(host_ips):
		userpassword_kvs.append("".join(host_ips[count]+" ansible_ssh_user=" + host_usernames[count][0] + " ansible_ssh_private_key_file=/usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa ansible_ssh_port=" + host_usernames[count][2] + " ansible_sudo_pass=" + host_usernames[count][1]))
		count += 1
	#mn_dump
	#if len(host_ips) > 1:
	#	os.system("bash crontab_dump.sh %s %s" % (host_ips[1], host_usernames[1][1]))
	kvs_str = "\n".join(userpassword_kvs)
	return kvs_str

def ssh_info(query):
	#query = 'echo "select hostname,username,sshPort,password from ImageStoreBackupStorageVO;\"|mysql -u zstack -pzstack.password zstack|grep -v hostname'
	#query = 'echo "select hostname,sshUsername,sshPort,sshPassword from CephPrimaryStorageMonVO;\"|mysql -u zstack -pzstack.password zstack|grep -v hostname'
	
	ssh_info = os.popen(query).read().split("\n")[:-1]
	
	count = 0
	userpassword_kvs = []
	while count < len(ssh_info):
		userpassword_kvs.append("".join(ssh_info[count].split("\t")[0]+" ansible_ssh_user=" +  ssh_info[count].split("\t")[1] + " ansible_ssh_private_key_file=/usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa ansible_ssh_port=" + ssh_info[count].split("\t")[2] + " ansible_sudo_pass=" + ssh_info[count].split("\t")[3]))
        	count += 1

	kvs_str = "\n".join(userpassword_kvs)
	return kvs_str
	#query2 = ';"| mysql -u zstack -pzstack.password zstack|grep -v managementIp'

def mn_ssh_info():
	query='echo "select hostname from ManagementNodeVO;\"|mysql -u zstack -pzstack.password zstack|grep -v hostname'
	ssh_info = os.popen(query).read().split("\n")[:-1]
	sshPort = os.popen("netstat -tulnp | grep sshd | grep -v tcp6 | awk  '{print $4}' | awk -F ':' '{print $2}'").read().split("\n")[:-1]
	count = 0
	userpassword_kvs = []
	while count < len(ssh_info):
		userpassword_kvs.append("".join(ssh_info[count] + " ansible_ssh_user=root" + " ansible_ssh_private_key_file=/usr/local/zstack/apache-tomcat/webapps/zstack/WEB-INF/classes/ansible/rsaKeys/id_rsa ansible_ssh_port=" + sshPort[0] + " ansible_sudo_pass=password"))
		count += 1

	kvs_str = "\n".join(userpassword_kvs)
	return kvs_str

def get_cluster_uuid_list():
	cluster_uuid_list = []
	if len(sys.argv) == 2:
		if sys.argv[1] != 'all':
			for cluster_uuid in sys.argv[1].split(","):
				cluster_uuid_list.append(cluster_uuid)
	return cluster_uuid_list

if __name__ == '__main__':
	try:
		file_asbc = open('ansible.conf','w')
		file_asbc.write(ssh_info_generate(get_cluster_uuid_list()) + "\n")
		file_asbc.write(ssh_info('echo "select hostname,username,sshPort,password from ImageStoreBackupStorageVO;\"|mysql -u zstack -pzstack.password zstack|grep -v hostname') + "\n")
		file_asbc.write(ssh_info('echo "select hostname,sshUsername,sshPort,sshPassword from CephPrimaryStorageMonVO ;\"|mysql -u zstack -pzstack.password zstack|grep -v hostname') + "\n")
		file_asbc.write(mn_ssh_info())
	#	os.system('cp ansible.conf ansible.conf.bak && cat ansible.conf.bak|sort -u >ansible.conf && rm -f ansible.conf.bak')
	except Exception as e:
		print logging.exception(e)
	finally:
		file_asbc.close()
	# os.system("sort -k2n inventory|uniq")
