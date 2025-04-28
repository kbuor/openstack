# Run on Controller
## Prepare OS
---
1. Set hostname
```shell
hostnamectl set-hostname controller01.openstack.local
```
2. Configure networking using Netplan
```shell
rm -rf /etc/netplan/*
cat <<'EOF' > /etc/netplan/openstack.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    ens192:
      dhcp4: no
      dhcp6: no
      addresses:
        - 10.21.4.11/24
      routes:
        - to: default
          via: 10.21.4.1
      nameservers:
        addresses:
          - 10.21.4.100
EOF
netplan apply
```
3. Configure Nameserver
```shell
systemctl enable --now systemd-resolved
systemctl restart systemd-resolved
ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
```
4. Update Linux
```shell
apt update -y && apt upgrade -y
reboot
```
## Install Time Server
---
### Install Chrony Server
```shell
apt install chrony -y
```
```shell
cat <<'EOF' > /etc/chrony/chrony.conf
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
```
```shell
systemctl enable --now chrony
systemctl restart chrony
```
## Install Databases
---
### Install SQL Database (MySQL/MariaDB)
```shell
apt install -y mariadb-server python3-pymysql
```
```shell
cat <<'EOF' > /etc/mysql/mariadb.conf.d/99-openstack.cnf
[mysqld]
bind-address = 10.21.4.11

default-storage-engine = innodb
innodb_file_per_table = on
max_connections = 4096
collation-server = utf8_general_ci
character-set-server = utf8
EOF
```
```shell
systemctl enable --now mysql
systemctl restart mysql
```
```shell
mysql_secure_installation
```
### Install In-memory Database (Memcached)
```shell
apt install -y memcached python3-memcache
```
```shell
cat <<'EOF' > /etc/memcached.conf
-d
logfile /var/log/memcached.log
-m 64
-p 11211
-u memcache
-l 10.21.4.11
-P /var/run/memcached/memcached.pid
EOF
```
```shell
systemctl enable --now memcached
systemctl restart memcached
```
### Install Key-Value Database (Etcd)
```shell
apt install -y etcd-server
```
```shell
cat <<'EOF' > /etc/default/etcd
ETCD_NAME="controller"
ETCD_DATA_DIR="/var/lib/etcd"
ETCD_INITIAL_CLUSTER_STATE="new"
ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster-01"
ETCD_INITIAL_CLUSTER="controller=http://10.21.4.11:2380"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://10.21.4.11:2380"
ETCD_ADVERTISE_CLIENT_URLS="http://10.21.4.11:2379"
ETCD_LISTEN_PEER_URLS="http://0.0.0.0:2380"
ETCD_LISTEN_CLIENT_URLS="http://10.21.4.11:2379"
EOF
```
```shell
systemctl enable --now etcd
systemctl restart etcd
```
## Install Message Queue
---
### Install RabbitMQ Server
```shell
apt install -y rabbitmq-server
```
```shell
rabbitmqctl add_user openstack OpenStack
rabbitmqctl set_permissions openstack ".*" ".*" ".*"
```
```shell
systemctl enable --now rabbitmq-server
systemctl restart rabbitmq-server
```
## Request SSL Wildcard Certificates
---
### Install Certbot
```shell
apt install -y certbot
```
### Request Certificate
```shell
certbot certonly \
--agree-tos \
--manual \
--preferred-challenges dns \
-m admin@kbuor.io.vn \
-d *.kbuor.io.vn
```
```shell
mkdir -p /etc/ssl/openstack
cp /etc/letsencrypt/live/kbuor.io.vn/fullchain.pem /etc/ssl/openstack/openstack.crt
cp /etc/letsencrypt/live/kbuor.io.vn/privkey.pem /etc/ssl/openstack/openstack.key
```
# Run on Compute Node
## Prepare OS
---
1. Set hostname
```shell
hostnamectl set-hostname compute01.openstack.local
```
2. Configure networking using Netplan
```shell
rm -rf /etc/netplan/*
cat <<'EOF' > /etc/netplan/openstack.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    ens192:
      dhcp4: no
      dhcp6: no
      addresses:
        - 10.21.4.101/24
      routes:
        - to: default
          via: 10.21.4.1
      nameservers:
        addresses:
          - 10.21.4.100
EOF
netplan apply
```
3. Configure Nameserver
```shell
systemctl enable --now systemd-resolved
systemctl restart systemd-resolved
ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
```
4. Update Linux
```shell
apt update -y && apt upgrade -y
reboot
```
## Install Time Server
---
### Install Chrony Server
```shell
apt install chrony -y
```
```shell
cat <<'EOF' > /etc/chrony/chrony.conf
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
server controller01.openstack.local iburst
EOF
```
```shell
systemctl enable --now chrony
systemctl restart chrony
```
# Run on Neutron Node
## Prepare OS
---
1. Set hostname
```shell
hostnamectl set-hostname neutron01.openstack.local
```
2. Configure networking using Netplan
```shell
rm -rf /etc/netplan/*
cat <<'EOF' > /etc/netplan/openstack.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    ens192:
      dhcp4: no
      dhcp6: no
      addresses:
        - 10.21.4.61/24
      routes:
        - to: default
          via: 10.21.4.1
      nameservers:
        addresses:
          - 10.21.4.100
EOF
netplan apply
```
3. Configure Nameserver
```shell
systemctl enable --now systemd-resolved
systemctl restart systemd-resolved
ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
```
4. Update Linux
```shell
apt update -y && apt upgrade -y
reboot
```
## Install Time Server
---
### Install Chrony Server
```shell
apt install chrony -y
```
```shell
cat <<'EOF' > /etc/chrony/chrony.conf
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
server controller01.openstack.local iburst
EOF
```
```shell
systemctl enable --now chrony
systemctl restart chrony
```
