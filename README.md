
# 🚀 CI/CD for a Containerized Application on AWS

## 📌 Project Overview

This project establishes a **production-grade CI/CD pipeline** for a **containerized web application on AWS**, defined entirely using **Terraform (IaC)**.

The objective is to showcase a **robust DevOps workflow** that:
- **Automatically builds, tests, and deploys** application updates
- Ensures **high availability, scalability, and fault-tolerance**
- Embeds **SRE principles** like idempotency, observability, and rollback

---

## 🏗️ Key Architectural Principles

### ✅ High Availability & Reliability
- Infrastructure spans **multiple Availability Zones (AZs)**
- **Application Load Balancer (ALB)** and **Auto Scaling Group (ASG)** ensure uptime during instance or AZ failures

### ⚙️ Automation
- **AWS CodePipeline** triggers deployment from a **Git push**
- Eliminates manual intervention and reduces human error

### 📊 Observability
- **CloudWatch Alarms** monitor metrics (e.g., 5xx errors, unhealthy hosts)
- **Container logs** are centralized in **CloudWatch Log Groups** for easy debugging

### ♻️ Idempotency
- All scripts are idempotent:  
  Example:
  ```bash
  docker stop hello-app || true
  ```
  Continues script execution even if the container doesn't exist.

### 📦 Infrastructure as Code (IaC)
- Everything is defined in **Terraform**:
  - VPC, Subnets, IAM roles, EC2, ALB, ASG, ECR, CodePipeline, etc.
  - Enables version control, auditing, and reproducibility

---

## 🛠️ Prerequisites

Ensure the following tools/accounts are ready:

- ✅ **AWS Account** with IAM user and programmatic access
- ✅ **AWS CLI** installed and configured
- ✅ **GitHub Account** with the application code and necessary files:
  - `Dockerfile`, `appspec.yml`, and deployment scripts
- ✅ **AWS CodeStar Connection** to GitHub (Connection ARN required)
- ✅ **Terraform CLI** version **1.7.0 or newer**
- ✅ **SSH Key Pair** named `sandy` in the `us-west-2` region

---

## ⚙️ Setup Instructions

### 1. Clone the Repository

```bash
git clone https://github.com/Vishwasoratur/AutoRABIT-Terraform-and-CICD-Project.git
cd AutoRABIT-Terraform-and-CICD-Project
```

### 2. Configure Terraform Backend

Create a `Terraform-backend` folder and a `backend.tf` file:

```hcl
terraform {
  backend "s3" {
    bucket         = "vishwa-devops-project-terraform-state-2025-us-west-2"
    key            = "devops-project/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "vishwa-devops-project-terraform-locks"
    encrypt        = true
  }
}
```

### 3. Initialize Terraform

```bash
terraform init
```

### 4. Define Project Variables

Create a `terraform.tfvars` file:

```hcl
project_name           = "devops-project"
aws_region             = "us-west-2"
github_owner           = "<your_github_username>"
github_repo_name       = "<your_repo_name>"
github_branch          = "main"
github_connection_arn  = "<your_codestar_connection_arn>"
```

### 5. Deploy the Infrastructure

```bash
terraform plan
terraform apply --auto-approve
```

---

## 🚀 Deployment Workflow: From Commit to Production

1. **Source Stage (CodePipeline)**  
   Detects push to `main` on GitHub via CodeStar Connection.

2. **Build Stage (CodeBuild)**  
   - Executes `buildspec.yml`
   - Builds Docker image
   - Pushes to **ECR**
   - Runs Terraform to update infrastructure (e.g., Launch Template)

3. **Deploy Stage (CodeDeploy)**  
   - Targets EC2 instances via **ASG tag: `codedeploy-group`**
   - Executes hooks in `appspec.yml` to deploy the new image

---

## 🔁 Rollback Strategy

### ✅ Automated Rollback (Zero-Touch)
- `validate_service.sh` script checks container health
- On failure (non-zero exit), **CodeDeploy automatically rolls back** to the last known good deployment
- Controlled by `auto_rollback_configuration`

### 🛠️ Manual Rollback (When Needed)
1. Go to **AWS Console > CodeDeploy**
2. Select the **Deployment Group**
3. Choose a **successful past deployment**
4. Click **"Redeploy"** to roll back

---

## 📁 Project Folder Structure

```
.
├── Terraform-backend/
│   ├── main.tf
│   ├── terraform.tfvars
│   └── variables.tf
├── app/
│   ├── app.py
│   └── requirements.txt
├── scripts/
│   ├── install_dependencies.sh
│   ├── start_application.sh
│   └── validate_service.sh
├── terraform/
│   ├── main.tf
│   ├── outputs.tf
│   ├── provider.tf
│   ├── terraform.tfvars
│   └── variables.tf
├── .gitignore
├── Dockerfile
├── README.md
├── appspec.yml
├── buildspec.yml
```

---

## 🙌 Final Words

This project demonstrates a **real-world DevOps workflow** by combining the power of:
- ✅ Terraform (IaC)
- ✅ AWS CodePipeline, CodeBuild, CodeDeploy
- ✅ Docker, ECR, EC2, ASG
- ✅ CloudWatch for Observability

Everything is automated from **code push to production deployment** — ensuring **speed, safety, and scalability**.

---

## 🗂️ Terraform Backend Bootstrap Configuration

This project includes a separate folder, **`Terraform-backend/`**, dedicated to **bootstrapping the Terraform backend infrastructure**. It contains:

- `main.tf` – Defines AWS provider, S3 bucket, and DynamoDB table
- `variables.tf` – Declares input variables
- `terraform.tfvars` – Provides actual values for the variables

These resources are required to **store Terraform state remotely in S3** and **enable state locking via DynamoDB**, which is critical for a team or production-grade setup.

### 🔧 Key Resources Provisioned:

#### ✅ S3 Bucket (Remote State Storage)
- Stores Terraform state files
- Enforces ownership and disables ACLs
- Enables versioning and server-side encryption (AES256)

#### ✅ DynamoDB Table (State Locking)
- Prevents concurrent Terraform runs
- Uses a simple `LockID` as the hash key

You must apply this folder **once before running the main infrastructure** to bootstrap the backend.

📝 Note: The terraform.tfstate and related files are excluded via .gitignore to prevent committing sensitive state information to Github.
---

**Vishwanath Soratur**  
🔗 [LinkedIn](https://www.linkedin.com/in/vishwanath-soratur-87295128a/) | 📁 [GitHub](https://github.com/Vishwasoratur)

