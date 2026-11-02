resource "aws_db_subnet_group" "main" {
  name       = "${var.project}-db"
  subnet_ids = aws_subnet.db[*].id
}

resource "aws_db_instance" "main" {
  identifier        = "${var.project}-db"
  engine            = "postgres"
  engine_version    = "16"
  instance_class    = var.db_instance_class
  allocated_storage = var.db_allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  # AWS generates the password and keeps it in Secrets Manager. It never appears in code.
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = false # set true for production

  backup_retention_period    = 7
  auto_minor_version_upgrade = true

  # Convenient for a student project. For production: deletion_protection = true, skip_final_snapshot = false.
  deletion_protection = false
  skip_final_snapshot = true
}

# MQTT passwords for the boxes and the ingest service
resource "random_password" "mqtt_esp32" {
  length  = 24
  special = false
}

resource "random_password" "mqtt_ingest" {
  length  = 24
  special = false
}

resource "aws_secretsmanager_secret" "mqtt" {
  name                    = "${var.project}/mqtt"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "mqtt" {
  secret_id = aws_secretsmanager_secret.mqtt.id
  secret_string = jsonencode({
    esp32  = random_password.mqtt_esp32.result
    ingest = random_password.mqtt_ingest.result
  })
}
