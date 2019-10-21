variable "region" {
    type        = string
    default     = "eu-west-3"
    description = "aws region"
}

variable "name" {
    type = string
    default = "ovpn_server"
    description = "name"
}

terraform {
  required_version = "> 0.12.0"
}

provider "aws" {
    region = var.region
}

data "aws_vpc" "selected" {
  default = true
}

data "aws_subnet_ids" "subnets" {
  vpc_id = data.aws_vpc.selected.id
}

data "aws_ami" "amzn_ami_hvm" {
  most_recent = true
  owners = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-*-x86_64-ebs"]
  }
}

resource "tls_private_key" "ovpn_private_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated_key" {
  key_name   = var.name
  public_key = tls_private_key.ovpn_private_key.public_key_openssh
}

resource "aws_security_group" "ingress_ovpn" {
  name = "allow_ovpn_${var.name}"
  vpc_id = data.aws_vpc.selected.id
  ingress {
    cidr_blocks = [
        "0.0.0.0/0"
    ]
    from_port = 1194
    to_port = 1194
    protocol = "udp"
  }
  ingress {
    cidr_blocks = [
        "0.0.0.0/0"
    ]
    from_port = 22
    to_port = 22
    protocol = "tcp"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "ovpn_server" {
  ami           = data.aws_ami.amzn_ami_hvm.id
  instance_type = "t2.micro"
  subnet_id = tolist(data.aws_subnet_ids.subnets.ids)[0]
  associate_public_ip_address = true
  vpc_security_group_ids = [aws_security_group.ingress_ovpn.id]
  key_name      = aws_key_pair.generated_key.key_name
}

resource "local_file" "pem" {
  content     = tls_private_key.ovpn_private_key.private_key_pem
  filename = "${path.module}/${var.name}_private_key.pem"
  file_permission = "0600"
}

resource "null_resource" "init_ovpn" {
  depends_on = [local_file.pem]

  connection {
    type = "ssh"
    user = "ec2-user"
    private_key = tls_private_key.ovpn_private_key.private_key_pem
    host = aws_instance.ovpn_server.public_dns
  }


  provisioner "remote-exec" {
    inline = [
      "docker volume create --name ovpn-data",
      "docker run -v ovpn-data:/etc/openvpn --rm kylemanna/openvpn ovpn_genconfig -u udp://$(curl -sS http://169.254.169.254/latest/meta-data/public-hostname)",
      "docker run -v ovpn-data:/etc/openvpn --rm -ti -e EASYRSA_BATCH=1 --entrypoint bash kylemanna/openvpn -c 'source \"$OPENVPN/ovpn_env.sh\" && easyrsa init-pki && easyrsa build-ca nopass && easyrsa gen-dh && openvpn --genkey --secret $EASYRSA_PKI/ta.key && easyrsa build-server-full \"$OVPN_CN\" nopass && easyrsa gen-crl && easyrsa build-client-full ${var.name} nopass'",
      "docker run -v ovpn-data:/etc/openvpn -d -p 1194:1194/udp --cap-add=NET_ADMIN kylemanna/openvpn",
      "docker run -v ovpn-data:/etc/openvpn --rm kylemanna/openvpn ovpn_getclient ${var.name} > ${var.name}.ovpn"
    ]
  }

  provisioner "local-exec" {
    command = "scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ${path.module}/${var.name}_private_key.pem ec2-user@${aws_instance.ovpn_server.public_dns}:~/${var.name}.ovpn ${path.module}/${var.name}.ovpn"
  }
}

output "openvpn" {
  value = "sudo openvpn ${path.module}/${var.name}.ovpn"
}