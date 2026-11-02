output "dashboard_url" {
  value = "http://${aws_eip.static["frontend"].public_ip}"
}

output "mqtt_host" {
  description = "Put this in MQTT_HOST in the ESP32 firmware (port 1883, user esp32)"
  value       = aws_eip.static["ingest"].public_ip
}

output "mqtt_esp32_password" {
  description = "Put this in MQTT_PASS in the ESP32 firmware. Show with: terraform output -raw mqtt_esp32_password"
  value       = random_password.mqtt_esp32.result
  sensitive   = true
}

output "jenkins_url" {
  value = "http://${aws_eip.static["jenkins"].public_ip}:8080"
}

output "jenkins_controller_instance_id" {
  value = aws_instance.jenkins.id
}

output "jenkins_agent_private_ip" {
  value = aws_instance.agent.private_ip
}

output "jenkins_agent_private_key" {
  description = "Add as a Jenkins SSH credential: terraform output -raw jenkins_agent_private_key"
  value       = tls_private_key.agent.private_key_openssh
  sensitive   = true
}

output "ecr_repositories" {
  value = { for k, r in aws_ecr_repository.repo : k => r.repository_url }
}

output "rds_endpoint" {
  value = aws_db_instance.main.address
}

output "db_secret_arn" {
  value = local.db_secret_arn
}
