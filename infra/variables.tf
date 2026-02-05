variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "fiqftcosmos"
}

variable "location" {
  description = "Location for all resources"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Application = "Foundry-ft-Cosmos"
  }
}
