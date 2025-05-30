# Terraform provider setup
provider "aws" {
  region = "us-west-2"
}

# Just checking the availability zones
data "aws_availability_zones" "available" {}

output "available_azs" {
  value = data.aws_availability_zones.available.names
}

# Allocate an Elastic IP

resource "aws_eip" "static_ip" {
  domain = "vpc"

  lifecycle {
    prevent_destroy = true
  }
}

# Lets Define our VPC.  The following is copied directly from ChatGPT but we will fix it (hopefully)

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = {
    Name = "main-vpc"
  }
}

resource "aws_subnet" "subnet_a" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  availability_zone = "us-west-2a"
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

# End of VPC definition area


# Define Security Group to allow SSH (22) and HTTP (80) traffic
resource "aws_security_group" "sg" {
  name        = "breakroom-sg"
  description = "Allow inbound SSH and HTTP traffic"
  
  # Inbound rules
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound rules
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Define EC2 instance
resource "aws_instance" "breakroom_instance" {
  ami           = "ami-01cf060c3da348f92" # ubuntu-minimal/images/hvm-ssd/ubuntu-focal-20.04-amd64-minimal-20250402 (us-west-2)
  instance_type = "t2.micro"
  key_name      = "Kubernetes Key"

  # Security Group Configuration
  vpc_security_group_ids = [aws_security_group.sg.id]

  # you are here...

  # User Data script to install Docker and start your container
  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install docker.io -y
              systemctl start docker
              systemctl enable docker
              usermod -aG docker ubuntu
              docker pull dallascaley/breakroom
              docker run -d -p 80:80 dallascaley/breakroom
              EOF

  # Tags for identification
  tags = {
    Name = "Breakroom EC2 Instance"
  }
}

# Associate Elatic IP address with EC2 Instance
resource "aws_eip_association" "eip_assoc" {
  instance_id   = aws_instance.breakroom_instance.id
  allocation_id = aws_eip.static_ip.id
}

# Output the instance's public IP address
output "instance_public_ip" {
  value = aws_instance.breakroom_instance.public_ip
}

# Output the static IP address
output "static_ip" {
  value = aws_eip.static_ip.public_ip
}

# Set up workspace and organization (these are optional and for organization purposes)
terraform {
  backend "remote" {
    organization = "Cherry-Blossom-Development"
    workspaces {
      name = "Development-Workspace"
    }
  }
}

