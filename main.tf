# 1. Provider Configuration
provider "aws" {
  region = "us-east-1" # Change to your preferred region
}

## 2. Network Setup (VPC & Subnet)
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

# 3. Security Group (Allows SSH and internal K8s traffic)
resource "aws_security_group" "k8s_sg" {
  name   = "k8s-security-group"
  vpc_id = aws_vpc.k8s_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # For production, restrict to your IP
  }

  # Allow HTTP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow HTTPS
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ## Allow ICMP (ping)
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true # Allow all internal traffic between nodes
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 4. Instance Definitions
locals {
  # Debian 12 (Bookworm) AMI for us-east-1 (AMD64)
  # Note: AMI IDs change by region. Search for "Debian 12" in the AWS Marketplace.
  ami_id = "ami-058bd2d568351da34" 
}

# Jumpbox
resource "aws_instance" "jumpbox" {
  ami           = local.ami_id
  instance_type = "t3.micro" # 1 vCPU, 0.5GB RAM matches your table
  subnet_id     = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.k8s_sg.id]
  
  root_block_device { volume_size = 10 }
  tags = { Name = "jumpbox" }
}

# Kubernetes Server (Control Plane)
resource "aws_instance" "server" {
  ami           = local.ami_id
  instance_type = "t3.micro" # 2 vCPU, 2GB RAM
  subnet_id     = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.k8s_sg.id]

  root_block_device { volume_size = 20 }
  tags = { Name = "server" }
}

# Worker Nodes
resource "aws_instance" "worker_nodes" {
  count         = 2
  ami           = local.ami_id
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.k8s_sg.id]

  root_block_device { volume_size = 20 }
  tags = { Name = "node-${count.index}" }
}