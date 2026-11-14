variable "orcamento_pagamento_db_enabled" {
  description = "Prepara o banco e a credencial isolados pela esteira; exige janela e validação no RDS real."
  type        = bool
  default     = false
}

locals {
  orcamento_pagamento_database = "OficinaMecanicaOrcamentoPagamento"
  orcamento_pagamento_login    = "oficina_orcamento_pagamento"
  orcamento_pagamento_prefix   = "/oficina-mecanica/${var.environment}/rds/orcamento-pagamento"
  orcamento_pagamento_status   = "/oficina-mecanica/${var.environment}/status/rds-orcamento-pagamento"
}

resource "aws_secretsmanager_secret" "orcamento_pagamento" {
  count                   = var.orcamento_pagamento_db_enabled ? 1 : 0
  name                    = "oficina-mecanica/${var.environment}/rds/orcamento-pagamento"
  description             = "Credencial exclusiva do banco de Orçamento/Pagamento; valor gerenciado pelo bootstrap da esteira."
  recovery_window_in_days = 0
  tags                    = local.common_tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ssm_parameter" "orcamento_pagamento_database" {
  count       = var.orcamento_pagamento_db_enabled ? 1 : 0
  name        = "${local.orcamento_pagamento_prefix}/database_name"
  description = "Nome não secreto do banco lógico exclusivo de Orçamento/Pagamento."
  type        = "String"
  value       = local.orcamento_pagamento_database
  tags        = local.common_tags
}

resource "aws_ssm_parameter" "orcamento_pagamento_secret_arn" {
  count       = var.orcamento_pagamento_db_enabled ? 1 : 0
  name        = "${local.orcamento_pagamento_prefix}/secret_arn"
  description = "ARN não secreto da credencial própria de Orçamento/Pagamento."
  type        = "String"
  value       = aws_secretsmanager_secret.orcamento_pagamento[0].arn
  tags        = local.common_tags
}

resource "aws_ssm_parameter" "orcamento_pagamento_status" {
  count       = var.orcamento_pagamento_db_enabled ? 1 : 0
  name        = local.orcamento_pagamento_status
  description = "Disponibilidade do banco isolado; ready somente após bootstrap e prova SQL pela esteira."
  type        = "String"
  value       = "bootstrap-pendente"
  tags        = local.common_tags

  lifecycle {
    # A esteira é dona da transição operacional após validar SQL e limpar o Job.
    ignore_changes = [value]
  }
}

output "orcamento_pagamento_bootstrap" {
  description = "Metadados do bootstrap; não contém senha ou connection string."
  value = {
    habilitado       = var.orcamento_pagamento_db_enabled
    database_name    = local.orcamento_pagamento_database
    username         = local.orcamento_pagamento_login
    secret_arn       = var.orcamento_pagamento_db_enabled ? aws_secretsmanager_secret.orcamento_pagamento[0].arn : ""
    status_parameter = var.orcamento_pagamento_db_enabled ? aws_ssm_parameter.orcamento_pagamento_status[0].name : ""
  }
}
