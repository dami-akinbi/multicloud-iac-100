variable "location" {
  description = "Azure deployment region"
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = "Dedicated Resource Group for Project 001"
  type        = string
  default     = "rg-url-shortener-001"
}

variable "app_name" {
  description = "Base name for Project 001 Azure resources"
  type        = string
  default     = "urlshortener001"
}

variable "image_tag" {
  description = "Container image tag built in Azure Container Registry"
  type        = string
  default     = ""
}