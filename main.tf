# Terraform provider setup
provider "aws" {
  region = "us-west-2"
  alias  = "cherry-blossom"
}

# Define EC2 instance
resource "aws_instance" "breakroom_instance" {
  ami           = "ami-0c55b159cbfafe1f0" # Change this to a valid AMI in your region or use the latest Amazon Linux AMI
  instance_type = "t2.micro"
  key_name      = "your-ssh-key" # Replace with your actual SSH key name

  # Security Group Configuration
  vpc_security_group_ids = [aws_security_group.sg.id]

  # User Data script to install Docker and start your container
  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              amazon-linux-extras enable docker
              yum install docker -y
              service docker start
              usermod -a -G docker ec2-user
              docker pull dallas.caley/breakroom
              docker run -d -p 80:80 dallas.caley/breakroom
              EOF

  # Tags for identification
  tags = {
    Name = "Breakroom EC2 Instance"
  }
}

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

# Output the instance's public IP address
output "instance_public_ip" {
  value = aws_instance.breakroom_instance.public_ip
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
