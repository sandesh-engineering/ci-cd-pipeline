# CI/CD Pipeline Deployment Guide

This repository demonstrates a complete automated CI/CD pipeline for a Dockerized full-stack application using GitHub Actions, Docker, Docker Compose, Nginx, PostgreSQL, and an AWS EC2 deployment target.

The current deployment approach is intentionally simple:

- GitHub Actions runs lint and test jobs.
- GitHub Actions builds frontend and backend Docker images.
- Images are pushed to Docker Hub.
- GitHub Actions connects to an EC2 instance over SSH.
- The EC2 instance pulls the latest images and restarts the application using Docker Compose.

This is a practical starting point for learning CI/CD, but production systems should usually move toward AWS ECR, ECS, managed databases, stronger secrets management, and safer deployment strategies.

## Application Stack

- Frontend: Next.js app in `frontend/`
- Backend: Node.js/Express API in `backend/`
- Database: PostgreSQL container
- Reverse proxy: Nginx container
- Local orchestration: `docker-compose.yaml`
- Production orchestration: `docker-compose.prod.yaml`
- CI/CD platform: GitHub Actions
- Current image registry: Docker Hub
- Current deployment target: AWS EC2

## Repository Structure

```text
.
├── .github/workflows/
│   ├── main.yml
│   ├── lint-test.yml
│   ├── build.yml
│   └── deploy.yml
├── backend/
│   └── Dockerfile
├── frontend/
│   └── Dockerfile
├── docker-compose.yaml
├── docker-compose.prod.yaml
├── nginx.conf
└── README.md
```

## CI/CD Flow

The main workflow is defined in `.github/workflows/main.yml`. It currently runs manually through `workflow_dispatch`, so deployment starts only when the workflow is triggered from the GitHub Actions UI.

The pipeline runs in this order:

1. `lint-test.yml`
   - Checks out the repository.
   - Installs backend dependencies.
   - Runs backend lint and test commands.
   - Installs frontend dependencies.
   - Runs frontend lint and test commands.

2. `build.yml`
   - Logs in to Docker Hub.
   - Builds the backend image from `backend/Dockerfile`.
   - Builds the frontend image from `frontend/Dockerfile`.
   - Pushes both images with two tags:
     - `${{ github.sha }}`
     - `latest`

3. `deploy.yml`
   - SSHs into the EC2 instance.
   - Creates `/app` if it does not exist.
   - Clones the repository on first deploy.
   - Pulls the latest repository state on later deploys.
   - Creates production environment files from GitHub Secrets.
   - Sets `IMAGE_TAG=${{ github.sha }}`.
   - Pulls the matching Docker images.
   - Restarts the stack with Docker Compose.
   - Runs a health check against `http://localhost/api/v1/health`.

## Required GitHub Secrets

Configure these secrets in the GitHub repository before running the workflow:

```text
DOCKERHUB_USERNAME
DOCKERHUB_TOKEN

EC2_HOST
EC2_SSH_KEY

PORT
DATABASE_URL
DATABASE_DB
DATABASE_USER
DATABASE_PASSWORD
NEXT_PUBLIC_API_URL
```

Notes:

- `DOCKERHUB_TOKEN` should be a Docker Hub access token, not the account password.
- `EC2_SSH_KEY` should contain the private SSH key used to connect to the EC2 instance.
- `DATABASE_URL` should point to the Compose PostgreSQL service when using the bundled database, for example:

```text
postgresql://postgres:strong-password@postgres:5432/appdb
```

- `NEXT_PUBLIC_API_URL` should point to the public API route exposed through Nginx, for example:

```text
http://your-ec2-public-ip/api/v1
```

## EC2 Environment Setup

Create an Ubuntu EC2 instance and allow inbound traffic for:

- SSH: port `22`, preferably restricted to your IP address
- HTTP: port `80`
- HTTPS: port `443`, if TLS is configured later

The EC2 instance must have Docker, Docker Compose, Git, and Curl installed. You can install them manually over SSH, or provide a user data script during instance creation.

### EC2 User Data Script

Use this as EC2 user data for an Ubuntu instance:

```bash
#!/bin/bash
set -e

apt-get update
apt-get install -y git curl

curl -fsSL https://get.docker.com | sh

systemctl enable docker
systemctl start docker

usermod -aG docker ubuntu
```

After the instance starts, log out and log back in so the `ubuntu` user receives Docker group permissions.

Verify the setup:

```bash
docker --version
docker compose version
git --version
```

### Alternatives to the User Data Script

The user data script is quick and convenient, but it is not the only option.

- Install Docker manually over SSH for a small learning project.
- Bake Docker and required tooling into a custom AMI.
- Use Terraform, Pulumi, or CloudFormation to provision EC2 and security groups.
- Use AWS Systems Manager instead of direct SSH access.
- Avoid EC2 setup entirely by deploying to ECS, Elastic Beanstalk, App Runner, or Kubernetes.

## Local Docker Compose Setup

For local or simple VM testing, `docker-compose.yaml` starts:

- `frontend` on port `3000`
- `backend` on port `5000`
- `postgres` on port `5432`

Run:

```bash
docker compose up -d
```

Check containers:

```bash
docker compose ps
```

View logs:

```bash
docker compose logs -f
```

Stop the stack:

```bash
docker compose down
```

Remove the database volume when you want a clean database:

```bash
docker compose down -v
```

The local Compose file currently uses Docker Hub images tagged as `latest`:

```yaml
frontend:
  image: sandesh1128/nextjs-app:latest

backend:
  image: sandesh1128/nodejs-api:latest
```

For local development, another common option is to build from local source instead of pulling images:

```yaml
frontend:
  build:
    context: ./frontend
    dockerfile: Dockerfile

backend:
  build:
    context: ./backend
    dockerfile: Dockerfile
```

## Production Docker Compose Setup

Production deployment uses `docker-compose.prod.yaml`.

It starts:

- `nginx`, exposed on port `80`
- `frontend`, exposed only inside the Docker network on port `3000`
- `backend`, exposed only inside the Docker network on port `5000`
- `postgres`, with persisted data in the `postgres_data` volume

Nginx routes traffic as follows:

- `/` forwards to the frontend container.
- `/api/v1/` forwards to the backend container.

The production Compose file expects these files to exist on the EC2 host:

```text
.env.backend.prod
.env.frontend.prod
```

The deploy workflow creates those files automatically from GitHub Secrets.

Example backend environment file:

```env
PORT=5000
DATABASE_URL=postgresql://postgres:strong-password@postgres:5432/appdb
POSTGRES_DB=appdb
POSTGRES_USER=postgres
POSTGRES_PASSWORD=strong-password
```

Example frontend environment file:

```env
NEXT_PUBLIC_API_URL=http://your-domain-or-ip/api/v1
```

Manual production deployment on the EC2 host would look like this:

```bash
cd /app
export IMAGE_TAG=<git-commit-sha>
docker compose -f docker-compose.prod.yaml pull
docker compose -f docker-compose.prod.yaml up -d --remove-orphans
docker image prune -f
curl --fail http://localhost/api/v1/health
```

## Current Deployment Process

1. Developer pushes or prepares code in GitHub.
2. Developer manually triggers the `CI/CD Pipeline` workflow.
3. GitHub Actions runs lint and test jobs.
4. If checks pass, GitHub Actions builds Docker images.
5. Images are pushed to Docker Hub using the commit SHA and `latest` tags.
6. GitHub Actions connects to EC2 using SSH.
7. EC2 updates the repository in `/app`.
8. EC2 receives fresh `.env.backend.prod` and `.env.frontend.prod` files.
9. EC2 pulls images matching the commit SHA.
10. Docker Compose recreates changed containers.
11. Nginx exposes frontend and backend routes on port `80`.
12. The workflow verifies deployment with a backend health check.

## Caveats of This Approach

This setup is useful and understandable, but it has important limitations.

- The EC2 host is a single point of failure.
- Deployments happen directly over SSH, so access to the server is highly privileged.
- Docker Hub rate limits or outages can affect deployments.
- Secrets are written to files on the EC2 instance.
- PostgreSQL runs as a container on the same VM, which is risky for production data.
- There is no automatic rollback if the new version starts but behaves incorrectly.
- `docker compose up -d` can briefly interrupt service during container replacement.
- There is no blue-green or canary deployment strategy.
- There is no load balancer or horizontal scaling.
- There is no built-in TLS certificate automation.
- Logs remain mostly on the host unless external log shipping is added.
- Disk usage can grow over time from images, volumes, and logs.
- The test scripts are currently minimal or placeholder-like, so the pipeline may pass without proving much application behavior.

## Recommended Improvements

### Use AWS ECR Instead of Docker Hub

ECR is the natural container registry when deploying to AWS.

Benefits:

- Images stay inside AWS infrastructure.
- IAM controls image push and pull permissions.
- ECS, EKS, and other AWS services integrate with ECR directly.
- ECR avoids Docker Hub pull limits.
- Image scanning and lifecycle policies can be configured.

The improved build flow would be:

1. GitHub Actions authenticates to AWS using OIDC.
2. GitHub Actions logs in to ECR.
3. Images are built and tagged with the commit SHA.
4. Images are pushed to ECR repositories.
5. Deployment pulls images from ECR instead of Docker Hub.

Example image names:

```text
<aws-account-id>.dkr.ecr.<region>.amazonaws.com/nodejs-api:<git-sha>
<aws-account-id>.dkr.ecr.<region>.amazonaws.com/nextjs-app:<git-sha>
```

### Use AWS ECS Instead of Docker Compose on EC2

ECS is a better production target for this kind of containerized application.

Benefits:

- No need to SSH into a server for normal deployments.
- ECS handles task placement and restarts.
- Services can run multiple copies of frontend and backend containers.
- Deployments can be rolling or blue-green.
- Application Load Balancer can route public traffic.
- ECS integrates cleanly with ECR, IAM, CloudWatch Logs, and Secrets Manager.
- Fargate removes the need to manage EC2 hosts.

A stronger AWS architecture would be:

```text
GitHub Actions
  -> build Docker images
  -> push images to ECR
  -> update ECS task definition
  -> deploy ECS service
  -> traffic served through Application Load Balancer
  -> database hosted on Amazon RDS PostgreSQL
```

### Move PostgreSQL to RDS

Running PostgreSQL inside Docker is fine for local testing, but production data should normally use Amazon RDS.

Benefits:

- Automated backups
- Managed patching
- Better durability
- Easier restore process
- Monitoring and metrics
- Separate scaling from the application server

### Improve Secrets Management

Instead of writing secrets into `.env` files on EC2, consider:

- AWS Secrets Manager
- AWS Systems Manager Parameter Store
- ECS task secrets
- GitHub Actions OIDC with short-lived AWS credentials

### Add Safer Deployment Strategies

Useful deployment upgrades:

- Rolling deployments
- Blue-green deployments
- Canary releases
- Automatic rollback on failed health checks
- Database migration step with rollback planning
- Separate staging and production environments

### Add Observability

Production deployments should include:

- Centralized application logs
- Container logs shipped to CloudWatch
- Metrics for CPU, memory, disk, and request latency
- Alerts for failed health checks
- Error tracking
- Uptime monitoring

### Add TLS and Domain Management

For public production use:

- Point a domain to the server or load balancer.
- Add HTTPS with ACM when using an AWS load balancer.
- Use Certbot if staying with Nginx directly on EC2.
- Redirect HTTP traffic to HTTPS.

### Strengthen CI Quality Gates

The pipeline should eventually include:

- Real backend unit/integration tests
- Real frontend tests
- Type checks
- Docker image vulnerability scanning
- Dependency auditing
- Build cache optimization
- Branch protection rules
- Required pull request checks before deployment

## Operational Commands

SSH into EC2:

```bash
ssh -i path/to/key.pem ubuntu@<ec2-public-ip>
```

Inspect running containers:

```bash
cd /app
docker compose -f docker-compose.prod.yaml ps
```

View logs:

```bash
docker compose -f docker-compose.prod.yaml logs -f
```

Restart the stack:

```bash
docker compose -f docker-compose.prod.yaml up -d --remove-orphans
```

Check the backend health endpoint from EC2:

```bash
curl --fail http://localhost/api/v1/health
```

Check disk usage:

```bash
df -h
docker system df
```

Clean unused Docker images:

```bash
docker image prune -f
```

## Summary

This repository provides a working CI/CD path from GitHub Actions to an EC2-hosted Docker Compose deployment. It is a good learning and small-project setup because the moving parts are visible and easy to reason about.

For production, the main next step is to replace Docker Hub plus EC2 SSH deployment with ECR plus ECS, ideally backed by RDS, AWS-managed secrets, centralized logging, HTTPS, and safer deployment strategies.
