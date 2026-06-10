variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "db_username" {
  type      = string
  sensitive = true
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "db_host" {
  type    = string
  default = "platform-db-rw.postgres.svc.cluster.local"
}

variable "db_name" {
  type    = string
  default = "platform"
}
