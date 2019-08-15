variable "region" {
  default = "par1"
}

variable "architecture" {
  default = "x86_64"
}

variable "image" {
  default = "Ubuntu Bionic"
}

variable "master_instance_type" {
  default = "DEV1-S"
}

variable "master_instance_count" {
  default = 1
}

variable "node_instance_type" {
  default = "DEV1-S"
}

variable "node_instance_count" {
  default = 2
}

