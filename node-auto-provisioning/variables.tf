variable "resource_group_name" {
  type = string
}

variable "resource_group_location" {
  type = string
}

variable "subscription_id" {
  type = string
}

variable "cluster_vnet_name" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "resource_tags" {
  type = map(string)
  default = {
    Environment     = "Development",
    SecurityControl = "Ignore",
    CostControl     = "Ignore"
  }
}
