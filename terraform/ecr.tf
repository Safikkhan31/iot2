locals {
  # role key => image name
  repos = {
    backend  = "backend"
    frontend = "frontend"
    ingest   = "mqtt-ingest"
  }
}

resource "aws_ecr_repository" "repo" {
  for_each             = local.repos
  name                 = "${var.project}/${each.value}"
  image_tag_mutability = "MUTABLE" # Jenkins pushes a commit tag and "latest"
  force_delete         = true      # lets "terraform destroy" remove non-empty repos

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "repo" {
  for_each   = aws_ecr_repository.repo
  repository = each.value.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the 10 most recent images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}
