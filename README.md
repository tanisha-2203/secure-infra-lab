# Secure Infrastructure Lab

A small, hands-on lab built to practice one core DevSecOps loop: **write infrastructure as code, scan it for security issues, fix them, and gate a CI/CD pipeline so insecure code can't merge silently.**

No cloud account is used anywhere in this repo. Everything is scanned statically — nothing is ever deployed (`terraform apply` is never run).

---

## What's in this repo

```
secure-infra-lab/
├── main.tf                        # Terraform: VPC, S3 bucket, IAM role
├── .terraform.lock.hcl            # Pinned provider versions
├── .gitignore
├── before-scan.txt                # Checkov output: initial insecure config
├── after-scan.txt                 # Checkov output: after fixing the IAM policy
├── final-scan.txt                 # Checkov output: after fixing remaining findings
├── .github/workflows/iac-scan.yml # CI pipeline: runs Checkov on every push/PR
└── k8s/
    ├── deployment.yaml            # Kubernetes manifest (hardened version)
    ├── k8s-before-scan.txt
    └── k8s-after-scan.txt
```

---

## 1. Terraform + Checkov: before and after

**The setup:** `main.tf` defines a VPC, a security group, an S3 bucket, and an IAM role — written deliberately insecure at first, to give Checkov something real to catch.

| Stage | Passed | Failed | Skipped |
|---|---|---|---|
| Initial scan (`before-scan.txt`) | 14 | 25 | 0 |
| After fixing the IAM policy (`after-scan.txt`) | 23 | 16 | 0 |
| After fixing remaining high-risk items (`final-scan.txt`) | 32 | 0 | 7 |

### The highest-risk fix: the IAM policy

**Before:**
```hcl
Action   = "*"
Resource = "*"
```
One stolen credential could do anything in the account.

**After:**
```hcl
Action   = ["s3:GetObject", "s3:PutObject"]
Resource = "${aws_s3_bucket.payments_data.arn}/*"
```
Scoped to exactly what the app needs. This single change resolved **9 of the 25 original findings** (privilege escalation, data exfiltration, credentials exposure, and more) — because they all traced back to one root cause: the wildcard policy.

### Other fixes applied

- **SSH exposure** — `0.0.0.0/0` on port 22 → restricted to the VPC's own CIDR block.
- **S3 public access block** — all four protections flipped from `false` to `true`.
- **Default security group** — locked down to deny all traffic (an empty default SG denies by default).
- **S3 versioning** — enabled, so objects can be recovered after accidental deletion or overwrite.

### Documented risk acceptance (not disabled — skipped with a reason)

Seven checks are intentionally skipped, each with a `#checkov:skip=<ID>:<reason>` comment directly above the resource in `main.tf`. Examples: KMS encryption, S3 access logging, VPC flow logs, cross-region replication. These need infrastructure this lab doesn't build (a KMS key, a log bucket), so each is an explicit, auditable decision — not a silenced scanner.

---

## 2. CI/CD gate: GitHub Actions

`.github/workflows/iac-scan.yml` runs Checkov automatically on every push and pull request:

- Pinned Checkov version (`checkov==3.3.19`) for reproducible results.
- `permissions: contents: read` — the workflow itself follows least privilege.
- Runner pinned to `ubuntu-24.04` rather than the floating `ubuntu-latest` tag.

**Two pipeline runs tell the story:**
- **Run #1** — red ❌, 16 failures, before the final round of fixes.
- **Run #2** — green ✅, 0 failures, 7 documented skips, after the fixes.

Checkov also scanned the workflow file itself (`CKV_GHA_*` checks) and passed all 24 checks — confirming the pipeline follows secure CI/CD practices, not just the infrastructure it scans.

---

## 3. Kubernetes manifest (extension of the same idea)

`k8s/deployment.yaml` applies the identical shift-left principle to a Kubernetes Deployment.

| Before | After |
|---|---|
| `image: ...:latest` | Pinned to a specific version tag |
| `privileged: true` | Removed; `runAsNonRoot`, dropped capabilities, `readOnlyRootFilesystem: true` |
| Hardcoded `DB_PASSWORD` in plain text | Pulled from a Kubernetes Secret via `secretKeyRef` |
| No resource limits | CPU/memory `limits` and `requests` set |
| Default service account token mounted | `automountServiceAccountToken: false` |

Scanned with the same Checkov tool used for the Terraform (`checkov -d k8s`), producing `k8s-before-scan.txt` and `k8s-after-scan.txt`.

**Note on Kubernetes Secrets:** they're base64-encoded, not encrypted. Using `secretKeyRef` here is better practice than a literal string in the manifest, but real protection comes from RBAC restricting who can read Secrets, etcd encryption at rest, and ideally an external secrets manager (e.g. Vault, AWS Secrets Manager).

### Kubernetes security topics covered (concept-level, ~30 min)

This lab is Terraform-focused, so Kubernetes cluster-level controls were studied rather than deployed:

- **RBAC** — Roles/ClusterRoles + RoleBindings scope what a user or service account can do; the same least-privilege idea as the IAM fix above.
- **Network policies** — pods can reach any pod by default; a default-deny policy plus explicit allows limits lateral movement.
- **Non-root containers** — `runAsNonRoot`, dropped capabilities, no privilege escalation, enforced cluster-wide via Pod Security Admission.
- **Secrets** — access-controlled storage, not encryption; real protection is RBAC + etcd encryption + an external secret store.
- **Image scanning** — scanning images (e.g. with Trivy) in CI and failing the build on high/critical CVEs, before deploy.

---

## 4. Ansible

Not used hands-on in this lab. Concept-level understanding only:

- Ansible is a configuration management tool. Playbooks are **idempotent** — running one repeatedly only changes what's out of the desired state, so it's safe to re-run.
- Typical security use case: **hardening playbooks** that apply a consistent baseline (e.g. CIS benchmarks) across a fleet of servers.

---

## Tools used

Terraform · Checkov · GitHub Actions · Git · (Kubernetes YAML, reviewed with Checkov)

## What I'd add next

- Branch protection requiring the Checkov check to pass before merging to `main`.
- SARIF upload so findings show in GitHub's Security tab.
- A second scanner (e.g. tfsec or Trivy) for cross-validation.
- Implementing the currently-skipped checks (KMS key, access logging, VPC flow logs) in a follow-up iteration.
