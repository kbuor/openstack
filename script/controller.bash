#!/bin/bash

hostnamectl set-hostname controller
rm -rf /etc/netplan/50*
cat <<'EOF' > /etc/netplan/99-netcfg-vmware.yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    ens224: {}
    ens192:
      dhcp4: no
      dhcp6: no
      addresses:
        - 10.0.0.11/24
      routes:
        - to: default
          via: 10.0.0.1
      nameservers:
        addresses:
          - 8.8.8.8
          - 1.1.1.1
EOF
netplan apply

echo "10.0.0.31 compute1" >> /etc/hosts
echo "PasswordAuthentication yes" > /etc/ssh/sshd_config.d/60-cloudimg-settings.conf
systemctl restart ssh

apt update -y && apt upgrade -y
apt install chrony -y
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
systemctl enable --now chrony
systemctl restart chrony

apt install mariadb-server python3-pymysql -y
cat <<'EOF' > /etc/mysql/mariadb.conf.d/99-openstack.cnf
[mysqld]
bind-address = 10.0.0.11

default-storage-engine = innodb
innodb_file_per_table = on
max_connections = 4096
collation-server = utf8_general_ci
character-set-server = utf8
EOF
systemctl enable --now mysql
systemctl restart mysql
clear
mysql_secure_installation
clear
apt install -y rabbitmq-server
rabbitmqctl add_user openstack Passw0rd
rabbitmqctl set_permissions openstack ".*" ".*" ".*"
systemctl restart rabbitmq-server
systemctl enable rabbitmq-server

apt install -y memcached python3-memcache
cat <<'EOF' > /etc/memcached.conf
-d
logfile /var/log/memcached.log
-m 64
-p 11211
-u memcache
-l 10.0.0.11
-P /var/run/memcached/memcached.pid
EOF
systemctl enable --now memcached
systemctl restart memcached

apt install -y etcd-server
cat <<'EOF' > /etc/default/etcd
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
systemctl enable --now etcd
systemctl restart etcd

apt install -y python3-openstackclient

mysql <<EOF
CREATE DATABASE keystone;
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY 'Passw0rd';
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY 'Passw0rd';
EXIT;
EOF
apt install -y keystone
cat <<'EOF' > /etc/keystone/keystone.conf
[DEFAULT]
log_dir = /var/log/keystone
[application_credential]
[assignment]
[auth]
[cache]
[catalog]
[cors]
[credential]
[database]
connection = mysql+pymysql://keystone:Passw0rd@controller/keystone
[domain_config]
[endpoint_filter]
[endpoint_policy]
[extra_headers]
Distribution = Ubuntu
[federation]
[fernet_receipts]
[fernet_tokens]
[healthcheck]
[identity]
[identity_mapping]
[jwt_tokens]
[ldap]
[oauth1]
[oauth2]
[oslo_messaging_amqp]
[oslo_messaging_kafka]
[oslo_messaging_notifications]
[oslo_messaging_rabbit]
[oslo_middleware]
[oslo_policy]
[policy]
[profiler]
[receipt]
[resource]
[revoke]
[role]
[saml]
[security_compliance]
[shadow_users]
[token]
provider = fernet
[tokenless_auth]
[totp]
[trust]
[unified_limit]
[wsgi]
EOF
su -s /bin/sh -c "keystone-manage db_sync" keystone
keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
keystone-manage credential_setup --keystone-user keystone --keystone-group keystone
keystone-manage bootstrap --bootstrap-password Passw0rd \
  --bootstrap-admin-url http://controller:5000/v3/ \
  --bootstrap-internal-url http://controller:5000/v3/ \
  --bootstrap-public-url http://controller:5000/v3/ \
  --bootstrap-region-id RegionOne
cat <<'EOF' > /etc/apache2/apache2.conf
DefaultRuntimeDir ${APACHE_RUN_DIR}
ServerName controller
PidFile ${APACHE_PID_FILE}
Timeout 300
KeepAlive On
MaxKeepAliveRequests 100
KeepAliveTimeout 5
User ${APACHE_RUN_USER}
Group ${APACHE_RUN_GROUP}
HostnameLookups Off
ErrorLog ${APACHE_LOG_DIR}/error.log
LogLevel warn
IncludeOptional mods-enabled/*.load
IncludeOptional mods-enabled/*.conf
Include ports.conf
<Directory />
        Options FollowSymLinks
        AllowOverride None
        Require all denied
</Directory>
<Directory /usr/share>
        AllowOverride None
        Require all granted
</Directory>
<Directory /var/www/>
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
</Directory>
AccessFileName .htaccess
<FilesMatch "^\.ht">
        Require all denied
</FilesMatch>
LogFormat "%v:%p %h %l %u %t \"%r\" %>s %O \"%{Referer}i\" \"%{User-Agent}i\"" vhost_combined
LogFormat "%h %l %u %t \"%r\" %>s %O \"%{Referer}i\" \"%{User-Agent}i\"" combined
LogFormat "%h %l %u %t \"%r\" %>s %O" common
LogFormat "%{Referer}i -> %U" referer
LogFormat "%{User-agent}i" agent
IncludeOptional conf-enabled/*.conf
IncludeOptional sites-enabled/*.conf
EOF
systemctl enable --now apache2
systemctl restart apache2
export OS_USERNAME=admin
export OS_PASSWORD=Passw0rd
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL=http://controller:5000/v3
export OS_IDENTITY_API_VERSION=3
cat <<'EOF' > /root/admin-openrc
export OS_USERNAME=admin
export OS_PASSWORD=Passw0rd
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL=http://controller:5000/v3
export OS_IDENTITY_API_VERSION=3
EOF
source /root/admin-openrc
openstack project create --domain default --description "Service Project" service

mysql <<EOF
CREATE DATABASE glance;
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY 'Passw0rd';
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY 'Passw0rd';
EXIT;
EOF
source /root/admin-openrc
openstack user create --domain default --password 'Passw0rd' glance
openstack role add --project service --user glance admin
openstack service create --name glance --description "OpenStack Image" image
openstack endpoint create --region RegionOne image public http://controller:9292
openstack endpoint create --region RegionOne image internal http://controller:9292
openstack endpoint create --region RegionOne image admin http://controller:9292
apt install glance -y
cat <<'EOF' > /etc/glance/glance-api.conf
[DEFAULT]
enabled_backends=fs:file
[barbican]
[barbican_service_user]
[cinder]
[cors]
[database]
connection = mysql+pymysql://glance:Passw0rd@controller/glance
backend = sqlalchemy
[file]
[fs]
filesystem_store_datadir = /var/lib/glance/images/
[glance.store.http.store]
[glance.store.rbd.store]
[glance.store.s3.store]
[glance.store.swift.store]
[glance.store.vmware_datastore.store]
[glance_store]
default_backend = fs
[healthcheck]
[image_format]
disk_formats = ami,ari,aki,vhd,vhdx,vmdk,raw,qcow2,vdi,iso,ploop.root-tar
[key_manager]
[keystone_authtoken]
www_authenticate_uri  = http://controller:5000
auth_url = http://controller:5000
memcached_servers = controller:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = glance
password = Passw0rd
[os_brick]
[oslo_concurrency]
[oslo_limit]
[oslo_messaging_amqp]
[oslo_messaging_kafka]
[oslo_messaging_notifications]
[oslo_messaging_rabbit]
[oslo_middleware]
[oslo_policy]
[oslo_reports]
[paste_deploy]
flavor = keystone
[profiler]
[store_type_location_strategy]
[task]
[taskflow_executor]
[vault]
[wsgi]
EOF
openstack role add --user glance --user-domain Default --system all reader
su -s /bin/sh -c "glance-manage db_sync" glance
systemctl enable --now glance-api
systemctl restart glance-api
wget http://download.cirros-cloud.net/0.4.0/cirros-0.4.0-x86_64-disk.img
glance image-create --name "cirros" \
  --file cirros-0.4.0-x86_64-disk.img \
  --disk-format qcow2 --container-format bare \
  --visibility=public

mysql <<EOF
CREATE DATABASE placement;
GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'localhost' IDENTIFIED BY 'Passw0rd';
GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'%' IDENTIFIED BY 'Passw0rd';
EXIT;
EOF
openstack user create --domain default --password 'Passw0rd' placement
openstack role add --project service --user placement admin
openstack service create --name placement --description "Placement API" placement
openstack endpoint create --region RegionOne placement public http://controller:8778
openstack endpoint create --region RegionOne placement internal http://controller:8778
openstack endpoint create --region RegionOne placement admin http://controller:8778
apt install placement-api -y
cat <<'EOF' > /etc/placement/placement.conf
[DEFAULT]
[api]
auth_strategy = keystone
[cors]
[keystone_authtoken]
auth_url = http://controller:5000/v3
memcached_servers = controller:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = placement
password = Passw0rd
[oslo_middleware]
[oslo_policy]
[placement]
[placement_database]
connection = mysql+pymysql://placement:Passw0rd@controller/placement
[profiler]
EOF
su -s /bin/sh -c "placement-manage db sync" placement
systemctl enable --now apache2
systemctl restart apache2

mysql <<EOF
CREATE DATABASE nova_api;
CREATE DATABASE nova;
CREATE DATABASE nova_cell0;
GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'localhost' IDENTIFIED BY 'Passw0rd';
GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'%' IDENTIFIED BY 'Passw0rd';
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY 'Passw0rd';
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY 'Passw0rd';
GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'localhost' IDENTIFIED BY 'Passw0rd';
GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'%' IDENTIFIED BY 'Passw0rd';
EXIT;
EOF
openstack user create --domain default --password 'Passw0rd' nova
openstack role add --project service --user nova admin
openstack service create --name nova --description "OpenStack Compute" compute
openstack endpoint create --region RegionOne compute public http://controller:8774/v2.1
openstack endpoint create --region RegionOne compute internal http://controller:8774/v2.1
openstack endpoint create --region RegionOne compute admin http://controller:8774/v2.1
apt install nova-api nova-conductor nova-novncproxy nova-scheduler -y
cat <<'EOF' > /etc/nova/nova.conf
[DEFAULT]
my_ip = 10.0.0.11
transport_url = rabbit://openstack:Passw0rd@controller:5672/
log_dir = /var/log/nova
lock_path = /var/lock/nova
state_path = /var/lib/nova
[api]
auth_strategy = keystone
[api_database]
connection = mysql+pymysql://nova:Passw0rd@controller/nova_api
[barbican]
[barbican_service_user]
[cache]
[cinder]
[compute]
[conductor]
[console]
[consoleauth]
[cors]
[cyborg]
[database]
connection = mysql+pymysql://nova:Passw0rd@controller/nova
[devices]
[ephemeral_storage_encryption]
[filter_scheduler]
[glance]
api_servers = http://controller:9292
[guestfs]
[healthcheck]
[image_cache]
[ironic]
[key_manager]
[keystone]
[keystone_authtoken]
www_authenticate_uri = http://controller:5000/
auth_url = http://controller:5000/
memcached_servers = controller:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = nova
password = Passw0rd
[libvirt]
[metrics]
[mks]
[neutron]
[notifications]
[os_vif_linux_bridge]
[os_vif_ovs]
[oslo_concurrency]
lock_path = /var/lib/nova/tmp
[oslo_limit]
[oslo_messaging_amqp]
[oslo_messaging_kafka]
[oslo_messaging_notifications]
[oslo_messaging_rabbit]
[oslo_middleware]
[oslo_policy]
[oslo_reports]
[oslo_versionedobjects]
[pci]
[placement]
region_name = RegionOne
project_domain_name = Default
project_name = service
auth_type = password
user_domain_name = Default
auth_url = http://controller:5000/v3
username = placement
password = Passw0rd
[privsep]
[profiler]
[quota]
[remote_debug]
[scheduler]
[serial_console]
[service_user]
send_service_user_token = true
auth_url = http://controller:5000/v3
auth_strategy = keystone
auth_type = password
project_domain_name = Default
project_name = service
user_domain_name = Default
username = nova
password = Passw0rd
[spice]
[upgrade_levels]
[vault]
[vendordata_dynamic_auth]
[vmware]
[vnc]
enabled = true
server_listen = $my_ip
server_proxyclient_address = $my_ip
[workarounds]
[wsgi]
[zvm]
[cells]
enable = False
[os_region_name]
openstack =
EOF
su -s /bin/sh -c "nova-manage api_db sync" nova
su -s /bin/sh -c "nova-manage cell_v2 map_cell0" nova
su -s /bin/sh -c "nova-manage cell_v2 create_cell --name=cell1 --verbose" nova
su -s /bin/sh -c "nova-manage db sync" nova
su -s /bin/sh -c "nova-manage cell_v2 list_cells" nova
systemctl enable nova-api
systemctl enable nova-scheduler
systemctl enable nova-conductor
systemctl enable nova-novncproxy
systemctl restart nova-api
systemctl restart nova-scheduler
systemctl restart nova-conductor
systemctl restart nova-novncproxy
openstack compute service list --service nova-compute
su -s /bin/sh -c "nova-manage cell_v2 discover_hosts --verbose" nova

mysql <<EOF
CREATE DATABASE neutron;
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY 'Passw0rd';
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY 'Passw0rd';
EOF
openstack user create --domain default --password 'Passw0rd' neutron
openstack role add --project service --user neutron admin
openstack service create --name neutron --description "OpenStack Networking" network
openstack endpoint create --region RegionOne network public http://controller:9696
openstack endpoint create --region RegionOne network internal http://controller:9696
openstack endpoint create --region RegionOne network admin http://controller:9696
apt install -y neutron-server neutron-plugin-ml2 \
  neutron-openvswitch-agent neutron-l3-agent neutron-dhcp-agent \
  neutron-metadata-agent
cat <<'EOF' > /etc/neutron/neutron.conf
[DEFAULT]
core_plugin = ml2
service_plugins = router
transport_url = rabbit://openstack:Passw0rd@controller
auth_strategy = keystone
notify_nova_on_port_status_changes = true
notify_nova_on_port_data_changes = true
[agent]
root_helper = "sudo /usr/bin/neutron-rootwrap /etc/neutron/rootwrap.conf"
[cache]
[cors]
[database]
connection = mysql+pymysql://neutron:Passw0rd@controller/neutron
[designate]
[experimental]
[healthcheck]
[ironic]
[keystone_authtoken]
www_authenticate_uri = http://controller:5000
auth_url = http://controller:5000
memcached_servers = controller:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = neutron
password = Passw0rd
[nova]
auth_url = http://controller:5000
auth_type = password
project_domain_name = Default
user_domain_name = Default
region_name = RegionOne
project_name = service
username = nova
password = Passw0rd
[oslo_concurrency]
lock_path = /var/lib/neutron/tmp
[oslo_messaging_amqp]
[oslo_messaging_kafka]
[oslo_messaging_notifications]
[oslo_messaging_rabbit]
[oslo_middleware]
[oslo_policy]
[oslo_reports]
[oslo_versionedobjects]
[placement]
[privsep]
[profiler]
[quotas]
[ssl]
EOF
cat <<'EOF' > /etc/neutron/plugins/ml2/ml2_conf.ini
[DEFAULT]
[ml2]
type_drivers = flat,vlan,vxlan
tenant_network_types = vxlan
mechanism_drivers = openvswitch,l2population
extension_drivers = port_security
[ml2_type_flat]
flat_networks = provider
[ml2_type_geneve]
[ml2_type_gre]
[ml2_type_vlan]
[ml2_type_vxlan]
vni_ranges = 1:1000
[ovn]
[ovn_nb_global]
[ovs]
[ovs_driver]
[securitygroup]
[sriov_driver]
EOF
cat <<'EOF' > /etc/neutron/plugins/ml2/openvswitch_agent.ini
[DEFAULT]
[agent]
tunnel_types = vxlan
l2_population = true
[dhcp]
[metadata]
[network_log]
[ovs]
bridge_mappings = provider:br-ex
local_ip = 10.0.0.11
[securitygroup]
enable_security_group = true
firewall_driver = openvswitch
EOF
ovs-vsctl add-br br-ex
ovs-vsctl add-port br-ex ens224
cat <<'EOF' > /etc/netplan/99-netcfg-vmware.yaml
network:
  version: 2
  renderer: networkd
  bridges:
    br-ex:
      interfaces: [ens224]
      dhcp4: yes
  ethernets:
    ens224: {}
    ens192:
      dhcp4: no
      dhcp6: no
      addresses:
        - 10.0.0.11/24
      routes:
        - to: default
          via: 10.0.0.1
      nameservers:
        addresses:
          - 8.8.8.8
          - 1.1.1.1
EOF
netplan apply
cat <<'EOF' > /etc/neutron/l3_agent.ini
[DEFAULT]
interface_driver = openvswitch
[agent]
[metadata_rate_limiting]
[network_log]
[ovs]
EOF
cat <<'EOF' > /etc/neutron/dhcp_agent.ini
[DEFAULT]
interface_driver = openvswitch
dhcp_driver = neutron.agent.linux.dhcp.Dnsmasq
enable_isolated_metadata = true
[agent]
[metadata_rate_limiting]
[ovs]
EOF
cat <<'EOF' > /etc/neutron/metadata_agent.ini
[DEFAULT]
nova_metadata_host = controller
metadata_proxy_shared_secret = Passw0rd
[agent]
[cache]
EOF
cat <<'EOF' > /etc/nova/nova.conf
[DEFAULT]
my_ip = 10.0.0.11
transport_url = rabbit://openstack:Passw0rd@controller:5672/
log_dir = /var/log/nova
lock_path = /var/lock/nova
state_path = /var/lib/nova
[api]
auth_strategy = keystone
[api_database]
connection = mysql+pymysql://nova:Passw0rd@controller/nova_api
[barbican]
[barbican_service_user]
[cache]
[cinder]
[compute]
[conductor]
[console]
[consoleauth]
[cors]
[cyborg]
[database]
connection = mysql+pymysql://nova:Passw0rd@controller/nova
[devices]
[ephemeral_storage_encryption]
[filter_scheduler]
[glance]
api_servers = http://controller:9292
[guestfs]
[healthcheck]
[image_cache]
[ironic]
[key_manager]
[keystone]
[keystone_authtoken]
www_authenticate_uri = http://controller:5000/
auth_url = http://controller:5000/
memcached_servers = controller:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = nova
password = Passw0rd
[libvirt]
[metrics]
[mks]
[neutron]
auth_url = http://controller:5000
auth_type = password
project_domain_name = Default
user_domain_name = Default
region_name = RegionOne
project_name = service
username = neutron
password = Passw0rd
service_metadata_proxy = true
metadata_proxy_shared_secret = Passw0rd
[notifications]
[os_vif_linux_bridge]
[os_vif_ovs]
[oslo_concurrency]
lock_path = /var/lib/nova/tmp
[oslo_limit]
[oslo_messaging_amqp]
[oslo_messaging_kafka]
[oslo_messaging_notifications]
[oslo_messaging_rabbit]
[oslo_middleware]
[oslo_policy]
[oslo_reports]
[oslo_versionedobjects]
[pci]
[placement]
region_name = RegionOne
project_domain_name = Default
project_name = service
auth_type = password
user_domain_name = Default
auth_url = http://controller:5000/v3
username = placement
password = Passw0rd
[privsep]
[profiler]
[quota]
[remote_debug]
[scheduler]
[serial_console]
[service_user]
send_service_user_token = true
auth_url = http://controller:5000/v3
auth_strategy = keystone
auth_type = password
project_domain_name = Default
project_name = service
user_domain_name = Default
username = nova
password = Passw0rd
[spice]
[upgrade_levels]
[vault]
[vendordata_dynamic_auth]
[vmware]
[vnc]
enabled = true
server_listen = $my_ip
server_proxyclient_address = $my_ip
[workarounds]
[wsgi]
[zvm]
[cells]
enable = False
[os_region_name]
openstack =
EOF
su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf \
  --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron

systemctl restart nova-api
systemctl enable neutron-server
systemctl enable neutron-openvswitch-agent
systemctl enable neutron-dhcp-agent
systemctl enable neutron-metadata-agent
systemctl enable neutron-l3-agent
systemctl restart neutron-server
systemctl restart neutron-openvswitch-agent
systemctl restart neutron-dhcp-agent
systemctl restart neutron-metadata-agent
systemctl restart neutron-l3-agent
