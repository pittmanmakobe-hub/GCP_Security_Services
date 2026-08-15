variable "gcp_project" {
  description = "GCP project ID this baseline applies to."
  type        = string
}

variable "gcp_region" {
  description = "Default region for the google provider."
  type        = string
  default     = "us-central1"
}

variable "github_repository" {
  description = "GitHub repo allowed to assume the WIF service account, as OWNER/REPO. Must match exactly (case and slash matter) or the OIDC attribute_condition will reject every auth attempt."
  type        = string
  default     = "GRCEngClub/cgep-app-starter"
}
