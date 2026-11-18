locals {
  os_database = "OficinaMecanicaDb"
  os_login    = "oficina_os"
  os_prefix   = "/oficina-mecanica/${var.environment}/rds/os"
  os_status   = "/oficina-mecanica/${var.environment}/status/rds-os"
}

resource "aws_secretsmanager_secret" "os" {
  name                    = "oficina-mecanica/${var.environment}/rds/os"
  description             = "Credencial exclusiva do banco de OS; valor preparado pela esteira RDS."
  recovery_window_in_days = 0
  tags                    = local.common_tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ssm_parameter" "os_database" {
  name  = "${local.os_prefix}/database_name"
  type  = "String"
  value = local.os_database
  tags  = local.common_tags
}

resource "aws_ssm_parameter" "os_secret_arn" {
  name  = "${local.os_prefix}/secret_arn"
  type  = "String"
  value = aws_secretsmanager_secret.os.arn
  tags  = local.common_tags
}

resource "aws_ssm_parameter" "os_status" {
  name        = local.os_status
  description = "Disponibilidade do banco de OS; ready somente após prova SQL e limpeza pela esteira."
  type        = "String"
  value       = "bootstrap-pendente"
  tags        = local.common_tags

  lifecycle {
    ignore_changes = [value]
  }
}

output "os_bootstrap" {
  description = "Metadados da preparação SQL de OS, sem senha ou connection string."
  value = {
    habilitado       = true
    database_name    = local.os_database
    username         = local.os_login
    secret_arn       = aws_secretsmanager_secret.os.arn
    status_parameter = aws_ssm_parameter.os_status.name
  }
}
