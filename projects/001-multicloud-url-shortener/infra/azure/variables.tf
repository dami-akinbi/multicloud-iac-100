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
  description = "Alphanumeric base name for Project 001 Azure resources"
  type        = string
  default     = "urlshortener001"
}

variable "image_tag" {
  description = "Image repository and tag inside ACR, e.g. url-shortener:latest (falls back to public quickstart image during PR plans)"
  type        = string
  default     = ""
}
