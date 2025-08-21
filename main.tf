terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "remote" {
    organization = "Cherry-Blossom-Development"
    workspaces {
      name = "Development-Workspace"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

# Data source for latest Amazon Linux 2 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# VPC and Networking resources
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "main-vpc"
  }
}

resource "aws_subnet" "subnet_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-west-2a"
  map_public_ip_on_launch = true

  tags = {
    Name = "subnet-a"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-igw"
  }
}

resource "aws_route_table" "route_table" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route" "internet_route" {
  route_table_id         = aws_route_table.route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "subnet_association" {
  subnet_id      = aws_subnet.subnet_a.id
  route_table_id = aws_route_table.route_table.id
}

# Security Group with restricted SSH, open HTTP/HTTPS
resource "aws_security_group" "sg" {
  name        = "breakroom-sg"
  description = "Allow SSH from my IP, HTTP, and HTTPS"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["96.41.68.133/32"]
  }

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

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_role" "ec2_role" {
  name = "breakroom-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "ec2_s3_read_policy" {
  name = "breakroom-ec2-s3-read"
  role = aws_iam_role.ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject"
        ],
        Resource = "arn:aws:s3:::breakroom-secrets/encrypt.tar.gz"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "breakroom-ec2-instance-profile"
  role = aws_iam_role.ec2_role.name
}

# EC2 Instance to run Docker containers
resource "aws_instance" "breakroom_instance" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.subnet_a.id
  key_name      = "Kubernetes Key"

  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.sg.id]

  iam_instance_profile = aws_iam_instance_profile.ec2_instance_profile.name

  user_data = <<-EOF
    #!/bin/bash -xe

    # Wait for yum lock to clear #1
    while sudo fuser /var/run/yum.pid >/dev/null 2>&1; do
        echo "Waiting for yum lock to be released... (1)"
        sleep 5
    done

    # Install Docker
    amazon-linux-extras install -y docker
    service docker start
    usermod -aG docker ec2-user

    # Install Docker Compose
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose

    # Wait for yum lock to clear #2
    while sudo fuser /var/run/yum.pid >/dev/null 2>&1; do
        echo "Waiting for yum lock to be released... (2)"
        sleep 5
    done

    yum update -y
    yum install -y git awscli

    cd /home/ec2-user

    # Download and extract secrets from S3
    aws s3 cp s3://breakroom-secrets/encrypt.tar.gz /home/ec2-user/encrypt.tar.gz
    mkdir -p /home/ec2-user/backend/etc/encrypt
    tar -xzf encrypt.tar.gz -C /home/ec2-user/backend/etc/encrypt --strip-components=1

    # Clone the Breakroom repo and copy nginx config
    git clone https://github.com/dallascaley/Breakroom.git

    mkdir -p /home/ec2-user/backend/etc/nginx
    curl -L -o /home/ec2-user/backend/etc/nginx/nginx-production.conf https://raw.githubusercontent.com/dallascaley/Breakroom/main/backend/etc/nginx/nginx-production.conf

    cp -r Breakroom/backend/etc/nginx /home/ec2-user/backend/etc/nginx

    chown -R ec2-user:ec2-user /home/ec2-user/backend

    # Download docker-compose.production.yml
    curl -L -o /home/ec2-user/docker-compose.production.yml https://raw.githubusercontent.com/dallascaley/Breakroom/main/docker-compose.production.yml
    chown ec2-user:ec2-user /home/ec2-user/docker-compose.production.yml

    # Run the app
    sudo -u ec2-user /usr/local/bin/docker-compose -f /home/ec2-user/docker-compose.production.yml pull
    sudo -u ec2-user /usr/local/bin/docker-compose -f /home/ec2-user/docker-compose.production.yml up -d
  EOF

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = file("~/.ssh/KubernetesKey.pem")  # Adjust to your private key path
    host        = self.public_ip
  }

  tags = {
    Name = "Breakroom EC2 Instance"
  }
}

# Associate Elastic IP with EC2 instance
resource "aws_eip_association" "eip_assoc" {
  instance_id   = aws_instance.breakroom_instance.id
  allocation_id = "eipalloc-0dcd99b6b29791b48"
}

# Outputs
output "instance_public_ip" {
  description = "Public IP of EC2 instance"
  value       = aws_instance.breakroom_instance.public_ip
}

output "static_ip_manual" {
  description = "Manually assigned Elastic IP"
  value       = "44.225.148.34"
}

