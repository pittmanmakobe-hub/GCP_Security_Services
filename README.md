# Lab 5.4 — GCP Security Services Baseline

Three identity-first controls for one GCP project: Org Policy enforced at
the API (rejection, not detection), Workload Identity Federation for GitHub
Actions (no service account keys), and Data Access audit logs (off by
default — the most-cited GCP audit finding).

## Prerequisites

- A GCP project with billing enabled and `cloudkms.googleapis.com`,
  `iam.googleapis.com`, `cloudresourcemanager.googleapis.com`,
  `orgpolicy.googleapis.com` enabled.
- `roles/orgpolicy.policyAdmin`, `roles/iam.workloadIdentityPoolAdmin`,
  `roles/logging.admin` at project scope.
- `gcloud auth login` (interactive) and `gcloud auth application-default
  login` (Terraform's `google` provider reads ADC).

## What each control satisfies

| Control | Resource(s) | Why it matters |
|---|---|---|
| `storage.uniformBucketLevelAccess` | `google_org_policy_policy.uniform_bucket_access` | CM-6 — rejects mixed ACL/IAM buckets at creation |
| `iam.disableServiceAccountKeyCreation` | `google_org_policy_policy.disable_sa_keys` | AC-2 — no long-lived key can be minted, full stop |
| `compute.requireOsLogin` | `google_org_policy_policy.require_oslogin` | AC-3 — SSH access tied to IAM identity, not baked-in keys |
| Workload Identity Federation | `wif.tf` | Replaces JSON key + GitHub Secret with a token minted per job, expires in 1 hour, never touches disk |
| Data Access audit logs | `audit_logs.tf` | Off by default in GCP; without this, reads of storage/KMS/IAM objects leave no trail at all |

## Usage

```bash
gcloud auth login
gcloud auth application-default login
gcloud services enable orgpolicy.googleapis.com --project=<your-gcp-project>

cd terraform/baselines/gcp
terraform init
terraform apply -var="gcp_project=<your-gcp-project>" -var="github_repository=<OWNER/REPO>"
```

Org Policy changes can take 5–10 minutes to propagate at the API. A test
immediately after apply may briefly still succeed.

After apply, wire the outputs into repo variables so `.github/workflows/gcp-wif-demo.yml` can use them:

```bash
gh variable set GCP_WORKLOAD_IDENTITY_PROVIDER --body "$(terraform output -raw workload_identity_provider)" --repo OWNER/REPO
gh variable set GCP_SERVICE_ACCOUNT --body "$(terraform output -raw gha_service_account_email)" --repo OWNER/REPO
```

## Verify

```bash
# Org Policies in effect
gcloud org-policies list --project=<your-gcp-project> \
  | grep -E "uniformBucket|disableServiceAccount|requireOsLogin"

# WIF pool exists
gcloud iam workload-identity-pools list --location=global --project=<your-gcp-project>

# Data Access logs enabled
gcloud projects get-iam-policy <your-gcp-project> --format=json \
  | python3 -c 'import sys,json; d=json.load(sys.stdin); print(json.dumps(d.get("auditConfigs",[]),indent=2))'

# Try a forbidden action — expect FAILED_PRECONDITION
gcloud iam service-accounts keys create /tmp/k.json \
  --iam-account=cgep-grc-gate-sa@<your-gcp-project>.iam.gserviceaccount.com \
  --project=<your-gcp-project>
```

**The lesson of Step 2:** the key-creation attempt above doesn't get flagged
after the fact by a finding three hours later — it's rejected at the API
before the key exists. That's the strongest layer of defense-in-depth GCP's
Org Policy gives you, and it's not something CloudTrail/Security Hub
(detective, after-the-fact) can do on their own.

## Capture evidence

```bash
mkdir -p evidence/lab-5-4
gcloud projects get-iam-policy <your-gcp-project> --format=json \
  > evidence/lab-5-4/iam-policy.json
```

`iam-policy.json` captures the `auditConfigs` block proving Data Access logs
are on — this is the artifact Lab 4.4's bundle/sign/upload step picks up.

If the project sits in an Organization with Security Command Center enabled:

```bash
gcloud scc findings list <ORG_ID> --source=- --format=json > evidence/lab-5-4/scc-findings.json
```

SCC is not provisioned by this Terraform (requires org admin); the Org
Policy enforcements above are the preventative-layer equivalent for
standalone projects without an Org.

## The Data Access logs lesson

Data Access audit logs are **off by default** in every GCP project. Admin
Activity logs (who created/deleted resources) are always on and free; Data
Access logs (who *read* a storage object, decrypted with a KMS key, or
touched an IAM policy) are not, and cost is the usual reason teams leave
them off. This is consistently the single most-cited finding in GCP audits
— not a misconfigured resource, just a missing "yes" to logging reads.
`audit_logs.tf` turns them on for the three services this project actually
uses (storage, KMS, IAM) rather than every service, to keep ingestion cost
predictable.

## Troubleshooting

- **Org Policy propagation latency** — first-apply changes can take 5–10
  minutes to take effect. Don't test enforcement immediately after apply.
- **`PERMISSION_DENIED` on `google_iam_workload_identity_pool_provider`** —
  you need `roles/iam.workloadIdentityPoolAdmin`, not just Owner.
- **WIF `attribute.repository` condition mismatch** — GitHub's
  `assertion.repository` is the literal `OWNER/REPO`. Case and the slash
  both matter; a mismatch surfaces as an opaque `PERMISSION_DENIED` from
  `auth@v2`.
- **Data Access logs cost** — a busy project can ingest GBs/day. Start with
  `storage.googleapis.com` alone before enabling KMS and IAM if cost is a
  concern.
- **`policySpec is not supported`** — the v2 Org Policy API isn't enabled.
  Run `gcloud services enable orgpolicy.googleapis.com`.
