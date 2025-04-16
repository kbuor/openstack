#!/bin/bash
mysql << EOF
CREATE DATABASE glance;
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY 'Passw0rd';
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY 'Passw0rd';
EXIT;
EOF

export OS_USERNAME=admin
export OS_PASSWORD=Passw0rd
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL=http://controller:5000/v3
export OS_IDENTITY_API_VERSION=3

openstack user create --domain default --password 'Passw0rd' glance
openstack role add --project service --user glance admin
openstack service create --name glance --description "OpenStack Image" image
openstack endpoint create --region RegionOne image public http://controller:9292
openstack endpoint create --region RegionOne image internal http://controller:9292
openstack endpoint create --region RegionOne image admin http://controller:9292
openstack registered limit create --service glance --default-limit 1000 --region RegionOne image_size_total
openstack registered limit create --service glance --default-limit 1000 --region RegionOne image_stage_total
openstack registered limit create --service glance --default-limit 100 --region RegionOne image_count_total
openstack registered limit create --service glance --default-limit 100 --region RegionOne image_count_uploading

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
systemctl enable glance-api
systemctl restart glance-api
