# 🗄️ Oficina Mecânica Infra RDS

Este repositório provisiona e opera o Amazon RDS SQL Server de `development` da Oficina Mecânica, para a Fase 3 do Tech Challenge FIAP.

## 🎯 Responsabilidades

- Consumir VPC e subnets privadas publicados pela esteira VPC, e o security group do EKS publicado pela esteira Kubernetes.
- Criar RDS SQL Server Express, DB subnet group e security group privado.
- Publicar endpoint, security group e status no AWS Systems Manager Parameter Store.
- Controlar `apply` e `destroy` com plano e validação real na AWS.

## 🔀 Fluxo Git

```text
branch de trabalho -> PR develop -> deploy development -> PR release -> deploy homologation -> PR main -> deploy production
```

As branches protegidas são `develop`, `release`, `release/*` e `main`. A governança segue as esteiras VPC e Kubernetes:

- **🔒 Proteção Git Flow:** PR, conversas resolvidas, bloqueio de push direto/force push/deleção, sem bypass; exige os checks `🔀 01 · Validar fluxo de branches` e `🚦 03 · Quality gate`.
- **👥 Aprovação de PR:** uma aprovação, descarte de aprovação antiga e aprovação diferente do último autor do push.

## 🔁 Workflows

| Workflow | Responsabilidade |
| --- | --- |
| `🧪 CI` | Valida PRs para `develop`, `release`/`release/**` e `main`; verifica Git Flow, Terraform e quality gate. |
| `🚀 CD Development` | Detecta mudanças de Terraform, chama o deploy AWS e pode abrir PR para release. |
| `☁️ AWS Deploy` | Resolve `apply`/`destroy`, planeja, aplica e verifica AWS/SSM. |
| `🔀 CD Release` | Registra o deploy lógico em homologation e pode abrir PR para main. |
| `🏁 CD Production` | Registra o deploy lógico em production. |

## 🌐 Contrato entre esteiras

Conforme [RFC-0004](https://github.com/geoscabio/oficina-mecanica-api/blob/main/docs/architecture/rfcs/rfc-0004-compartilhamento-de-outputs-entre-esteiras-via-aws-systems-manager-parameter-store.md) e [ADR-0022](https://github.com/geoscabio/oficina-mecanica-api/blob/main/docs/architecture/adrs/adr-0022-uso-do-aws-systems-manager-parameter-store-para-compartilhamento-de-outputs-entre-esteiras.md), esta esteira consome:

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

## 🧭 Controle apply/destroy

O arquivo `infra/terraform/environments/dev/terraform-action.env` controla a ação:

```env
TERRAFORM_ACTION=apply
```

Para destruir, altere-o explicitamente para `destroy` em um PR dedicado. O workflow recusa destroy se esse arquivo não mudou no mesmo push.

## 🧪 Validação local

```powershell
terraform fmt -check -recursive infra/terraform
terraform -chdir=infra/terraform/environments/dev init -backend=false
terraform -chdir=infra/terraform/environments/dev validate
```

Para gerar plano, configure credenciais AWS e a variável não secreta `TF_VAR_db_username`. O RDS gerencia a senha master no Secrets Manager. A ordem da Fase 3 é:

```text
infra-vpc -> infra-kubernetes -> infra-rds -> api
```

Depois do `apply`, a esteira valida o RDS, o secret gerenciado e os contratos SSM. Depois do `destroy`, valida a ausência do banco e dos parâmetros publicados.

## ⚠️ AWS Academy

O apply do RDS com credencial master gerenciada depende de `secretsmanager:CreateSecret`, `secretsmanager:TagResource` e `kms:DescribeKey`. Essas permissões serão comprovadas somente no apply controlado; se o LabRole as bloquear, a esteira deve falhar sem fazer fallback para senha em Terraform.

Documentação central e arquitetura completa: [README da Oficina Mecânica API](https://github.com/geoscabio/oficina-mecanica-api).

### Reconciliação de destroy após reset do laboratório

O destroy restaura o cache Terraform existente e usa uma configuração temporária sem data sources de contratos SSM. O state original não é editado nem descartado: o provider confirma os recursos ausentes durante o plano de destruição. Somente o plano salvo, sem criação ou atualização, pode ser aplicado. Ao terminar, a esteira verifica que o state não contém recursos gerenciados antes de persistir o cache final. Falhas de autenticação, permissão ou rede bloqueiam a operação.

Na API, vínculos Kubernetes só podem ser retirados por blocos declarativos removed com destroy=false após ResourceNotFoundException confirmar que o EKS registrado no state não existe. Com EKS existente, permanece a configuração normal de destroy. Não há uso de state rm, import ou mv.

O retorno de terraform-action.env para apply é reconhecido como mudança de infraestrutura pelo detector de CD. O bloqueio AWS_DEPLOY_ENABLED descrito abaixo separa a preparação da execução; somente autorize nova subida em janela própria.

#### State isolado por conta AWS

As chaves de cache incluem o ID da conta retornado pela autenticação AWS, antes do ambiente e da execução. A restauração só pesquisa esse escopo, sem fallback para chaves históricas sem conta. Os caches anteriores permanecem preservados como histórico do laboratório encerrado 058264466885, inclusive quando contêm referências que a conta atual não consegue consultar. AccessDenied não é convertido em ausência.

Sem cache no escopo atual, a esteira bloqueia apply. Um destroy dedicado só pode iniciar state novo depois de consultas read-only confirmarem que não existem recursos ou contratos do projeto na conta atual. Recursos internos do laboratório são preservados. Depois disso, o plano exclusivo de destroy e a validação de state vazio produzem o cache usado pelas próximas execuções da mesma conta. Em laboratório com recursos existentes e cache ausente, é necessário recuperar o state correto; o bootstrap não libera provisionamento automático.

## Preparação da subida e plano único — F4-04

O retorno a `TERRAFORM_ACTION=apply` prepara o RDS após VPC e Kubernetes disponíveis. A variável de repositório `AWS_DEPLOY_ENABLED` foi cadastrada como `false`; CD Development e workflow reutilizável exigem valor `true`, e o reutilizável também exige branch develop. Ausente/false/inválido bloqueia AWS. Não configurar override divergente no Environment. Aprovação/merge do PR não autoriza a janela de execução.

A preparação corrige a divergência de planos registrada no plano de Gabriel como PIPE-002: o job `plan` grava `tfplan` para apply e destroy, confere o plano exclusivo de destroy quando aplicável e publica artefato com ID da execução/tentativa. O job `apply_or_destroy` restaura e valida o state da conta, prepara o ambiente, baixa **o mesmo artefato** e aplica `tfplan`; não gera outro plano. A validação exclusiva de destroy também permanece antes da execução. Retenção de um dia e falha caso o plano não exista seguem as referências VPC/Kubernetes; o identificador da tentativa evita confusão em reexecuções.

Não altera state/cache, regras de recuperação, promoção, environment, contratos SSM ou as verificações reais de RDS/rede. A ordem restore → validação → preparação de destroy → init é mantida nos dois jobs. Os testes novos são inline no CI existente e verificam esse fluxo, os nomes correspondentes de artefato, ausência de replanejamento no job de aplicação e bloqueio real da etapa de resolução em fixture temporária. Nenhuma pasta/arquivo de scripts foi acrescentado.

A futura execução autorizada provisionará a configuração já declarada: RDS SQL Server Express `16.00.4185.3.v1`, `db.t3.micro`, 20 GB criptografados, sem acesso público; DB subnet group nas subnets privadas e security group com entrada TCP/1433 do SG do EKS; senha master gerenciada pelo RDS no Secrets Manager e contratos SSM existentes. Não muda engine, classe, storage ou política de dados, não cria banco lógico de Orçamento/Pagamento, não executa migrations e não implanta aplicações. A separação de credenciais/bancos da F4-07 continua na frente responsável, sem anunciar isolamento já implementado.

Em 11/11/2026, consulta read-only confirmou que a combinação declarada de engine/versão/classe possui opções disponíveis em us-east-1 e que DB_USERNAME está configurado. Isso não comprova permissão de criação, conectividade SQL ou autenticação de consumidores. Terraform fmt/validate, quatro testes de recuperação, teste inline do fluxo e actionlint (sem shellcheck/pyflakes locais) passaram; o CI do PR é a evidência antes do merge. Nenhum plano autenticado, apply/destroy ou banco foi criado nesta preparação. Gabriel realiza o merge e autoriza separadamente a implantação; o bloqueio deve ser restaurado ao final da janela.
