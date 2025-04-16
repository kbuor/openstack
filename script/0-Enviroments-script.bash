#!/bin/bash
# Prepare OS
echo '10.0.0.11 controller' >> /etc/hosts
echo '10.0.0.31 compute1' >> /etc/hosts
apt update -y && apt upgrade -y
apt install python3-openstackclient -y
echo 'PasswordAuthentication yes' > 60-cloudimg-settings.conf
systemctl restart ssh

# Install Chrony
apt install chrony -y
cat <<EOF > /etc/chrony/chrony.conf
confdir /etc/chrony/conf.d
sourcedir /run/chrony-dhcp
sourcedir /etc/chrony/sources.d
keyfile /etc/chrony/chrony.keys
driftfile /var/lib/chrony/chrony.drift
ntsdumpdir /var/lib/chrony
logdir /var/log/chrony
maxupdateskew 100.0
rtcsync
makestep 1 3
leapsectz right/UTC
server 0.vn.pool.ntp.org iburst
allow 10.0.0.0/24
EOF
systemctl enable chrony
systemctl restart chrony

# Install SQL Database
apt install mariadb-server python3-pymysql -y
cat <<EOF > /etc/mysql/mariadb.conf.d/99-openstack.cnf
[mysqld]
bind-address = 10.0.0.11

default-storage-engine = innodb
innodb_file_per_table = on
max_connections = 4096
collation-server = utf8_general_ci
character-set-server = utf8
EOF
systemctl enable mysql
systemctl restart mysql

# Install Message Queue
apt install -y rabbitmq-server
rabbitmqctl add_user openstack Passw0rd
rabbitmqctl set_permissions openstack ".*" ".*" ".*"
systemctl enable rabbitmq-server
systemctl restart rabbitmq-server

# Install Memcached
apt install -y memcached python3-memcache
cat <<EOF > /etc/memcached.conf
-d
logfile /var/log/memcached.log
-m 64
-p 11211
-u memcache
-l 10.0.0.11
-P /var/run/memcached/memcached.pid
EOF
systemctl enable memcached
systemctl restart memcached

# Install Etcd
apt install -y etcd-server
cat <<EOF > /etc/default/etcd
ETCD_NAME="controller"
ETCD_DATA_DIR="/var/lib/etcd"
ETCD_INITIAL_CLUSTER_STATE="new"
ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster-01"
ETCD_INITIAL_CLUSTER="controller=http://10.0.0.11:2380"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://10.0.0.11:2380"
ETCD_ADVERTISE_CLIENT_URLS="http://10.0.0.11:2379"
ETCD_LISTEN_PEER_URLS="http://0.0.0.0:2380"
ETCD_LISTEN_CLIENT_URLS="http://10.0.0.11:2379"
EOF
systemctl enable etcd
systemctl restart etcd

clear

echo "VUI LONG CHAY LENH INTI MYSQL DATABASE"
echo ""
mysql_secure_installation
