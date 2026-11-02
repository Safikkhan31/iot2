data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  registry      = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com"
  backend_dns   = "backend.${var.project}.internal"
  db_secret_arn = aws_db_instance.main.master_user_secret[0].secret_arn

  servers = {
    backend = {
      subnet      = aws_subnet.private[0].id
      sg          = aws_security_group.backend.id
      public      = false
      db_secret   = true
      mqtt_secret = false
    }
    frontend = {
      subnet      = aws_subnet.public[0].id
      sg          = aws_security_group.frontend.id
      public      = true
      db_secret   = false
      mqtt_secret = false
    }
    ingest = {
      subnet      = aws_subnet.public[0].id
      sg          = aws_security_group.ingest.id
      public      = true
      db_secret   = true
      mqtt_secret = true
    }
  }
}

# ---------- Backend, frontend and mqtt-ingest servers ----------
resource "aws_instance" "app" {
  for_each = local.servers

  ami                         = data.aws_ssm_parameter.al2023.value
  instance_type               = var.instance_type_app
  subnet_id                   = each.value.subnet
  vpc_security_group_ids      = [each.value.sg]
  iam_instance_profile        = aws_iam_instance_profile.server[each.key].name
  associate_public_ip_address = each.value.public

  user_data = templatefile("${path.module}/templates/app_server.sh.tftpl", {
    role            = each.key
    region          = var.region
    registry        = local.registry
    repo_url        = aws_ecr_repository.repo[each.key].repository_url
    db_host         = aws_db_instance.main.address
    db_name         = var.db_name
    db_secret_arn   = local.db_secret_arn
    mqtt_secret_arn = aws_secretsmanager_secret.mqtt.arn
    backend_dns     = local.backend_dns
  })

  metadata_options {
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 1          # containers cannot reach instance credentials
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true
  }

  tags = { Name = "${var.project}-${each.key}", Role = each.key }

  # To re-run the bootstrap script: terraform apply -replace='aws_instance.app["backend"]'
  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

# ---------- Jenkins controller ----------
resource "aws_instance" "jenkins" {
  ami                         = data.aws_ssm_parameter.al2023.value
  instance_type               = var.instance_type_jenkins
  subnet_id                   = aws_subnet.public[0].id
  vpc_security_group_ids      = [aws_security_group.jenkins.id]
  iam_instance_profile        = aws_iam_instance_profile.jenkins.name
  associate_public_ip_address = true
  user_data                   = file("${path.module}/templates/jenkins.sh.tftpl")

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 30
    encrypted   = true
  }

  tags = { Name = "${var.project}-jenkins", Role = "jenkins" }

  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

# ---------- Jenkins agent (private subnet) ----------
resource "tls_private_key" "agent" {
  algorithm = "ED25519"
}

resource "aws_instance" "agent" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = var.instance_type_agent
  subnet_id              = aws_subnet.private[0].id
  vpc_security_group_ids = [aws_security_group.agent.id]
  iam_instance_profile   = aws_iam_instance_profile.agent.name

  user_data = templatefile("${path.module}/templates/agent.sh.tftpl", {
    public_key    = tls_private_key.agent.public_key_openssh
    project       = var.project
    region        = var.region
    registry      = local.registry
    db_host       = aws_db_instance.main.address
    db_name       = var.db_name
    db_secret_arn = local.db_secret_arn
    backend_id    = aws_instance.app["backend"].id
    frontend_id   = aws_instance.app["frontend"].id
    ingest_id     = aws_instance.app["ingest"].id
  })

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 40
    encrypted   = true
  }

  tags = { Name = "${var.project}-jenkins-agent", Role = "jenkins-agent" }

  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

# ---------- Stable public addresses ----------
resource "aws_eip" "static" {
  for_each   = toset(["frontend", "ingest", "jenkins"])
  domain     = "vpc"
  depends_on = [aws_internet_gateway.main]
  tags       = { Name = "${var.project}-${each.key}" }
}

resource "aws_eip_association" "static" {
  for_each = {
    frontend = aws_instance.app["frontend"].id
    ingest   = aws_instance.app["ingest"].id
    jenkins  = aws_instance.jenkins.id
  }
  instance_id   = each.value
  allocation_id = aws_eip.static[each.key].id
}
