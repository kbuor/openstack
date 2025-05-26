# Triển khai Cinder trên Controller và Cinder Node

## Prerequisites

### 1. Chuẩn bị Cơ sở dữ liệu cho Cinder
```shell
# Đăng nhập vào MySQL
mysql
```
```sql
-- Tạo database cinder
CREATE DATABASE cinder;

-- Cấp quyền cho user neutron
GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'localhost' IDENTIFIED BY 'OpenStack';
GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'%' IDENTIFIED BY 'OpenStack';

-- Thoát MySQL
EXIT;
```

### 2. Chuẩn bị Keystone
```shell
# Load biến môi trường admin
. admin-openrc
```
```shell
# Tạo user neutron và các endpoint
openstack user create --domain default --password 'OpenStack' cinder
openstack role add --project service --user cinder admin
openstack service create --name cinderv3 --description "OpenStack Block Storage" volumev3
openstack endpoint create --region RegionOne volumev3 public https://cinder.tpcoms.ai:8776/v3/%\(project_id\)s
openstack endpoint create --region RegionOne volumev3 internal https://cinder.tpcoms.ai:8776/v3/%\(project_id\)s
openstack endpoint create --region RegionOne volumev3 admin https://cinder.tpcoms.ai:8776/v3/%\(project_id\)s
```

---

## Cài đặt và cấu hình Cinder trên Controller Node

### 3. Cài đặt package Cinder
```shell
apt install -y cinder-api cinder-scheduler
```

### 4. Cấu hình các file cấu hình Cinder
#### cinder.conf
```shell
cat <<'EOF' > /etc/cinder/cinder.conf
[DEFAULT]
rootwrap_config = /etc/cinder/rootwrap.conf
api_paste_confg = /etc/cinder/api-paste.ini
iscsi_helper = lioadm
volume_name_template = volume-%s
volume_group = cinder-volumes
verbose = True
auth_strategy = keystone
state_path = /var/lib/cinder
lock_path = /var/lock/cinder
volumes_dir = /var/lib/cinder/volumes
enabled_backends = lvm
transport_url = rabbit://openstack:OpenStack@controller01.openstack.local
my_ip = 10.20.30.11

[database]
connection = mysql+pymysql://cinder:OpenStack@controller01.openstack.local/cinder

[keystone_authtoken]
www_authenticate_uri = https://keystone.tpcoms.ai:5000
auth_url = https://keystone.tpcoms.ai:5000
memcached_servers = controller01.openstack.local:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = cinder
password = OpenStack

[oslo_concurrency]
lock_path = /var/lib/cinder/tmp
EOF
```

---

## Đồng bộ database và khởi động dịch vụ Cinder

### 5. Đồng bộ CSDL Cinder
```shell
su -s /bin/sh -c "cinder-manage db sync" cinder
```

---

## Cập nhật Nova để tích hợp Cinder (trên Controller Node)

### 6. Chỉnh sửa file `/etc/nova/nova.conf`
```ini
[cinder]
os_region_name = RegionOne
```

---

### 7. Khởi động các dịch vụ Cinder
```shell
systemctl enable cinder-scheduler
systemctl restart cinder-scheduler
```

---

## Chạy Cinder API bằng Apache HTTPD

### 9. Tạo VirtualHost chạy Cinder API qua HTTPS
```shell
rm -rf /etc/apache2/conf-available/cinder*
```
```shell
cat <<'EOF' > /etc/apache2/sites-available/cinder-https.conf
<VirtualHost *:8776>
    ServerName cinder.tpcoms.ai

    SSLEngine on
    SSLCertificateFile /etc/ssl/openstack/openstack.crt
    SSLCertificateKeyFile /etc/ssl/openstack/openstack.key

    WSGIDaemonProcess cinder-wsgi processes=5 threads=1 user=cinder group=cinder display-name=%{GROUP}
    WSGIProcessGroup cinder-wsgi
    WSGIScriptAlias / /usr/bin/cinder-wsgi
    WSGIApplicationGroup %{GLOBAL}
    WSGIPassAuthorization On

    <Directory /usr/bin>
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/neutron_ssl_error.log
    CustomLog ${APACHE_LOG_DIR}/neutron_ssl_access.log combined
</VirtualHost>
EOF

echo 'Listen 8776' >> /etc/apache2/ports.conf
```

### 10. Bật HTTPS cho Cinder và khởi động Apache
```shell
a2ensite cinder-https
systemctl restart apache2
systemctl reload apache2
```
---
## Cài đặt và cấu hình Cinder trên Storage (Cinder) Node
### 1. Cài gói cho LVM
```shell
apt install lvm2 thin-provisioning-tools
```

### 2. Cấu hình Volume Group cho LVM
```shell
pvcreate /dev/sdb
vgcreate cinder-volumes /dev/sdb
```
```shell
sed -i '/^\s*#/d;/^\s*$/d' /etc/lvm/lvm.conf
sed -i '/^devices\s*{/,/^}/ {
  /^}/i\
        filter = [ "a/sda/", "a/sdb/", "r/.*/"]
}' /etc/lvm/lvm.conf
```

### 3. Cài gói Cinder-Volume
```shell
apt -y install cinder-volume tgt
```
### 4. Edit configure file
```shell
cat <<'EOF' > /etc/cinder/cinder.conf
[DEFAULT]
transport_url = rabbit://openstack:OpenStack@controller01.openstack.local
rootwrap_config = /etc/cinder/rootwrap.conf
api_paste_confg = /etc/cinder/api-paste.ini
iscsi_helper = lioadm
volume_name_template = volume-%s
volume_group = cinder-volumes
verbose = True
auth_strategy = keystone
state_path = /var/lib/cinder
lock_path = /var/lock/cinder
volumes_dir = /var/lib/cinder/volumes
enabled_backends = lvm
my_ip = 10.20.30.41
glance_api_servers = https://glance.tpcoms.ai:9292

[database]
connection = mysql+pymysql://cinder:OpenStack@controller01.openstack.local/cinder

[keystone_authtoken]
www_authenticate_uri = https://keystone.tpcoms.ai:5000
auth_url = https://keystone.tpcoms.ai:5000
memcached_servers = controller01.openstack.local:11211
auth_type = password
project_domain_name = default
user_domain_name = default
project_name = service
username = cinder
password = OpenStack

[lvm]
volume_driver = cinder.volume.drivers.lvm.LVMVolumeDriver
volume_group = cinder-volumes
target_protocol = iscsi
target_helper = tgtadm

[oslo_concurrency]
lock_path = /var/lib/cinder/tmp
EOF
```
```shell
echo 'include /var/lib/cinder/volumes/*' > include /var/lib/cinder/volumes/*
```
### 5. Restart service
```shell
systemctl restart cinder-volume
systemctl restart tgt
systemctl enable cinder-volume
systemctl enable tgt
```
