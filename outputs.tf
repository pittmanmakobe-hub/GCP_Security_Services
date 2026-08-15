output "workload_identity_provider" {
  description = "Full resource name to paste into a GitHub Actions workflow's workload_identity_provider input."
  value       = "projects/${data.google_project.current.number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.github.workload_identity_pool_id}/providers/${google_iam_workload_identity_pool_provider.github.workload_identity_pool_provider_id}"
}

output "gha_service_account_email" {
  description = "Service account GitHub Actions authenticates as via WIF."
  value       = google_service_account.gha.email
}
