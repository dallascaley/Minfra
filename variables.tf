variable "instance_name" {
  description = "Prosaurus Breakroom Primary Instance"
  type        = string
  default     = "Prosaurus"
}

variable "private_key_path" {
  description = "The path to the SSH private key used to access EC2 instances"
  type        = string
  default     = "C:/Users/dalla/Repo/Infrastructure/.ssh/KubernetesKey.pem"  # Windows path format
}

variable "ssh_key_name" {
  description = "The name of the SSH key pair to use for EC2 access"
  type        = string
  default     = "Kubernetes Key"
}

variable "KUBERNETES_PRIVATE_KEY" {
  type        = string
  description = "The private key for SSH access to the EC2 instances"
  sensitive   = true  # Make sure this is sensitive to avoid exposing the key in logs
}
