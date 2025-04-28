
# Triển khai Keystone trên Controller Node

## Prerequisites

### 1. Chuẩn bị Cơ sở dữ liệu cho Keystone
```shell
# Đăng nhập vào MySQL
mysql
```
```sql
-- Tạo database 'keystone'
CREATE DATABASE keystone;

-- Cấp quyền cho user 'keystone' chỉ định từ localhost
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY 'OpenStack';

-- Cấp quyền cho user 'keystone' từ mọi địa chỉ IP
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY 'OpenStack';

-- Thoát khỏi MySQL
EXIT;
```

---

## Install and Configure Keystone

### 2. Cài đặt các package cần thiết
```shell
# Cài đặt Keystone và OpenStack client
apt install -y keystone python3-openstackclient
```

### 3. Cấu hình Keystone
```shell
# Ghi đè file cấu hình keystone.conf với các thiết lập cần thiết
cat <<'EOF' > /etc/keystone/keystone.conf
[DEFAULT]
log_dir = /var/log/keystone

[database]
connection = mysql+pymysql://keystone:OpenStack@controller01.openstack.local/keystone

[token]
provider = fernet

[extra_headers]
Distribution = Ubuntu
EOF
```

### 4. Đồng bộ Database cho Keystone
```shell
# Chạy lệnh đồng bộ database Keystone
su -s /bin/sh -c "keystone-manage db_sync" keystone
```

### 5. Khởi tạo kho khóa Fernet và Credential
```shell
# Khởi tạo kho khóa Fernet
keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone

# Khởi tạo kho Credential
keystone-manage credential_setup --keystone-user keystone --keystone-group keystone
```

### 6. Bootstrap dịch vụ Identity
```shell
# Khởi tạo tài khoản admin và các endpoint cho Keystone
keystone-manage bootstrap --bootstrap-password OpenStack --bootstrap-admin-url https://keystone.kbuor.io.vn:5000/v3/ --bootstrap-internal-url https://keystone.kbuor.io.vn:5000/v3/ --bootstrap-public-url https://keystone.kbuor.io.vn:5000/v3/ --bootstrap-region-id RegionOne
```

---

## Cấu hình Web Server Apache

### 7. Gỡ cấu hình site mặc định và tạo site mới sử dụng HTTPS
```shell
# Vô hiệu hóa site cũ
a2dissite keystone

# Xóa file cấu hình cũ (nếu có)
rm -rf /etc/apache2/sites-available/keystone.conf
```
```shell
# Tạo mới VirtualHost sử dụng SSL
cat <<'EOF' > /etc/apache2/sites-available/keystone-https.conf
<VirtualHost *:5000>
    ServerName keystone.kbuor.io.vn

    SSLEngine on
    SSLCertificateFile /etc/ssl/openstack/openstack.crt
    SSLCertificateKeyFile /etc/ssl/openstack/openstack.key

    WSGIDaemonProcess keystone-public user=keystone group=keystone processes=5 threads=1 display-name=%{GROUP}
    WSGIProcessGroup keystone-public
    WSGIScriptAlias / /usr/bin/keystone-wsgi-public

    <Directory /usr/bin>
        Require all granted
    </Directory>

    ErrorLog ${APACHE_LOG_DIR}/keystone_ssl_error.log
    CustomLog ${APACHE_LOG_DIR}/keystone_ssl_access.log combined
</VirtualHost>
EOF

# Lệnh bổ sung cổng 5000 cho Apache
echo "Listen 5000" >> /etc/apache2/ports.conf
```

### 8. Kích hoạt HTTPS và reload Apache
```shell
# Kích hoạt module SSL
a2enmod ssl

# Kích hoạt site Keystone sử dụng SSL
a2ensite keystone-https

# Restart Apache để áp dụng thay đổi
systemctl restart apache2

# Reload Apache để đảm bảo mọi cấu hình mới đã load
systemctl reload apache2
```

---

## Thiết lập biến môi trường cho quản trị viên

### 9. Tạo file `admin-openrc`
```shell
# Tạo file lưu biến môi trường đăng nhập OpenStack
cat <<'EOF' > /root/admin-openrc
export OS_USERNAME=admin
export OS_PASSWORD=OpenStack
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL=https://keystone.kbuor.io.vn:5000/v3
export OS_IDENTITY_API_VERSION=3
EOF

# Load biến môi trường
source /root/admin-openrc
```

---

## Tạo Service Project

### 10. Tạo Service Project
```shell
# Tạo project tên "service" cho các service OpenStack sử dụng
openstack project create --domain default --description "Service Project" service
```

---

# Ghi chú
- Các domain, username, password, URL cần được thay đổi theo môi trường thực tế.
- Đảm bảo hostname `controller01.openstack.local` và `keystone.kbuor.io.vn` đã được khai báo đúng DNS hoặc `/etc/hosts`.
