# Estratégia de armazenamento por topologia

## Sumário
1. Como a skill detecta os discos
2. SSD único (ou disco único)
3. SSD + HD
4. Vários SSDs (ex.: NVMe + SATA)
5. HD único
6. Sistema no HD + SSD sobrando
7. Disco sem letra / não inicializado
8. Discos externos (USB) e unidades de rede
9. Regras que valem para todos

---

## 1. Como a skill detecta os discos

`Diagnostico-Completo.ps1` cruza `Get-PhysicalDisk` (MediaType SSD/HDD), `Get-Disk` (estilo de partição, status), `Get-Partition` (letras) e `Win32_LogicalDisk` (espaço). Quando MediaType vem como "Unspecified", ela usa o barramento (NVMe = SSD) e a rotação (SpindleSpeed 0 = SSD). Discos USB/SD contam como **externos** e nunca entram na estratégia de bibliotecas. Unidades de rede (ex.: `P:` corporativo) são listadas, mas ignoradas para mover arquivos.

A topologia aparece no relatório (`Armazenamento.Topologia`) com um destes valores: `SSD único`, `SSD + HD`, `Vários SSDs`, `HD único`, `Sistema no HD + SSD extra`, `Vários HDs` ou `Disco único` (tipo desconhecido).

---

## 2. SSD único (ou disco único)

É o cenário mais comum em notebooks. Tudo divide o mesmo espaço, então o objetivo é **manter 15–20% livre**. Abaixo de 10%, o Windows fica lento, as atualizações falham e o SSD se desgasta mais.

Para liberar espaço, siga esta ordem (do maior para o menor impacto típico):
1. **Hibernação** em desktop: `DesativarHibernacao` libera cerca de 40% da RAM (6–13 GB). Em notebook, prefira `ReduzirHibernacao`.
2. **Jogos e programas grandes que não usa:** desinstalar pelo launcher ou por Configurações > Aplicativos.
3. **Downloads e Área de Trabalho:** instaladores antigos, .zip já extraídos e duplicados.
4. **Limpeza:** temporários, caches de navegador, Windows Update e cleanmgr.
5. **DISM** (WinSxS) e **CompactOS** (2–4 GB), quando ainda estiver apertado.
6. **Pontos de restauração** limitados a 5%.
7. **Arquivo morto** (vídeos antigos, backups, ISOs) para um disco externo ou nuvem. O OneDrive com "Arquivos sob demanda" mantém os arquivos visíveis sem ocupar disco.

Para organizar com um disco só, a estrutura proposta fica nas próprias bibliotecas do Windows (Documentos, Imagens, Vídeos, Músicas). Não existe "mover para o HD". Se houver disco externo, o arquivo morto pode ir para `X:\Arquivo\...` com `Planejar-Organizacao.ps1 -DestinoBase 'X:\Arquivo'`.

---

## 3. SSD + HD

| Fica no SSD (velocidade) | Vai para o HD (capacidade) |
|---|---|
| Windows, arquivo de paginação, hiberfil | Imagens, Vídeos, Músicas (bibliotecas) |
| Programas que você usa todo dia | Documentos de arquivo (anos anteriores) |
| Jogos que você joga com frequência (menos tempo de carregamento) | Jogos pouco jogados, bibliotecas extras da Steam |
| Projetos em andamento (código, edição de vídeo ativa) | Backups, instaladores guardados, ISOs |
| Downloads (transitória, mantenha enxuta) | Gravações e clipes de jogo |

**Como mover, com segurança:**
- **Bibliotecas do Windows:** use `Mover-Biblioteca.ps1 -Biblioteca Videos -Destino 'E:\Vídeos'`. O script faz o mesmo que a aba "Local" das Propriedades da pasta: copia com robocopy, verifica, aponta o Windows para o novo caminho (com backup do registro) e mantém os originais até o usuário responder à pergunta obrigatória. Depois de sair e entrar na conta, rode `-RemoverOriginal`.
  - Comece por **Vídeos** e **Imagens**, que costumam ser os maiores.
  - **Documentos** pode ir, mas alguns jogos salvam em `Documentos\My Games`. Eles seguem o novo local automaticamente, mas avise o usuário.
  - **Área de Trabalho** e **Downloads** normalmente ficam no SSD.
  - Se o caminho contém `OneDrive`, a pasta é gerenciada pelo backup do OneDrive. Mude pelas configurações do OneDrive, nunca pelo script.
- **Jogos:** use sempre o launcher.
  - **Steam:** Configurações > Armazenamento > adicionar uma biblioteca no HD > selecionar o jogo > Mover.
  - **Xbox/Game Pass:** app Xbox > jogo > Gerenciar > Arquivos > Mover.
  - **Epic:** não tem "mover". Desinstale e reinstale no HD, ou mova a pasta e use "Verificar" apontando para o novo local (avançado).
  - **Battle.net / EA app:** opções de instalação do jogo.
- **Programas:** nunca mova o `Program Files`. Para mudar um programa de disco, desinstale e reinstale escolhendo o HD.
- **Navegador:** a pasta de downloads pode ir para o HD nas configurações do navegador, se o usuário quiser.

---

## 4. Vários SSDs (ex.: NVMe + SATA)

- O SSD do sistema (de preferência o NVMe) fica com o Windows e os programas.
- O SSD secundário recebe jogos (o desempenho é praticamente igual em qualquer SSD), bibliotecas grandes e projetos.
- Use `Mover-Biblioteca.ps1` para Vídeos e Imagens se o SSD do sistema estiver apertado.

---

## 5. HD único

- O upgrade para SSD é, de longe, a melhoria mais perceptível. Um SSD SATA ou NVMe de 500 GB deixa o boot e a abertura de programas de 3 a 5 vezes mais rápidos. Recomende sem pressionar.
- Enquanto isso:
  - mantenha a otimização semanal ativa (`ReativarOtimizacaoAgendada`);
  - reduza os programas na inicialização (o maior ganho de boot em HD);
  - mantenha o SysMain ativo (ele ajuda muito em HD);
  - mantenha 15% livre.

---

## 6. Sistema no HD + SSD sobrando

É a configuração invertida. Recomende **clonar** o Windows para o SSD com a ferramenta do fabricante do SSD (Samsung Data Migration, Kingston/Crucial com Acronis etc.) e depois usar o HD para arquivos. É um processo manual e sensível: oriente a fazer backup antes e não execute nada automaticamente.

---

## 7. Disco sem letra / não inicializado

O relatório avisa quando há um disco interno com estilo **RAW** (não inicializado) ou com partições grandes sem letra.

- **Nunca** inicialize ou formate sem o usuário confirmar que o disco está vazio. Um disco que veio de outro PC pode ter dados.
- Oriente a abrir `diskmgmt.msc`:
  - **Partição saudável sem letra:** clique direito > "Alterar letra e caminho" > Adicionar.
  - **Disco "Não inicializado":** só inicialize (GPT) se o usuário tiver certeza de que está vazio; depois, "Novo volume simples".
- Depois disso, rode o diagnóstico de novo: a topologia passa a ser `SSD + HD`, e as recomendações de mover bibliotecas aparecem.

---

## 8. Discos externos (USB) e unidades de rede

- **Externos** são bons para arquivo morto e backup, não para bibliotecas do dia a dia nem programas (podem ser desconectados). A Steam aceita bibliotecas em SSD/HD externo, uma boa saída para jogos pouco jogados em notebook.
- **Unidades de rede** (comum em empresas) são do TI. Não mova nada para lá sem orientação do usuário.

---

## 9. Regras que valem para todos

- Mantenha 15–20% livre no disco do sistema.
- O arquivo de paginação fica no SSD do sistema, gerenciado automaticamente. Não desative.
- SSD não se desfragmenta: o Windows faz TRIM semanal. HD sim; a tarefa agendada cuida disso.
- Saúde do disco diferente de "Healthy" no relatório significa **backup imediato**, antes de qualquer otimização.
