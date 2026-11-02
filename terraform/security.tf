# One security group per role. Only the traffic each role needs is allowed, in both directions.

resource "aws_security_group" "frontend" {
  name        = "${var.project}-frontend"
  description = "Dashboard web server"
  vpc_id      = aws_vpc.main.id
}

resource "aws_security_group" "backend" {
  name        = "${var.project}-backend"
  description = "API server (private)"
  vpc_id      = aws_vpc.main.id
}

resource "aws_security_group" "ingest" {
  name        = "${var.project}-ingest"
  description = "MQTT broker and ingest service"
  vpc_id      = aws_vpc.main.id
}

resource "aws_security_group" "rds" {
  name        = "${var.project}-rds"
  description = "PostgreSQL (private)"
  vpc_id      = aws_vpc.main.id
}

resource "aws_security_group" "jenkins" {
  name        = "${var.project}-jenkins"
  description = "Jenkins controller"
  vpc_id      = aws_vpc.main.id
}

resource "aws_security_group" "agent" {
  name        = "${var.project}-jenkins-agent"
  description = "Jenkins build agent (private)"
  vpc_id      = aws_vpc.main.id
}

# ---------- Inbound ----------
resource "aws_vpc_security_group_ingress_rule" "frontend_http" {
  security_group_id = aws_security_group.frontend.id
  description       = "Dashboard"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "backend_from_frontend" {
  security_group_id            = aws_security_group.backend.id
  description                  = "API from frontend only"
  ip_protocol                  = "tcp"
  from_port                    = 3000
  to_port                      = 3000
  referenced_security_group_id = aws_security_group.frontend.id
}

resource "aws_vpc_security_group_ingress_rule" "ingest_mqtt" {
  for_each          = toset(var.device_cidrs)
  security_group_id = aws_security_group.ingest.id
  description       = "MQTT from devices"
  ip_protocol       = "tcp"
  from_port         = 1883
  to_port           = 1883
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_clients" {
  for_each = {
    backend = aws_security_group.backend.id
    ingest  = aws_security_group.ingest.id
    agent   = aws_security_group.agent.id
  }
  security_group_id            = aws_security_group.rds.id
  description                  = "PostgreSQL from ${each.key}"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = each.value
}

resource "aws_vpc_security_group_ingress_rule" "jenkins_admin" {
  for_each          = toset(var.admin_cidrs)
  security_group_id = aws_security_group.jenkins.id
  description       = "Jenkins UI from admin"
  ip_protocol       = "tcp"
  from_port         = 8080
  to_port           = 8080
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_ingress_rule" "jenkins_webhook" {
  for_each          = toset(var.webhook_cidrs)
  security_group_id = aws_security_group.jenkins.id
  description       = "Jenkins webhook"
  ip_protocol       = "tcp"
  from_port         = 8080
  to_port           = 8080
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_ingress_rule" "agent_ssh_from_jenkins" {
  security_group_id            = aws_security_group.agent.id
  description                  = "Controller connects to agent over SSH"
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = aws_security_group.jenkins.id
}

# ---------- Outbound ----------
# HTTPS out for package installs, ECR, Secrets Manager, SSM and GitHub. RDS and Docker Hub use 5432/443.
resource "aws_vpc_security_group_egress_rule" "https_out" {
  for_each = {
    frontend = aws_security_group.frontend.id
    backend  = aws_security_group.backend.id
    ingest   = aws_security_group.ingest.id
    jenkins  = aws_security_group.jenkins.id
    agent    = aws_security_group.agent.id
  }
  security_group_id = each.value
  description       = "HTTPS out"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "frontend_to_backend" {
  security_group_id            = aws_security_group.frontend.id
  description                  = "Proxy to API"
  ip_protocol                  = "tcp"
  from_port                    = 3000
  to_port                      = 3000
  referenced_security_group_id = aws_security_group.backend.id
}

resource "aws_vpc_security_group_egress_rule" "to_rds" {
  for_each = {
    backend = aws_security_group.backend.id
    ingest  = aws_security_group.ingest.id
    agent   = aws_security_group.agent.id
  }
  security_group_id            = each.value
  description                  = "PostgreSQL"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.rds.id
}

resource "aws_vpc_security_group_egress_rule" "jenkins_to_agent" {
  security_group_id            = aws_security_group.jenkins.id
  description                  = "SSH to build agent"
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = aws_security_group.agent.id
}
