# Terraform provider setup
provider "aws" {
  region = "us-west-2"
}

# Just checking the availability zones
data "aws_availability_zones" "available" {}

output "available_azs" {
  value = data.aws_availability_zones.available.names
}

# Create VPC, Subnet, Internet Gateway
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

# Allocate an Elastic IP
resource "aws_eip" "static_ip" {
  domain = "vpc"
}

# End of VPC definition area


# Security Group for ports 22 (SSH), 80 (HTTP), 443 (HTTPS)
resource "aws_security_group" "sg" {
  name        = "breakroom-sg"
  description = "Allow SSH, HTTP, and HTTPS"

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

# Define EC2 instance
resource "aws_instance" "breakroom_instance" {
  ami           = "ami-01cf060c3da348f92"  # Ubuntu 20.04 minimal (us-west-2)
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.subnet_a.id
  key_name      = "Kubernetes Key"

  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.sg.id]

  # Minimal bootstrap script
  user_data = <<-EOF
              #!/bin/bash
              echo "User data script started..."
              EOF

  # Upload Docker Compose file
  provisioner "file" {
    source      = "docker-compose.production.yml"
    destination = "/home/ubuntu/docker-compose.production.yml"
  }

  # Upload Nginx config folder
  provisioner "file" {
    source      = "backend/etc/nginx"
    destination = "/home/ubuntu/nginx"
  }

  # Remote commands
  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update -y",
      "sudo apt-get install -y docker.io docker-compose",
      "sudo systemctl start docker",
      "sudo systemctl enable docker",
      "sudo usermod -aG docker ubuntu",
      "cd /home/ubuntu",
      "docker-compose -f docker-compose.production.yml up -d"
    ]
  }

  # SSH connection for provisioners
  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = file("~/.ssh/kubernetes-key.pem") # Adjust this path
    host        = self.public_ip
  }

  tags = {
    Name = "Breakroom EC2 Instance"
  }
}

# Associate EIP to EC2
resource "aws_eip_association" "eip_assoc" {
  instance_id   = aws_instance.breakroom_instance.id
  allocation_id = aws_eip.static_ip.id
}

# Output public IP
output "instance_public_ip" {
  value = aws_instance.breakroom_instance.public_ip
}

output "static_ip" {
  value = aws_eip.static_ip.public_ip
}

# Optional: Use Terraform Cloud
terraform {
  backend "remote" {
    organization = "Cherry-Blossom-Development"

    workspaces {
      name = "Development-Workspace"
    }
  }
}

