# O que o cliente tem hoje

Os tres apps que o enunciado cita, reconstruidos na forma em que o
`pac canvas unpack` os entrega: `CanvasManifest.json`, `Src/*.fx.yaml`,
`Connections/`, `DataSources/`, mais as definicoes de tabela do Dataverse.

Nao sao os arquivos do cliente. Sao fieis na **forma** e nos **modos de falha**,
que e o que interessa: cada um foi escrito para conter os defeitos que uma
ferramenta low-code produz quando um app cresce sem ninguem revisar o schema.

| App | Autor | Ultima publicacao | O que caracteriza |
|---|---|---|---|
| `KYCReviewQueue/` | compliance-ops | 11/03/2026 | Controle de acesso na UI, PII em claro, delegacao |
| `RefundsDashboard/` | ops-tools | 02/05/2026 | Alcada divergente em dois lugares, aprovacao na propria linha |
| `FeatureFlagAdmin/` | platform | 18/06/2026 | Producao sem gate, ambiente como texto livre |

Tres autores diferentes, tres meses diferentes. **Isso e o ponto.** Nenhum dos
tres compartilha uma linha de codigo com os outros, porque o Power Apps nao tem
biblioteca compartilhavel: uma UDF vive dentro do app que a declarou.

---

## KYC Review Queue

| Onde | O que acontece |
|---|---|
| `QueueScreen.fx.yaml` · `galCasos.Items` | `Filter` sobre coluna sem indice, com aviso de delegacao. Acima de 500 linhas para de trazer o resto **sem erro**. |
| `QueueScreen.fx.yaml` · `btnAbrir.Visible` | A unica coisa que impede um analista de abrir o caso de outro time. A linha ja veio para o cliente. |
| `QueueScreen.fx.yaml` · `lblCpf.Text` | CPF em claro. Mascarar exige escrever a funcao a mao em cada tela. |
| `QueueScreen.fx.yaml` · `btnExportar` | Exporta a colecao inteira, sem passar pelo filtro da galeria e sem registro. |
| `QueueScreen` + `ReviewScreen` + fluxo | A regra dos 30 dias escrita em **tres** lugares. |
| `ReviewScreen.fx.yaml` · `btnAprovar.DisplayMode` | Segregacao de funcoes vive numa propriedade de UI. |
| `ReviewScreen.fx.yaml` · `btnComunicarCoaf` | Uma tentativa recusada nao deixa rastro: o botao so fica desabilitado. |
| `ReviewScreen.fx.yaml` · `btnExcluir` | `Remove()`. Sem exclusao logica e sem trilha. |
| `cr8a2_casodekyc.table.json` | `HasAuditEnabled: false`, sem coluna de retencao, sem column-level security no CPF. |

## Refunds Dashboard

| Onde | O que acontece |
|---|---|
| `RefundsScreen.fx.yaml` · `btnAprovar.DisplayMode` | A alcada esta escrita aqui: **50.000**. |
| `RefundsScreen.fx.yaml` · `btnAprovarSelecionadas` | A mesma alcada, escrita de novo: **60.000**. As duas divergiram e nada acusa. |
| `RefundsScreen.fx.yaml` · `btnAprovarSelecionadas` | A aprovação em lote **não repete** a checagem de quem solicitou. Marcando a caixa, o solicitante aprova a própria devolução. |
| `RefundsScreen.fx.yaml` · `lblTotalAberto` | `Sum()` sobre a coleção truncada em 500. O total exibido está errado e não há como perceber. |
| `cr8a2_devolucao.table.json` | A aprovação mora em `cr8a2_aprovadopor`, na própria linha. **Aprovação dupla não cabe no modelo**: a segunda sobrescreve a primeira. |
| `cr8a2_devolucao.table.json` | Não há coluna com a faixa aplicada, então não se reconstroi depois qual regra valia na hora. |

> O par `btnAprovar` / `btnAprovarSelecionadas` e o defeito mais instrutivo do
> conjunto. Nao e um bug de digitacao: e o que acontece quando a mesma regra
> precisa ser escrita duas vezes porque nao existe onde escrever uma vez so.

## Feature Flag Admin

| Onde | O que acontece |
|---|---|
| `FlagsScreen.fx.yaml` · `tglAtiva.OnChange` | Liga e desliga em producao direto. **Nao existe aprovacao.** |
| `FlagsScreen.fx.yaml` · `tglAtiva.OnChange` | A mensagem no Teams e enviada **depois** da escrita e nao bloqueia. Se o fluxo falhar, a flag ja mudou e ninguem fica sabendo. |
| `FlagsScreen.fx.yaml` · `drpAmbiente` | O dropdown lista tres valores, a tabela guarda `producao`, `Producao` e `prod`. Filtrar por um esconde os outros e o painel parece limpo. |
| `cr8a2_featureflag.table.json` | `OrganizationOwned`: sem dono por linha, nao ha como restringir por time no nivel do dado. |
| `cr8a2_featureflag.table.json` | `cr8a2_alteradopor` guarda so a ultima alteracao. **Quem ligou e desligou a flag na semana passada nao existe em lugar nenhum.** |

---

## Como isto e usado

Entrada da **sessao 1** do protótipo. O Devin le os `.fx.yaml` e as definicoes
de tabela, extrai os requisitos e constroi o nucleo e os tres apps sobre ele.

A instrucao que importa: **pegar o requisito, nao a forma**. Onde o legado
resolve com `Visible`, o requisito e controle de acesso e a resposta e policy
no banco. Onde o legado tem dois numeros divergentes, o requisito e uma faixa
de alcada e a resposta e uma declaracao unica.

O PR volta com uma tabela de duas colunas: **onde o legado impoe cada controle,
onde nos impomos.** Essa tabela e o argumento do video.
