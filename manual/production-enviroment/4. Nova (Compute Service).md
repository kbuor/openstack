# Triển khai Nova trên Controller và Compute Node

## Prerequisites

### 1. Chuẩn bị Cơ sở dữ liệu cho Nova
```shell
# Đăng nhập vào MySQL
mysql
```
```sql
-- Tạo các database cần thiết cho Nova
CREATE DATABASE nova_api;
CREATE DATABASE nova;
CREATE DATABASE nova_cell0;

-- Cấp quyền truy cập cho user nova từ localhost và từ xa
GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'localhost' IDENTIFIED BY 'OpenStack';
GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'%' IDENTIFIED BY 'OpenStack';
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY 'OpenStack';
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY 'OpenStack';
GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'localhost' IDENTIFIED BY 'OpenStack';
GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'%' IDENTIFIED BY 'OpenStack';

-- Thoát MySQL
EXIT;
```

### 2. Chuẩn bị Keystone
```shell
# Load biến môi trường admin
. admin-openrc
```
```shell
# Tạo user nova và gán quyền admin
openstack user create --domain default --password 'OpenStack' nova
openstack role add --project service --user nova admin

# Tạo dịch vụ Compute và các endpoint
openstack service create --name nova --description "OpenStack Compute" compute
openstack endpoint create --region RegionOne compute public https://nova.kbuor.io.vn:8774/v2.1
openstack endpoint create --region RegionOne compute internal https://nova.kbuor.io.vn:8774/v2.1
openstack endpoint create --region RegionOne compute admin https://nova.kbuor.io.vn:8774/v2.1
```

---

## Cài đặt và cấu hình Nova trên Controller Node

### 3. Cài đặt package Nova
```shell
apt install -y nova-api nova-conductor nova-novncproxy nova-scheduler
```

### 4. Cấu hình Nova
```shell
# Ghi đè file cấu hình nova.conf
cat <<'EOF' > /etc/nova/nova.conf
[DEFAULT]
my_ip = 10.21.4.11
transport_url = rabbit://openstack:OpenStack@controller01.openstack.local:5672/
log_dir = /var/log/nova
lock_path = /var/lock/nova
state_path = /var/lib/nova
[api]
auth_strategy = keystone
[api_database]
connection = mysql+pymysql://nova:OpenStack@controller01.openstack.local/nova_api
[database]
connection = mysql+pymysql://nova:OpenStack@controller01.openstack.local/nova
[glance]
api_servers = https://glance.kbuor.io.vn:9292
[keystone_authtoken]
www_authenticate_uri = https://keystone.kbuor.io.vn:5000/
auth_url = https://keystone.kbuor.io.vn:5000/
memcached_servers = controller01.openstack.local:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = nova
password = OpenStack
[placement]
region_name = RegionOne
project_domain_name = Default
project_name = service
auth_type = password
user_domain_name = Default
auth_url = https://keystone.kbuor.io.vn:5000/v3
username = placement
password = OpenStack
[service_user]
send_service_user_token = true
auth_url = https://keystone.kbuor.io.vn:5000/v3
auth_strategy = keystone
auth_type = password
project_domain_name = Default
project_name = service
user_domain_name = Default
username = nova
password = OpenStack
[vnc]
enabled = true
server_listen = $my_ip
server_proxyclient_address = $my_ip
[oslo_concurrency]
lock_path = /var/lib/nova/tmp
EOF
```

### 5. Đồng bộ CSDL và tạo cell
```shell
su -s /bin/sh -c "nova-manage api_db sync" nova
su -s /bin/sh -c "nova-manage cell_v2 map_cell0" nova
su -s /bin/sh -c "nova-manage cell_v2 create_cell --name=cell1 --verbose" nova
su -s /bin/sh -c "nova-manage db sync" nova
su -s /bin/sh -c "nova-manage cell_v2 list_cells" nova
```

---

## Cấu hình Web Server Apache cho Nova

### 7. Tạo VirtualHost cho Nova sử dụng HTTPS
```shell
cat <<'EOF' > /etc/apache2/sites-available/nova-https.conf
<VirtualHost *:8774>
    ServerName nova.kbuor.io.vn

    SSLEngine on
    SSLCertificateFile /etc/ssl/openstack/openstack.crt
    SSLCertificateKeyFile /etc/ssl/openstack/openstack.key

    WSGIDaemonProcess nova-api user=nova group=nova processes=4 threads=1 display-name=%{GROUP}
    WSGIProcessGroup nova-api
    WSGIApplicationGroup %{GLOBAL}
    WSGIScriptAlias / /usr/bin/nova-api-wsgi

    WSGIPassAuthorization On
    LimitRequestBody 0

    <Directory /usr/bin>
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/nova_ssl_error.log
    CustomLog ${APACHE_LOG_DIR}/nova_ssl_access.log combined
</VirtualHost>
EOF

# Thêm port 8774 vào Apache
echo "Listen 8774" >> /etc/apache2/ports.conf
```

### 8. Bật dịch vụ Nova và Apache
```shell
# Enable các dịch vụ Nova backend
systemctl enable nova-scheduler nova-conductor nova-novncproxy
systemctl restart nova-scheduler nova-conductor nova-novncproxy

# Disable dịch vụ nova-api độc lập
systemctl disable nova-api
systemctl stop nova-api

# Kích hoạt VirtualHost nova
a2ensite nova-https
systemctl restart apache2
systemctl reload apache2
```

---

## Cài đặt và cấu hình Nova trên Compute Node

### 9. Cài đặt package Nova
```shell
apt install -y nova-compute
```

### 10. Cấu hình Nova trên Compute Node
```shell
# Ghi đè file cấu hình nova.conf
cat <<'EOF' > /etc/nova/nova.conf
[DEFAULT]
my_ip = 10.21.4.101
transport_url = rabbit://openstack:OpenStack@controller01.openstack.local
log_dir = /var/log/nova
lock_path = /var/lock/nova
state_path = /var/lib/nova
[api]
auth_strategy = keystone
[glance]
api_servers = https://glance.kbuor.io.vn:9292
[keystone_authtoken]
www_authenticate_uri = https://keystone.kbuor.io.vn:5000/
auth_url = https://keystone.kbuor.io.vn:5000/
memcached_servers = controller01.openstack.local:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = nova
password = OpenStack
[placement]
region_name = RegionOne
project_domain_name = Default
project_name = service
auth_type = password
user_domain_name = Default
auth_url = https://keystone.kbuor.io.vn:5000/v3
username = placement
password = OpenStack
[service_user]
send_service_user_token = true
auth_url = https://keystone.kbuor.io.vn:5000/v3
auth_strategy = keystone
auth_type = password
project_domain_name = Default
project_name = service
user_domain_name = Default
username = nova
password = OpenStack
[vnc]
enabled = true
server_listen = 0.0.0.0
server_proxyclient_address = $my_ip
novncproxy_base_url = https://nova.kbuor.io.vn:6080/vnc_auto.html
[oslo_concurrency]
lock_path = /var/lib/nova/tmp
EOF
```

### 11. Bật dịch vụ nova-compute
```shell
systemctl enable nova-compute
systemctl restart nova-compute
```

---

## Đồng bộ lại thông tin Compute Node về Controller

### 12. Discover Hosts
```shell
# Kiểm tra và đồng bộ compute node
openstack compute service list --service nova-compute
su -s /bin/sh -c "nova-manage cell_v2 discover_hosts --verbose" nova
```

---

## Ghi chú
- Đảm bảo `controller01.openstack.local`, `nova.kbuor.io.vn`, `glance.kbuor.io.vn`, và `keystone.kbuor.io.vn` đều đã được khai báo đúng DNS hoặc `/etc/hosts`.
- Tham số `my_ip` cần được thay đổi phù hợp với từng node thực tế.
