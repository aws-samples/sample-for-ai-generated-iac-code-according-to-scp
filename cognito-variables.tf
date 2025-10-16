
# Variables for Cognito configuration
variable "user_pool_name" {
  description = "Name for the Cognito User Pool"
  type        = string
  default     = "api-user-pool"
}


variable "app_client_name" {
  description = "name of the application client"
  type = string
  default = "api-client"
}
variable "cognito_domain_name" {
  description = "Domain name for Cognito User Pool"
  type        = string
  default     = "ai-scp-app"
}

variable "callback_urls" {
  description = "List of callback URLs for Cognito"
  type        = list(string)
  default     = ["https://localhost:8080/callback"]
}

variable "logout_urls" {
  description = "List of logout URLs for Cognito"
  type        = list(string)
  default     = ["https://localhost:8080/logout"]
}


variable "access_token_expiration" {
  description = "Expiration time in minutes for access token"
  type        = string
  default     = "60"
}

variable "id_token_expiration" {
  description = "Expiration time in minutes for ID token"
  type        = string
  default     = "60"
}

variable "refresh_token_expiration" {
  description = "Expiration time in minutes for refresh token"
  type        = string
  default     = "30"
}
