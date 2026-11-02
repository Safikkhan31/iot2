data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# ---------- App servers: pull their own image, read only the secrets they need ----------
data "aws_iam_policy_document" "server" {
  for_each = local.servers

  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid       = "EcrPullOwnRepoOnly"
    actions   = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"]
    resources = [aws_ecr_repository.repo[each.key].arn]
  }

  dynamic "statement" {
    for_each = (each.value.db_secret || each.value.mqtt_secret) ? [1] : []
    content {
      sid     = "ReadOwnSecrets"
      actions = ["secretsmanager:GetSecretValue"]
      resources = compact([
        each.value.db_secret ? local.db_secret_arn : "",
        each.value.mqtt_secret ? aws_secretsmanager_secret.mqtt.arn : "",
      ])
    }
  }
}

resource "aws_iam_role" "server" {
  for_each           = local.servers
  name               = "${var.project}-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy" "server" {
  for_each = local.servers
  name     = "least-privilege"
  role     = aws_iam_role.server[each.key].id
  policy   = data.aws_iam_policy_document.server[each.key].json
}

resource "aws_iam_role_policy_attachment" "server_ssm" {
  for_each   = local.servers
  role       = aws_iam_role.server[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "server" {
  for_each = local.servers
  name     = "${var.project}-${each.key}"
  role     = aws_iam_role.server[each.key].name
}

# ---------- Jenkins controller: no AWS permissions except Session Manager access ----------
resource "aws_iam_role" "jenkins" {
  name               = "${var.project}-jenkins"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "jenkins_ssm" {
  role       = aws_iam_role.jenkins.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "jenkins" {
  name = "${var.project}-jenkins"
  role = aws_iam_role.jenkins.name
}

# ---------- Jenkins agent: push images, trigger deploys on exactly these 3 servers, read the DB secret ----------
data "aws_iam_policy_document" "agent" {
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    sid = "EcrPushProjectRepos"
    actions = [
      "ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer",
    ]
    resources = [for r in aws_ecr_repository.repo : r.arn]
  }

  statement {
    sid     = "RunDeployScriptOnAppServers"
    actions = ["ssm:SendCommand"]
    resources = concat(
      [for i in aws_instance.app : "arn:aws:ec2:${var.region}:${data.aws_caller_identity.current.account_id}:instance/${i.id}"],
      ["arn:aws:ssm:${var.region}::document/AWS-RunShellScript"],
    )
  }

  statement {
    sid       = "ReadDeployResults"
    actions   = ["ssm:GetCommandInvocation", "ssm:ListCommandInvocations", "ssm:ListCommands"]
    resources = ["*"]
  }

  statement {
    sid       = "ReadDbSecretForMigrations"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [local.db_secret_arn]
  }
}

resource "aws_iam_role" "agent" {
  name               = "${var.project}-jenkins-agent"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy" "agent" {
  name   = "least-privilege"
  role   = aws_iam_role.agent.id
  policy = data.aws_iam_policy_document.agent.json
}

resource "aws_iam_role_policy_attachment" "agent_ssm" {
  role       = aws_iam_role.agent.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "agent" {
  name = "${var.project}-jenkins-agent"
  role = aws_iam_role.agent.name
}
