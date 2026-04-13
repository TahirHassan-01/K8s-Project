# 1. Provider Configuration
provider "aws" {
  region = "us-east-1"
}

# 2. IAM Role for Systems Manager (SSM) Access
resource "aws_iam_role" "ssm_role" {
  name = "k8s_ssm_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_attach" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_profile" {
  name = "k8s_ssm_instance_profile"
  role = aws_iam_role.ssm_role.name
}

# 3. Network Setup
resource "aws_vpc" "k8s_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags                 = { Name = "k8s-tutorial-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.k8s_vpc.id
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.k8s_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  tags                    = { Name = "k8s-public-subnet" }
}

resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.k8s_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.rt.id
}

# 4. Security Group
resource "aws_security_group" "k8s_sg" {
  name   = "k8s-security-group"
  vpc_id = aws_vpc.k8s_vpc.id

  # Internal cluster traffic (all protocols)
  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  # Standard web traffic
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound traffic (required for SSM and updates)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 5. Locals & User Data
locals {
  ami_id = "ami-058bd2d568351da34" # Debian 12 us-east-1
  
  # Script to install SSM agent on Debian 12
  ssm_install = <<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y wget
              mkdir -p /tmp/ssm
              cd /tmp/ssm
              wget https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/debian_amd64/amazon-ssm-agent.deb
              dpkg -i amazon-ssm-agent.deb
              systemctl enable amazon-ssm-agent
              systemctl start amazon-ssm-agent
              EOF
}

# 6. Instances
# Jumpbox
resource "aws_instance" "jumpbox" {
  ami                    = local.ami_id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.k8s_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ssm_profile.name
  user_data              = local.ssm_install
  
  root_block_device { volume_size = 10 }
  tags = { Name = "jumpbox" }
}

## Kubernetes Server
resource "aws_instance" "server" {
  ami                    = local.ami_id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.k8s_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ssm_profile.name
  user_data              = local.ssm_install

  root_block_device { volume_size = 20 }
  tags = { Name = "server" }
}

# Worker Nodes
resource "aws_instance" "worker_nodes" {
  count                  = 2
  ami                    = local.ami_id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.k8s_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ssm_profile.name
  user_data              = local.ssm_install

  root_block_device { volume_size = 20 }
  tags = { Name = "node-${count.index}" }
}