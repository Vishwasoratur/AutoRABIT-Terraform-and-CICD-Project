# Define local variables for consistency
locals {
  # CHANGED: Availability Zones for us-west-2
  availability_zones = ["us-west-2a", "us-west-2b"]
  cidr_ranges = {
    public_0  = "10.0.0.0/24"
    public_1  = "10.0.1.0/24"
    private_0 = "10.0.2.0/24"
    private_1 = "10.0.3.0/24"
  }
}

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

# --- VPC and Networking ---
resource "aws_vpc" "main" {
  cidr_block         = "10.0.0.0/16"
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

// ADDED: Elastic IP for the NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"
}

// ADDED: NAT Gateway to allow private instances to reach the internet
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public["us-west-2a"].id
  tags = {
    Name = "${var.project_name}-nat-gw"
  }
}

// ADDED: Private Route Table to route traffic through the NAT Gateway
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
  tags = {
    Name = "${var.project_name}-private-rt"
  }
}

// ADDED: Associate private subnets with the new private route table
resource "aws_route_table_association" "private" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}


# --- Application Load Balancer ---
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

# --- EC2, IAM and Auto Scaling Group ---
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
        ]
        Effect   = "Allow"
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_instance_profile" "main" {
  name = "${var.project_name}-ec2-profile"
  role = aws_iam_role.ec2_instance_profile.name
}

resource "aws_launch_template" "main" {
  name_prefix       = "${var.project_name}-lt-"
  image_id          = data.aws_ami.amazon_linux_2.id
  instance_type     = "t2.micro"
  # IMPORTANT: This key pair must exist in the us-west-2 region.
  key_name          = "sandy"
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile {
    arn = aws_iam_instance_profile.main.arn
  }
  user_data = base64encode(<<-EOF
#!/bin/bash
sudo yum update -y
sudo yum install -y ruby
sudo yum install -y wget
cd /home/ec2-user
# CHANGED: Using var.aws_region to make the CodeDeploy URL dynamic
wget https://aws-codedeploy-${var.aws_region}.s3.${var.aws_region}.amazonaws.com/latest/install
chmod +x ./install
sudo ./install auto
sudo service codedeploy-agent status
sudo yum install -y docker
sudo service docker start
sudo usermod -a -G docker ec2-user
EOF
  )
}

resource "aws_autoscaling_group" "main" {
  name                  = "${var.project_name}-asg"
  vpc_zone_identifier   = [for subnet in aws_subnet.private : subnet.id]
  desired_capacity      = 1
  max_size              = 3
  min_size              = 1
  target_group_arns     = [aws_lb_target_group.app.arn]
  launch_template {
    id      = aws_launch_template.main.id
    version = "$Latest"
  }
  tag {
    key             = "Name"
    value           = "${var.project_name}-instance"
    propagate_at_launch = true
  }
  tag {
    key             = "Environment"
    value           = "production"
    propagate_at_launch = true
  }
  tag {
    key             = "codedeploy-group"
    value           = "${var.project_name}-group"
    propagate_at_launch = true
  }
}

# --- CI/CD Stack Resources ---
resource "aws_ecr_repository" "app_repo" {
  name              = "${var.project_name}-repo"
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

# This policy grants the CodePipeline role permissions to access the S3 artifact bucket.
resource "aws_iam_role_policy" "codepipeline_s3_access" {
  name = "${var.project_name}-codepipeline-s3-access"
  role = aws_iam_role.codepipeline.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.codepipeline_artifacts.arn,
          "${aws_s3_bucket.codepipeline_artifacts.arn}/*",
        ]
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

resource "aws_iam_role_policy" "codebuild_policy" {
  role   = aws_iam_role.codebuild.id
  name   = "devops-project-codebuild-policy"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:PutImage",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "s3:GetObject",
          "s3:PutObject",
          "s3:GetBucketAcl",
          "s3:GetBucketLocation",
          "s3:ListBucket",
          "codedeploy:CreateDeployment",
          "codedeploy:GetDeployment",
          "codedeploy:GetDeploymentConfig",
          "codedeploy:RegisterApplicationRevision",
          "codedeploy:UpdateDeploymentGroup",
          "ec2:DescribeAddresses",
          "iam:PassRole"
        ]
        Resource = "*"
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
  role        = aws_iam_role.codedeploy.name
  policy_arn  = "arn:aws:iam::aws:policy/service-role/AWSCodeDeployRole"
}

resource "aws_iam_role_policy" "codedeploy_autoscaling" {
  name = "${var.project_name}-codedeploy-autoscaling-policy"
  role = aws_iam_role.codedeploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "autoscaling:CreateAutoScalingGroup",
          "autoscaling:UpdateAutoScalingGroup",
          "autoscaling:DeleteAutoScalingGroup",
          "autoscaling:CreateLaunchConfiguration",
          "autoscaling:CreateOrUpdateTags",
          "autoscaling:PutLifecycleHook",
          "autoscaling:DeleteLifecycleHook",
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeTags",
          "ec2:CreateLaunchTemplateVersion",
          "ec2:DescribeLaunchTemplates",
        ]
        Resource = "*"
      },
    ]
  })
}

# --- CodeDeploy Application and Deployment Group ---
resource "aws_codedeploy_app" "main" {
  name = "${var.project_name}-app"
}

resource "aws_codedeploy_deployment_group" "main" {
  app_name              = aws_codedeploy_app.main.name
  deployment_group_name = "${var.project_name}-group"
  service_role_arn      = aws_iam_role.codedeploy.arn

  ec2_tag_set {
    ec2_tag_filter {
      key   = "codedeploy-group"
      type  = "KEY_AND_VALUE"
      value = "${var.project_name}-group"
    }
  }

  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }

  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout     = "CONTINUE_DEPLOYMENT"
      wait_time_in_minutes  = 0
    }

    terminate_blue_instances_on_deployment_success {
      action                          = "TERMINATE"
      termination_wait_time_in_minutes = 5
    }
  }

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE"]
  }

  autoscaling_groups = [aws_autoscaling_group.main.name]

  load_balancer_info {
    target_group_info {
      name = aws_lb_target_group.app.name
    }
  }
}

# --- CodePipeline and CodeBuild ---
resource "aws_codepipeline" "main" {
  name      = "${var.project_name}-pipeline"
  role_arn  = aws_iam_role.codepipeline.arn

  artifact_store {
    location = aws_s3_bucket.codepipeline_artifacts.id
    type     = "S3"
  }

  stage {
    name = "Source"
    action {
      name            = "Source"
      category        = "Source"
      owner           = "AWS"
      provider        = "CodeStarSourceConnection"
      version         = "1"
      output_artifacts  = ["SourceArtifact"]

      configuration = {
        ConnectionArn     = var.github_connection_arn
        FullRepositoryId  = "${var.github_owner}/${var.github_repo_name}"
        BranchName        = var.github_branch
      }
    }
  }

  stage {
    name = "Build"
    action {
      name            = "Build"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts   = ["SourceArtifact"]
      output_artifacts  = ["BuildArtifact"]

      configuration = {
        ProjectName = aws_codebuild_project.main.name
      }
    }
  }

  stage {
    name = "Deploy"
    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CodeDeploy"
      version         = "1"
      input_artifacts = ["BuildArtifact"]

      configuration = {
        ApplicationName     = aws_codedeploy_app.main.name
        DeploymentGroupName = aws_codedeploy_deployment_group.main.deployment_group_name
      }
    }
  }
}

resource "aws_codebuild_project" "main" {
  name          = "${var.project_name}-build"
  description   = "CodeBuild project for the DevOps project"
  service_role  = aws_iam_role.codebuild.arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    type         = "LINUX_CONTAINER"
    image        = "aws/codebuild/standard:5.0"
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