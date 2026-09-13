# SCAA Final Project — Complete Step-by-Step Guide

**For:** a beginner who already built the app (Step 1) and now needs Docker + GitLab CI/CD + Terraform + AWS + CloudWatch.
**Your stack:** ASP.NET Core 10 MVC (`SCAA-Final/SCAA-Final-Web`).
**Language level:** simple English. Every command is written out fully.

---

## Table of contents

1. [What you are building (the big picture)](#1-what-you-are-building)
2. [Before you start — accounts and tools](#2-before-you-start)
3. [Step 1 review — fix your application and Dockerfile](#3-step-1-review)
4. [Step 2 — prepare AWS (state bucket + CI user)](#4-step-2-prepare-aws)
   * [4A. Step 2 in full detail — empty AWS account, console walkthrough](#4a-step-2-detailed)
5. [Step 3 — Terraform infrastructure as code](#5-step-3-terraform)
6. [Step 4 — GitLab CI/CD pipeline](#6-step-4-gitlab-cicd)
7. [Step 5 — deployment and monitoring check](#7-step-5-deployment-and-monitoring)
8. [Step 6 — destroy the infrastructure](#8-step-6-destroy)
9. [Step 7 — README.md for the graders](#9-step-7-readme)
10. [Best practices checklist (what you get points for)](#10-best-practices-checklist)
11. [Troubleshooting](#11-troubleshooting)
12. [Final submission checklist](#12-final-submission-checklist)

---

<a name="1-what-you-are-building"></a>

## 1. What you are building

Read this part slowly. If you understand the picture, the rest is only typing.

```
   You push code to GitLab
            |
            v
  +---------------------------+
  | GitLab CI/CD pipeline     |
  +---------------------------+
  | 1. build_test             |  Build the Docker image, start it, call /health.
  |                           |  If /health is not 200 -> pipeline STOPS.
  +---------------------------+
  | 2. terraform_apply        |  Terraform creates AWS resources:
  |                           |    ECR (image storage)
  |                           |    IAM role (permissions for the server)
  |                           |    Security Group (firewall)
  |                           |    EC2 instance (the server)
  |                           |    CloudWatch log groups + alarm + dashboard
  +---------------------------+
  | 3. deploy                 |  Push image to ECR, then tell EC2 (via SSM)
  |                           |  to pull the image and run the container.
  +---------------------------+
  | 4. destroy (manual)       |  Terraform deletes everything, so you pay 0.
  +---------------------------+
            |
            v
   http://<EC2 public IP>  <- you open this in the browser
            |
            v
   Container logs -> CloudWatch Logs
   CPU / memory / disk -> CloudWatch Metrics
```

### Key words, one sentence each

| Word | Meaning |
|---|---|
| **Docker image** | A frozen box that contains your app plus everything it needs to run. |
| **Container** | A running copy of an image. |
| **ECR** | Amazon's private storage for Docker images (like a private Docker Hub). |
| **EC2** | A virtual Linux computer in Amazon's data centre. |
| **IAM role** | A set of permissions that you attach to the EC2 server. |
| **Security Group** | A firewall: which ports are open, and to whom. |
| **Terraform** | A tool where you *write* infrastructure in files, then it creates or deletes it. |
| **Terraform state** | A JSON file that remembers what Terraform already created. It must be shared, so we keep it in S3. |
| **CloudWatch** | AWS monitoring: logs, metrics, alarms, dashboards. |
| **SSM (Systems Manager)** | AWS feature that runs a command on an EC2 server **without SSH**. Safer — no keys to manage. |
| **GitLab CI/CD** | A robot that runs commands for you every time you push code. Configured in `.gitlab-ci.yml`. |
| **Pipeline / stage / job** | Pipeline = the whole run. Stage = a group of steps. Job = one script. |

### Why SSM and not SSH?

With SSH you must open port 22, create a key pair, store the private key inside GitLab, and hope nobody steals it.
With SSM you open **no extra port** and store **no key**. It is simpler *and* it gives you points for "restricted Security Groups" and "least privilege IAM".

### Money warning

EC2 `t3.micro`, ECR and CloudWatch are almost free in the AWS Free Tier, but **not free forever**.
Rule: **always run the `destroy` job when you finish working.** Set a phone reminder.

---

<a name="2-before-you-start"></a>

## 2. Before you start

### 2.1 Accounts you need

1. **AWS account** with a card attached (Free Tier is fine) — https://aws.amazon.com
2. **GitLab account** (free) — https://gitlab.com

> Your repository is currently on **GitHub** (`https://github.com/nikachkharti/SCAA-FinalProject.git`).
> The task requires **GitLab CI**, so the code must also live on GitLab. Section 6.1 shows how to move it.

### 2.2 Tools on your Windows machine

| Tool | Check command | Status |
|---|---|---|
| Docker Desktop | `docker --version` | ✅ you have 29.6.1 |
| AWS CLI v2 | `aws --version` | ✅ you have 2.32.26 |
| .NET SDK 10 | `dotnet --version` | ✅ you have 10.0.401 |
| Git | `git --version` | ✅ you have it |
| Terraform | `terraform -version` | ❌ **not installed — install it now** |

**Install Terraform (PowerShell):**

```powershell
winget install --id HashiCorp.Terraform -e
```

Close the terminal, open a new one, then check:

```powershell
terraform -version
```

You should see `Terraform v1.13.x` or newer.

> You only need Terraform locally to *test* your code and to run `terraform fmt`. The real `apply` happens in the pipeline.

---

<a name="3-step-1-review"></a>

## 3. Step 1 review — fix your application and Dockerfile

You said Step 1 is done. It is *almost* done. Below are the real problems I found in your code. **Do not skip this section** — three of these will make the app unreachable in the browser.

### Problem list

| # | File | Problem | Why it matters |
|---|---|---|---|
| 1 | `Dockerfile` | No `LABEL` metadata | The task explicitly asks for author + version. Free points lost. |
| 2 | `Program.cs` | `app.UseHttpsRedirection()` | The container serves only HTTP on 8080. This line sends the browser to `https://...:8081`, which is closed. **The site will look broken.** |
| 3 | `Program.cs` | `app.UseHsts()` | Tells the browser "never use HTTP for this host again". Your EC2 has no certificate, so the browser refuses to load. |
| 4 | — | No `/health` endpoint | The pipeline needs a simple URL to test ("Build & Test" stage). |
| 5 | `Dockerfile` | `EXPOSE 8081` | You do not serve HTTPS. Remove it — keep the image honest and minimal. |
| 6 | `.gitignore` | No Terraform rules | You could accidentally commit `terraform.tfstate`, which can contain secrets. |

### 3.1 Fix `Program.cs`

Open `SCAA-Final/SCAA-Final-Web/Program.cs` and replace the whole file with this:

```csharp
namespace SCAA_Final_Web
{
    public class Program
    {
        public static void Main(string[] args)
        {
            var builder = WebApplication.CreateBuilder(args);

            builder.Services.AddControllersWithViews();

            // Health checks give us a simple /health URL.
            // The CI pipeline and the deploy script call it to prove the app is alive.
            builder.Services.AddHealthChecks();

            // Simple one-line console logging.
            // Docker forwards console output to CloudWatch Logs for us.
            builder.Logging.ClearProviders();
            builder.Logging.AddSimpleConsole(options =>
            {
                options.SingleLine = true;
                options.TimestampFormat = "yyyy-MM-dd HH:mm:ss ";
            });

            var app = builder.Build();

            if (!app.Environment.IsDevelopment())
            {
                app.UseExceptionHandler("/Home/Error");
            }

            // NOTE: no UseHttpsRedirection() and no UseHsts().
            // Inside the container we serve plain HTTP on port 8080 only.
            // In real production, TLS would be handled by an ALB or CloudFront.

            app.UseRouting();
            app.UseAuthorization();

            app.MapStaticAssets();

            // Liveness endpoint used by CI and by the deploy script.
            app.MapHealthChecks("/health");

            // Small info endpoint - proves which version is running on the server.
            app.MapGet("/version", () => Results.Json(new
            {
                application = "SCAA-Final-Web",
                version = Environment.GetEnvironmentVariable("APP_VERSION") ?? "local",
                host = Environment.MachineName,
                utcTime = DateTime.UtcNow
            }));

            app.MapControllerRoute(
                name: "default",
                pattern: "{controller=Home}/{action=Index}/{id?}")
                .WithStaticAssets();

            app.Run();
        }
    }
}
```

**What changed and why:**

* `AddHealthChecks()` + `MapHealthChecks("/health")` — `GET /health` now returns `200 Healthy`. This is your "basic validation" for the Build & Test stage.
* Removed `UseHttpsRedirection` and `UseHsts` — fixes the "site not reachable" bug.
* `/version` — shows which image tag is deployed. Very useful for the demo and for the graders.
* `AddSimpleConsole` — clean one-line logs, which look good in CloudWatch.

### 3.2 Rewrite the Dockerfile

Open `SCAA-Final/SCAA-Final-Web/Dockerfile` and replace it with this:

```dockerfile
# syntax=docker/dockerfile:1

# ---------------------------------------------------------------------------
# Stage 1: build - uses the big SDK image (about 1 GB). It never ships.
# ---------------------------------------------------------------------------
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
ARG BUILD_CONFIGURATION=Release
WORKDIR /src

# Copy only the project file first, then restore.
# Docker caches this layer, so NuGet restore is skipped when only code changes.
COPY ["SCAA-Final-Web/SCAA-Final-Web.csproj", "SCAA-Final-Web/"]
RUN dotnet restore "SCAA-Final-Web/SCAA-Final-Web.csproj"

# Now copy the rest of the source and publish.
COPY . .
WORKDIR /src/SCAA-Final-Web
RUN dotnet publish "SCAA-Final-Web.csproj" \
        -c $BUILD_CONFIGURATION \
        -o /app/publish \
        /p:UseAppHost=false

# ---------------------------------------------------------------------------
# Stage 2: runtime - small image (about 110 MB). Only this one is shipped.
# ---------------------------------------------------------------------------
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS final

# Build arguments, filled in by the CI pipeline.
ARG APP_VERSION=0.0.0-local
ARG BUILD_DATE=unknown
ARG VCS_REF=unknown

# --- Required metadata (OCI standard labels) -------------------------------
LABEL org.opencontainers.image.title="SCAA-Final-Web" \
      org.opencontainers.image.description="SCAA DevOps final project - ASP.NET Core MVC web application" \
      org.opencontainers.image.authors="Nikoloz Chkhartishvili <nika.chkhartishviliyt7@gmail.com>" \
      org.opencontainers.image.vendor="SCAA DevOps Course" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.licenses="MIT" \
      maintainer="Nikoloz Chkhartishvili <nika.chkhartishviliyt7@gmail.com>"

WORKDIR /app

# The application listens on port 8080 (plain HTTP) inside the container.
ENV ASPNETCORE_ENVIRONMENT=Production \
    ASPNETCORE_HTTP_PORTS=8080 \
    DOTNET_RUNNING_IN_CONTAINER=true \
    APP_VERSION=${APP_VERSION}

COPY --from=build /app/publish .

# Run as a non-root user. $APP_UID (=1654) is defined by the Microsoft base image.
USER $APP_UID

EXPOSE 8080

ENTRYPOINT ["dotnet", "SCAA-Final-Web.dll"]
```

**Why this Dockerfile earns full marks:**

* **Multi-stage build** — the 1 GB SDK stays in stage 1. Only the small runtime image goes to ECR.
* **Metadata** — the `LABEL` lines give author and version, exactly as the task asks. They use the OCI standard names, which is the professional way.
* **Non-root user** — `USER $APP_UID` means the process cannot write to system folders. If someone breaks the app, damage is limited.
* **Layer caching** — `csproj` copied before the source, so restore is cached.
* **One port only** — 8080, no HTTPS confusion.
* **`ARG` + `LABEL`** — the pipeline passes the real version at build time.

Check the labels after building:

```powershell
docker inspect scaa-final-web:test --format "{{json .Config.Labels}}"
```

### 3.3 Update `docker-compose.yml` (local testing only)

`SCAA-Final/docker-compose.yml`:

```yaml
name: scaa

services:
  scaa-final-web:
    image: ${DOCKER_REGISTRY-}scaa-final-web
    container_name: scaa-final-web
    build:
      context: .
      dockerfile: SCAA-Final-Web/Dockerfile
      args:
        APP_VERSION: "local-dev"
    ports:
      - "5080:8080"
    environment:
      ASPNETCORE_ENVIRONMENT: Production
    restart: unless-stopped
```

Compose is only for your laptop. AWS does not use it.

### 3.4 Test locally before touching AWS

Open PowerShell in `C:\Users\User\Desktop\SCAA-FinalProject`:

```powershell
# 1. Build
docker build --pull `
  -f SCAA-Final/SCAA-Final-Web/Dockerfile `
  -t scaa-final-web:test `
  --build-arg APP_VERSION=test-1 `
  SCAA-Final

# 2. Run
docker run -d --name scaa-test -p 8080:8080 scaa-final-web:test

# 3. Wait a few seconds, then check health
curl.exe http://localhost:8080/health

# 4. Check version info
curl.exe http://localhost:8080/version

# 5. Open the home page in a browser
start http://localhost:8080

# 6. Look at the logs
docker logs scaa-test

# 7. Clean up
docker rm -f scaa-test
docker rmi scaa-final-web:test
```

`curl.exe http://localhost:8080/health` must print `Healthy`.
**Do not continue until this works.** Fixing it locally takes 2 minutes; fixing it on EC2 takes an hour.

> The build context is `SCAA-Final` (not the repo root), because the Dockerfile copies `SCAA-Final-Web/SCAA-Final-Web.csproj`. Keep this in mind — the pipeline uses exactly the same paths.

### 3.5 Update `.gitignore`

Add these lines to the **end** of `C:\Users\User\Desktop\SCAA-FinalProject\.gitignore`:

```gitignore
# ---- Terraform ----
**/.terraform/*
*.tfstate
*.tfstate.*
*.tfstate.backup
crash.log
crash.*.log
override.tf
override.tf.json
*_override.tf
*_override.tf.json
.terraformrc
terraform.rc
tfplan
*.tfplan

# Never commit variable values that may contain secrets
*.auto.tfvars
secrets.tfvars

# ---- CI helper files ----
tf_output.json
image/
```

> **Important:** `terraform.tfstate` can contain sensitive data. Our state lives in S3, but this rule protects you if you ever run Terraform on your laptop.

---

<a name="4-step-2-prepare-aws"></a>

## 4. Step 2 — prepare AWS

Two things must exist **before** the pipeline runs for the first time:

1. An **S3 bucket** to hold the Terraform state.
2. An **IAM user** whose access keys the pipeline uses.

This is called *bootstrapping*. It is normal that these two things are created by hand — Terraform cannot store its own state in a bucket that does not exist yet.

### 4.1 Log in with AWS CLI on your laptop

In the AWS Console: **IAM → Users → your user → Security credentials → Create access key → Command Line Interface (CLI)**.
Copy the key ID and secret.

```powershell
aws configure
```

Answer:

```
AWS Access Key ID     : AKIA....................
AWS Secret Access Key : ........................
Default region name   : eu-central-1
Default output format : json
```

Verify:

```powershell
aws sts get-caller-identity
```

You should see your account ID. Write that account ID down — you will need it.

> **Region choice:** `eu-central-1` (Frankfurt) is the closest AWS region to Georgia, so the site will feel fast. If you use a different region, change it *everywhere* in this guide.

### 4.2 Create the S3 bucket for Terraform state

Bucket names must be **globally unique** across all AWS customers. Add your name and a random number.

```powershell
$env:TF_STATE_BUCKET = "scaa-final-tfstate-nika-7431"
$env:AWS_REGION = "eu-central-1"

# Create the bucket
aws s3api create-bucket `
  --bucket $env:TF_STATE_BUCKET `
  --region $env:AWS_REGION `
  --create-bucket-configuration LocationConstraint=$env:AWS_REGION

# Turn on versioning - lets you recover an old state if something breaks
aws s3api put-bucket-versioning `
  --bucket $env:TF_STATE_BUCKET `
  --versioning-configuration Status=Enabled

# Encrypt everything at rest
aws s3api put-bucket-encryption `
  --bucket $env:TF_STATE_BUCKET `
  --server-side-encryption-configuration '{\"Rules\":[{\"ApplyServerSideEncryptionByDefault\":{\"SSEAlgorithm\":\"AES256\"}}]}'

# Block all public access
aws s3api put-public-access-block `
  --bucket $env:TF_STATE_BUCKET `
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

Check it exists:

```powershell
aws s3 ls | Select-String scaa-final-tfstate
```

> **Remember your bucket name.** You will put it into a GitLab variable called `TF_STATE_BUCKET`.

### 4.3 Create the IAM user for GitLab CI

The pipeline needs its own user with its own keys. Never use your personal root keys.

**Step A — create the user:**

```powershell
aws iam create-user --user-name gitlab-ci-scaa
```

**Step B — create a policy file.** Create a file on your Desktop called `ci-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "TerraformStateBucket",
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetBucketVersioning",
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::REPLACE_WITH_YOUR_BUCKET",
        "arn:aws:s3:::REPLACE_WITH_YOUR_BUCKET/*"
      ]
    },
    {
      "Sid": "ContainerRegistry",
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:CreateRepository",
        "ecr:DeleteRepository",
        "ecr:DescribeRepositories",
        "ecr:ListTagsForResource",
        "ecr:TagResource",
        "ecr:UntagResource",
        "ecr:PutLifecyclePolicy",
        "ecr:GetLifecyclePolicy",
        "ecr:DeleteLifecyclePolicy",
        "ecr:PutImageScanningConfiguration",
        "ecr:SetRepositoryPolicy",
        "ecr:GetRepositoryPolicy",
        "ecr:DeleteRepositoryPolicy",
        "ecr:BatchCheckLayerAvailability",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:PutImage",
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer",
        "ecr:ListImages",
        "ecr:DescribeImages",
        "ecr:BatchDeleteImage"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ComputeAndNetwork",
      "Effect": "Allow",
      "Action": [
        "ec2:Describe*",
        "ec2:RunInstances",
        "ec2:TerminateInstances",
        "ec2:StopInstances",
        "ec2:StartInstances",
        "ec2:CreateTags",
        "ec2:DeleteTags",
        "ec2:CreateSecurityGroup",
        "ec2:DeleteSecurityGroup",
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:AuthorizeSecurityGroupEgress",
        "ec2:RevokeSecurityGroupIngress",
        "ec2:RevokeSecurityGroupEgress",
        "ec2:ModifySecurityGroupRules",
        "ec2:AllocateAddress",
        "ec2:ReleaseAddress",
        "ec2:AssociateAddress",
        "ec2:DisassociateAddress",
        "ec2:ModifyInstanceAttribute",
        "ec2:ModifyInstanceMetadataOptions"
      ],
      "Resource": "*"
    },
    {
      "Sid": "IamForInstanceRole",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:PassRole",
        "iam:TagRole",
        "iam:UntagRole",
        "iam:ListRoleTags",
        "iam:PutRolePolicy",
        "iam:GetRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:ListRolePolicies",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:ListAttachedRolePolicies",
        "iam:ListInstanceProfilesForRole",
        "iam:CreateInstanceProfile",
        "iam:DeleteInstanceProfile",
        "iam:GetInstanceProfile",
        "iam:AddRoleToInstanceProfile",
        "iam:RemoveRoleFromInstanceProfile",
        "iam:TagInstanceProfile",
        "iam:UntagInstanceProfile"
      ],
      "Resource": [
        "arn:aws:iam::*:role/scaa-final-*",
        "arn:aws:iam::*:instance-profile/scaa-final-*"
      ]
    },
    {
      "Sid": "Monitoring",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:DeleteLogGroup",
        "logs:DescribeLogGroups",
        "logs:PutRetentionPolicy",
        "logs:DeleteRetentionPolicy",
        "logs:TagResource",
        "logs:UntagResource",
        "logs:ListTagsForResource",
        "cloudwatch:PutMetricAlarm",
        "cloudwatch:DeleteAlarms",
        "cloudwatch:DescribeAlarms",
        "cloudwatch:ListTagsForResource",
        "cloudwatch:TagResource",
        "cloudwatch:UntagResource",
        "cloudwatch:PutDashboard",
        "cloudwatch:DeleteDashboards",
        "cloudwatch:GetDashboard",
        "cloudwatch:ListDashboards"
      ],
      "Resource": "*"
    },
    {
      "Sid": "RemoteDeployViaSsm",
      "Effect": "Allow",
      "Action": [
        "ssm:SendCommand",
        "ssm:GetCommandInvocation",
        "ssm:ListCommandInvocations",
        "ssm:ListCommands",
        "ssm:DescribeInstanceInformation",
        "ssm:GetParameter",
        "ssm:GetParameters"
      ],
      "Resource": "*"
    }
  ]
}
```

**Replace `REPLACE_WITH_YOUR_BUCKET` with your real bucket name (two places).**

**Step C — attach the policy and create keys:**

```powershell
cd C:\Users\User\Desktop

aws iam put-user-policy `
  --user-name gitlab-ci-scaa `
  --policy-name scaa-final-ci-policy `
  --policy-document file://ci-policy.json

aws iam create-access-key --user-name gitlab-ci-scaa
```

The last command prints something like:

```json
{
  "AccessKey": {
    "AccessKeyId": "AKIA................",
    "SecretAccessKey": "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
    ...
  }
}
```

**Copy both values now.** AWS shows the secret only once.
**Do not put them in any file inside the repository.** They go into GitLab variables only (section 6.2).

> **Why this policy?** It is "least privilege": the CI user can only touch the S3 bucket you created, only IAM roles whose name starts with `scaa-final-`, and only the services this project needs. It cannot delete other people's resources or create new users.

> **Simpler alternative** (if you are short on time and this is a personal sandbox account): attach the AWS managed policy `PowerUserAccess` plus a small inline IAM policy. It works, but you will lose "least privilege" points. The JSON above is better.


---

<a name="4a-step-2-detailed"></a>

## 4A. Step 2 in full detail — building the bootstrap from a completely empty AWS account

> **Read this if:** you just opened your AWS account, you see an empty console, and sections 4.1 – 4.3 above felt too short.
>
> Sections 4.1 – 4.3 are the **short version** (CLI). This section 4A is the **long version** (console, click by click) of exactly the same work, plus everything an empty account needs *before* those commands can work.
>
> **You do not have to do both.** Do the console clicks here, or the CLI commands above — the result is identical. Most beginners do 4A.1 – 4A.6 in the console, then use the CLI for the checks.

### What "prepare AWS" really means

At the end of Step 2 your AWS account must contain exactly **four** things:

| # | Thing | Why | Created in |
|---|---|---|---|
| 1 | A **normal IAM user for you** (not root) with an access key | You must never work as root, and `aws configure` needs a key | 4A.3 |
| 2 | A **budget / billing alert** | So AWS cannot surprise you with a bill | 4A.4 |
| 3 | An **S3 bucket** for the Terraform state file | Terraform runs on a fresh CI machine every time and must keep its memory somewhere | 4A.5 |
| 4 | An **IAM user `gitlab-ci-scaa`** with a least-privilege policy and an access key | The pipeline logs in to AWS as this user | 4A.6 |

**That is all.** Everything else in this project — the ECR repository, the EC2 instance, the security group, the instance role, the Elastic IP, the CloudWatch log groups, the alarms and the dashboard — is created by **Terraform** in Step 3. Do **not** click those together by hand. Section 4A.8 lists every "hands off" resource and explains what breaks if you create them anyway.

---

### 4A.1 First look at an empty AWS account

Open https://console.aws.amazon.com and sign in with the e-mail address you used to open the account (that is the **root user**).

Learn these four parts of the screen — you will use them constantly:

```
+---------------------------------------------------------------------------+
|  aws   [ Q Search for services... ]        [ Frankfurt v ]  [ Your name v ]|
|         (1) search box                      (2) region       (3) account   |
+---------------------------------------------------------------------------+
|                                                                           |
|   (4) the service page you opened (S3, IAM, EC2, CloudWatch ...)          |
|                                                                           |
+---------------------------------------------------------------------------+
```

1. **Search box** — the fastest way to open any service. Type `S3`, `IAM`, `EC2`, `CloudWatch`, `Budgets`, press Enter.
2. **Region selector (top right)** — AWS is split into regions and **each region is a separate world**. A bucket created in Frankfurt is invisible in Ireland. Set it to **Europe (Frankfurt) eu-central-1** and never change it during this project. If a resource "disappears", 90 % of the time you are just looking at the wrong region.
3. **Account menu** — your account ID, "Security credentials", "Billing and Cost Management".
4. The page itself.

> **Two things are global, not regional:** **IAM** (users, policies, roles) and **S3 bucket names**. IAM pages show "Global" instead of a region. Everything else in this project (EC2, ECR, CloudWatch, SSM) lives inside eu-central-1.

**Write down your account ID now.** Account menu (top right) → the 12-digit number under your name; click it to copy. You will need it for the ECR URL later (`<account-id>.dkr.ecr.eu-central-1.amazonaws.com`).

**Check which Free Tier plan you are on** (AWS changed this in mid-2025, so a new account looks different from older tutorials):
**Account menu → Billing and Cost Management → Free tier** (left menu).

* If you see a **credit balance** (for example "$100 free credits, expires in 6 months") you are on the new plan. Your EC2 hours are paid from those credits — fine for this project, which costs roughly $1–4 per month if you follow the destroy rule.
* If you see a table of **"12 months free"** usage lines, you are on the older plan — also fine.
* If the console says your account is on a **"Free plan"** (signed up without a card), some launches are blocked. Open **Billing → Account overview** and switch to the paid plan, otherwise `terraform apply` will fail when it tries to start EC2.

---

### 4A.2 Protect the root user (10 minutes, done once)

The root user can do *everything*, including closing the account and spending money. It cannot be limited by any policy. So we lock it and stop using it.

**A. Turn on MFA for root**

1. Account menu (top right) → **Security credentials**.
2. Find the block **Multi-factor authentication (MFA)** → **Assign MFA device**.
3. Device name: `root-phone`. Choose **Authenticator app** → **Next**.
4. Install *Google Authenticator* or *Microsoft Authenticator* on your phone, scan the QR code.
5. Type **two codes in a row** (wait for the app to change the number between them) → **Add MFA**.

**B. Confirm root has no access keys**

On the same page, the block **Access keys** must be empty. If a key exists, delete it. Root access keys are the most dangerous object in an AWS account — if one leaks, the finder owns the account.

**C. Give your sign-in page a name (optional but nice)**

Account menu → **Account** → **Account Alias** → Create → for example `scaa-nika`.
Your sign-in URL becomes `https://scaa-nika.signin.aws.amazon.com/console` instead of the 12-digit number.

> **Grading note:** "MFA on root, no root access keys, daily work done by a non-root user" is a standard security checklist item. Take a screenshot of the MFA block — good material for the security section of your report.

---

### 4A.3 Create your own admin IAM user and stop using root

You need a second user — a normal one — for daily work and for `aws configure`.

**Click by click:**

1. Search box → **IAM** → left menu **Users** → button **Create user**.
2. **User name:** `nika-admin` → tick **Provide user access to the AWS Management Console**.
3. Choose **I want to create an IAM user** (the console pushes you toward Identity Center; for a one-person student project a plain IAM user is simpler and perfectly acceptable).
4. **Custom password** → type a strong password. Untick *"Users must create a new password at next sign-in"* if you do not want the extra step → **Next**.
5. **Set permissions** → **Attach policies directly** → search `AdministratorAccess` → tick it → **Next**.
6. **Create user** → on the success page click **Download .csv file** and save the sign-in URL + password somewhere safe (**not** in the repository).

**Now switch users:**

1. Sign out of root (Account menu → Sign out).
2. Open the sign-in URL from the CSV (or `https://<account-id>.signin.aws.amazon.com/console`).
3. Sign in as `nika-admin`. From here on, **every console click in this guide is done as `nika-admin`.**
4. Recommended: give this user MFA too (**IAM → Users → nika-admin → Security credentials → Assign MFA device**).

**Create the access key for the CLI** — this is the key section 4.1 asks for:

1. **IAM → Users → nika-admin → Security credentials** tab.
2. Scroll to **Access keys** → **Create access key**.
3. Use case: **Command Line Interface (CLI)** → tick the confirmation box → **Next**.
4. Description tag: `laptop-cli` → **Create access key**.
5. **Download .csv file.** The secret is shown **once**. If you lose it, delete the key and create a new one — that is normal and free.

Now run `aws configure` from section 4.1 with this key, then `aws sts get-caller-identity`. The output must look like:

```json
{
    "UserId": "AIDA....................",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:user/nika-admin"
}
```

If the `Arn` ends with `:root`, you configured a root key — delete that key and redo this section.

> **Why two users?** `nika-admin` is *you*: laptop, password, MFA. `gitlab-ci-scaa` (section 4A.6) is *the robot*: no password, no console, only the permissions this project needs. Separating humans from machines is core IAM practice and it is worth points.

---

### 4A.4 Put a fence around the money (do this before creating anything)

Five minutes now can save you a real bill later.

**A. Let IAM users see billing** — this is a root-only setting, so sign in as root once, then sign back out:

Account menu → **Account** → scroll to **IAM user and role access to Billing information** → **Edit** → tick **Activate IAM Access** → **Update**.

**B. Create a budget with an e-mail alert:**

1. Search box → **Billing and Cost Management** → left menu **Budgets** → **Create budget**.
2. Choose **Use a template (simplified)** → **Monthly cost budget**.
3. **Budget amount:** `5` (US dollars). This project should normally stay under that.
4. **E-mail recipients:** your e-mail → **Create budget**.

AWS now e-mails you when actual or forecast spend passes the thresholds of that $5 budget.

**C. Turn on Free Tier usage alerts:**

**Billing and Cost Management → Billing preferences → Alert preferences → Edit** → tick the Free Tier / usage alert options → add your e-mail → **Update**.

**D. Know what actually costs money here:**

| Resource | Cost reality |
|---|---|
| EC2 `t3.micro` running 24/7 | The main cost — a few dollars a month, or covered by Free Tier hours / credits depending on your plan. |
| **Public IPv4 address** (the Elastic IP on the instance) | Since 2024 AWS charges about **$0.005 per hour (~$3.60/month)** for *every* public IPv4 address, even an attached one. Normal and expected for this project. |
| Elastic IP **not attached** to a running instance | Also charged. This is why `terraform destroy` matters — a forgotten EIP is the classic "why is my bill $4" story. |
| ECR storage | ~$0.10 per GB-month. Your image is ~110 MB and the lifecycle policy in Step 3 deletes old ones. Pennies. |
| CloudWatch logs | 7-day retention (Step 3 sets it). Pennies. |
| S3 state bucket | A few kilobytes. Effectively free. |

**The rule from section 1 still applies: run the `destroy` job when you stop working.** A budget alert is a safety net, not a substitute.

---

### 4A.5 Create the Terraform state bucket in the console (same result as 4.2)

**What this bucket is for, in one picture:**

```
   pipeline run #1                 S3 bucket (your account)
   terraform apply  ──writes──▶   scaa-final-tfstate-nika-7431/
                                     terraform.tfstate      <- "what exists in AWS"
                                     terraform.tfstate.tflock <- "someone is applying now"
   pipeline run #2
   terraform apply  ──reads───▶   the same file, so it knows it must only CHANGE
                                  the instance, not create a second one
```

Without this bucket, every pipeline run would start with amnesia and build a **new** copy of everything.

**Click by click:**

1. Check the region selector says **Europe (Frankfurt) eu-central-1**.
2. Search box → **S3** → **Create bucket**.
3. **Bucket type:** General purpose.
4. **Bucket name:** `scaa-final-tfstate-nika-7431`
   * must be **globally unique across every AWS customer on earth** — add your name and random digits;
   * lowercase letters, digits and dashes only; 3–63 characters; no underscores, no capitals.
   * If the console says *"Bucket with the same name already exists"*, change the digits and try again.
5. **Region:** Europe (Frankfurt) eu-central-1 — it must match `aws_region` in `variables.tf`.
6. **Object Ownership:** leave **ACLs disabled (recommended)**.
7. **Block Public Access settings:** leave **Block all public access** ticked. ✅ Your state file can contain sensitive values; it must never be public.
8. **Bucket Versioning:** select **Enable**. This keeps every old copy of the state file, so if a run corrupts it you can roll back.
9. **Default encryption:** **Server-side encryption with Amazon S3 managed keys (SSE-S3)**. Leave **Bucket Key** enabled.
   *Do not pick SSE-KMS* — it works, but then the CI user also needs KMS permissions that the policy in 4.3 does not grant.
10. **Create bucket**.

**Verify in the console:** open the bucket → **Properties** tab. You must see:

| Property | Required value |
|---|---|
| Bucket Versioning | Enabled |
| Default encryption | Enabled, SSE-S3 (AES-256) |
| Region | eu-central-1 |
| (Permissions tab) Block public access | On, all four options |

**Verify from PowerShell** (this is what the graders' checklist really wants):

```powershell
$env:TF_STATE_BUCKET = "scaa-final-tfstate-nika-7431"

aws s3api get-bucket-versioning --bucket $env:TF_STATE_BUCKET
aws s3api get-bucket-encryption --bucket $env:TF_STATE_BUCKET
aws s3api get-public-access-block --bucket $env:TF_STATE_BUCKET
```

Expected, in order: `"Status": "Enabled"` — `"SSEAlgorithm": "AES256"` — four times `true`.

> **The bucket stays empty for now.** The first `terraform init` in the pipeline creates `terraform.tfstate` inside it. If you look in the bucket after Step 4 and see that file, the remote backend works.

> **Write the bucket name down.** It goes into the GitLab variable `TF_STATE_BUCKET` (section 6.2) and into the `ci-policy.json` you are about to create.

---

### 4A.6 Create the CI policy and the `gitlab-ci-scaa` user in the console (same result as 4.3)

Section 4.3 does this with two CLI commands and an **inline** policy. The console version below creates the same permissions as a **customer managed policy** and attaches it. Either is correct — a managed policy is slightly nicer because you can see it, edit it and reuse it in the IAM console.

**Do only one of the two.** If you already ran the commands in 4.3, skip to 4A.7.

**Step A — create the policy**

1. Search box → **IAM** → left menu **Policies** → **Create policy**.
2. Switch from *Visual* to the **JSON** tab.
3. Delete what is there and paste the **whole JSON document from section 4.3** above.
4. **Replace `REPLACE_WITH_YOUR_BUCKET` with your real bucket name — in both places** (the plain ARN and the one ending in `/*`). They are different: the first means "the bucket itself" (needed for `ListBucket`), the second means "the objects inside it" (needed for `GetObject`/`PutObject`).
5. **Next** → **Policy name:** `scaa-final-ci-policy` → Description: `Least-privilege policy for the GitLab CI pipeline of the SCAA final project` → **Create policy**.

If the JSON editor shows a red error, it is almost always a missing comma or a broken quote from copy-paste. The editor points at the line.

**Step B — create the user**

1. **IAM → Users → Create user**.
2. **User name:** `gitlab-ci-scaa`.
3. **Do NOT tick** "Provide user access to the AWS Management Console" — a robot does not need a login page. → **Next**.
4. **Permissions options:** **Attach policies directly** → in the filter type `scaa-final-ci-policy` → tick it.
   (Make sure nothing else is ticked — no `AdministratorAccess` here.) → **Next**.
5. Review, then **Create user**.

**Step C — create its access key**

1. Open the user **gitlab-ci-scaa** → **Security credentials** tab → **Access keys** → **Create access key**.
2. Use case: choose **Third-party service** (GitLab is a third-party CI) or **Command Line Interface (CLI)** — both produce an identical key; the choice only changes the warning text.
3. Tick the confirmation box → **Next** → Description tag: `gitlab-ci` → **Create access key**.
4. **Download .csv file** and keep it outside the repository. The secret is shown once.

**Step D — where these keys go**

| Value | Goes to |
|---|---|
| `AccessKeyId` | GitLab → Settings → CI/CD → Variables → `AWS_ACCESS_KEY_ID` (masked, protected) |
| `SecretAccessKey` | GitLab → `AWS_SECRET_ACCESS_KEY` (masked, protected) |
| `eu-central-1` | GitLab → `AWS_DEFAULT_REGION` |
| your bucket name | GitLab → `TF_STATE_BUCKET` |

Section 6.2 shows the exact GitLab screen. **These four values never appear in a file inside the repository.**

**Step E — test the robot key without breaking your own login**

Never overwrite your `nika-admin` profile with the CI key. Use a **named profile** instead:

```powershell
# Creates a second profile called "ci" - your default profile stays untouched
aws configure --profile ci
# paste the gitlab-ci-scaa key id, secret, region eu-central-1, output json

# Who am I with that key?
aws sts get-caller-identity --profile ci

# Can it see the state bucket? (should list nothing, but must NOT say AccessDenied)
aws s3 ls s3://scaa-final-tfstate-nika-7431 --profile ci

# It must NOT be able to create users - this SHOULD fail with AccessDenied.
# That failure is proof that least privilege works.
aws iam create-user --user-name should-not-work --profile ci
```

Expected results:

```
Arn ends with :user/gitlab-ci-scaa       <- right identity
s3 ls prints nothing                     <- bucket reachable, still empty
create-user -> AccessDenied              <- least privilege proven
```

Take a screenshot of that `AccessDenied` — it is the cleanest possible evidence for the "least privilege" point in your report.

> **Common mistake:** creating the access key **before** attaching the policy, then testing immediately. New IAM permissions can take a few seconds to spread. If something says `AccessDenied` right after you attach a policy, wait 10 seconds and try again before you start debugging.

---

### 4A.7 Things that must already exist in an empty account — check, do not create

These are things AWS gives you for free with the account. Terraform expects them. Check them once now; fixing a missing one later, in the middle of a failing pipeline, is much less pleasant.

**A. The default VPC and its subnets**

`terraform/main.tf` (section 5.11) looks up the **default VPC** instead of building a network. Every new account normally has one in every region — but it can be missing if someone deleted it.

```powershell
aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[].VpcId" --output text
aws ec2 describe-subnets --filters "Name=default-for-az,Values=true" --query "Subnets[].{AZ:AvailabilityZone,Subnet:SubnetId}" --output table
```

You should get one VPC id (`vpc-0abc...`) and **two or more** subnets in different availability zones.

If the first command prints nothing, create the default VPC back:

```powershell
aws ec2 create-default-vpc
```

Console equivalent: **VPC → Your VPCs → Actions → Create default VPC**.

**B. EC2 capacity limits (service quotas)**

Brand-new accounts sometimes have a very small vCPU limit, and `terraform apply` then dies with `VcpuLimitExceeded`.

Search box → **Service Quotas** → **AWS services** → **Amazon Elastic Compute Cloud (Amazon EC2)** → find
**"Running On-Demand Standard (A, C, D, H, I, M, R, T, Z) instances"**.
The applied value must be **at least 2** (a `t3.micro` uses 2 vCPUs). Most accounts show 5 or more. If yours shows 0, click **Request increase at account level** and ask for 8 — approval is usually automatic but can take a few hours, so check this *before* you need it.

**C. Your account is fully activated**

Right after sign-up AWS sometimes keeps an account in verification for a few hours. Symptom: launching EC2 fails with a "pending verification" or "Blocked" message. Fix: wait, and check your e-mail for a message from AWS.

**D. No EC2 key pair is needed — on purpose**

You will not create one. There is no SSH into this instance: port 22 stays closed and the pipeline runs commands through **SSM Session Manager** (see section 1 and 5.7). If you catch yourself creating a `.pem` file, stop — you took a wrong turn.

**E. SSM requires nothing from you in advance**

The SSM Agent is pre-installed on Amazon Linux 2023, and the instance role Terraform creates (`AmazonSSMManagedInstanceCore`) gives it permission to register. There is no service to "switch on" in the console.

---

### 4A.8 What you must **not** create by hand

This is the part beginners get wrong. An empty console feels like something is missing, so people start clicking "Launch instance" and "Create repository". **Don't.** Terraform owns these resources, and it only knows about things it created itself.

| Resource | Name it will get | Created by |
|---|---|---|
| ECR repository | `scaa-final-dev` | Terraform, section 5.5 |
| Security group | `scaa-final-dev-sg` (port 80 in, 22 closed) | Terraform, section 5.6 |
| IAM role + instance profile for EC2 | `scaa-final-dev-...` | Terraform, section 5.7 |
| CloudWatch log groups | `/scaa-final-dev/application`, `/scaa-final-dev/system` | Terraform, section 5.8 |
| CloudWatch alarms + dashboard | `scaa-final-dev-...` | Terraform, sections 5.8 / 5.11 |
| EC2 instance | `scaa-final-dev-web` | Terraform, section 5.9 |
| Elastic IP | attached to that instance | Terraform, section 5.9 |
| The Docker image inside ECR | tagged with the commit SHA | the GitLab pipeline, section 6.3 |

**What happens if you create one anyway?** Terraform does not adopt existing resources. You get an error like:

```
Error: creating ECR Repository (scaa-final-dev): RepositoryAlreadyExistsException
Error: creating IAM Role (scaa-final-dev-ec2-role): EntityAlreadyExists
```

The fix is to delete the hand-made resource in the console and re-run the pipeline (or `terraform import` it, which is an advanced topic you do not need here).

> **The one legitimate exception** is the bootstrap itself: the state bucket and the CI user are created by hand *because* Terraform cannot create the place where it stores its own memory. That is why they are not in the Terraform code, and saying this sentence in your report shows you understand the chicken-and-egg problem.

---

### 4A.9 One script that verifies the whole bootstrap

Paste this into PowerShell after you finish 4A.5 and 4A.6. It checks everything Step 2 was supposed to produce and prints a pass/fail line for each item.

```powershell
$ErrorActionPreference = "Continue"
$bucket = "scaa-final-tfstate-nika-7431"   # <- your bucket name
$region = "eu-central-1"

function Check($label, $ok) {
  if ($ok) { Write-Host ("PASS  " + $label) -ForegroundColor Green }
  else     { Write-Host ("FAIL  " + $label) -ForegroundColor Red }
}

# 1. Am I logged in, and not as root?
$me = aws sts get-caller-identity --output json | ConvertFrom-Json
Check "CLI logged in as $($me.Arn)" ($me.Arn -notmatch ":root$")
Write-Host "      account id: $($me.Account)   <- write this down"

# 2. Bucket exists in the right region
$loc = aws s3api get-bucket-location --bucket $bucket --output json | ConvertFrom-Json
Check "state bucket exists in $region" ($loc.LocationConstraint -eq $region)

# 3. Versioning on
$ver = aws s3api get-bucket-versioning --bucket $bucket --output json | ConvertFrom-Json
Check "bucket versioning enabled" ($ver.Status -eq "Enabled")

# 4. Encryption on
$enc = aws s3api get-bucket-encryption --bucket $bucket --output json | ConvertFrom-Json
Check "bucket encrypted (AES256)" ($enc.ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm -eq "AES256")

# 5. Public access blocked
$pab = aws s3api get-public-access-block --bucket $bucket --output json | ConvertFrom-Json
Check "public access fully blocked" ($pab.PublicAccessBlockConfiguration.BlockPublicAcls -and $pab.PublicAccessBlockConfiguration.RestrictPublicBuckets)

# 6. CI user exists
$u = aws iam get-user --user-name gitlab-ci-scaa --output json 2>$null | ConvertFrom-Json
Check "IAM user gitlab-ci-scaa exists" ($null -ne $u)

# 7. CI user has a policy (inline from 4.3 OR managed from 4A.6)
$inline  = (aws iam list-user-policies --user-name gitlab-ci-scaa --output json 2>$null | ConvertFrom-Json).PolicyNames
$managed = (aws iam list-attached-user-policies --user-name gitlab-ci-scaa --output json 2>$null | ConvertFrom-Json).AttachedPolicies
Check "CI user has a permissions policy" (($inline.Count + $managed.Count) -gt 0)

# 8. CI user has exactly one active access key
$keys = (aws iam list-access-keys --user-name gitlab-ci-scaa --output json 2>$null | ConvertFrom-Json).AccessKeyMetadata
Check "CI user has 1 access key" ($keys.Count -eq 1)

# 9. Default VPC + at least 2 default subnets
$vpc = aws ec2 describe-vpcs --filters "Name=isDefault,Values=true" --query "Vpcs[].VpcId" --output text
Check "default VPC exists ($vpc)" (-not [string]::IsNullOrWhiteSpace($vpc))
$subnets = (aws ec2 describe-subnets --filters "Name=default-for-az,Values=true" --query "Subnets[].SubnetId" --output text) -split "\s+" | Where-Object { $_ }
Check "default subnets found ($($subnets.Count))" ($subnets.Count -ge 1)

# 10. Nothing from Terraform exists yet - the account should still be clean
$ecr = aws ecr describe-repositories --repository-names scaa-final-dev --output json 2>$null
Check "ECR repo NOT created by hand" ($null -eq $ecr -or $ecr -eq "")
```

All ten lines green means Step 2 is finished and you can start Step 3.

---

### 4A.10 Your bootstrap notebook — the five values you must keep

Write these down in a note on your laptop (never in the repository). Every later step asks for one of them.

| Value | Example | Where you need it later |
|---|---|---|
| AWS account ID | `123456789012` | the ECR image URL, reading error messages |
| Region | `eu-central-1` | GitLab variable `AWS_DEFAULT_REGION`, `variables.tf` |
| State bucket name | `scaa-final-tfstate-nika-7431` | GitLab variable `TF_STATE_BUCKET`, `ci-policy.json` |
| CI access key ID | `AKIA...` | GitLab variable `AWS_ACCESS_KEY_ID` |
| CI secret access key | `wJal...` | GitLab variable `AWS_SECRET_ACCESS_KEY` |

**If you lose the secret:** IAM → Users → `gitlab-ci-scaa` → Security credentials → deactivate and delete the old key → **Create access key** → put the new pair into GitLab. Nothing else breaks; keys are disposable.

**If a key ever leaks** (pushed to Git, pasted in a chat): delete it *first*, then worry. IAM → the user → Security credentials → Actions → **Delete**. A deleted key is dead immediately.

---

### 4A.11 Errors you are likely to hit during Step 2, and the fix

| Message | What it means | Fix |
|---|---|---|
| `BucketAlreadyExists` | Someone else on earth owns that bucket name | Change the random digits in the name |
| `BucketAlreadyOwnedByYou` | You already created it | Nothing to do — continue |
| `IllegalLocationConstraintException` | The region in the command and the region of the bucket disagree | Use the same region everywhere; note that for `us-east-1` you must **omit** `--create-bucket-configuration` |
| `InvalidClientTokenId` / `SignatureDoesNotMatch` | Wrong or half-pasted key, or a stray space | Re-run `aws configure`; paste the key with no spaces or quotes |
| `AccessDenied` right after attaching a policy | IAM changes take a few seconds to propagate | Wait 10 seconds, try again |
| `AccessDenied` on `iam:PutUserPolicy` | You are signed in as a user without IAM rights | Use `nika-admin` (AdministratorAccess), not a limited user |
| `Error parsing parameter '--policy-document'` | PowerShell mangled the JSON, or Notepad saved the file as UTF-8 **with BOM** | Save `ci-policy.json` from VS Code as "UTF-8" (not "UTF-8 with BOM"), or run `Set-Content -Path ci-policy.json -Value (Get-Content ci-policy.json -Raw) -Encoding ascii` |
| `The config profile (ci) could not be found` | You used `--profile ci` before creating it | Run `aws configure --profile ci` first |
| `Could not connect to the endpoint URL` | The region string has a typo (`eu-central1`, `eu-central-l`) | Fix the region — it is `eu-central-1` |
| `VcpuLimitExceeded` (later, in `terraform apply`) | New-account EC2 quota is too small | Service Quotas → EC2 → request an increase (see 4A.7 B) |
| `UnauthorizedOperation` in the pipeline on some `ec2:*` call | The CI policy is missing an action | Add that exact action name from the error message to `ci-policy.json` and update the policy |
| Console shows "0 buckets" / "no instances" | You are in the wrong region | Switch the region selector back to Frankfurt |

> **How to read an AWS permission error.** A message like
> `User: arn:aws:iam::123456789012:user/gitlab-ci-scaa is not authorized to perform: ec2:DescribeAddresses`
> tells you three things: **who** (the CI user), **what** (`ec2:DescribeAddresses`) and therefore **the fix** (add `ec2:DescribeAddresses` to the policy). You never have to guess — the missing action is printed literally.

---

### 4A.12 Screenshots worth taking now (for the report)

While the account is small and clean, these are quick to capture and they cover several grading points:

1. **IAM → Users** list showing `nika-admin` and `gitlab-ci-scaa` — proves separation of human and machine identities.
2. **Root Security credentials** page showing MFA assigned and no access keys.
3. **IAM → Policies → scaa-final-ci-policy** (JSON tab) — proves least privilege.
4. The `AccessDenied` output of `aws iam create-user --profile ci` from 4A.6 Step E — proves the limits actually work.
5. **S3 → your bucket → Properties** showing versioning + encryption on, and **Permissions** showing public access blocked — proves secure state storage.
6. **Budgets** page showing the $5 budget — proves cost awareness.

Section 12 lists the screenshots for the later steps.

---

### 4A.13 What the account looks like when Step 2 is done

```
AWS account 123456789012
├── IAM (global)
│   ├── user nika-admin        (AdministratorAccess, console + MFA + CLI key)  <- you
│   ├── user gitlab-ci-scaa    (scaa-final-ci-policy, one access key, no console) <- the pipeline
│   └── policy scaa-final-ci-policy
├── S3 (global names, stored in eu-central-1)
│   └── scaa-final-tfstate-nika-7431   (empty, versioned, encrypted, private)
├── Billing
│   └── budget "Monthly cost budget" $5 -> your e-mail
└── eu-central-1
    ├── default VPC + subnets   (came with the account)
    └── nothing else — EC2, ECR and CloudWatch are still empty on purpose
```

If your account looks like this, Step 2 is complete. **Go to section 5 (Step 3) and start writing the Terraform code.** The next time you touch the AWS console will be in Step 5, to look at the running instance, the logs, the metrics and the dashboard that Terraform and the pipeline created for you.

---

<a name="5-step-3-terraform"></a>

## 5. Step 3 — Terraform infrastructure as code

### 5.1 Folder structure you will create

In `C:\Users\User\Desktop\SCAA-FinalProject`, create this tree:

```
terraform/
├── backend.tf            # where the state file lives (S3)
├── providers.tf          # AWS provider + global tags
├── variables.tf          # all inputs
├── main.tf               # wires the modules together
├── outputs.tf            # what Terraform prints at the end
├── terraform.tfvars      # your values (no secrets)
└── modules/
    ├── ecr/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── security/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── iam/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── monitoring/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    └── compute/
        ├── main.tf
        ├── variables.tf
        ├── outputs.tf
        └── user_data.sh.tftpl
```

Create all folders at once:

```powershell
cd C:\Users\User\Desktop\SCAA-FinalProject
New-Item -ItemType Directory -Force -Path `
  terraform\modules\ecr, `
  terraform\modules\security, `
  terraform\modules\iam, `
  terraform\modules\monitoring, `
  terraform\modules\compute | Out-Null
```

**What is a module?** A folder with Terraform files that does one job. You "call" it from `main.tf` and pass values in. It is like a function. The task asks for "modular, reusable" Terraform — this is exactly that.

---

### 5.2 `terraform/backend.tf`

```hcl
# ---------------------------------------------------------------------------
# Remote state.
#
# The pipeline runs on a fresh machine every time, so the state file cannot
# live on disk. We keep it in S3. `use_lockfile = true` makes Terraform write
# a small lock object in the same bucket, so two pipelines can never apply at
# the same time (no DynamoDB table needed).
#
# The bucket name is NOT written here on purpose. The pipeline passes it with
#   terraform init -backend-config="bucket=$TF_STATE_BUCKET"
# This is called a "partial backend configuration".
# ---------------------------------------------------------------------------
terraform {
  backend "s3" {
    key          = "scaa-final/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
```

> `use_lockfile` needs Terraform **1.10 or newer**. Check with `terraform -version`. If yours is older, upgrade — it is the simplest option.

---

### 5.3 `terraform/providers.tf`

```hcl
terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }
}

provider "aws" {
  region = var.aws_region

  # default_tags are added automatically to EVERY resource that supports tags.
  # This is the "proper tagging" best practice - you write it once.
  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      Owner       = var.owner
      ManagedBy   = "Terraform"
      Repository  = var.repository_url
      CostCenter  = "scaa-devops-course"
    }
  }
}
```

---

### 5.4 `terraform/variables.tf`

```hcl
variable "aws_region" {
  description = "AWS region where everything is created."
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Short name used as a prefix for every resource name."
  type        = string
  default     = "scaa-final"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,20}$", var.project_name))
    error_message = "project_name must be lowercase letters, digits and dashes (3-21 chars)."
  }
}

variable "environment" {
  description = "Environment name: dev, staging or prod."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "owner" {
  description = "Who owns this infrastructure (shown in tags)."
  type        = string
  default     = "Nikoloz Chkhartishvili"
}

variable "repository_url" {
  description = "Source repository, shown in tags."
  type        = string
  default     = "https://gitlab.com/CHANGE-ME/scaa-finalproject"
}

# ---------------------------------------------------------------------- app
variable "container_port" {
  description = "Port the application listens on inside the container."
  type        = number
  default     = 8080
}

variable "host_port" {
  description = "Port opened on the EC2 instance. 80 lets you open the site without :port."
  type        = number
  default     = 80
}

variable "image_tag" {
  description = "Docker image tag to deploy. The pipeline passes the short commit SHA."
  type        = string
  default     = "latest"
}

# ----------------------------------------------------------------- compute
variable "instance_type" {
  description = "EC2 size. t3.micro is Free Tier eligible in most regions."
  type        = string
  default     = "t3.micro"
}

variable "root_volume_size" {
  description = "Size of the EC2 disk in GB."
  type        = number
  default     = 20
}

# ---------------------------------------------------------------- security
variable "allowed_http_cidr" {
  description = "Who may open the website. 0.0.0.0/0 = the whole internet (needed for grading)."
  type        = string
  default     = "0.0.0.0/0"
}

# -------------------------------------------------------------- monitoring
variable "log_retention_days" {
  description = "How many days CloudWatch keeps the logs. Short retention = low cost."
  type        = number
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365], var.log_retention_days)
    error_message = "Use a retention value that CloudWatch accepts."
  }
}

variable "cpu_alarm_threshold" {
  description = "Fire the CloudWatch alarm when average CPU goes above this percent."
  type        = number
  default     = 80
}
```

**Why validations?** They stop bad input early with a clear message, instead of a confusing AWS error 5 minutes later. Graders like this.

---

### 5.5 `terraform/modules/ecr/`

**`modules/ecr/variables.tf`**

```hcl
variable "repository_name" {
  description = "Name of the ECR repository."
  type        = string
}

variable "keep_last_images" {
  description = "How many images to keep. Older ones are deleted automatically."
  type        = number
  default     = 5
}
```

**`modules/ecr/main.tf`**

```hcl
resource "aws_ecr_repository" "this" {
  name                 = var.repository_name
  image_tag_mutability = "MUTABLE"

  # Lets `terraform destroy` delete the repository even when images are inside.
  # Without this the destroy job fails and you keep paying.
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true # free vulnerability scan of every pushed image
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

# Keep storage small and cheap: delete old images automatically.
resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only the newest ${var.keep_last_images} images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.keep_last_images
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
```

**`modules/ecr/outputs.tf`**

```hcl
output "repository_url" {
  description = "Full URL used by docker push / docker pull."
  value       = aws_ecr_repository.this.repository_url
}

output "repository_arn" {
  description = "ARN, used to give the EC2 role pull-only access to THIS repo."
  value       = aws_ecr_repository.this.arn
}

output "repository_name" {
  description = "Repository name."
  value       = aws_ecr_repository.this.name
}

output "registry_id" {
  description = "AWS account ID that owns the registry."
  value       = aws_ecr_repository.this.registry_id
}
```

---

### 5.6 `terraform/modules/security/`

**`modules/security/variables.tf`**

```hcl
variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "vpc_id" {
  description = "VPC where the security group is created."
  type        = string
}

variable "allowed_http_cidr" {
  description = "CIDR allowed to reach the web port."
  type        = string
}

variable "host_port" {
  description = "Port opened on the instance."
  type        = number
}
```

**`modules/security/main.tf`**

```hcl
# A security group is a stateful firewall attached to the EC2 instance.
resource "aws_security_group" "web" {
  name        = "${var.name_prefix}-web-sg"
  description = "Allow inbound HTTP only. No SSH - deployment uses AWS SSM."
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-web-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ---- INBOUND -------------------------------------------------------------
# Only one rule: the web port. Port 22 (SSH) stays CLOSED on purpose.
resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.web.id
  description       = "HTTP access to the web application"
  cidr_ipv4         = var.allowed_http_cidr
  from_port         = var.host_port
  to_port           = var.host_port
  ip_protocol       = "tcp"
}

# ---- OUTBOUND ------------------------------------------------------------
# The instance must reach ECR, CloudWatch and SSM over HTTPS.
resource "aws_vpc_security_group_egress_rule" "https_out" {
  security_group_id = aws_security_group.web.id
  description       = "HTTPS out - ECR, CloudWatch, SSM, package updates"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "http_out" {
  security_group_id = aws_security_group.web.id
  description       = "HTTP out - Amazon Linux package repositories"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}
```

**`modules/security/outputs.tf`**

```hcl
output "security_group_id" {
  description = "ID of the web security group."
  value       = aws_security_group.web.id
}
```

> **Note on egress:** by default AWS allows *all* outbound traffic. Here we allow only ports 80 and 443. That is stricter and gives you "restricted Security Groups" points.

---

### 5.7 `terraform/modules/iam/`

**`modules/iam/variables.tf`**

```hcl
variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "ecr_repository_arn" {
  description = "ARN of the ECR repo the instance may pull from."
  type        = string
}

variable "log_group_arns" {
  description = "ARNs of the CloudWatch log groups the instance may write to."
  type        = list(string)
}
```

**`modules/iam/main.tf`**

```hcl
# ---------------------------------------------------------------------------
# The EC2 instance needs permissions, but we must NEVER put access keys on it.
# Instead we create a ROLE that the EC2 service is allowed to assume, and
# attach it through an INSTANCE PROFILE. AWS then gives the instance temporary
# credentials that rotate automatically.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  name               = "${var.name_prefix}-ec2-role"
  description        = "Role for the application EC2 instance"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

# ---- 1. Pull images from OUR repository only ------------------------------
data "aws_iam_policy_document" "ecr_pull" {
  # GetAuthorizationToken cannot be limited to one repo - AWS requires "*".
  statement {
    sid       = "EcrLogin"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  # Pulling the actual layers IS limited to our single repository.
  statement {
    sid    = "EcrPullFromThisRepoOnly"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage"
    ]
    resources = [var.ecr_repository_arn]
  }
}

resource "aws_iam_role_policy" "ecr_pull" {
  name   = "${var.name_prefix}-ecr-pull"
  role   = aws_iam_role.instance.id
  policy = data.aws_iam_policy_document.ecr_pull.json
}

# ---- 2. Write logs and metrics to CloudWatch ------------------------------
data "aws_iam_policy_document" "cloudwatch" {
  statement {
    sid    = "WriteLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams"
    ]
    # Only our own log groups, not every log group in the account.
    resources = concat(var.log_group_arns, [for a in var.log_group_arns : "${a}:*"])
  }

  statement {
    sid    = "PublishCustomMetrics"
    effect = "Allow"
    # PutMetricData does not support resource-level permissions, so we limit it
    # by namespace with a condition instead.
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["${var.name_prefix}/system"]
    }
  }

  statement {
    sid       = "ReadOwnTags"
    effect    = "Allow"
    actions   = ["ec2:DescribeTags"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "cloudwatch" {
  name   = "${var.name_prefix}-cloudwatch-write"
  role   = aws_iam_role.instance.id
  policy = data.aws_iam_policy_document.cloudwatch.json
}

# ---- 3. Let the pipeline run commands without SSH -------------------------
# AmazonSSMManagedInstanceCore is the AWS managed policy that turns on
# Systems Manager. This is what replaces SSH keys.
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# ---- The instance profile is the "wrapper" EC2 actually accepts -----------
resource "aws_iam_instance_profile" "instance" {
  name = "${var.name_prefix}-ec2-profile"
  role = aws_iam_role.instance.name
}
```

**`modules/iam/outputs.tf`**

```hcl
output "instance_profile_name" {
  description = "Instance profile to attach to the EC2 instance."
  value       = aws_iam_instance_profile.instance.name
}

output "role_arn" {
  description = "ARN of the EC2 role."
  value       = aws_iam_role.instance.arn
}

output "role_name" {
  description = "Name of the EC2 role."
  value       = aws_iam_role.instance.name
}
```

---

### 5.8 `terraform/modules/monitoring/`

This module creates **only the log groups**. The alarm and the dashboard need the instance ID, which does not exist yet, so they live in the root `main.tf` (section 5.10). This avoids a circular dependency.

**`modules/monitoring/variables.tf`**

```hcl
variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "retention_in_days" {
  description = "Log retention in days."
  type        = number
}
```

**`modules/monitoring/main.tf`**

```hcl
# Log group for the application container (Docker awslogs driver writes here).
resource "aws_cloudwatch_log_group" "application" {
  name              = "/${var.name_prefix}/application"
  retention_in_days = var.retention_in_days

  tags = {
    Name      = "${var.name_prefix}-application-logs"
    LogSource = "container"
  }
}

# Log group for the operating system (CloudWatch agent writes here).
resource "aws_cloudwatch_log_group" "system" {
  name              = "/${var.name_prefix}/system"
  retention_in_days = var.retention_in_days

  tags = {
    Name      = "${var.name_prefix}-system-logs"
    LogSource = "ec2-os"
  }
}
```

**`modules/monitoring/outputs.tf`**

```hcl
output "application_log_group_name" {
  value = aws_cloudwatch_log_group.application.name
}

output "system_log_group_name" {
  value = aws_cloudwatch_log_group.system.name
}

output "log_group_arns" {
  description = "Both log group ARNs - used by the IAM module."
  value = [
    aws_cloudwatch_log_group.application.arn,
    aws_cloudwatch_log_group.system.arn,
  ]
}
```

---

### 5.9 `terraform/modules/compute/`

**`modules/compute/variables.tf`**

```hcl
variable "name_prefix" {
  type        = string
  description = "Prefix for resource names."
}

variable "aws_region" {
  type        = string
  description = "Region - needed inside the user data script."
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type."
}

variable "root_volume_size" {
  type        = number
  description = "Root disk size in GB."
}

variable "subnet_id" {
  type        = string
  description = "Subnet to launch into."
}

variable "security_group_id" {
  type        = string
  description = "Security group to attach."
}

variable "instance_profile_name" {
  type        = string
  description = "IAM instance profile name."
}

variable "ecr_repository_url" {
  type        = string
  description = "ECR repository URL to pull the image from."
}

variable "image_tag" {
  type        = string
  description = "Image tag to run."
}

variable "container_name" {
  type        = string
  description = "Name of the running container."
}

variable "container_port" {
  type        = number
  description = "Port inside the container."
}

variable "host_port" {
  type        = number
  description = "Port on the instance."
}

variable "application_log_group" {
  type        = string
  description = "CloudWatch log group for container logs."
}

variable "system_log_group" {
  type        = string
  description = "CloudWatch log group for OS logs."
}

variable "metrics_namespace" {
  type        = string
  description = "CloudWatch namespace for custom metrics."
}
```

**`modules/compute/main.tf`**

```hcl
# Always get the newest Amazon Linux 2023 AMI instead of hard-coding an ID.
# Hard-coded AMI IDs are different in every region and become outdated.
data "aws_ssm_parameter" "amazon_linux_2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_instance" "app" {
  ami                    = data.aws_ssm_parameter.amazon_linux_2023.value
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  iam_instance_profile   = var.instance_profile_name

  associate_public_ip_address = true
  monitoring                  = true # detailed CloudWatch monitoring (1-minute metrics)

  # Force IMDSv2. This blocks a common cloud attack (SSRF stealing credentials).
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2 # 2 so Docker containers can still reach it
    instance_metadata_tags      = "enabled"
  }

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true

    tags = {
      Name = "${var.name_prefix}-root-volume"
    }
  }

  # When the script changes, replace the instance so the change really applies.
  user_data_replace_on_change = true

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    aws_region            = var.aws_region
    ecr_repository_url    = var.ecr_repository_url
    image_tag             = var.image_tag
    container_name        = var.container_name
    container_port        = var.container_port
    host_port             = var.host_port
    application_log_group = var.application_log_group
    system_log_group      = var.system_log_group
    metrics_namespace     = var.metrics_namespace
  })

  tags = {
    Name = "${var.name_prefix}-app-server"
    Role = "application"
  }

  lifecycle {
    # The AMI ID changes when Amazon publishes an update. Ignoring it stops
    # Terraform from destroying your server on every single pipeline run.
    ignore_changes = [ami]
  }
}

# A static public IP, so the address does not change when the instance restarts.
resource "aws_eip" "app" {
  instance = aws_instance.app.id
  domain   = "vpc"

  tags = {
    Name = "${var.name_prefix}-eip"
  }

  depends_on = [aws_instance.app]
}
```

**`modules/compute/outputs.tf`**

```hcl
output "instance_id" {
  description = "EC2 instance ID - used by the SSM deploy command."
  value       = aws_instance.app.id
}

output "public_ip" {
  description = "Static public IP of the application."
  value       = aws_eip.app.public_ip
}

output "public_dns" {
  description = "Public DNS name."
  value       = aws_instance.app.public_dns
}

output "availability_zone" {
  value = aws_instance.app.availability_zone
}
```

---

### 5.10 `terraform/modules/compute/user_data.sh.tftpl`

This is the script that runs **once**, automatically, the first time the server boots.

> ⚠️ **Very important beginner trap.** This is a *template* file. Terraform replaces anything written as `${something}`. So inside the bash code you must **never** write `${VAR}` — always write `$VAR` without braces. If you really need a literal `${`, write `$${`.

```bash
#!/bin/bash
# ---------------------------------------------------------------------------
# EC2 bootstrap script (runs once, as root, on first boot).
# Rendered by Terraform: ${...} placeholders are replaced before upload.
# ---------------------------------------------------------------------------
set -euxo pipefail
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

echo "=== [1/5] Updating packages ==="
dnf update -y

echo "=== [2/5] Installing Docker and the CloudWatch agent ==="
dnf install -y docker amazon-cloudwatch-agent
systemctl enable --now docker

# Let ec2-user run docker without sudo (useful if you ever connect manually).
usermod -aG docker ec2-user || true

echo "=== [3/5] Configuring the CloudWatch agent (metrics + OS logs) ==="
cat > /opt/aws/amazon-cloudwatch-agent/etc/scaa-agent.json <<'CWAGENT'
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root"
  },
  "metrics": {
    "namespace": "METRICS_NAMESPACE_PLACEHOLDER",
    "append_dimensions": {
      "InstanceId": "$${aws:InstanceId}"
    },
    "aggregation_dimensions": [["InstanceId"]],
    "metrics_collected": {
      "mem": {
        "measurement": [
          {"name": "mem_used_percent", "rename": "MemoryUsedPercent", "unit": "Percent"}
        ],
        "metrics_collection_interval": 60
      },
      "disk": {
        "resources": ["/"],
        "measurement": [
          {"name": "used_percent", "rename": "DiskUsedPercent", "unit": "Percent"}
        ],
        "metrics_collection_interval": 60
      },
      "swap": {
        "measurement": ["swap_used_percent"],
        "metrics_collection_interval": 60
      }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/messages",
            "log_group_name": "SYSTEM_LOG_GROUP_PLACEHOLDER",
            "log_stream_name": "{instance_id}/messages",
            "retention_in_days": -1
          },
          {
            "file_path": "/var/log/user-data.log",
            "log_group_name": "SYSTEM_LOG_GROUP_PLACEHOLDER",
            "log_stream_name": "{instance_id}/user-data",
            "retention_in_days": -1
          },
          {
            "file_path": "/var/log/scaa-deploy.log",
            "log_group_name": "SYSTEM_LOG_GROUP_PLACEHOLDER",
            "log_stream_name": "{instance_id}/deploy",
            "retention_in_days": -1
          }
        ]
      }
    }
  }
}
CWAGENT

# Replace the placeholders with the values Terraform gave us.
sed -i "s|METRICS_NAMESPACE_PLACEHOLDER|${metrics_namespace}|g" /opt/aws/amazon-cloudwatch-agent/etc/scaa-agent.json
sed -i "s|SYSTEM_LOG_GROUP_PLACEHOLDER|${system_log_group}|g" /opt/aws/amazon-cloudwatch-agent/etc/scaa-agent.json

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/scaa-agent.json

echo "=== [4/5] Writing the deployment script ==="
cat > /usr/local/bin/deploy-app.sh <<'DEPLOY'
#!/bin/bash
# Pull an image tag from ECR and (re)start the container.
# Usage: deploy-app.sh <image-tag>
set -euo pipefail
exec >> /var/log/scaa-deploy.log 2>&1

TAG="$1"
REGION="__AWS_REGION__"
REPO="__ECR_REPOSITORY_URL__"
NAME="__CONTAINER_NAME__"
HOST_PORT="__HOST_PORT__"
CONTAINER_PORT="__CONTAINER_PORT__"
APP_LOG_GROUP="__APP_LOG_GROUP__"
REGISTRY="$(echo "$REPO" | cut -d/ -f1)"

echo "----------------------------------------------------------------"
echo "[deploy] $(date -u +%FT%TZ) starting deploy of tag: $TAG"

echo "[deploy] logging in to ECR"
aws ecr get-login-password --region "$REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"

echo "[deploy] pulling $REPO:$TAG"
docker pull "$REPO:$TAG"

echo "[deploy] stopping the old container (if any)"
docker rm -f "$NAME" 2>/dev/null || true

echo "[deploy] starting the new container"
docker run -d \
  --name "$NAME" \
  --restart unless-stopped \
  -p "$HOST_PORT":"$CONTAINER_PORT" \
  -e ASPNETCORE_ENVIRONMENT=Production \
  -e APP_VERSION="$TAG" \
  --log-driver awslogs \
  --log-opt awslogs-region="$REGION" \
  --log-opt awslogs-group="$APP_LOG_GROUP" \
  --log-opt awslogs-stream="$(hostname)/$TAG" \
  --memory 768m \
  --cpus 1.0 \
  --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,size=64m \
  --security-opt no-new-privileges:true \
  "$REPO:$TAG"

echo "[deploy] waiting for the health endpoint"
for i in $(seq 1 30); do
  if curl -fsS "http://localhost:$HOST_PORT/health" >/dev/null 2>&1; then
    echo "[deploy] OK - application is healthy after $i attempt(s)"
    echo "[deploy] cleaning up unused images"
    docker image prune -af >/dev/null 2>&1 || true
    echo "[deploy] finished successfully"
    exit 0
  fi
  sleep 2
done

echo "[deploy] ERROR - application did not become healthy in 60 seconds"
docker logs --tail 100 "$NAME" || true
exit 1
DEPLOY

# Fill in the placeholders in the deploy script.
sed -i \
  -e "s|__AWS_REGION__|${aws_region}|g" \
  -e "s|__ECR_REPOSITORY_URL__|${ecr_repository_url}|g" \
  -e "s|__CONTAINER_NAME__|${container_name}|g" \
  -e "s|__HOST_PORT__|${host_port}|g" \
  -e "s|__CONTAINER_PORT__|${container_port}|g" \
  -e "s|__APP_LOG_GROUP__|${application_log_group}|g" \
  /usr/local/bin/deploy-app.sh

chmod 755 /usr/local/bin/deploy-app.sh

echo "=== [5/5] First deploy attempt ==="
# On the very first apply the image is not in ECR yet, so this is allowed to
# fail. The pipeline's deploy stage runs the same script again afterwards.
/usr/local/bin/deploy-app.sh "${image_tag}" || \
  echo "First deploy skipped - the pipeline will deploy the image."

echo "=== Bootstrap finished ==="
```

**Notice these details — they are all "best practice" points:**

| Detail | Why |
|---|---|
| `--log-driver awslogs` | Container stdout goes **straight** to CloudWatch Logs. No agent needed for app logs. |
| `--restart unless-stopped` | If the server reboots, the app comes back by itself. |
| `--read-only` + `--tmpfs /tmp` | The container cannot write to its own filesystem. Strong protection. |
| `--security-opt no-new-privileges` | Blocks privilege escalation inside the container. |
| `--memory` / `--cpus` | One bad container cannot eat the whole server. |
| `docker image prune -af` | **Cleanup** — the task asks for this. |
| Health loop with `exit 1` | **Fail fast** — the pipeline sees the failure. |
| Everything logged to `/var/log/scaa-deploy.log` | And that file is shipped to CloudWatch. **Clear logging.** |

---

### 5.11 `terraform/main.tf` — wiring it all together

```hcl
# ---------------------------------------------------------------------------
# Look up the default VPC and its subnets.
# Using the default VPC keeps this project small. In a real company you would
# create your own VPC module with private subnets and a load balancer.
# ---------------------------------------------------------------------------
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_caller_identity" "current" {}

locals {
  name_prefix       = "${var.project_name}-${var.environment}"
  container_name    = "${var.project_name}-web"
  metrics_namespace = "${var.project_name}-${var.environment}/system"

  # Pick the first default subnet, sorted so the choice is stable.
  subnet_id = sort(data.aws_subnets.default.ids)[0]
}

# ------------------------------------------------------------- 1. Registry
module "ecr" {
  source = "./modules/ecr"

  repository_name  = local.name_prefix
  keep_last_images = 5
}

# ----------------------------------------------------------- 2. Monitoring
# Created before compute, because the log groups must exist before the
# container starts writing to them.
module "monitoring" {
  source = "./modules/monitoring"

  name_prefix       = local.name_prefix
  retention_in_days = var.log_retention_days
}

# ------------------------------------------------------------- 3. Firewall
module "security" {
  source = "./modules/security"

  name_prefix       = local.name_prefix
  vpc_id            = data.aws_vpc.default.id
  allowed_http_cidr = var.allowed_http_cidr
  host_port         = var.host_port
}

# ---------------------------------------------------------- 4. Permissions
module "iam" {
  source = "./modules/iam"

  name_prefix        = local.name_prefix
  ecr_repository_arn = module.ecr.repository_arn
  log_group_arns     = module.monitoring.log_group_arns
}

# -------------------------------------------------------------- 5. Compute
module "compute" {
  source = "./modules/compute"

  name_prefix      = local.name_prefix
  aws_region       = var.aws_region
  instance_type    = var.instance_type
  root_volume_size = var.root_volume_size

  subnet_id             = local.subnet_id
  security_group_id     = module.security.security_group_id
  instance_profile_name = module.iam.instance_profile_name

  ecr_repository_url = module.ecr.repository_url
  image_tag          = var.image_tag

  container_name = local.container_name
  container_port = var.container_port
  host_port      = var.host_port

  application_log_group = module.monitoring.application_log_group_name
  system_log_group      = module.monitoring.system_log_group_name
  metrics_namespace     = local.metrics_namespace

  depends_on = [module.monitoring, module.iam]
}

# ---------------------------------------------------------------------------
# 6. Alarm + dashboard
#
# These are defined here (not inside the monitoring module) because they need
# the instance ID, and the instance needs the log groups. Putting them in the
# module would create a circular dependency.
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "${local.name_prefix}-high-cpu"
  alarm_description   = "Average CPU above ${var.cpu_alarm_threshold}% for 10 minutes"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = var.cpu_alarm_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    InstanceId = module.compute.instance_id
  }

  tags = {
    Name = "${local.name_prefix}-high-cpu"
  }
}

resource "aws_cloudwatch_metric_alarm" "instance_unhealthy" {
  alarm_name          = "${local.name_prefix}-status-check-failed"
  alarm_description   = "EC2 status check failed - the instance is unhealthy"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "breaching"

  dimensions = {
    InstanceId = module.compute.instance_id
  }

  tags = {
    Name = "${local.name_prefix}-status-check-failed"
  }
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${local.name_prefix}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "EC2 CPU utilisation (%)"
          region = var.aws_region
          view   = "timeSeries"
          stat   = "Average"
          period = 300
          metrics = [
            ["AWS/EC2", "CPUUtilization", "InstanceId", module.compute.instance_id]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Memory and disk used (%)"
          region = var.aws_region
          view   = "timeSeries"
          stat   = "Average"
          period = 300
          metrics = [
            [local.metrics_namespace, "MemoryUsedPercent", "InstanceId", module.compute.instance_id],
            [local.metrics_namespace, "DiskUsedPercent", "InstanceId", module.compute.instance_id]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Network traffic (bytes)"
          region = var.aws_region
          view   = "timeSeries"
          stat   = "Sum"
          period = 300
          metrics = [
            ["AWS/EC2", "NetworkIn", "InstanceId", module.compute.instance_id],
            ["AWS/EC2", "NetworkOut", "InstanceId", module.compute.instance_id]
          ]
        }
      },
      {
        type   = "log"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Latest application logs"
          region = var.aws_region
          query  = "SOURCE '${module.monitoring.application_log_group_name}' | fields @timestamp, @message | sort @timestamp desc | limit 50"
          view   = "table"
        }
      }
    ]
  })
}
```

---

### 5.12 `terraform/outputs.tf`

```hcl
output "application_url" {
  description = "Open this in the browser."
  value       = "http://${module.compute.public_ip}"
}

output "health_check_url" {
  description = "Health endpoint used by the pipeline."
  value       = "http://${module.compute.public_ip}/health"
}

output "version_url" {
  description = "Shows which image tag is running."
  value       = "http://${module.compute.public_ip}/version"
}

output "public_ip" {
  description = "Static public IP (Elastic IP)."
  value       = module.compute.public_ip
}

output "public_dns" {
  description = "Public DNS name of the instance."
  value       = module.compute.public_dns
}

output "instance_id" {
  description = "EC2 instance ID - the deploy job sends the SSM command here."
  value       = module.compute.instance_id
}

output "ecr_repository_url" {
  description = "Where the pipeline pushes the Docker image."
  value       = module.ecr.repository_url
}

output "application_log_group" {
  description = "CloudWatch log group with the container logs."
  value       = module.monitoring.application_log_group_name
}

output "system_log_group" {
  description = "CloudWatch log group with the OS logs."
  value       = module.monitoring.system_log_group_name
}

output "cloudwatch_dashboard_url" {
  description = "Direct link to the CloudWatch dashboard."
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}

output "aws_account_id" {
  description = "Account the resources were created in."
  value       = data.aws_caller_identity.current.account_id
}
```

---

### 5.13 `terraform/terraform.tfvars`

This file holds your values. **It contains no secrets**, so it is safe to commit.

```hcl
aws_region     = "eu-central-1"
project_name   = "scaa-final"
environment    = "dev"
owner          = "Nikoloz Chkhartishvili"
repository_url = "https://gitlab.com/YOUR-USERNAME/scaa-finalproject"

instance_type    = "t3.micro"
root_volume_size = 20

container_port = 8080
host_port      = 80

allowed_http_cidr  = "0.0.0.0/0"
log_retention_days = 7

cpu_alarm_threshold = 80
```

> Change `repository_url` to your real GitLab URL once you create the project.

---

### 5.14 Check the Terraform code locally

You do **not** have to apply from your laptop — the pipeline does that. But run these checks so the pipeline does not fail on a typo:

```powershell
cd C:\Users\User\Desktop\SCAA-FinalProject\terraform

# 1. Auto-format all files (also fixes indentation)
terraform fmt -recursive

# 2. Download the AWS provider and connect to the S3 backend
terraform init `
  -backend-config="bucket=scaa-final-tfstate-nika-7431" `
  -backend-config="region=eu-central-1"

# 3. Check the syntax and the module wiring
terraform validate
```

`terraform validate` must print **"Success! The configuration is valid."**

Optional — see what would be created without creating it:

```powershell
terraform plan -var="image_tag=local-test"
```

You should see roughly `Plan: 16 to add, 0 to change, 0 to destroy.`

> Do **not** run `terraform apply` from your laptop. Let the pipeline do it — the task asks for that, and it keeps the state clean.

---

<a name="6-step-4-gitlab-cicd"></a>

## 6. Step 4 — GitLab CI/CD pipeline

### 6.1 Move the repository to GitLab

1. Go to https://gitlab.com → **New project** → **Create blank project**.
2. Name: `scaa-finalproject`. Visibility: **Private** (or Public if your teacher needs to see it).
3. **Uncheck** "Initialize repository with a README".
4. Click **Create project** and copy the HTTPS URL, for example
   `https://gitlab.com/nikachkharti/scaa-finalproject.git`.

Then, in PowerShell:

```powershell
cd C:\Users\User\Desktop\SCAA-FinalProject

# Keep GitHub as "origin", add GitLab as a second remote called "gitlab"
git remote add gitlab https://gitlab.com/YOUR-USERNAME/scaa-finalproject.git

# Check
git remote -v
```

When you push later:

```powershell
git push gitlab main
```

> **Simpler option:** if you do not need GitHub, just change origin:
> `git remote set-url origin https://gitlab.com/YOUR-USERNAME/scaa-finalproject.git`
> Then `git push -u origin main` works as usual.

GitLab will ask for a password — use a **Personal Access Token**:
**GitLab → your avatar → Edit profile → Access tokens → Add new token**, scope `write_repository`.

### 6.2 Add the CI/CD variables

In your GitLab project: **Settings → CI/CD → Variables → Add variable**.

Add these four:

| Key | Value | Type | Protect | Mask | Expand |
|---|---|---|---|---|---|
| `AWS_ACCESS_KEY_ID` | the key from section 4.3 | Variable | ✅ | ✅ | ✅ |
| `AWS_SECRET_ACCESS_KEY` | the secret from section 4.3 | Variable | ✅ | ✅ | ✅ |
| `AWS_DEFAULT_REGION` | `eu-central-1` | Variable | ✅ | ❌ | ✅ |
| `TF_STATE_BUCKET` | `scaa-final-tfstate-nika-7431` | Variable | ✅ | ❌ | ✅ |

**What the checkboxes mean:**

* **Masked** — GitLab replaces the value with `[MASKED]` in the job log. Always mask secrets.
* **Protected** — the variable is only given to jobs running on a *protected* branch or tag. This stops someone from opening a merge request with a malicious `.gitlab-ci.yml` and stealing your AWS keys.

**Make `main` a protected branch:**
**Settings → Repository → Protected branches** → `main` should already be protected. If not, protect it.

> This is exactly the "secure credentials management" the task asks for: no keys in Git, masked in logs, only available to protected branches.

### 6.3 Create `.gitlab-ci.yml`

Put this file in the **repository root** (`C:\Users\User\Desktop\SCAA-FinalProject\.gitlab-ci.yml`):

```yaml
# ===========================================================================
# SCAA DevOps Final Project - CI/CD pipeline
#
# Stages:
#   1. build_test       Build the Docker image and validate it (fail fast).
#   2. terraform_apply  Create the AWS infrastructure.
#   3. deploy           Push the image to ECR and start it on EC2 via SSM.
#   4. destroy          Delete everything (manual, or automatic on the
#                       "destroy" branch).
# ===========================================================================

stages:
  - build_test
  - terraform_apply
  - deploy
  - destroy

variables:
  # ---- Docker ----
  DOCKER_TLS_CERTDIR: "/certs"          # secure connection to the dind service
  DOCKER_BUILDKIT: "1"

  # ---- Application ----
  IMAGE_NAME: "scaa-final-web"
  IMAGE_TAG: "$CI_COMMIT_SHORT_SHA"     # a unique, traceable tag per commit
  DOCKER_CONTEXT_DIR: "SCAA-Final"
  DOCKERFILE_PATH: "SCAA-Final/SCAA-Final-Web/Dockerfile"
  APP_PORT: "8080"

  # ---- Terraform ----
  TF_DIR: "terraform"
  TF_VERSION: "1.13.3"
  TF_IN_AUTOMATION: "true"              # cleaner, non-interactive output
  TF_INPUT: "0"                         # never wait for keyboard input

  # ---- Git ----
  GIT_DEPTH: "10"                       # shallow clone = faster pipeline

default:
  interruptible: true                   # a new push cancels the old pipeline
  retry:
    max: 1
    when:
      - runner_system_failure
      - stuck_or_timeout_failure

# ---------------------------------------------------------------------------
# Reusable pieces
# ---------------------------------------------------------------------------
.docker_job: &docker_job
  image: docker:28-cli
  services:
    - name: docker:28-dind
      alias: docker
  before_script:
    - set -euo pipefail
    - apk add --no-cache curl jq aws-cli bash > /dev/null
    - docker info > /dev/null
    - echo "Runner is ready. Commit ${CI_COMMIT_SHORT_SHA} on branch ${CI_COMMIT_REF_NAME}."

.terraform_job: &terraform_job
  image:
    name: hashicorp/terraform:$TF_VERSION
    entrypoint: [""]
  before_script:
    - set -euo pipefail
    - apk add --no-cache jq bash curl > /dev/null
    - cd "$TF_DIR"
    - echo "Initialising Terraform with backend bucket ${TF_STATE_BUCKET}"
    - |
      terraform init \
        -input=false \
        -reconfigure \
        -backend-config="bucket=${TF_STATE_BUCKET}" \
        -backend-config="region=${AWS_DEFAULT_REGION}" \
        -backend-config="key=scaa-final/${CI_PROJECT_PATH_SLUG}/terraform.tfstate"

# ===========================================================================
# STAGE 1 - BUILD & TEST
# ===========================================================================
build_and_test:
  <<: *docker_job
  stage: build_test
  script:
    - echo "===== Building the Docker image ====="
    - |
      docker build \
        --pull \
        --file "$DOCKERFILE_PATH" \
        --tag "$IMAGE_NAME:$IMAGE_TAG" \
        --build-arg APP_VERSION="$IMAGE_TAG" \
        --build-arg BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --build-arg VCS_REF="$CI_COMMIT_SHA" \
        "$DOCKER_CONTEXT_DIR"

    - echo "===== Checking the image metadata (author + version) ====="
    - docker inspect "$IMAGE_NAME:$IMAGE_TAG" --format '{{json .Config.Labels}}' | jq .
    - |
      AUTHORS=$(docker inspect "$IMAGE_NAME:$IMAGE_TAG" \
                 --format '{{index .Config.Labels "org.opencontainers.image.authors"}}')
      VERSION=$(docker inspect "$IMAGE_NAME:$IMAGE_TAG" \
                 --format '{{index .Config.Labels "org.opencontainers.image.version"}}')
      if [ -z "$AUTHORS" ] || [ -z "$VERSION" ]; then
        echo "FAIL: required image metadata is missing."
        exit 1
      fi
      echo "OK: author='$AUTHORS' version='$VERSION'"

    - echo "===== Checking that the container does NOT run as root ====="
    - |
      UID_IN_IMAGE=$(docker run --rm --entrypoint sh "$IMAGE_NAME:$IMAGE_TAG" -c 'id -u')
      echo "Container runs as UID $UID_IN_IMAGE"
      if [ "$UID_IN_IMAGE" = "0" ]; then
        echo "FAIL: the container runs as root."
        exit 1
      fi
      echo "OK: non-root user."

    - echo "===== Smoke test: start the container and call /health ====="
    # Ports are published on the dind service, which the job reaches
    # at the hostname "docker".
    - docker run -d --name smoke -p 8080:8080 "$IMAGE_NAME:$IMAGE_TAG"
    - |
      OK=0
      for i in $(seq 1 30); do
        if curl -fsS "http://docker:8080/health" > /dev/null 2>&1; then
          OK=1
          echo "Health check passed on attempt $i."
          break
        fi
        echo "Attempt $i/30 - waiting for the application..."
        sleep 2
      done
      if [ "$OK" -ne 1 ]; then
        echo "FAIL: /health never answered. Container logs:"
        docker logs smoke || true
        exit 1
      fi

    - echo "===== Checking the home page and /version ====="
    - curl -fsS -o /dev/null -w "GET /          -> HTTP %{http_code}\n" http://docker:8080/
    - curl -fsS -w "\n" http://docker:8080/version
    - curl -fsS -w "\n" http://docker:8080/health

    - echo "===== Application logs from the smoke test ====="
    - docker logs smoke

    - echo "===== Saving the image so the deploy job can reuse it ====="
    - mkdir -p image
    - docker save "$IMAGE_NAME:$IMAGE_TAG" | gzip -1 > image/app.tar.gz
    - ls -lh image/app.tar.gz

  after_script:
    # Cleanup runs even when the script above fails.
    - docker rm -f smoke > /dev/null 2>&1 || true
    - docker image prune -af > /dev/null 2>&1 || true
    - echo "Local Docker cleanup done."

  artifacts:
    name: "image-$CI_COMMIT_SHORT_SHA"
    paths:
      - image/app.tar.gz
    expire_in: 1 day

  rules:
    - if: $CI_COMMIT_BRANCH == "destroy"
      when: never
    - when: always

# ===========================================================================
# STAGE 2 - TERRAFORM APPLY
# ===========================================================================
terraform_apply:
  <<: *terraform_job
  stage: terraform_apply
  needs: ["build_and_test"]
  environment:
    name: production
    url: $DYNAMIC_ENVIRONMENT_URL
  script:
    - echo "===== Checking formatting ====="
    - terraform fmt -check -recursive -diff

    - echo "===== Validating the configuration ====="
    - terraform validate

    - echo "===== Planning ====="
    - terraform plan -input=false -var="image_tag=$IMAGE_TAG" -out=tfplan

    - echo "===== Applying ====="
    - terraform apply -input=false -auto-approve tfplan

    - echo "===== Outputs ====="
    - terraform output
    - terraform output -json > "$CI_PROJECT_DIR/tf_output.json"

    - |
      APP_URL=$(jq -r '.application_url.value' "$CI_PROJECT_DIR/tf_output.json")
      echo "DYNAMIC_ENVIRONMENT_URL=$APP_URL" >> "$CI_PROJECT_DIR/deploy.env"
      echo "Infrastructure is ready. Application URL: $APP_URL"

  artifacts:
    name: "tfoutput-$CI_COMMIT_SHORT_SHA"
    paths:
      - tf_output.json
    reports:
      dotenv: deploy.env
    expire_in: 1 day

  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
      when: on_success
    - when: never

# ===========================================================================
# STAGE 3 - DEPLOY APPLICATION
# ===========================================================================
deploy_application:
  <<: *docker_job
  stage: deploy
  needs:
    - job: build_and_test
      artifacts: true
    - job: terraform_apply
      artifacts: true
  environment:
    name: production
    url: $DYNAMIC_ENVIRONMENT_URL
  script:
    - echo "===== Reading Terraform outputs ====="
    - ECR_URL=$(jq -r '.ecr_repository_url.value' tf_output.json)
    - INSTANCE_ID=$(jq -r '.instance_id.value' tf_output.json)
    - APP_URL=$(jq -r '.application_url.value' tf_output.json)
    - HEALTH_URL=$(jq -r '.health_check_url.value' tf_output.json)
    - REGISTRY=$(echo "$ECR_URL" | cut -d/ -f1)
    - echo "ECR=$ECR_URL  INSTANCE=$INSTANCE_ID  URL=$APP_URL"

    - echo "===== Loading the image built in stage 1 ====="
    - gunzip -c image/app.tar.gz | docker load
    - docker images "$IMAGE_NAME"

    - echo "===== Logging in to ECR ====="
    - aws ecr get-login-password --region "$AWS_DEFAULT_REGION" | docker login --username AWS --password-stdin "$REGISTRY"

    - echo "===== Tagging and pushing ====="
    - docker tag "$IMAGE_NAME:$IMAGE_TAG" "$ECR_URL:$IMAGE_TAG"
    - docker tag "$IMAGE_NAME:$IMAGE_TAG" "$ECR_URL:latest"
    - docker push "$ECR_URL:$IMAGE_TAG"
    - docker push "$ECR_URL:latest"

    - echo "===== Waiting until the instance is registered in SSM ====="
    - |
      READY=0
      for i in $(seq 1 40); do
        STATUS=$(aws ssm describe-instance-information \
                  --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
                  --query 'InstanceInformationList[0].PingStatus' \
                  --output text 2>/dev/null || echo "None")
        if [ "$STATUS" = "Online" ]; then
          READY=1
          echo "Instance is online in SSM (attempt $i)."
          break
        fi
        echo "Attempt $i/40 - SSM status: $STATUS"
        sleep 15
      done
      if [ "$READY" -ne 1 ]; then
        echo "FAIL: the instance never appeared in SSM."
        exit 1
      fi

    - echo "===== Running the deployment on the EC2 instance ====="
    - |
      COMMAND_ID=$(aws ssm send-command \
        --instance-ids "$INSTANCE_ID" \
        --document-name "AWS-RunShellScript" \
        --comment "Deploy $IMAGE_TAG from pipeline $CI_PIPELINE_ID" \
        --parameters "commands=[\"/usr/local/bin/deploy-app.sh $IMAGE_TAG\"]" \
        --timeout-seconds 600 \
        --query 'Command.CommandId' \
        --output text)
      echo "SSM command id: $COMMAND_ID"

      # Wait for it to finish (the waiter can time out; we check the status next).
      aws ssm wait command-executed \
        --command-id "$COMMAND_ID" \
        --instance-id "$INSTANCE_ID" || true

      RESULT=$(aws ssm get-command-invocation \
        --command-id "$COMMAND_ID" \
        --instance-id "$INSTANCE_ID")

      echo "----- remote stdout -----"
      echo "$RESULT" | jq -r '.StandardOutputContent'
      echo "----- remote stderr -----"
      echo "$RESULT" | jq -r '.StandardErrorContent'

      STATUS=$(echo "$RESULT" | jq -r '.Status')
      echo "Remote command status: $STATUS"
      if [ "$STATUS" != "Success" ]; then
        echo "FAIL: the deployment on EC2 did not succeed."
        exit 1
      fi

    - echo "===== Verifying the public URL ====="
    - |
      OK=0
      for i in $(seq 1 20); do
        CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$HEALTH_URL" || echo "000")
        if [ "$CODE" = "200" ]; then
          OK=1
          echo "Public health check returned 200 on attempt $i."
          break
        fi
        echo "Attempt $i/20 - got HTTP $CODE"
        sleep 6
      done
      if [ "$OK" -ne 1 ]; then
        echo "FAIL: the application is not reachable at $HEALTH_URL"
        exit 1
      fi

    - echo "===== Deployed version ====="
    - curl -fsS --max-time 10 "$APP_URL/version"; echo
    - echo ""
    - echo "==============================================================="
    - echo " DEPLOYMENT SUCCESSFUL"
    - echo " Application : $APP_URL"
    - echo " Health      : $HEALTH_URL"
    - echo " Image tag   : $IMAGE_TAG"
    - echo "==============================================================="

  after_script:
    - docker image prune -af > /dev/null 2>&1 || true
    - docker logout "$(jq -r '.ecr_repository_url.value' tf_output.json 2>/dev/null | cut -d/ -f1)" > /dev/null 2>&1 || true
    - echo "Local Docker cleanup done."

  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
      when: on_success
    - when: never

# ===========================================================================
# STAGE 4 - DESTROY
# ===========================================================================

# 4a. Manual button on main. Click it when you finish working.
terraform_destroy_manual:
  <<: *terraform_job
  stage: destroy
  needs: []
  environment:
    name: production
    action: stop
  script:
    - echo "===== DESTROYING ALL INFRASTRUCTURE ====="
    - terraform plan -destroy -input=false -var="image_tag=$IMAGE_TAG" -out=destroy.tfplan
    - terraform apply -input=false -auto-approve destroy.tfplan
    - echo "All AWS resources for this project have been deleted."
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
      when: manual
      allow_failure: true
    - when: never

# 4b. Automatic destroy: push to a branch named "destroy".
#     Shows the "different branch trigger" option from the task.
terraform_destroy_on_branch:
  <<: *terraform_job
  stage: destroy
  needs: []
  script:
    - echo "===== Branch 'destroy' detected - removing infrastructure ====="
    - terraform destroy -input=false -auto-approve -var="image_tag=latest"
    - echo "All AWS resources for this project have been deleted."
  rules:
    - if: $CI_COMMIT_BRANCH == "destroy"
      when: always
    - when: never
```

### 6.4 How the pipeline meets every requirement

| Task requirement | Where it happens |
|---|---|
| Build & Test stage | `build_and_test` — builds, checks metadata, checks non-root, smoke-tests `/health` |
| Terraform Apply stage | `terraform_apply` |
| Deploy Application stage | `deploy_application` |
| Terraform Destroy stage | `terraform_destroy_manual` (button) **and** `terraform_destroy_on_branch` (branch trigger) |
| Secure AWS credentials | GitLab masked + protected variables; nothing in Git |
| Fail fast | `set -euo pipefail`, explicit `exit 1` on every check, GitLab stops the pipeline on any failed job |
| Clear logs | `echo "===== ... ====="` headers, remote stdout/stderr printed, attempt counters |
| Local image cleanup | `after_script` with `docker image prune -af` in both Docker jobs |

### 6.5 Push and watch the pipeline

```powershell
cd C:\Users\User\Desktop\SCAA-FinalProject

git add .
git commit -m "Add Docker metadata, health endpoint, Terraform IaC and GitLab CI/CD pipeline"
git push gitlab main
```

Then open GitLab → **Build → Pipelines**. Click the running pipeline and watch each job.

**Expected timing on the first run:**

| Job | Time |
|---|---|
| `build_and_test` | 3–6 min (NuGet restore is slow the first time) |
| `terraform_apply` | 2–4 min (EC2 creation) |
| `deploy_application` | 4–8 min (waiting for SSM to come online is the slow part) |

The **first** run is the slowest. Later runs are much faster.

---

<a name="7-step-5-deployment-and-monitoring"></a>

## 7. Step 5 — deployment and monitoring check

### 7.1 Open the site

At the end of `deploy_application` the log prints the URL. It looks like:

```
 Application : http://3.121.45.67
```

Open it in your browser. You should see your ASP.NET MVC home page.

Also check:

* `http://<IP>/health` → `Healthy`
* `http://<IP>/version` → JSON with the commit SHA as the version

**Take screenshots of all three.** You will need them for the report.

### 7.2 Check CloudWatch Logs (application)

AWS Console → **CloudWatch → Logs → Log groups**.

1. Open `/scaa-final-dev/application`.
2. Click the newest log stream.
3. You will see lines from your ASP.NET app, for example:

```
2026-09-12 11:04:12 info: Microsoft.Hosting.Lifetime[14] Now listening on: http://[::]:8080
```

These arrive because of `--log-driver awslogs` in the deploy script.

Confirm retention: on the log group list, the **Retention** column must show `7 days`. That is the "retention policy" requirement.

### 7.3 Check CloudWatch Logs (system)

Open `/scaa-final-dev/system`. You should find three streams:

* `<instance-id>/user-data` — the whole bootstrap log
* `<instance-id>/messages` — Linux system log
* `<instance-id>/deploy` — every deployment run

### 7.4 Check CloudWatch Metrics

AWS Console → **CloudWatch → Metrics → All metrics**.

* **`AWS/EC2`** namespace → **Per-Instance Metrics** → `CPUUtilization`, `NetworkIn`, `NetworkOut`, `StatusCheckFailed`. These come free from AWS.
* **`scaa-final-dev/system`** namespace → `MemoryUsedPercent`, `DiskUsedPercent`. These come from the CloudWatch agent you installed.

> Memory and disk metrics need 2–5 minutes after boot to appear. Be patient.

### 7.5 Check the dashboard and alarms

* **CloudWatch → Dashboards → `scaa-final-dev-dashboard`** — four widgets: CPU, memory/disk, network, and live log table.
* **CloudWatch → Alarms** — two alarms: `scaa-final-dev-high-cpu` and `scaa-final-dev-status-check-failed`. Both should be in `OK` state.

The dashboard link is also printed by `terraform output cloudwatch_dashboard_url`.

**Take screenshots of the dashboard, the log group list (showing retention), and the alarm list.**

### 7.6 Prove the deployment updates itself

Make a small visible change (for example, edit the heading in `SCAA-Final/SCAA-Final-Web/Views/Home/Index.cshtml`), then:

```powershell
git add .
git commit -m "Change home page heading"
git push gitlab main
```

Watch the pipeline run again. When it finishes, refresh the browser — the new text is there, and `/version` shows the new commit SHA. This is your proof that the automation really works. **Record a short screen video if you can.**

---

<a name="8-step-6-destroy"></a>

## 8. Step 6 — destroy the infrastructure

### Option A — the manual button (recommended)

1. GitLab → **Build → Pipelines** → open the latest successful pipeline.
2. In the **destroy** stage, find `terraform_destroy_manual`.
3. Click the ▶ **play** button.
4. Wait 2–3 minutes. The log ends with `Destroy complete! Resources: N destroyed.`

### Option B — the destroy branch

```powershell
git checkout -b destroy
git push gitlab destroy
```

The `terraform_destroy_on_branch` job runs automatically.

To use it again later:

```powershell
git checkout main
git push gitlab --delete destroy   # remove the remote branch
git branch -D destroy              # remove the local branch
```

### Verify that nothing is left

```powershell
# No running instances
aws ec2 describe-instances `
  --filters "Name=tag:Project,Values=scaa-final" "Name=instance-state-name,Values=running,pending,stopping,stopped" `
  --query "Reservations[].Instances[].[InstanceId,State.Name]" --output table

# No ECR repository
aws ecr describe-repositories --query "repositories[].repositoryName" --output table

# No log groups
aws logs describe-log-groups --log-group-name-prefix "/scaa-final" --query "logGroups[].logGroupName" --output table

# No elastic IPs left over (these cost money when unattached!)
aws ec2 describe-addresses --query "Addresses[].[PublicIp,InstanceId]" --output table
```

All four should be empty.

> The S3 state bucket and the IAM CI user stay — they are your bootstrap, not project resources. They cost almost nothing. Delete them by hand at the very end of the course if you wish.

---

<a name="9-step-7-readme"></a>

## 9. Step 7 — README.md for the graders

Documentation is a graded item. Replace `README.md` in the repository root with this. **Fill in the `<...>` parts.**

````markdown
# SCAA DevOps Final Project — Containerised Web Application on AWS

An ASP.NET Core 10 MVC application, packaged with Docker, deployed to AWS EC2
through a fully automated GitLab CI/CD pipeline, with infrastructure managed by
Terraform and monitoring in Amazon CloudWatch.

**Author:** Nikoloz Chkhartishvili
**Course:** SCAA DevOps
**Repository:** <your GitLab URL>

---

## 1. Architecture

```
Developer  ->  GitLab  ->  Pipeline  ->  AWS
                              |
      +-----------------------+-----------------------+
      |            |              |                   |
  build_test  terraform_apply   deploy          destroy (manual)
      |            |              |
   Docker      ECR / EC2 /    ECR push +
   image +     IAM / SG /     SSM run
   /health     CloudWatch
```

| Layer | Technology |
|---|---|
| Application | ASP.NET Core 10 MVC, listens on port 8080 |
| Container | Docker, multi-stage build, non-root user, OCI labels |
| Registry | Amazon ECR (private, scan on push, 5-image lifecycle policy) |
| Compute | Amazon EC2 `t3.micro`, Amazon Linux 2023, Elastic IP |
| IaC | Terraform 1.13, 5 modules, remote state in S3 with locking |
| CI/CD | GitLab CI, 4 stages |
| Monitoring | CloudWatch Logs (7-day retention), Metrics, 2 Alarms, 1 Dashboard |
| Remote access | AWS SSM Session Manager — **no SSH, no open port 22** |

---

## 2. Repository layout

```
.
├── .gitlab-ci.yml                     # CI/CD pipeline
├── README.md
├── SCAA-Final/
│   ├── docker-compose.yml             # local development only
│   └── SCAA-Final-Web/
│       ├── Dockerfile                 # multi-stage, non-root, labelled
│       ├── Program.cs                 # /health and /version endpoints
│       ├── Controllers/ Views/ wwwroot/
│       └── SCAA-Final-Web.csproj
└── terraform/
    ├── backend.tf  providers.tf  variables.tf
    ├── main.tf     outputs.tf    terraform.tfvars
    └── modules/
        ├── ecr/          # private container registry
        ├── security/     # security group (HTTP in, 80/443 out, no SSH)
        ├── iam/          # least-privilege EC2 role + instance profile
        ├── monitoring/   # CloudWatch log groups with retention
        └── compute/      # EC2 instance, EIP, bootstrap script
```

---

## 3. Application

| Endpoint | Purpose |
|---|---|
| `GET /` | Home page |
| `GET /health` | Returns `200 Healthy`. Used by CI and by the deploy script. |
| `GET /version` | JSON: application name, deployed image tag, host, UTC time. |

The container listens on **8080**; the EC2 instance publishes it on **80**.

### Image metadata

```bash
docker inspect <image> --format '{{json .Config.Labels}}'
```

| Label | Value |
|---|---|
| `org.opencontainers.image.title` | SCAA-Final-Web |
| `org.opencontainers.image.authors` | Nikoloz Chkhartishvili |
| `org.opencontainers.image.version` | short commit SHA of the build |
| `org.opencontainers.image.created` | build timestamp |
| `org.opencontainers.image.revision` | full commit SHA |

---

## 4. Running locally

```bash
docker build --pull \
  -f SCAA-Final/SCAA-Final-Web/Dockerfile \
  -t scaa-final-web:local \
  --build-arg APP_VERSION=local \
  SCAA-Final

docker run -d --name scaa -p 8080:8080 scaa-final-web:local

curl http://localhost:8080/health    # -> Healthy
curl http://localhost:8080/version

docker rm -f scaa
```

Or with Compose:

```bash
cd SCAA-Final
docker compose up --build      # http://localhost:5080
```

---

## 5. One-time setup (bootstrap)

Terraform state needs an S3 bucket, and the pipeline needs AWS keys.
Both are created once, by hand.

```bash
BUCKET=<your-unique-bucket-name>
REGION=eu-central-1

aws s3api create-bucket --bucket $BUCKET --region $REGION \
  --create-bucket-configuration LocationConstraint=$REGION
aws s3api put-bucket-versioning --bucket $BUCKET \
  --versioning-configuration Status=Enabled
aws s3api put-public-access-block --bucket $BUCKET \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

aws iam create-user --user-name gitlab-ci-scaa
aws iam put-user-policy --user-name gitlab-ci-scaa \
  --policy-name scaa-final-ci-policy --policy-document file://ci-policy.json
aws iam create-access-key --user-name gitlab-ci-scaa
```

### GitLab CI/CD variables

**Settings → CI/CD → Variables**

| Key | Masked | Protected |
|---|---|---|
| `AWS_ACCESS_KEY_ID` | yes | yes |
| `AWS_SECRET_ACCESS_KEY` | yes | yes |
| `AWS_DEFAULT_REGION` | no | yes |
| `TF_STATE_BUCKET` | no | yes |

No credential is stored in this repository.

---

## 6. Pipeline

| Stage | Job | Trigger | What it does |
|---|---|---|---|
| `build_test` | `build_and_test` | every push (except `destroy`) | Builds the image, verifies labels, verifies non-root, starts the container, smoke-tests `/health`, `/`, `/version`, saves the image as an artifact, prunes local images. |
| `terraform_apply` | `terraform_apply` | `main` | `fmt -check`, `validate`, `plan`, `apply`. Creates ECR, IAM, SG, EC2, EIP, log groups, alarms, dashboard. Exports outputs as an artifact. |
| `deploy` | `deploy_application` | `main` | Loads the artifact image, pushes to ECR (`:sha` and `:latest`), waits for SSM, runs `/usr/local/bin/deploy-app.sh` on EC2, verifies the public `/health`. |
| `destroy` | `terraform_destroy_manual` | `main`, manual button | `terraform destroy`. |
| `destroy` | `terraform_destroy_on_branch` | push to branch `destroy` | `terraform destroy`. |

**Fail fast:** every job uses `set -euo pipefail` and exits non-zero on any
failed check, so GitLab stops the pipeline immediately.

**Cleanup:** both Docker jobs run `docker image prune -af` in `after_script`,
which executes even when the job fails.

---

## 7. Infrastructure (Terraform)

| Resource | Module | Notes |
|---|---|---|
| `aws_ecr_repository` | `ecr` | AES256 encryption, scan on push, `force_delete`, lifecycle policy keeps 5 images |
| `aws_security_group` | `security` | Ingress: TCP 80 only. Egress: 80/443 only. **Port 22 closed.** |
| `aws_iam_role` + inline policies | `iam` | ECR pull limited to this repository, CloudWatch writes limited to these log groups, `PutMetricData` limited by namespace condition, plus `AmazonSSMManagedInstanceCore` |
| `aws_cloudwatch_log_group` ×2 | `monitoring` | `/scaa-final-dev/application`, `/scaa-final-dev/system`, 7-day retention |
| `aws_instance` + `aws_eip` | `compute` | Amazon Linux 2023 (latest via SSM parameter), gp3 encrypted root volume, IMDSv2 required, detailed monitoring on |
| `aws_cloudwatch_metric_alarm` ×2 | root | High CPU, failed status check |
| `aws_cloudwatch_dashboard` | root | CPU, memory/disk, network, live logs |

**State:** S3 with `encrypt = true` and `use_lockfile = true` (native S3 locking,
no DynamoDB table needed).

**Tagging:** `provider "aws" { default_tags { ... } }` adds
`Project`, `Environment`, `Owner`, `ManagedBy`, `Repository`, `CostCenter`
to every taggable resource automatically.

**Outputs:**

```
application_url  health_check_url  version_url  public_ip  public_dns
instance_id  ecr_repository_url  application_log_group  system_log_group
cloudwatch_dashboard_url  aws_account_id
```

---

## 8. Verification

After a successful pipeline:

```bash
curl -i  http://<public-ip>/          # 200, HTML home page
curl     http://<public-ip>/health    # Healthy
curl     http://<public-ip>/version   # {"application":"SCAA-Final-Web","version":"<sha>",...}
```

CloudWatch:

| What | Where |
|---|---|
| Application logs | CloudWatch → Logs → `/scaa-final-dev/application` |
| System + deploy logs | CloudWatch → Logs → `/scaa-final-dev/system` |
| CPU / network | Metrics → `AWS/EC2` |
| Memory / disk | Metrics → `scaa-final-dev/system` |
| Dashboard | Dashboards → `scaa-final-dev-dashboard` |
| Alarms | Alarms → `scaa-final-dev-high-cpu`, `scaa-final-dev-status-check-failed` |

---

## 9. Destroying the infrastructure

* **Manual:** latest pipeline on `main` → stage `destroy` → play `terraform_destroy_manual`.
* **Branch trigger:** `git push origin HEAD:destroy`.

Verify:

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Project,Values=scaa-final" \
            "Name=instance-state-name,Values=running,pending,stopped" \
  --query "Reservations[].Instances[].InstanceId"
aws ecr describe-repositories --query "repositories[].repositoryName"
aws logs describe-log-groups --log-group-name-prefix "/scaa-final"
aws ec2 describe-addresses --query "Addresses[].PublicIp"
```

---

## 10. Security decisions

| Decision | Reason |
|---|---|
| No SSH, SSM instead | No open port 22, no private key stored in CI |
| Non-root container user (`$APP_UID`) | Limits damage if the app is compromised |
| `--read-only` container + tmpfs `/tmp` | The container cannot modify its own filesystem |
| `no-new-privileges` | Blocks privilege escalation inside the container |
| IMDSv2 required (`http_tokens = "required"`) | Protects instance credentials from SSRF attacks |
| Encrypted EBS volume and ECR repository | Data protected at rest |
| Protected + masked GitLab variables | Credentials never printed, never given to unprotected branches |
| Scoped IAM policies | The CI user and the instance role can only touch this project's resources |
| Egress limited to 80/443 | Reduces what a compromised host can reach |

---

## 11. Known limitations

* HTTP only, no TLS. A production setup would put an Application Load Balancer
  with an ACM certificate in front, or use CloudFront.
* Single EC2 instance in the default VPC; no auto-scaling and no high availability.
* Deployment is "stop then start", so there are a few seconds of downtime.
  Blue/green or ECS rolling updates would remove that.
* Static IAM user keys. GitLab-to-AWS OIDC federation would remove long-lived keys.
````

---

<a name="10-best-practices-checklist"></a>

## 10. Best practices checklist

Go through this before you submit. Each line is something the task grades.

### Docker

- [x] Multi-stage build — SDK stage is thrown away
- [x] Small runtime base image (`aspnet:10.0`, ~110 MB)
- [x] Non-root user (`USER $APP_UID`)
- [x] Metadata labels: author, version, created, revision, title, description
- [x] Only the port you actually use is exposed (8080)
- [x] `.dockerignore` keeps `bin/`, `obj/`, `.vs/`, `.git/` out of the build context
- [x] Layer caching: `csproj` copied and restored before the source

### Terraform

- [x] 5 reusable modules, each with `variables.tf` / `main.tf` / `outputs.tf`
- [x] All values come from variables with descriptions, types and defaults
- [x] Input validation on `project_name`, `environment`, `log_retention_days`
- [x] Useful outputs (URL, instance id, ECR URL, dashboard link)
- [x] Remote state in S3, encrypted, versioned, with locking
- [x] `default_tags` on the provider — consistent tagging everywhere
- [x] `terraform fmt -check` and `terraform validate` run in the pipeline
- [x] Apply and destroy happen only in the pipeline, never by hand
- [x] No hard-coded AMI id — looked up from an SSM public parameter

### CI/CD

- [x] Four stages, exactly as the task describes
- [x] `set -euo pipefail` everywhere — fail fast
- [x] Every check ends with an explicit `exit 1` on failure
- [x] Credentials as masked + protected GitLab variables, never in Git
- [x] Clear section headers and attempt counters in the logs
- [x] Remote stdout and stderr printed back into the job log
- [x] `docker image prune -af` in `after_script` — cleanup even on failure
- [x] Image built once and reused as an artifact — no duplicate builds
- [x] Destroy available both as a manual button and as a branch trigger

### AWS

- [x] Least-privilege IAM: ECR pull scoped to one repository ARN, CloudWatch
      writes scoped to two log groups, `PutMetricData` scoped by namespace
- [x] Security Group: inbound port 80 only, no SSH, outbound 80/443 only
- [x] IMDSv2 required
- [x] Encrypted root volume, encrypted ECR
- [x] Consistent tags on every resource
- [x] ECR lifecycle policy so storage does not grow forever

### Monitoring

- [x] Application logs in CloudWatch through the Docker `awslogs` driver
- [x] System, bootstrap and deployment logs through the CloudWatch agent
- [x] Retention policy set to 7 days on both log groups
- [x] Built-in EC2 metrics plus custom memory and disk metrics
- [x] Two alarms (high CPU, failed status check)
- [x] One dashboard combining metrics and live logs

### Documentation

- [x] README with architecture, setup, pipeline table, verification steps,
      destroy instructions, security decisions and known limitations

---

<a name="11-troubleshooting"></a>

## 11. Troubleshooting

### Pipeline problems

**`terraform fmt -check` fails**
Run `terraform fmt -recursive` inside `terraform/` on your laptop, commit, push.

**`Error: Failed to get existing workspaces: S3 bucket does not exist`**
The `TF_STATE_BUCKET` variable is wrong, or the bucket is in another region.
Check with `aws s3 ls` and compare with the GitLab variable.

**`AccessDenied` or `UnauthorizedOperation` during apply**
The CI IAM user is missing a permission. Read the error — it names the exact
action, for example `ec2:AllocateAddress`. Add it to `ci-policy.json` and run
`aws iam put-user-policy` again.

**Variables are empty in the job (`TF_STATE_BUCKET` is blank)**
The variables are **Protected** but the branch is not protected.
Either protect the branch (Settings → Repository → Protected branches) or
uncheck "Protect variable".

**`curl: (7) Failed to connect to docker port 8080` in the smoke test**
With Docker-in-Docker, published ports live on the `docker` service host, not
on `localhost`. The URL must be `http://docker:8080/health`, not
`http://localhost:8080/health`.

**The `deploy` job says "the instance never appeared in SSM"**
The instance needs 2–4 minutes to install the SSM agent and register.
Causes: the instance has no internet route (check that the subnet is public and
`associate_public_ip_address = true`), or egress 443 is blocked, or the IAM
role is missing `AmazonSSMManagedInstanceCore`. Check the
`/scaa-final-dev/system` log group, stream `<instance-id>/user-data`.

**`docker load` fails or the artifact is missing**
The `build_and_test` job must finish successfully and the `deploy_application`
job must list it under `needs:` with `artifacts: true`.

### Application problems

**The browser shows "connection refused"**
1. Is the container running? Check the deploy job log — it prints the remote output.
2. Does the Security Group allow port 80? `aws ec2 describe-security-groups`.
3. Is `host_port = 80` in `terraform.tfvars`?

**The browser redirects to `https://` and fails**
You did not remove `app.UseHttpsRedirection()` / `app.UseHsts()` from
`Program.cs`. Remove them, commit, push. Also clear the browser HSTS cache:
in Chrome open `chrome://net-internals/#hsts`, put your IP into "Delete domain
security policies" and click Delete.

**`/health` returns 404**
`builder.Services.AddHealthChecks()` or `app.MapHealthChecks("/health")` is
missing, or `MapHealthChecks` was placed after `app.Run()`.

**No logs appear in CloudWatch**
1. The log group must exist **before** the container starts. Terraform creates
   it first, but if you changed the name, they no longer match.
2. Check the IAM role has `logs:PutLogEvents` on that log group.
3. On the instance, read `/var/log/scaa-deploy.log` through
   CloudWatch → `/scaa-final-dev/system` → `<instance-id>/deploy`.

**Memory and disk metrics are missing**
The CloudWatch agent takes a few minutes. Check the agent status through SSM:

```powershell
aws ssm send-command `
  --instance-ids "i-xxxxxxxxxxxx" `
  --document-name "AWS-RunShellScript" `
  --parameters 'commands=["/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a status"]'
```

Then read the result with `aws ssm get-command-invocation --command-id <id> --instance-id <id>`.

### Terraform problems

**`Error acquiring the state lock`**
Another pipeline is running, or one crashed. Wait a minute. If it is really
stuck, delete the `.tflock` object in the S3 bucket, or run
`terraform force-unlock <LOCK_ID>`.

**`RepositoryNotEmptyException` on destroy**
`force_delete = true` is missing from the ECR resource. Add it and apply again
before destroying.

**Terraform wants to replace the EC2 instance on every run**
This is caused by the AMI id changing. The `lifecycle { ignore_changes = [ami] }`
block prevents it. Make sure you copied it.

**`Error: creating EC2 Instance: InvalidAMIID.NotFound`**
The region in `terraform.tfvars` does not match `AWS_DEFAULT_REGION` in GitLab.

### Other small problems

**`apk add aws-cli` fails or is very slow in the job**
The Alpine community repository sometimes lags. Replace that one line in the
`.docker_job` `before_script` with the official installer:

```yaml
- apk add --no-cache curl jq bash python3 py3-pip > /dev/null
- pip install --break-system-packages --quiet awscli
```

Or use `amazon/aws-cli:2` as the job image and install the Docker CLI instead.

**The app logs a warning about Data Protection keys**
You will see something like
`No XML encryptor configured. Key ... may be persisted in unencrypted form.`
or a warning that the key ring could not be written. This happens because the
container runs with `--read-only`. The app still works — ASP.NET falls back to
in-memory keys. If it actually crashes on your app, give it a writable folder
by adding one line to the `docker run` command in `user_data.sh.tftpl`:

```
  --tmpfs /home/app/.aspnet:rw,size=16m \
```

**GitLab says "This job is stuck because you don't have any active runners"**
On gitlab.com you must verify your account (add a credit card — you are not
charged) before shared runners are enabled. Go to
**Settings → CI/CD → Runners** and check that shared runners are turned on.

**The pipeline uses all your free CI minutes**
gitlab.com gives 400 free minutes per month on the free plan. This pipeline
uses roughly 10–15 minutes per full run. Do not push 50 times in one day. Test
Docker builds locally first.

### Getting a shell on the instance (for debugging)

You have no SSH key, but SSM gives you a session:

```powershell
aws ssm start-session --target i-xxxxxxxxxxxxx
```

Then on the instance:

```bash
sudo docker ps -a
sudo docker logs scaa-final-web
sudo cat /var/log/user-data.log
sudo cat /var/log/scaa-deploy.log
curl -i http://localhost/health
```

(You may need the Session Manager plugin:
`winget install Amazon.SessionManagerPlugin`.)

---

<a name="12-final-submission-checklist"></a>

## 12. Final submission checklist

### Files that must exist in the repository

```
.gitlab-ci.yml
README.md
.gitignore                       (with Terraform rules added)
SCAA-Final/docker-compose.yml
SCAA-Final/.dockerignore
SCAA-Final/SCAA-Final-Web/Dockerfile          (with LABEL metadata)
SCAA-Final/SCAA-Final-Web/Program.cs          (with /health and /version)
terraform/backend.tf
terraform/providers.tf
terraform/variables.tf
terraform/main.tf
terraform/outputs.tf
terraform/terraform.tfvars
terraform/modules/ecr/{main,variables,outputs}.tf
terraform/modules/security/{main,variables,outputs}.tf
terraform/modules/iam/{main,variables,outputs}.tf
terraform/modules/monitoring/{main,variables,outputs}.tf
terraform/modules/compute/{main,variables,outputs}.tf
terraform/modules/compute/user_data.sh.tftpl
```

### Things that must NOT be in the repository

```
Any AWS access key or secret
terraform.tfstate / terraform.tfstate.backup
.terraform/ folder
ci-policy.json with real account numbers (keep it on your Desktop)
```

Check before you push:

```powershell
git status
git ls-files | Select-String "tfstate|\.terraform|credentials|\.pem"
```

That last command must print nothing.

### Screenshots to collect for the report

1. GitLab pipeline — all four stages, green
2. `build_and_test` log — the metadata check and the passing health check
3. `terraform_apply` log — the "Apply complete!" line with the outputs
4. `deploy_application` log — the "DEPLOYMENT SUCCESSFUL" banner
5. Browser — the home page at `http://<public-ip>`
6. Browser — `/health` showing `Healthy`
7. Browser — `/version` showing the commit SHA
8. AWS Console — EC2 instance running, with tags visible
9. AWS Console — ECR repository with the pushed images
10. AWS Console — Security Group rules (proving port 22 is closed)
11. CloudWatch — log group list showing the 7-day retention
12. CloudWatch — application log stream with real ASP.NET log lines
13. CloudWatch — the dashboard with all four widgets
14. CloudWatch — the two alarms in `OK` state
15. GitLab — the destroy job finishing, plus empty AWS resource lists

### Suggested order of work

| Day | Work |
|---|---|
| 1 | Section 3 — fix `Program.cs`, Dockerfile, `.gitignore`. Test locally. |
| 2 | Section 4 — AWS bootstrap: bucket, IAM user, keys. |
| 3 | Section 5 — write all Terraform files. `terraform validate` must pass. |
| 4 | Section 6 — GitLab project, variables, `.gitlab-ci.yml`. First pipeline run and fixes. |
| 5 | Section 7 — verify everything, collect screenshots. |
| 6 | Section 9 — write the README. Section 8 — destroy. |

### Last reminder

**Run the destroy job when you are done.** Leaving an EC2 instance and an
Elastic IP running for a month costs real money. Then check with:

```powershell
aws ec2 describe-instances --query "Reservations[].Instances[].State.Name" --output table
aws ec2 describe-addresses --query "Addresses[].PublicIp" --output table
```

Good luck. 🚀
