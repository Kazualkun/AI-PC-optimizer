# Catálogo de limpezas e otimizações

A fonte de verdade é `scripts/Catalogo.ps1` (o que é medido e o que pode ser feito). Este arquivo explica cada item em linguagem simples, para você justificar as recomendações e responder dúvidas.

## Sumário
1. Itens de limpeza (`Limpeza-Sistema.ps1 -Itens …`)
2. Ações de otimização (`Otimizar-Sistema.ps1 -Acoes …`)
3. Serviços: o catálogo seguro e o que manter
4. Apps pré-instalados
5. Sobre RAM: o que realmente ajuda
6. Mitos e práticas a evitar
7. Rotina de manutenção

---

## 1. Itens de limpeza

| Id | Remove | Risco | Admin | Observações |
|---|---|---|---|---|
| `TempUsuario` | `%TEMP%`, arquivos com 2+ dias | Baixo | Não | Arquivos em uso são pulados |
| `TempWindows` | `C:\Windows\Temp`, 2+ dias | Baixo | Sim | |
| `Lixeira` | Todo o conteúdo da Lixeira | **Médio** | Não | **Definitivo.** Confirme que não há nada para recuperar |
| `CacheNavegadores` | Cache, Code Cache e GPUCache (Chrome, Edge, Brave, Opera, Firefox) | Baixo | Não | Não toca senhas, cookies nem histórico. **Feche o navegador** (o Edge roda em segundo plano) |
| `CacheApps` | Caches do Discord, Teams clássico, Slack, Spotify e VS Code | Baixo | Não | O Spotify pode precisar baixar de novo as músicas offline |
| `CacheMiniaturas` | `thumbcache_*.db` | Baixo | Não | O Windows recria. Arquivos em uso pelo Explorador são pulados |
| `CacheShaders` | DirectX, NVIDIA, AMD e Intel | Baixo | Não | Jogos podem engasgar nos primeiros minutos |
| `RelatoriosErro` | Crash dumps, WER, MEMORY.DMP, LiveKernelReports | Baixo | Parcial | Só servem para investigar travamentos |
| `CacheWindowsUpdate` | `SoftwareDistribution\Download` | Baixo | Sim | Para e religa o Windows Update |
| `OtimizacaoEntrega` | Cache da Otimização de Entrega | Baixo | Sim | Usa o cmdlet oficial |
| `InstaladoresDrivers` | `C:\AMD`, `C:\NVIDIA`, Downloader da NVIDIA | Baixo | Sim | O driver instalado não é afetado |
| `CacheDev` | Caches do npm, pip, Yarn e NuGet | Baixo | Não | Baixados de novo sob demanda |
| `LimpezaDiscoWindows` | cleanmgr: sobras de update, Windows.old, logs, drivers antigos | Baixo | Sim | Remover o Windows.old impede voltar à versão anterior. **Não** inclui Downloads, Lixeira nem arquivos de reinstalação (ESD) |
| `ComponentesWindows` | DISM `/StartComponentCleanup` | Baixo | Sim | De 5 a 30 min. Sem `/ResetBase` |

## 2. Ações de otimização

| Ação | O que faz | Risco | Admin | Como desfazer |
|---|---|---|---|---|
| `DesativarHibernacao` | `powercfg /hibernate off`: apaga o hiberfil.sys (~40% da RAM) | Baixo (desktop) | Sim | `powercfg /hibernate on` |
| `ReduzirHibernacao` | Hiberfil reduzido (~20% da RAM); mantém a Inicialização Rápida | Baixo | Sim | `/type full` |
| `CompactarWindows` | CompactOS: 2–4 GB, de 10 a 20 min | Baixo | Sim | `compact /CompactOS:never` |
| `LimitarPontosRestauracao` | Limita o espaço dos pontos de restauração a 5% | Médio | Sim | O backup grava o limite anterior |
| `AtivarSensorArmazenamento` | Limpeza automática (temporários + Lixeira com 30+ dias). **Downloads nunca é tocada** | Baixo | Não | Registro restaurado |
| `DesativarInicializacao` | Mesmo mecanismo do Gerenciador de Tarefas (StartupApproved), tarefas agendadas e apps da Loja | Baixo | Depende | Registro/tarefa restaurados |
| `DesativarServicos` | Manual/Desativado, só para serviços do catálogo | Baixo/Médio | Sim | Tipo de inicialização anterior restaurado |
| `DesativarAppsSegundoPlano` | Win10: bloqueia apps da Loja em segundo plano | Baixo | Não | Registro |
| `RemoverApps` | `Remove-AppxPackage` (usuário atual); pacotes protegidos são recusados | Baixo/Médio | Não | Reinstalar pela Microsoft Store |
| `DesativarRecursos` | SMB1, PowerShell 2.0, IE11 etc. | Baixo/Médio | Sim | `Enable-WindowsOptionalFeature` |
| `DesativarGameDVR` | Gravação contínua do Game Bar | Baixo | Não | Registro |
| `DesativarSugestoes` | Apps patrocinados e sugestões no Iniciar | Baixo | Não | Registro |
| `DesativarNoticias` | Notícias e Interesses (Win10) / Widgets (Win11) | Baixo | Não | Registro |
| `EfeitosVisuais` | Transparência e animações (útil com ≤ 8 GB de RAM) | Baixo | Não | Registro |
| `PlanoEnergiaDesempenho` | Alto desempenho (desktop em modo Economia) | Baixo | Não | Plano anterior |
| `AtivarTRIM` | `DisableDeleteNotify = 0` | Baixo | Sim | Comando inverso |
| `ReativarOtimizacaoAgendada` | Tarefa semanal de TRIM/desfragmentação | Baixo | Sim | Desativar a tarefa |
| `OtimizarUnidades` | TRIM agora (SSD) ou desfragmentar (HD) | Baixo | Sim | (sem efeito a desfazer) |

Antes de ações de admin, `Otimizar-Sistema.ps1` tenta criar um ponto de restauração. O Windows limita a um por 24 h, e o aviso de falha é normal. O backup próprio da skill continua valendo.

## 3. Serviços

**Catálogo seguro** (só esses podem ser alterados pelo script):
- `DiagTrack` (telemetria): Desativado.
- `dmwappushservice`: Desativado. É *Médio* e fica fora em PC corporativo, porque o MDM/Intune depende dele.
- `MapsBroker`, `Fax`, `RetailDemo`, `WMPNetworkSvc`: Desativado.
- `RemoteRegistry`: Desativado (segurança).
- `TrkWks`: Manual.
- `Spooler`: Manual, **só sem impressora física**. O "Imprimir em PDF" também depende dele.
- `bthserv`: Manual, só sem adaptador Bluetooth.

**Mantenha** (explique ao usuário se ele leu um guia que manda desativar):
- `SysMain`: pré-carrega os apps usados; a Microsoft recomenda manter, inclusive em SSD.
- `WSearch`: indexação; sem ela, a busca fica lenta. Em SSD o custo é mínimo.
- `wuauserv`: Windows Update, essencial para a segurança.
- `WinDefend`: antivírus.
- `TabletInputService`: painel de emojis (Win + .), teclado virtual e métodos de entrada.

Desativar serviços economiza pouca RAM em PCs modernos (dezenas de MB). Em PC com 16 GB, priorize a inicialização e os apps em segundo plano.

## 4. Apps pré-instalados

- **Risco Baixo** (raramente usados): Notícias, Clima, Obter Ajuda, Dicas, Solitaire, Pessoas, Hub de Feedback, Filmes e TV, Realidade Misturada, 3D Viewer, Paint 3D, Skype (Loja), hub do Office, Cortana, Mapas, Clipchamp, Power Automate e jogos/apps patrocinados (Candy Crush, TikTok, Disney+…).
- **Risco Médio** (pergunte se usa): Groove/Media Player, OneNote para Win10, Vincular ao Celular, Email e Calendário, Xbox Console Companion, Teams pessoal, Spotify da Loja.
- **Protegidos** (o script recusa): Microsoft Store, App Installer (winget), Fotos, Calculadora, Ferramenta de Captura, Bloco de Notas, Paint, Segurança do Windows, componentes Xbox usados por jogos, codecs (HEIF, HEVC, VP9, WebP…), frameworks (VCLibs, .NET, UI.Xaml), Edge, Terminal e Portal da Empresa.

## 5. Sobre RAM: o que realmente ajuda

- **RAM "em uso" não é problema.** O Windows usa a memória livre como cache e libera na hora quando um programa precisa. "Otimizadores" que esvaziam a RAM deixam tudo mais lento.
- O que reduz o consumo de verdade, nesta ordem:
  1. programas na inicialização;
  2. abas e extensões do navegador;
  3. apps em segundo plano (Loja, launchers, overlays);
  4. Widgets e notícias;
  5. serviços.
- **Sinais de falta real de RAM:** uso acima de 85% de forma constante, "memória comprometida" perto do limite, e o disco a 100% por paginação. Nesse caso, a solução é hardware (16 GB).
- Reiniciar uma vez por semana resolve vazamentos de memória. "Desligar" com Inicialização Rápida não conta como reinício.

## 6. Mitos e práticas a evitar

| Prática | Por que não |
|---|---|
| Limpador de registro | Ganho zero comprovado; risco de quebrar programas |
| Apagar Prefetch | O Windows recria e os programas abrem mais devagar até lá |
| Desativar o pagefile "porque tenho RAM" | Programas travam ao esgotar a memória comprometida; não há dump de erro |
| Desfragmentar SSD | Desgaste sem benefício. O Windows faz TRIM |
| Apagar WinSxS ou Installer à mão | Quebra atualizações, reparos e desinstalações. Use DISM/cleanmgr |
| Desativar Windows Update ou Defender | Brechas de segurança |
| Scripts de "debloat" da internet | Removem componentes de que o Windows depende; difíceis de reverter |
| Mover a pasta de um programa ou jogo manualmente | Atalhos, registro e atualizações quebram. Use o launcher ou reinstale |
| "Otimizadores de RAM" | Esvaziam o cache útil e deixam o sistema mais lento |

## 7. Rotina de manutenção (sugira no fechamento)

- **Semanal:** reiniciar o PC (não só desligar).
- **Mensal:** esvaziar Downloads (instaladores e .zip já usados), esvaziar a Lixeira e rodar `Diagnostico-Completo.ps1 -Rapido`.
- **Trimestral:** revisar programas e jogos que não usa; limpeza de cache de navegador e Windows Update.
- **Sempre:** manter 15–20% livre no disco do sistema e ter backup dos arquivos importantes (nuvem ou HD externo).
