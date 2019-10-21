Terraform script to start and configure an ovpn server on aws.

1. Requirements

- terraform
- scp
- openvpn (to start a vpn session)

2. Instructions

Launch instance and configure ovpn server

```
MY_OVPN_SERVER_NAME=ovpn_server_name
git clone
cd terraform-ovpn
terraform init
terraform apply -var name=$MY_OVPN_SERVER_NAME -var region=eu-west-3 -auto-approve
```

Use `$MY_OVPN_SERVER_NAME.ovpn` to initiate a connection to the vpn server

```
sudo openvpn $MY_OVPN_SERVER_NAME.ovpn
```

3. Credits

- (docker-openvpn)[https://github.com/kylemanna/docker-openvpn]