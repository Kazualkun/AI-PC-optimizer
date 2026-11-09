# Estrutura de pastas proposta e regras de classificação

## Sumário
1. Princípios
2. Estrutura proposta (bibliotecas do Windows)
3. O que o planejador faz automaticamente
4. Refinando o plano pelo nome dos arquivos
5. Casos especiais (projetos, pastas, Área de Trabalho)
6. Como editar o CSV do plano

---

## 1. Princípios

- **Poucas pastas no topo, nomes claros.** É melhor ter cinco pastas que você entende do que trinta que ninguém lembra para que servem.
- **A data organiza o que não tem assunto.** Fotos e vídeos ficam por ano (`2025\`). Documentos financeiros ficam por ano dentro de Financeiro.
- **Downloads é uma área de passagem.** O que fica vai para a biblioteca certa; instaladores são apagados depois de instalar.
- **Área de Trabalho é para o dia a dia:** atalhos e, no máximo, uma pasta "Em andamento".
- **`_Triagem` é honesta.** O que o script não consegue classificar com segurança vai para `Documentos\_Triagem\<tipo>`. O underline faz a pasta aparecer no topo, lembrando o usuário de revisá-la.
- **Projetos não se desmontam.** Uma pasta de código, um app portátil ou um projeto de design se move inteiro.

## 2. Estrutura proposta (bibliotecas do Windows)

```
Documentos\
├── Pessoal\            (documentos pessoais, saúde, casa, veículo)
├── Financeiro\
│   └── 2025\           (boletos, notas fiscais, extratos, comprovantes, IR)
├── Trabalho\           (por empresa/cliente)
├── Estudos\            (por curso/disciplina)
├── Projetos\           (cada projeto inteiro: código, design, TCC…)
├── Modelos\            (currículo-base, modelos de contrato…)
└── _Triagem\           (destino automático, para revisar depois)
    ├── PDFs\  Textos\  Planilhas\  Apresentações\  Código\  Outros\
Imagens\
├── 2025\               (fotos por ano; opcional: "2025-07 Viagem Praia")
├── Capturas de Tela\2025\
├── Papéis de Parede\
└── Design\             (logos, artes, banners)
Vídeos\
├── 2025\
├── Gravações de Tela\2025\
├── Clipes de Jogos\
└── Filmes e Séries\
Músicas\
└── Importadas\
Downloads\              (passagem: o que sobrar fica em subpastas por tipo)
├── Instaladores\       (apagar depois de instalar)
├── Compactados\        (apagar se já extraído)
├── Imagens de Disco\   (ISOs)
├── Fontes\
└── Torrents\
```

Com SSD + HD, a mesma árvore vale para o HD. Ou se movem as bibliotecas (`Mover-Biblioteca.ps1`), ou se usa `Planejar-Organizacao.ps1 -DestinoBase 'E:\Arquivos'`.

Adapte ao usuário. Quem trabalha com vídeo pode querer `Vídeos\Projetos\`; estudante, `Documentos\Estudos\<Semestre>\`. Mostre a árvore adaptada e peça aprovação antes de planejar.

## 3. O que o planejador faz automaticamente

| Categoria (extensão) | Destino padrão |
|---|---|
| Imagens (.jpg .png .heic .webp…) | `Imagens\<ano>`; capturas (`Screenshot`, `Captura de tela`…) em `Imagens\Capturas de Tela\<ano>`; wallpapers em `Papéis de Parede` |
| Vídeos | `Vídeos\<ano>`; gravações de tela em `Vídeos\Gravações de Tela\<ano>` |
| Músicas | `Músicas\Importadas` |
| PDF | `Documentos\_Triagem\PDFs` |
| Textos (.docx .txt .odt…) | `Documentos\_Triagem\Textos` |
| Planilhas / Apresentações / Código | `Documentos\_Triagem\<tipo>` |
| Compactados / Instaladores / ISOs / Fontes / Torrents | `Downloads\<tipo>` |
| Atalhos (.lnk .url) | Ficam onde estão |
| Downloads incompletos (.crdownload .part) | "Revisar" (provavelmente apagar) |
| Subpastas | "Revisar" (o usuário decide; projetos vão inteiros) |
| Arquivos só na nuvem (OneDrive) | Não são tocados |

O ano vem da data de modificação do arquivo. Nomes que já existem no destino ganham " (2)"; nada é sobrescrito. Se já existe uma cópia idêntica no destino, a linha vira `JaExiste`: não copia, e o original pode ser removido depois.

## 4. Refinando o plano pelo nome dos arquivos

Depois de gerar o plano, leia as linhas `Copiar` que caíram em `_Triagem` e reclassifique pelo nome. Esta é a parte em que você agrega mais valor. Regras sugeridas (sem diferenciar maiúsculas):

| Se o nome contém… | Destino |
|---|---|
| boleto, fatura, nota fiscal, nf-e, nfe, danfe, extrato, comprovante, recibo, pix, irpf, darf, informe de rendimentos | `Documentos\Financeiro\<ano>` |
| curriculo, currículo, cv_, rg, cpf, cnh, certidão, passaporte, título de eleitor, comprovante de residência | `Documentos\Pessoal` |
| exame, laudo, receita médica, atestado, resultado, vacina | `Documentos\Pessoal\Saúde` |
| contrato, proposta, orçamento, procuração | Pergunte: `Trabalho\` ou `Pessoal\` |
| apostila, aula, lista de exercícios, tcc, monografia, artigo, certificado, diploma, histórico | `Documentos\Estudos` |
| logo, banner, post, arte, mockup, .psd, .ai | `Imagens\Design` |
| wallpaper, papel de parede | `Imagens\Papéis de Parede` |

Quando houver muitos arquivos de um mesmo cliente, empresa ou assunto (padrão recorrente nos nomes), proponha uma subpasta própria. Se não tiver certeza, deixe na `_Triagem`. Errar o destino é pior que deixar para revisão.

## 5. Casos especiais

- **Projetos de código e apps portáteis.** São detectados por `.git`, `package.json`, `requirements.txt`, `*.sln`, `.vscode`, exe+dll etc. Nunca separe os arquivos. Proponha mover a pasta inteira para `Documentos\Projetos\<nome>`: no CSV, a linha "Pasta/Projeto" recebe a Ação `Copiar` e o Destino com o caminho completo da nova pasta. Atenção: projetos com `node_modules` ou `venv` podem ter dezenas de milhares de arquivos, e a cópia demora. Mover dentro do mesmo disco (`-Modo Mover`) é instantâneo, mas só com aprovação explícita.
- **Subpastas comuns** (ex.: "manuais", "documentos"). Pergunte ao usuário: mover inteira para uma pasta de Documentos, ou classificar o conteúdo (`-IncluirSubpastas`)?
- **Área de Trabalho.** Atalhos ficam. Arquivos vão para as bibliotecas. Sugira criar no máximo uma pasta "Em andamento" para o que está sendo usado agora.
- **Arquivos abertos em programas** (ex.: uma planilha aberta no Excel) podem falhar na cópia. O resultado mostra "Falhou"; peça para fechar e rode de novo só com os que falharam.

## 6. Como editar o CSV do plano

O plano usa o delimitador `;` e codificação UTF-8. As colunas são: `Tipo;Acao;Categoria;Origem;Destino;Bytes;Tamanho;Modificado;Motivo`.

```powershell
$p = Import-Csv -LiteralPath $plano -Delimiter ';' -Encoding UTF8
$docs = [Environment]::GetFolderPath('MyDocuments')
foreach ($l in $p) {
    if ($l.Acao -eq 'Copiar' -and (Split-Path $l.Origem -Leaf) -match '(?i)boleto|fatura|nota fiscal|danfe|comprovante') {
        $ano = $l.Modificado.Substring(0,4)
        $l.Destino = Join-Path $docs "Financeiro\$ano\$(Split-Path $l.Origem -Leaf)"
        $l.Motivo = 'Reclassificado pelo nome (financeiro)'
    }
}
$p | Export-Csv -LiteralPath $plano -Delimiter ';' -NoTypeInformation -Encoding UTF8
```

Depois de editar, rode a prévia (`Executar-Organizacao.ps1 -Plano $plano`). O executor resolve conflitos de nome sozinho, sem sobrescrever nada.
