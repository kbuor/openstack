
# Triển khai Glance trên Controller Node

## Prerequisites

### 1. Chuẩn bị Cơ sở dữ liệu cho Glance
```shell
# Đăng nhập vào MySQL
mysql
```
```sql
-- Tạo database 'glance'
CREATE DATABASE glance;

-- Cấp quyền cho user 'glance' chỉ định từ localhost
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY 'OpenStack';

-- Cấp quyền cho user 'glance' từ mọi địa chỉ IP
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY 'OpenStack';

-- Thoát khỏi MySQL
EXIT;
```

### 2. Chuẩn bị Keystone
```shell
# Load file biến môi trường admin
. admin-openrc
```
```shell
# Tạo user glance trong Keystone
openstack user create --domain default --password 'OpenStack' glance

# Gán quyền admin cho user glance
openstack role add --project service --user glance admin

# Tạo dịch vụ glance
openstack service create --name glance --description "OpenStack Image" image

# Tạo các endpoint cho dịch vụ glance
openstack endpoint create --region RegionOne image public https://glance.kbuor.io.vn:9292
openstack endpoint create --region RegionOne image internal https://glance.kbuor.io.vn:9292
openstack endpoint create --region RegionOne image admin https://glance.kbuor.io.vn:9292
```

---

## Install and Configure Glance

### 3. Cài đặt package Glance
```shell
apt install glance -y
```

### 4. Cấu hình Glance
```shell
# Ghi đè file cấu hình glance-api.conf
cat <<'EOF' > /etc/glance/glance-api.conf
[DEFAULT]
enabled_backends=fs:file

[database]
connection = mysql+pymysql://glance:OpenStack@controller01.openstack.local/glance
backend = sqlalchemy

[glance_store]
default_backend = fs

[fs]
filesystem_store_datadir = /var/lib/glance/images/

[image_format]
disk_formats = ami,ari,aki,vhd,vhdx,vmdk,raw,qcow2,vdi,iso,ploop.root-tar

[keystone_authtoken]
www_authenticate_uri  = https://keystone.kbuor.io.vn:5000
auth_url = https://keystone.kbuor.io.vn:5000
memcached_servers = controller01.openstack.local:11211
auth_type = password
project_domain_name = Default
user_domain_name = Default
project_name = service
username = glance
password = OpenStack

[paste_deploy]
flavor = keystone
EOF
```

### 5. Gán quyền đọc hệ thống cho user Glance
```shell
openstack role add --user glance --user-domain Default --system all reader
```

### 6. Đồng bộ Database Glance
```shell
su -s /bin/sh -c "glance-manage db_sync" glance
```

---

## Cấu hình Web Server Apache cho Glance

### 7. Tạo VirtualHost chạy Glance API qua HTTPS
```shell
cat <<'EOF' > /etc/apache2/sites-available/glance-https.conf
<VirtualHost *:9292>
    ServerName glance.kbuor.io.vn

    SSLEngine on
    SSLCertificateFile /etc/ssl/openstack/openstack.crt
    SSLCertificateKeyFile /etc/ssl/openstack/openstack.key

    WSGIDaemonProcess glance-api user=glance group=glance processes=4 threads=1 display-name=%{GROUP}
    WSGIProcessGroup glance-api
    WSGIScriptAlias / /usr/bin/glance-wsgi-api
    WSGIPassAuthorization On
    LimitRequestBody 0

    <Directory /usr/bin>
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/glance_ssl_error.log
    CustomLog ${APACHE_LOG_DIR}/glance_ssl_access.log combined
</VirtualHost>
EOF

# Thêm cổng 9292 vào Apache
echo "Listen 9292" >> /etc/apache2/ports.conf
```

### 8. Khởi động lại Apache
```shell
# Tắt dịch vụ glance-api chạy độc lập
systemctl stop glance-api
systemctl disable glance-api

# Kích hoạt site Apache cho Glance
a2ensite glance-https

# Restart và reload Apache để áp dụng cấu hình mới
systemctl restart apache2
systemctl reload apache2
```

---

## Verify

### 9. Kiểm tra tải và upload image mẫu Cirros
```shell
# Tải image mẫu Cirros
wget http://download.cirros-cloud.net/0.4.0/cirros-0.4.0-x86_64-disk.img

# Tạo image mới trên OpenStack
openstack image create "cirros" --file cirros-0.4.0-x86_64-disk.img --disk-format qcow2 --container-format bare --public
```

---

# Ghi chú
- Các domain, username, password, URL cần được điều chỉnh phù hợp môi trường triển khai.
- Đảm bảo hostname `controller01.openstack.local` và `glance.kbuor.io.vn` đã được khai báo đúng DNS hoặc `/etc/hosts`.
