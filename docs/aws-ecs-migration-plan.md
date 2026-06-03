# AWS ECS Migration Plan

Target deployment for the Advantage Master Program (excluding `projects` / TMS).
Replaces the current Civo k3s + ArgoCD direction with **AWS ECS on EC2 (Graviton)**.
Traefik in this repo stays as the **local-dev** gateway only; in AWS, ALB plays that role.

> Scope: `sales`, `identity`, `calender`, `observability`, `events`, plus this `gateway`
> repo (local dev only). `projects` (TMS) is **out of scope** — it keeps its existing
> ECS Fargate stack.

---

## 1. Goals

1. Run prod on AWS ECS at a target of **~$95–115/month** with off-hours shutdown,
   ~$135–160 always-on.
2. Keep the per-repo bounded-context model and the existing local-dev workflow
   (Traefik + Docker Compose) unchanged.
3. Modern, hardened images; OIDC-only AWS auth; no static keys.
4. Zero-downtime rolling deploys for app services; predictable rollback.
5. Self-hosted observability (Prometheus/VictoriaMetrics + Loki + Grafana) on the
   same ECS cluster — no managed Grafana / CloudWatch Insights bills.

## 2. Why ECS (not EKS, not Kubernetes)

1. EKS control plane alone is ~$73/mo before nodes, NAT, RDS — incompatible with the
   budget.
2. At 10–15 office users we don't need K8s features (HPA, complex scheduling,
   multi-tenant isolation).
3. ECS on EC2 + Compute Savings Plan is the cheapest AWS path that still gives us
   rolling deploys, service discovery, IAM-per-task, and ECR.
4. Fargate is rejected for the lean prod shape (~15 always-on tasks would cost
   $80–130/mo more than EC2 capacity).

## 3. Target architecture

```
                                 Route53 + ACM
                                       │
                                CloudFront (SPAs)
                              ┌────────┴────────┐
                              │                 │
                          S3 buckets         ALB (HTTPS)
                       (sales / identity /   │
                        calendar SPA)        │ host + path rules
                                             │
                          ┌──────────────────┼─────────────────┐
                          │                  │                 │
                     identity-api        sales-api       calendar-api
                     identity-logic   quotation-logic  projection-consumer
                     identity-dba     quotation-dba         audit-service
                     outbox-publisher outbox-publisher
                          │                  │                 │
                          └────────► Redpanda (1×, ECS+EBS) ◄──┘
                                             │
                                       RDS Postgres 17
                                    (single-AZ, multi-DB)

         Sidecar on every task: Fluent Bit (FireLens) → Loki
         Scrape /metrics: Prometheus (or VictoriaMetrics) → Grafana
```

1. **Compute**: 2× `t4g.medium` Graviton in an ECS-managed ASG, Bottlerocket AMI.
2. **Ingress**: ALB with ACM cert, host-based routing per app subdomain, `/api/*`
   path routing where the SPA and API share a host.
3. **Frontends**: built in CI, uploaded to S3, served via CloudFront. **No nginx /
   Caddy container in prod.**
4. **Database**: RDS Postgres 17, `db.t4g.micro`, single-AZ, separate logical DBs
   for identity / sales / calendar / audit / observability.
5. **Events bus**: single-node Redpanda 24.x on ECS with EBS-backed task volume.
   Accept SPOF for v1; plan a 3-node upgrade later.
6. **Networking**: 1 VPC, 2 public + 2 private subnets, **single NAT** (cost lever).
7. **Observability**: Prometheus or **VictoriaMetrics** (preferred — lower RAM),
   Loki 3.x (single-binary), Grafana 11, Fluent Bit 3.x as FireLens sidecar.
8. **Secrets**: AWS Secrets Manager; ECS injects as env at task start.
9. **Auth between GH and AWS**: OIDC, per-repo IAM deploy roles.

## 4. Repo changes

### `Advantage_master_program_infra` — rebuild as AWS Terraform

Layout under `terraform/aws/`:

1. `modules/network` — VPC, public + private subnets, single NAT, IGW, RTs.
2. `modules/ecs-cluster` — ECS cluster, ASG with Bottlerocket, capacity provider,
   instance profile.
3. `modules/alb` — ALB, listeners, target groups, host/path rules, ACM ref.
4. `modules/rds` — Postgres 17, parameter group, subnet group, KMS.
5. `modules/redpanda` — single ECS service + EBS volume + private DNS.
6. `modules/ecs-service` — reusable: task def, service, autoscaling, log group,
   IAM exec/task roles, Secrets Manager refs.
7. `modules/cloudfront-spa` — S3 bucket + OAC + CloudFront dist + cache policy.
8. `modules/observability` — VictoriaMetrics, Loki, Grafana ECS services + EBS.
9. `modules/scheduler` — IAM + EventBridge rules used by the off-hours workflows
   (or just GitHub Actions cron — no infra needed).
10. `envs/prod/`, `envs/staging/` (staging optional, off by default).

State: S3 + DynamoDB lock. Provider: `hashicorp/aws ~> 5.70`. Tooling: OpenTofu
1.8+ or Terraform 1.9+.

Actions:

1. Archive existing Civo Terraform under `legacy-civo/`.
2. Delete `bootstrap/bootstrap-cluster.sh` and ArgoCD-related workflows
   (`prod-up.yml`, `staging-up.yml`, `staging-scale.yml`,
   `staging-nightly-zero.yml`, `prod-scale.yml`).
3. Add `aws-prod-apply.yml` + `aws-staging-apply.yml` (manual dispatch + protected
   `production` env).

### `Advantage_master_program_depl` — rebuild as ECS deploy controller

```
depl/
├── task-definitions/
│   ├── sales-api.json.tpl
│   ├── sales-quotation-logic.json.tpl
│   ├── sales-quotation-dba.json.tpl
│   ├── sales-outbox-publisher.json.tpl
│   ├── identity-auth.json.tpl
│   ├── identity-logic.json.tpl
│   ├── identity-dba.json.tpl
│   ├── identity-outbox-publisher.json.tpl
│   ├── calendar-api.json.tpl
│   ├── calendar-projection-consumer.json.tpl
│   ├── observability-audit.json.tpl
│   ├── redpanda.json.tpl
│   ├── victoriametrics.json.tpl
│   ├── loki.json.tpl
│   ├── grafana.json.tpl
│   └── migration-runner.json.tpl       # one-shot Alembic
├── service-config/<service>.yaml       # desiredCount, CPU/mem, target group ARN
├── scripts/
│   ├── render-taskdef.ps1
│   ├── deploy.ps1
│   ├── run-migrations.ps1
│   └── smoke-tests.ps1
├── smoke/*.http
└── .github/workflows/
    ├── deploy-reusable.yml             # called by every app repo on main
    ├── system-up.yml                   # cron 06:30 weekdays + dispatch
    ├── system-down.yml                 # cron 19:00 weekdays
    ├── rollback.yml                    # manual: revert to previous task def
    └── nightly-canary.yml              # post-up smoke run
```

### Per-app repo CI changes (`sales`, `identity`, `observability`, `events`, `calender`)

1. Replace GHCR push with **ECR** push (OIDC).
2. Add **Trivy** (fail HIGH/CRITICAL) + **syft** SBOM.
3. Build `linux/arm64` only (Graviton) via `docker/build-push-action@v6`.
4. On push to `main`, `workflow_call` into `depl/.github/workflows/deploy-reusable.yml`
   with the image digests.
5. Drop the existing "bump digest in depl" step; deploy workflow updates ECS
   directly.
6. Frontend repos: skip image build; instead `aws s3 sync` build output +
   `aws cloudfront create-invalidation`.
7. Keep `PIP_CONF` as a GH secret (build-time only) until private wheels are
   published to CodeArtifact.

### `Advantage_master_program_gateway` (this repo)

1. **No CI/CD changes for cloud** — Traefik remains the local-dev gateway.
2. Document in `AGENTS.md` that Traefik is local-only and ALB is its cloud
   counterpart (already partially noted).
3. `system.local.env` and `scripts/*` unchanged.

### Image hardening (every service repo)

1. Multi-stage build → **`gcr.io/distroless/python3-debian12:nonroot`** runtime,
   pinned by digest.
2. `readonlyRootFilesystem: true`, `linuxParameters.capabilities.drop: ["ALL"]`,
   non-root UID 10001 (Sales/Identity already do this).
3. Healthcheck endpoints (`/health`, `/ready`) must reflect real readiness
   (DB pool initialized, Kafka producer connected).
4. Pinned base image digests; **Renovate** keeps them current.
5. ECR enhanced scanning (Inspector v2) on every push.
6. Image-size budget: API services <150 MB; frontends not built as images.

## 5. CI/CD pipeline

```mermaid
flowchart LR
  A[Push to main] --> B[Lint + tests]
  B --> C[Build arm64 images]
  C --> D[Trivy + SBOM]
  D --> E[Push to ECR<br/>tag=git sha]
  E --> F[Call deploy-reusable.yml]
  F --> G[Render task def<br/>+ inject secrets ARNs]
  G --> H[register-task-definition<br/>+ update-service]
  H --> I[Run Alembic<br/>one-shot ECS task]
  I --> J[wait services-stable]
  J --> K[Smoke tests via ALB]
  K --> L[Tag release]
```

1. **PRs**: stages 1–4 only. No push, no deploy.
2. **`main`**: full pipeline, gated by GitHub `production` environment.
3. **Migrations**: one-shot `migration-runner` task (Alembic), separate from API
   container startup. Idempotent.
4. **Rollback**: previous task def revision is always available; `rollback.yml`
   re-points services in 30–60s.
5. **Notifications**: deploy success/failure to Slack (or Teams) via webhook.

## 6. Zero-downtime deploy settings (per task def)

| Setting | Value | Why |
|---|---|---|
| `minimumHealthyPercent` | 100 | Never drop capacity |
| `maximumPercent` | 200 | Spin up new before old leaves |
| `healthCheckGracePeriodSeconds` | 45 | Skip ALB checks during boot |
| `stopTimeout` | 30 | Graceful uvicorn shutdown |
| ALB `deregistration_delay` | 30s | Drain in-flight connections |
| Target group `healthy_threshold` | 2 | Avoid flapping |
| Target group `interval` | 10s | Detect bad task fast |

Rule: **migrations must be backward-compatible** (old code works against new
schema and vice versa). Same backward-compat rule already applies to API
responses and token claims.

## 7. Observability

1. **Logs**: Fluent Bit FireLens sidecar on every app task → Loki 3.x. 14-day
   retention.
2. **Metrics**: VictoriaMetrics (preferred) or Prometheus, scraping `/metrics`
   via ECS Service Connect / Cloud Map. 14-day retention.
3. **Host metrics**: `node_exporter` + `cAdvisor` daemon service (one task per
   EC2 host).
4. **Dashboards**: Grafana 11 behind ALB at `grafana.<domain>`. Auth via
   identity OIDC if possible, otherwise basic auth + WAF allowlist.
5. **Audit events**: existing observability `audit_service` runs as ECS service,
   consumes `advantage.audit.events` from Redpanda, writes to RDS.
6. **Alerts**: Slack webhook for high 5xx rate, p95 latency, disk free,
   container restart spikes, RDS CPU, NAT egress spikes.

## 8. Off-hours shutdown

UK office hours assumed: weekdays 07:00–19:00.

1. `system-down.yml` (cron `0 19 * * 1-5`):
   - `aws ecs update-service --desired-count 0` for every app + observability
     service.
   - `aws autoscaling update-auto-scaling-group --desired-capacity 0`.
   - `aws rds stop-db-instance` (auto-restarts within 7 days; weekly cycle is
     fine).
2. `system-up.yml` (cron `30 6 * * 1-5`):
   - `rds start-db-instance` → wait `available`.
   - ASG to 2.
   - ECS services back to configured `desiredCount`.
   - Smoke run; alert if any service is not healthy by 06:55.
3. **Manual override**: `system-up.yml` `workflow_dispatch` for evening/weekend
   work; "Keep Awake" repo variable disables `system-down` for N hours.
4. **What stays on**: ALB, Route53, ACM, ECR, S3, CloudFront, NAT, RDS storage.

Cost impact: ~25% off the bill, ~$35–45/mo saved.

## 9. Cost estimate (eu-west-1, 10–15 users)

| Item | Sizing | Monthly USD |
|---|---|---|
| ECS control plane | free | 0 |
| EC2 (2× t4g.medium, 1-yr Compute Savings Plan) | 24/7 | ~$38 |
| EBS (gp3, ~120 GB total) | host + Loki/VM/Redpanda | ~$12 |
| ALB | low LCU | ~$20 |
| RDS Postgres 17 | db.t4g.micro single-AZ, 20 GB gp3 | ~$18 |
| NAT Gateway (single) | low traffic | ~$35 |
| ECR | ~5 GB | ~$1 |
| CloudWatch (errors only) | 5 GB ingest, 7-day retention | ~$5 |
| Secrets Manager | ~10 secrets | ~$4 |
| Route53 + ACM | 1 HZ, free certs | ~$1 |
| Data egress | low | ~$3 |
| **Always-on prod** | | **~$135–160** |
| **Off-hours schedule (~36% uptime)** | | **~$95–115** |

Optional staging on-demand (`db.t4g.micro`, scale 0 nights/weekends): **+$10–15**.

## 10. Decisions

1. ECS on EC2 (Graviton) + Compute Savings Plan; not Fargate, not EKS.
2. ALB replaces Traefik in cloud. Traefik stays for local dev only.
3. Frontends: S3 + CloudFront (no nginx, no Caddy).
4. RDS Postgres 17 single-AZ; multiple logical DBs on one instance.
5. Single-node Redpanda on ECS; revisit at ~30 users.
6. Single NAT (cost lever).
7. Self-hosted VictoriaMetrics + Loki + Grafana; FireLens for logs.
8. ECR replaces GHCR; OIDC; no static AWS keys.
9. Distroless `nonroot` runtime, pinned digests, Trivy + ECR scanning.
10. Backward-compatible migrations; Alembic via one-shot ECS task.
11. Off-hours scheduler via GitHub Actions cron (no Lambda).
12. ArgoCD removed; deployment is GH Actions → ECS API.
13. `projects` (TMS) excluded from this migration.

## 11. Phased delivery

1. **Phase 1 — Image hardening** (per app repo): distroless runtime, healthchecks,
   Trivy, SBOM, arm64.
2. **Phase 2 — Infra Terraform**: VPC, ECS cluster, ALB, RDS, NAT, ECR, S3,
   CloudFront, observability stack, scheduler IAM.
3. **Phase 3 — `depl` rebuild**: task-def templates, `deploy-reusable.yml`,
   migration runner, rollback, smoke tests.
4. **Phase 4 — Per-repo CI cutover**: GHCR → ECR, call new deploy workflow.
5. **Phase 5 — Observability bring-up**: VictoriaMetrics + Loki + Grafana +
   FireLens; first dashboards and alerts.
6. **Phase 6 — Off-hours scheduler**: `system-up.yml` / `system-down.yml`.
7. **Phase 7 — Cutover**: stand up prod ECS, pg_dump → RDS restore, flip DNS,
   1-week soak, decommission Civo.

## 12. Verification

1. `terraform plan` clean in `envs/prod`.
2. ECR shows new digests after each merge to main.
3. `aws ecs describe-services` → `desired == running` for all services.
4. ALB target groups all healthy.
5. Smoke: `curl https://identity.<domain>/health`, login, Sales
   `/api/sales/quotes`, Calendar projection lag = 0.
6. Trivy reports zero unwaived HIGH/CRITICAL.
7. Image-size budget met (API <150 MB).
8. Grafana dashboards: per-service CPU, memory, RPS, p95, 5xx; host CPU/mem/disk;
   Loki query for any service returns recent logs.
9. Off-hours: AWS Cost Explorer shows compute drop on the day after first
   `system-down`; `system-up` brings everything back green by 06:55.
10. Rollback workflow returns to N-1 task def in <2 min.

## 13. Further considerations

1. **Renovate vs Dependabot** for base-image digest bumps — recommend Renovate
   (stronger Dockerfile + Terraform support).
2. **Notifications channel** — Slack vs Teams; pick before workflow drafting.
3. **Permanent staging?** — recommend none; use on-demand staging or PR previews.
4. **Holiday calendar** for off-hours — recommend ignore; users trigger wake.
5. **Redpanda HA** — single-node SPOF accepted for v1; plan 3-node upgrade at
   ~30 users (~+$30/mo) or move to MSK Serverless (~+$100/mo).
6. **Blue/green via CodeDeploy** instead of rolling — only if strict version
   isolation becomes a need.
