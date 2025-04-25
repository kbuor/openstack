# IN THIS LAB

## Networking Design:
1. Management Network: 10.21.4.0/24 | Gateway: 10.21.4.1
2. Provider Network: 20.21.4.0/24 | Gateway: 20.21.4.1
3. VXLAN Tunnel Network: 30.21.4.0/24 | Gateway: 30.21.4.1

## Server Design:
1. Domain Controller: Windows Server 2022
- Resource: 4 Core - 6GB RAM - 50GB SSD
- IP: 10.21.4.100
- Hostname: dc.openstack.local
2. OpenStack Controller Node 01: Ubuntu 24.04 TLS
- Resource: 4 Core - 8GB RAM - 50GB SSD
- IP: 10.21.4.11
- Hostname: controller01.openstack.local
- Alias:    keystone.kbuor.io.vn
            glance.kbuor.io.vn
            placement.kbuor.io.vn
            nova.kbuor.io.vn
