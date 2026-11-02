variable "project" {
  type    = string
  default = "coldchain"
}

variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "admin_cidrs" {
  description = "Your public IP(s) in CIDR form (e.g. 203.0.113.10/32). Only these can reach the Jenkins UI."
  type        = list(string)

  validation {
    condition     = length(var.admin_cidrs) > 0 && !contains(var.admin_cidrs, "0.0.0.0/0")
    error_message = "Set admin_cidrs to your own IP(s). 0.0.0.0/0 is not allowed."
  }
}

variable "device_cidrs" {
  description = "Source ranges allowed to connect to MQTT (port 1883). Narrow this if your boxes have fixed IPs."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "webhook_cidrs" {
  description = "Optional: ranges allowed to call the Jenkins webhook (e.g. GitHub hook IPs). Leave empty to use SCM polling."
  type        = list(string)
  default     = []
}

variable "instance_type_app" {
  type    = string
  default = "t3.small"
}

variable "instance_type_jenkins" {
  type    = string
  default = "t3.medium"
}

variable "instance_type_agent" {
  type    = string
  default = "t3.medium"
}

variable "db_instance_class" {
  type    = string
  default = "db.t4g.micro"
}

variable "db_allocated_storage" {
  type    = number
  default = 20
}

variable "db_name" {
  type    = string
  default = "coldchain"
}

variable "db_username" {
  type    = string
  default = "coldchain"
}
