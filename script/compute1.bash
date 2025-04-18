#!/bin/bash

hostnamectl set-hostname compute1
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
        - 10.0.0.31/24
      routes:
        - to: default
          via: 10.0.0.1
      nameservers:
        addresses:
          - 8.8.8.8
          - 1.1.1.1
EOF
netplan apply

echo "10.0.0.11 controller" >> /etc/hosts
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
server controller iburst
EOF
systemctl restart chrony
systemctl enable chrony

apt install -y python3-openstackclient

apt install -y nova-compute
cat <<'EOF' > /etc/nova/nova.conf
[DEFAULT]
my_ip = 10.0.0.31
transport_url = rabbit://openstack:Passw0rd@controller
log_dir = /var/log/nova
lock_path = /var/lock/nova
state_path = /var/lib/nova
[api]
auth_strategy = keystone
[api_database]
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
[devices]
[ephemeral_storage_encryption]
[filter_scheduler]
[glance]
api_servers = http://controller:9292
[guestfs]
[healthcheck]
[hyperv]
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
[oslo_concurrency]
lock_path = /var/lib/nova/tmp
[oslo_messaging_amqp]
[oslo_messaging_kafka]
[oslo_messaging_notifications]
[oslo_messaging_rabbit]
[oslo_middleware]
[oslo_policy]
[oslo_reports]
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
[powervm]
[privsep]
[profiler]
[quota]
[rdp]
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
server_listen = 0.0.0.0
server_proxyclient_address = $my_ip
novncproxy_base_url = http://controller:6080/vnc_auto.html
[workarounds]
[wsgi]
[zvm]
[cells]
enable = False
[os_region_name]
openstack =
EOF
systemctl enable nova-compute
systemctl restart nova-compute

apt install neutron-openvswitch-agent -y
cat <<'EOF' > /etc/neutron/neutron.conf
[DEFAULT]
transport_url = rabbit://openstack:Passw0rd@controller
core_plugin = ml2 
[agent]
root_helper = "sudo /usr/bin/neutron-rootwrap /etc/neutron/rootwrap.conf"
[cache]
[cors]
[database]
[healthcheck]
[ironic]
[keystone_authtoken]
[nova]
[oslo_concurrency]
lock_path = /var/lib/neutron/tmp
[oslo_messaging_amqp]
[oslo_messaging_kafka]
[oslo_messaging_notifications]
[oslo_messaging_rabbit]
[oslo_middleware]
[oslo_policy]
[oslo_reports]
[placement]
[privsep]
[profiler]
[quotas]
[ssl]
EOF
cat <<'EOF' > /etc/neutron/plugins/ml2/openvswitch_agent.ini
[DEFAULT]
[agent]
tunnel_types = vxlan
l2_population = true
[dhcp]
[network_log]
[ovs]
bridge_mappings = provider:br-ex
local_ip = 10.0.0.31
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
        - 10.0.0.31/24
      routes:
        - to: default
          via: 10.0.0.1
      nameservers:
        addresses:
          - 8.8.8.8
          - 1.1.1.1
EOF
netplan apply
cat <<'EOF' > /etc/nova/nova.conf
[DEFAULT]
my_ip = 10.0.0.31
transport_url = rabbit://openstack:Passw0rd@controller
log_dir = /var/log/nova
lock_path = /var/lock/nova
state_path = /var/lib/nova
[api]
auth_strategy = keystone
[api_database]
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
[devices]
[ephemeral_storage_encryption]
[filter_scheduler]
[glance]
api_servers = http://controller:9292
[guestfs]
[healthcheck]
[hyperv]
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
[notifications]
[oslo_concurrency]
lock_path = /var/lib/nova/tmp
[oslo_messaging_amqp]
[oslo_messaging_kafka]
[oslo_messaging_notifications]
[oslo_messaging_rabbit]
[oslo_middleware]
[oslo_policy]
[oslo_reports]
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
[powervm]
[privsep]
[profiler]
[quota]
[rdp]
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
server_listen = 0.0.0.0
server_proxyclient_address = $my_ip
novncproxy_base_url = http://controller:6080/vnc_auto.html
[workarounds]
[wsgi]
[zvm]
[cells]
enable = False
[os_region_name]
openstack =
EOF
systemctl enable nova-compute
systemctl restart nova-compute
systemctl enable neutron-openvswitch-agent
systemctl restart neutron-openvswitch-agent
