
# Triển khai Placement trên Controller Node

## Prerequisites

### 1. Chuẩn bị Cơ sở dữ liệu cho Placement
```shell
# Đăng nhập vào MySQL
mysql
```
```sql
-- Tạo database 'placement'
CREATE DATABASE placement;

-- Cấp quyền cho user 'placement' chỉ định từ localhost
GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'localhost' IDENTIFIED BY 'OpenStack';

-- Cấp quyền cho user 'placement' từ mọi địa chỉ IP
GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'%' IDENTIFIED BY 'OpenStack';

-- Thoát khỏi MySQL
EXIT;
```

### 2. Chuẩn bị Keystone
```shell
# Load file biến môi trường admin
. admin-openrc
```
```shell
# Tạo user placement trong Keystone
openstack user create --domain default --password 'OpenStack' placement

# Gán quyền admin cho user placement
openstack role add --project service --user placement admin

# Tạo dịch vụ Placement
openstack service create --name placement --description "Placement API" placement

# Tạo các endpoint cho Placement
openstack endpoint create --region RegionOne placement public https://placement.kbuor.io.vn:8778
openstack endpoint create --region RegionOne placement internal https://placement.kbuor.io.vn:8778
openstack endpoint create --region RegionOne placement admin https://placement.kbuor.io.vn:8778
```

---

## Install and Configure Placement

### 3. Cài đặt package Placement
```shell
apt install placement-api -y
```

### 4. Cấu hình Placement
```shell
# Ghi đè file cấu hình placement.conf
cat <<'EOF' > /etc/placement/placement.conf
[DEFAULT]

[api]
auth_strategy = keystone

[keystone_authtoken]
auth_url = https://keystone.kbuor.io.vn:5000/v3
memcached_servers = controller01.openstack.local:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = placement
password = OpenStack

[placement_database]
connection = mysql+pymysql://placement:OpenStack@controller01.openstack.local/placement
EOF
```

### 5. Đồng bộ Database Placement
```shell
su -s /bin/sh -c "placement-manage db sync" placement
```

---

## Cấu hình Web Server Apache cho Placement

### 6. Tạo VirtualHost chạy Placement API qua HTTPS
```shell
cat <<'EOF' > /etc/apache2/sites-available/placement-api.conf
<VirtualHost *:8778>
    ServerName placement.kbuor.io.vn

    SSLEngine on
    SSLCertificateFile /etc/ssl/openstack/openstack.crt
    SSLCertificateKeyFile /etc/ssl/openstack/openstack.key

    WSGIDaemonProcess placement-api-https user=placement group=placement processes=4 threads=1 display-name=%{GROUP}
    WSGIProcessGroup placement-api-https
    WSGIScriptAlias / /usr/bin/placement-api

    WSGIPassAuthorization On
    LimitRequestBody 0

    <Directory /usr/bin>
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/placement_ssl_error.log
    CustomLog ${APACHE_LOG_DIR}/placement_ssl_access.log combined
</VirtualHost>
EOF

# Thêm cổng 8778 vào Apache
echo "Listen 8778" >> /etc/apache2/ports.conf
```

### 7. Kích hoạt site và restart Apache
```shell
# Kích hoạt site Apache cho Placement
a2ensite placement-api

# Restart và reload Apache để áp dụng cấu hình mới
systemctl restart apache2
systemctl reload apache2
```

---

# Ghi chú
- Các domain, username, password, URL cần được điều chỉnh phù hợp môi trường triển khai.
- Đảm bảo hostname `controller01.openstack.local` và `placement.kbuor.io.vn` đã được khai báo đúng DNS hoặc `/etc/hosts`.
