# Kazi AWS Architecture & CI/CD

Diagrams reflect the state after the persistent/runtime split (A11) with staging
values; production differs only in tfvars (2 NAT, no Spot, `email_mode=ses`, no
Mailpit/bastion by default).

## Infrastructure (staging)

```mermaid
flowchart TB
    user((Browser))
    operator((Operator))
    r53["Route 53<br/>heykazi.com (Z09699881RA35D5R3WUQV)"]

    subgraph aws["AWS af-south-1 — account 735927667026"]
        subgraph persistent["PERSISTENT LAYER — persistent/ root, never destroyed (~$10/mo idle)"]
            ecr[("ECR<br/>kazi/frontend..keycloak<br/>(cross-env, owned by staging)")]
            secrets[("Secrets Manager<br/>kazi/staging/* — 19 secrets")]
            s3[("S3 kazi-staging<br/>documents")]
            oidc["GitHub OIDC provider<br/>+ kazi-staging-github-actions role"]
        end

        subgraph runtime["RUNTIME LAYER — root, env-up.sh / env-down.sh"]
            subgraph vpc["VPC 10.1.0.0/16 (2 AZ)"]
                subgraph pub["Public subnets"]
                    alb["Public ALB :443<br/>ACM *.heykazi.com"]
                    nat["NAT GW x1 (staging)"]
                end
                subgraph priv["Private subnets — ECS Fargate Spot (4:1), Cloud Map kazi.internal"]
                    fe["Frontend (Next.js) :3000"]
                    gw["Gateway BFF (Spring) :8443<br/>profile: production"]
                    be["Backend (Spring Boot) :8080<br/>profiles: prod,keycloak"]
                    portal["Portal (Next.js) :3002"]
                    kc["Keycloak :8080<br/>realm b2mash"]
                    mp["Mailpit :1025 SMTP / :8025 UI<br/>(email_mode=capture only)"]
                    bastion["SSM bastion t4g.nano<br/>no SSH, no public IP"]
                    ialb["Internal ALB"]
                    rds[("RDS Postgres 16<br/>db kazi (schema-per-tenant)<br/>db kazi_keycloak")]
                    redis[("ElastiCache Redis<br/>TLS + auth token")]
                end
            end
            cw["CloudWatch Logs<br/>/kazi/staging/*"]
        end
    end

    user -->|HTTPS| r53
    r53 --> alb
    operator -.->|"aws ssm start-session<br/>(port forward)"| bastion

    alb -->|"staging-app (p50)"| fe
    alb -->|"staging-app/bff/* (p30)<br/>staging-app/api/* (p40)"| gw
    alb -->|"staging-portal (p20)"| portal
    alb -->|"staging-auth (p10)"| kc
    alb -->|"staging-mail (p25)<br/>Mailpit basic auth"| mp

    fe -->|"backend.kazi.internal"| be
    gw -->|"backend.kazi.internal"| be
    gw -->|sessions| redis
    gw -.->|"OIDC code flow"| kc
    fe -.-> ialb -.-> be
    be --> rds
    be --> s3
    be -->|"SMTP :1025 (capture)<br/>or SES :587 (ses)"| mp
    kc -->|"realm SMTP"| mp
    kc --> rds
    bastion -.->|":5432 / :6379"| rds
    bastion -.-> redis

    priv -.->|"awslogs"| cw
    priv -. "image pulls (execution role)" .-> ecr
    priv -. "secret injection" .-> secrets
```

Notes:
- The runtime layer references the persistent layer only via **naming convention
  + data sources** (`kazi/staging/<secret>`, `kazi/<svc>` ECR, `kazi-staging`
  bucket) — no remote-state coupling.
- `env-down.sh` destroys everything in the runtime box; RDS writes the final
  snapshot `kazi-staging-postgres-final`, which `env-up.sh` restores from
  (tenant schemas + Keycloak realm + users survive). Redis sessions and the
  Mailpit inbox do not.
- Switching `email_mode` capture↔ses = `terraform apply` (backend SMTP env) +
  re-running the Keycloak realm SMTP bootstrap step.

## CI/CD

```mermaid
flowchart LR
    subgraph repos["GitHub repos"]
        bs["b2b-strawman<br/>(4 app services + keycloak image)"]
        kcs["keycloak-saas<br/>(image + realm bootstrap)"]
        infra["aws-infra<br/>(Terraform, 2 layers)"]
    end

    subgraph actions["GitHub Actions (assume kazi-staging-github-actions via OIDC)"]
        seed["seed-images<br/>(manual, one-off)<br/>build ALL 5 → ECR :staging<br/>NO ECS"]
        ds["deploy-staging<br/>(on merge to main)<br/>changed services only"]
        dp["deploy-prod<br/>(manual + confirm)<br/>re-tag 4 from :staging,<br/>rebuild frontend"]
        rb["rollback<br/>(manual, per env)<br/>previous task def revision"]
        tf["terraform.yml<br/>PR: plan both layers<br/>merge: apply persistent→runtime<br/>dispatch: plan/apply/destroy per layer+env<br/>(destroy needs 'destroy-&lt;env&gt;')"]
        kcd["keycloak deploy<br/>(on merge)"]
    end

    subgraph awsT["AWS"]
        ecrT[("ECR kazi/*")]
        ecsT["ECS services<br/>kazi-staging-*"]
        infraT["VPC / ALB / RDS / Redis /<br/>Mailpit / bastion / DNS"]
    end

    bs --> seed --> ecrT
    bs --> ds -->|"build → push :sha+:staging"| ecrT
    ds -->|"new task def revision<br/>+ smoke tests"| ecsT
    bs --> dp --> ecrT
    dp --> ecsT
    bs --> rb --> ecsT
    kcs --> kcd --> ecrT
    kcd --> ecsT
    infra --> tf -->|"apply = env-up<br/>destroy = env-down<br/>(RDS final-snapshot dance)"| infraT
    ecsT -->|pull| ecrT
```

## First-provisioning order (Part B runbook)

```mermaid
flowchart TB
    b1["1 · bootstrap/<br/>state bucket + lock table"]
    b2["2 · scripts/persistent-up.sh staging<br/>ECR + 19 secrets + S3 + OIDC/CI role"]
    b3["3 · populate secrets<br/>(SMTP creds can stay placeholders<br/>while email_mode=capture)"]
    b4["4 · set AWS_ROLE_ARN secret<br/>in all 3 repos (persistent output)"]
    b5["5 · run seed-images workflow<br/>all 5 images → ECR :staging"]
    b6["6 · redis-auth-token secret value"]
    b7["7 · scripts/env-up.sh staging<br/>runtime comes up on seeded images"]
    b8["8 · create kazi_keycloak DB + users<br/>via bastion port-forward;<br/>force-redeploy kc/gw/backend"]
    b9["9 · bootstrap-realm.sh<br/>(SMTP → mailpit.kazi.internal:1025)"]
    b10["10 · verify end-to-end<br/>login, portal, magic link in Mailpit UI"]
    b11["later · SES setup (B7)<br/>only when flipping email_mode=ses"]

    b1 --> b2 --> b3 --> b4 --> b5 --> b6 --> b7 --> b8 --> b9 --> b10 -.-> b11
```
