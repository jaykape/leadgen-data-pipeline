variable "db_username" {
  type = string
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "keypair" {
  type      = string
  sensitive = true
}

