# 🗄️ Oficina Mecânica Infra RDS

Instância privada SQL Server Express com bancos lógicos e credenciais próprias para OS e Orçamento/Pagamento. Compartilhar a instância não autoriza compartilhar schemas, logins ou consultas.

## 🏗️ Recursos provisionados por esta esteira

| Escopo | Recursos | Como são preparados |
| --- | --- | --- |
| Compartilhado por OS e Orçamento/Pagamento | Uma instância RDS SQL Server Express privada e com armazenamento cifrado; DB subnet group; security group e regra TCP/1433 a partir do security group do EKS | Terraform, consumindo VPC/subnets e os contratos de Kubernetes |
| Administração da instância | Credencial master gerenciada pelo RDS no Secrets Manager | RDS gerencia a senha; uso administrativo restrito à preparação dos bancos pela esteira |
| OS / API | Banco lógico `OficinaMecanicaDb`, login `oficina_os` e secret exclusivo `oficina-mecanica/development/rds/os` | Preparação obrigatória por Job temporário no EKS após criar a instância e os metadados do secret |
| Orçamento/Pagamento | Banco lógico `OficinaMecanicaOrcamentoPagamento`, login `oficina_orcamento_pagamento` e secret exclusivo `oficina-mecanica/development/rds/orcamento-pagamento` | Preparação por Job temporário quando `ORCAMENTO_PAGAMENTO_DB_ENABLED=true` |
| Execução | Nenhum banco SQL, login SQL ou tabela DynamoDB nesta esteira | O [repositório de Execução](https://github.com/oficina-mecanica-soat/oficina-mecanica-execucao) provisiona a própria tabela DynamoDB |
| Contratos | Endpoint/SG/ARN administrativo da instância; nome de banco, ARN do secret e prontidão por aplicação no SSM | Terraform publica metadados; o CD confirma prontidão após validar SQL e remover recursos temporários |

**A console do RDS mostra uma instância compartilhada, não uma instância por microsserviço.** Dentro dela existem dois bancos lógicos e dois logins de aplicação independentes. As credenciais são distintas; as aplicações não usam o login master nem consultam o banco do outro serviço. O compartilhamento físico mantém um domínio comum de disponibilidade, conforme a ADR-0025.

Terraform cria a infraestrutura e os contêineres de secrets. O workflow gera/persiste ou reutiliza a credencial de cada aplicação, cria/valida banco e login com permissões no banco próprio e limpa Job/Secret temporários. **Tabelas, schemas e migrations de negócio continuam nas aplicações**: a API aplica suas migrations em OS, e Orçamento/Pagamento aplica as suas no banco correspondente. Auth, no modo distribuído, consulta a API privada e não recebe banco próprio.

Fontes: [instância e rede](infra/terraform/environments/dev/rds.tf), [contratos de OS](infra/terraform/environments/dev/banco-os.tf), [contratos de Orçamento/Pagamento](infra/terraform/environments/dev/orcamento-pagamento.tf) e [preparação SQL no CD](.github/workflows/aws-deploy.yml).

<a id="dados-e-credenciais"></a>

## 🗄️ Dados e credenciais

- OS: banco `OficinaMecanicaDb`, login `oficina_os`.
- Orçamento/Pagamento: banco `OficinaMecanicaOrcamentoPagamento`, login `oficina_orcamento_pagamento`.
- `ORCAMENTO_PAGAMENTO_DB_ENABLED=true` habilita o preparo do banco de Orçamento/Pagamento.
- RDS gerencia a credencial administrativa no Secrets Manager. A esteira persiste/reutiliza credenciais exclusivas e prepara os bancos por Job temporário no EKS; por isso Kubernetes precede RDS.
- O login de cada aplicação possui permissões somente no banco próprio. Migrations pertencem aos serviços. Job e Secret temporários são removidos antes de publicar prontidão.
- Contratos: `rds/os/{database_name,secret_arn}`, `rds/orcamento-pagamento/{database_name,secret_arn}` e status `rds-os`/`rds-orcamento-pagamento`, sob `/oficina-mecanica/development/`.

O status da instância não substitui a prova de acesso SQL de cada aplicação. Falha de preparação ou limpeza mantém o banco pendente. O CD de destroy bloqueia consumidores remanescentes; remoção da instância implica perda dos dados, conforme as simplificações acadêmicas registradas na ADR-0006.


## 🌐 Contrato entre esteiras

Conforme [RFC-0004](https://github.com/oficina-mecanica-soat/oficina-mecanica-api/blob/main/docs/architecture/rfcs/rfc-0004-compartilhamento-de-outputs-entre-esteiras-via-aws-systems-manager-parameter-store.md) e [ADR-0022](https://github.com/oficina-mecanica-soat/oficina-mecanica-api/blob/main/docs/architecture/adrs/adr-0022-uso-do-aws-systems-manager-parameter-store-para-compartilhamento-de-outputs-entre-esteiras.md), esta esteira consome:

| Parâmetro SSM | Uso |
| --- | --- |
| `/oficina-mecanica/development/status/vpc` | Deve ser `ready`. |
| `/oficina-mecanica/development/vpc/vpc_id` | VPC do RDS. |
| `/oficina-mecanica/development/vpc/private_subnet_ids` | DB subnet group. |
| `/oficina-mecanica/development/status/kubernetes` | Deve ser `ready`. |
| `/oficina-mecanica/development/kubernetes/cluster_security_group_id` | Source autorizado para TCP/1433. |

Após `apply`, publica:

| Parâmetro SSM | Uso |
| --- | --- |
| `/oficina-mecanica/development/rds/endpoint` | Endpoint não secreto do RDS. |
| `/oficina-mecanica/development/rds/security_group_id` | Security group do banco. |
| `/oficina-mecanica/development/rds/master_secret_arn` | ARN não secreto do secret master gerenciado pelo RDS. |
| `/oficina-mecanica/development/status/rds` | Marca o RDS como pronto. |

O valor das credenciais de banco nunca é gravado no SSM. O RDS gera e gerencia a senha master no AWS Secrets Manager; somente o ARN não secreto é publicado para consumidores autorizados.

## 🔐 GitHub Environment

No Environment `development`, configurar os secrets `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` e `AWS_SESSION_TOKEN`. As variables esperadas são `AWS_REGION` (padrão `us-east-1`), `DB_USERNAME`, `AUTO_PR_ENABLED` e `RELEASE_BRANCH` (padrão `release`). `DB_USERNAME` não é segredo; a senha master é gerada e gerenciada pelo RDS no Secrets Manager.

Crie esses itens em **Settings > Environments > development**. Os três itens `AWS_*` são Environment Secrets com as credenciais temporárias do AWS Academy. `AWS_REGION`, `DB_USERNAME`, `AUTO_PR_ENABLED` e `RELEASE_BRANCH` são Variables; não inclua senha de banco no GitHub.

## 🧪 Validação local

```powershell
terraform fmt -check -recursive infra/terraform
terraform -chdir=infra/terraform/environments/dev init -backend=false
terraform -chdir=infra/terraform/environments/dev validate
```

Para gerar plano, configure credenciais AWS e a variável não secreta `TF_VAR_db_username`. O RDS gerencia a senha master no Secrets Manager. Este é o terceiro apply, depois de VPC e Kubernetes:

```text
infra-vpc -> infra-kubernetes -> infra-rds -> aplicações -> infra-api-gateway
```

Na implantação distribuída, usar `ORCAMENTO_PAGAMENTO_DB_ENABLED=true`: a preparação SQL cria banco/login exclusivos pelo Job temporário da esteira e só publica prontidão após prova SQL e limpeza. O RDS compartilhado fisicamente não autoriza acesso cruzado aos bancos. Seguir a [sequência completa](https://github.com/oficina-mecanica-soat/oficina-mecanica-api#deploy-aws); nenhum apply/destroy real deve ser executado localmente.

Depois do `apply`, a esteira valida o RDS, o secret gerenciado e os contratos SSM. Depois do `destroy`, valida a ausência do banco e dos parâmetros publicados.

<a id="operação-e-documentação"></a>

## 🧭 Operação e documentação

- [Visão geral, arquitetura e ordem das esteiras](https://github.com/oficina-mecanica-soat/oficina-mecanica-api#deploy-aws).
- [Configuração, primeira aplicação e recuperação após Reset](https://github.com/oficina-mecanica-soat/oficina-mecanica-api/blob/develop/docs/deploy/deploy-aws.md).
- [Collection consolidada e ambientes Local/Development](https://github.com/oficina-mecanica-soat/oficina-mecanica-api/blob/develop/docs/evidencias/postman.md).

Todo provisionamento, atualização e destroy na AWS ocorre pelas esteiras oficiais. O controle é `infra/terraform/environments/dev/terraform-action.env`; destroy exige alteração dedicada e verificação dos consumidores. `AWS_DEPLOY_ENABLED` autoriza a janela real, e `AUTO_PR_ENABLED` controla somente a abertura de promoções. Alterar uma Variable não dispara o CD.

Um ambiente disponível pode ser testado sem destroy. Sem estado compatível, alguns owners exigem primeiro uma recuperação por destroy dedicado com inventário vazio comprovado. Não apague recursos ou caches para contornar o bloqueio; consulte o guia antes de iniciar uma conta ou retomar um laboratório.

Fluxo Git: branch de trabalho → PR para `develop` → `release` → `main`. O CD físico ocorre em development; release e production registram promoções lógicas. PRs e merges permanecem sujeitos aos checks e à revisão. Mudanças somente em README/docs não exigem deploy físico pelos detectores atuais.
