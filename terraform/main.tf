# Define local variables for consistency
locals {
  # Availability Zones for us-west-2
  availability_zones = ["us-west-2a", "us-west-2b"]
  cidr_ranges = {
    public_0  = "10.0.0.0/24"
    public_1  = "10.0.1.0/24"
    private_0 = "10.0.2.0/24"
    private_1 = "10.0.3.0/24"
  }
}

# --- Data Source: AMI for EC2 Instances ---
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# -----------------------------------------------------------------------------
# --- VPC and Networking ---
# -----------------------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_subnet" "public" {
  for_each          = toset(local.availability_zones)
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.cidr_ranges["public_${index(local.availability_zones, each.value)}"]
  availability_zone = each.value
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.project_name}-public-subnet-${each.value}"
  }
}

resource "aws_subnet" "private" {
  for_each          = toset(local.availability_zones)
  vpc_id            = aws_vpc.main.id
  cidr_block        = local.cidr_ranges["private_${index(local.availability_zones, each.value)}"]
  availability_zone = each.value
  tags = {
    Name = "${var.project_name}-private-subnet-${each.value}"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# --- NAT Gateway for Internet Access in Private Subnets ---
resource "aws_eip" "nat_gateway" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat_gateway.id
  # Use one of your public subnets for the NAT Gateway
  subnet_id     = aws_subnet.public["us-west-2a"].id
  tags = {
    Name = "${var.project_name}-nat-gateway"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
  tags = {
    Name = "${var.project_name}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

# -----------------------------------------------------------------------------
# --- Application Load Balancer ---
# -----------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  vpc_id      = aws_vpc.main.id
  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "main" {
  name              = "${var.project_name}-alb"
  internal          = false
  load_balancer_type = "application"
  security_groups   = [aws_security_group.alb.id]
  subnets           = [for subnet in aws_subnet.public : subnet.id]
}

resource "aws_lb_target_group" "app" {
  name        = "${var.project_name}-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"
  health_check {
    path                = "/"
    protocol            = "HTTP"
    port                = 80
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type              = "forward"
    target_group_arn  = aws_lb_target_group.app.arn
  }
}

# -----------------------------------------------------------------------------
# --- EC2, IAM and Auto Scaling Group ---
# -----------------------------------------------------------------------------
resource "aws_security_group" "ec2" {
  name        = "${var.project_name}-ec2-sg"
  vpc_id      = aws_vpc.main.id
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_role" "ec2_instance_profile" {
  name = "${var.project_name}-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "ec2_instance_policy" {
  name = "${var.project_name}-ec2-policy"
  role = aws_iam_role.ec2_instance_profile.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetAuthorizationToken",
          "codedeploy:PutLifecycleEventHookExecutionStatus",
          "ssm:GetParameters",
          "s3:GetObject",
          # NEW: Permissions for CloudWatch Logs
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

# Attach the AWSCodeDeployRole policy to the EC2 instance role
resource "aws_iam_role_policy_attachment" "ec2_codedeploy_attachment" {
  role       = aws_iam_role.ec2_instance_profile.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
}

# Attach the AmazonSSMManagedInstanceCore policy for Session Manager
resource "aws_iam_role_policy_attachment" "ec2_ssm_attachment" {
  role       = aws_iam_role.ec2_instance_profile.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "main" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2_instance_profile.name
}

resource "aws_launch_template" "main" {
  name_prefix           = "${var.project_name}-lt-"
  image_id              = data.aws_ami.amazon_linux_2.id
  instance_type         = "t2.micro"
  key_name              = "sandy" # Make sure this key pair exists in us-west-2
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile {
    arn = aws_iam_instance_profile.main.arn
  }
  user_data = base64encode(<<-EOF
#!/bin/bash
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1
set -e

echo "=== Updating system and installing packages ==="
sudo yum update -y
sudo yum install -y ruby wget docker

echo "=== Installing CodeDeploy agent ==="
cd /home/ec2-user
wget https://aws-codedeploy-${var.aws_region}.s3.${var.aws_region}.amazonaws.com/latest/install
chmod +x ./install
sudo ./install auto
sudo systemctl enable codedeploy-agent
sudo systemctl start codedeploy-agent

echo "=== Starting Docker service ==="
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker ec2-user

echo "=== Checking Docker logging driver support ==="
if docker info 2>/dev/null | grep -q 'awslogs'; then
  LOG_DRIVER="awslogs"
else
  LOG_DRIVER="json-file"
fi

echo "=== Writing Docker daemon configuration with driver: $LOG_DRIVER ==="
sudo mkdir -p /etc/docker
cat <<JSON | sudo tee /etc/docker/daemon.json
{
  "log-driver": "$LOG_DRIVER",
  "log-opts": {
    "awslogs-group": "${var.project_name}-container-logs",
    "awslogs-region": "${var.aws_region}",
    "awslogs-stream-prefix": "app"
  }
}
JSON

echo "=== Restarting Docker service ==="
sudo systemctl daemon-reload
sudo systemctl restart docker

echo "=== User data script completed successfully ==="
EOF
  )
}

resource "aws_autoscaling_group" "main" {
  name                = "${var.project_name}-asg"
  vpc_zone_identifier = [for subnet in aws_subnet.private : subnet.id]
  desired_capacity    = 1
  max_size            = 3
  min_size            = 1
  target_group_arns   = [aws_lb_target_group.app.arn]
  launch_template {
    id      = aws_launch_template.main.id
    version = "$Latest"
  }
  tag {
    key                 = "Name"
    value               = "${var.project_name}-instance"
    propagate_at_launch = true
  }
  tag {
    key                 = "Environment"
    value               = "production"
    propagate_at_launch = true
  }
  tag {
    key                 = "codedeploy-group"
    value               = "${var.project_name}-group"
    propagate_at_launch = true
  }
}

# -----------------------------------------------------------------------------
# --- CI/CD Stack Resources ---
# -----------------------------------------------------------------------------
resource "aws_ecr_repository" "app_repo" {
  name                 = "${var.project_name}-repo"
  image_tag_mutability = "MUTABLE"
  tags = {
    Name = "${var.project_name}-ecr"
  }
}

resource "aws_s3_bucket" "codepipeline_artifacts" {
  bucket = "${var.project_name}-codepipeline-artifacts"
  tags = {
    Name = "${var.project_name}-artifacts"
  }
}

# --- DynamoDB table for Terraform state locking ---
resource "aws_dynamodb_table" "terraform_locks" {
  name           = "vishwa-devops-project-terraform-locks"
  hash_key       = "LockID"
  read_capacity  = 5
  write_capacity = 5

  attribute {
    name = "LockID"
    type = "S"
  }
}

# --- IAM Roles for CodePipeline, CodeBuild, and CodeDeploy ---
resource "aws_iam_role" "codepipeline" {
  name = "${var.project_name}-codepipeline-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codepipeline.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "codepipeline" {
  name = "${var.project_name}-codepipeline-policy"
  role = aws_iam_role.codepipeline.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:*",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetAuthorizationToken",
          "codebuild:StartBuild",
          "codebuild:StopBuild",
          "codebuild:BatchGetBuilds",
          "codedeploy:*",
          "iam:PassRole",
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role_policy" "codepipeline_connections_policy" {
  name = "${var.project_name}-codepipeline-connections-policy"
  role = aws_iam_role.codepipeline.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "codestar-connections:UseConnection",
        ]
        Resource = var.github_connection_arn
      },
    ]
  })
}

resource "aws_iam_role" "codebuild" {
  name = "${var.project_name}-codebuild-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
      },
    ]
  })
}

# This IAM policy now includes all the necessary read permissions
# and resource-specific permissions for Terraform to function.
resource "aws_iam_role_policy" "codebuild_policy" {
  name = "${var.project_name}-codebuild-policy"
  role = aws_iam_role.codebuild.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:PutRetentionPolicy",
          "logs:DescribeLogGroups",
          "cloudwatch:DescribeAlarms",
          "logs:ListTagsForResource",
          "cloudwatch:ListTagsForResource",
          "sns:*",
          "s3:*", # Broad permissions for S3 for artifact and state management
          "ecr:*", # Broad permissions for ECR for image management
          "iam:PassRole",
          "ssm:*",
          "ec2:Describe*",
          "iam:List*",
          "iam:Get*",
          "codedeploy:ListApplications",
          "codedeploy:GetApplication",
          "codepipeline:ListActionTypes",
          # Added new permissions for Terraform to read resource states
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeTargetGroups",
          "dynamodb:DescribeTimeToLive",
          "codedeploy:ListTagsForResource",
          "codebuild:BatchGetProjects",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:DescribeTargetGroupAttributes",
          "dynamodb:ListTagsOfResource",
          "elasticloadbalancing:DescribeTags",
          "codedeploy:GetDeploymentGroup",
          "autoscaling:DescribeAutoScalingGroups",
          "elasticloadbalancing:DescribeListeners",
          "codepipeline:GetPipeline",
          "elasticloadbalancing:DescribeListenerAttributes",
          # Newly added permissions
          "codepipeline:*",
          "iam:PutRolePolicy",
          "ec2:CreateLaunchTemplateVersion",
          "codedeploy:PutLifecycleEventHookExecutionStatus",
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:DescribeContinuousBackups",
          "dynamodb:DescribeTable"
        ]
        Resource = aws_dynamodb_table.terraform_locks.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:GetBucketAcl",
        ]
        Resource = [
          "${aws_s3_bucket.codepipeline_artifacts.arn}/*",
          aws_s3_bucket.codepipeline_artifacts.arn,
        ]
      },
    ]
  })
}

resource "aws_iam_role" "codedeploy" {
  name = "${var.project_name}-codedeploy-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codedeploy.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codedeploy_attachment" {
  role       = aws_iam_role.codedeploy.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
}

# --- CodeDeploy Application and Deployment Group ---
resource "aws_codedeploy_app" "main" {
  name = "${var.project_name}-app"
}

resource "aws_codedeploy_deployment_group" "main" {
  app_name              = aws_codedeploy_app.main.name
  deployment_group_name = "${var.project_name}-group"
  service_role_arn      = aws_iam_role.codedeploy.arn

  # The Auto Scaling Group for an in-place deployment
  autoscaling_groups = [aws_autoscaling_group.main.name]

  # Tag-based filtering to select the instances for deployment
  ec2_tag_set {
    ec2_tag_filter {
      key   = "codedeploy-group"
      type  = "KEY_AND_VALUE"
      value = "${var.project_name}-group"
    }
  }

  # This is the correct configuration for an in-place deployment
  deployment_config_name = "CodeDeployDefault.AllAtOnce"

  load_balancer_info {
    target_group_info {
      name = aws_lb_target_group.app.name
    }
  }

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE"]
  }
}

# --- CloudWatch Resources for Observability (NEW) ---
resource "aws_cloudwatch_log_group" "app_logs" {
  name              = "${var.project_name}-container-logs"
  retention_in_days = 14
}

resource "aws_sns_topic" "alarm_notifications" {
  name = "${var.project_name}-alarm-notifications"
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx_alarm" {
  alarm_name          = "${var.project_name}-alb-5xx-errors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "This alarm monitors for 5xx errors from the ALB."
  
  dimensions = {
    LoadBalancer = aws_lb.main.name
  }

  alarm_actions = [aws_sns_topic.alarm_notifications.arn]
  ok_actions    = [aws_sns_topic.alarm_notifications.arn]
}

resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_hosts" {
  alarm_name          = "${var.project_name}-alb-unhealthy-hosts"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Minimum"
  threshold           = 1
  alarm_description   = "This alarm monitors the number of healthy instances in the target group."

  dimensions = {
    TargetGroup = aws_lb_target_group.app.name
  }
  
  alarm_actions = [aws_sns_topic.alarm_notifications.arn]
  ok_actions    = [aws_sns_topic.alarm_notifications.arn]
}


# --- CodePipeline and CodeBuild ---
resource "aws_codepipeline" "main" {
  name     = "${var.project_name}-pipeline"
  role_arn = aws_iam_role.codepipeline.arn

  artifact_store {
    location = aws_s3_bucket.codepipeline_artifacts.id
    type     = "S3"
  }

  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["SourceArtifact"]

      configuration = {
        ConnectionArn      = var.github_connection_arn
        FullRepositoryId   = "${var.github_owner}/${var.github_repo_name}"
        BranchName         = var.github_branch
      }
    }
  }

  stage {
    name = "Build"
    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["SourceArtifact"]
      output_artifacts = ["BuildArtifact"]

      configuration = {
        ProjectName = aws_codebuild_project.main.name
      }
    }
  }

  stage {
    name = "Deploy"
    action {
      name             = "Deploy"
      category         = "Deploy"
      owner            = "AWS"
      provider         = "CodeDeploy"
      version          = "1"
      input_artifacts  = ["BuildArtifact"]

      configuration = {
        ApplicationName      = aws_codedeploy_app.main.name
        DeploymentGroupName  = aws_codedeploy_deployment_group.main.deployment_group_name
      }
    }
  }
}

resource "aws_codebuild_project" "main" {
  name        = "${var.project_name}-build"
  description = "CodeBuild project for the DevOps project"
  service_role = aws_iam_role.codebuild.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    type            = "LINUX_CONTAINER"
    image           = "aws/codebuild/standard:5.0"
    privileged_mode = true
    environment_variable {
        name  = "DOCKER_REPOSITORY_URI"
        value = aws_ecr_repository.app_repo.repository_url
    }
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec.yml"
  }

  tags = {
    Name = "${var.project_name}-codebuild"
  }
}