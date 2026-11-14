mock_provider "aws" {
  override_during = plan
  mock_data "aws_ssm_parameter" {
    defaults = { value = "ready" }
  }
}

variables {
  db_username = "master_apenas_teste"
}

override_resource {
  target          = aws_db_instance.this
  override_during = plan
  values = {
    master_user_secret = [{
      secret_arn    = "arn:aws:secretsmanager:us-east-1:123456789012:secret:rds!db-teste-Ab123Z"
      secret_status = "active"
      kms_key_id    = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
    }]
  }
}

run "bootstrap_desabilitado_preserva_infraestrutura_atual" {
  command = plan
  assert {
    condition = (length(aws_secretsmanager_secret.orcamento_pagamento) == 0
      && length(aws_ssm_parameter.orcamento_pagamento_database) == 0
      && length(aws_ssm_parameter.orcamento_pagamento_secret_arn) == 0
      && length(aws_ssm_parameter.orcamento_pagamento_status) == 0
      && !output.orcamento_pagamento_bootstrap.habilitado
    && output.orcamento_pagamento_bootstrap.secret_arn == "")
    error_message = "O merge não deve habilitar o bootstrap ou criar contratos incompletos."
  }
}

run "banco_isolado_publica_metadados_sem_segredo_e_aguarda_prova_sql" {
  command = plan
  override_resource {
    target          = aws_secretsmanager_secret.orcamento_pagamento[0]
    override_during = plan
    values = {
      arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:oficina-mecanica/development/rds/orcamento-pagamento-Ab123Z"
    }
  }
  variables {
    orcamento_pagamento_db_enabled = true
  }
  assert {
    condition = (aws_secretsmanager_secret.orcamento_pagamento[0].name == "oficina-mecanica/development/rds/orcamento-pagamento"
      && aws_ssm_parameter.orcamento_pagamento_database[0].value == "OficinaMecanicaOrcamentoPagamento"
      && aws_ssm_parameter.orcamento_pagamento_database[0].type == "String"
      && aws_ssm_parameter.orcamento_pagamento_secret_arn[0].value == aws_secretsmanager_secret.orcamento_pagamento[0].arn
      && aws_ssm_parameter.orcamento_pagamento_secret_arn[0].type == "String"
      && aws_ssm_parameter.orcamento_pagamento_status[0].value == "bootstrap-pendente"
      && aws_ssm_parameter.orcamento_pagamento_status[0].name == "/oficina-mecanica/development/status/rds-orcamento-pagamento"
      && output.orcamento_pagamento_bootstrap.username == "oficina_orcamento_pagamento"
    && output.orcamento_pagamento_bootstrap.username != var.db_username)
    error_message = "A credencial deve ser própria; ready só pode ser publicado após a prova SQL na esteira."
  }
}
