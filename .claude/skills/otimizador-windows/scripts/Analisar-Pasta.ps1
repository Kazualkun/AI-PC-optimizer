<#
.SYNOPSIS
    Analisa uma pasta (ex.: Downloads, Área de Trabalho) - SOMENTE LEITURA.
.DESCRIPTION
    Mostra categorias de arquivos, maiores arquivos, subpastas, instaladores antigos, downloads
    incompletos, .zip já extraídos, arquivos sem uso há muito tempo e duplicados (comparação por
    conteúdo/SHA-256). Gera listas CSV de candidatos que podem ser usadas com Remover-Arquivos.ps1.
    Pastas de desenvolvimento (node_modules, .git, venv...) entram nos totais, mas NUNCA nas listas
    de candidatos - arquivos repetidos ali são normais e apagá-los quebraria projetos.
.PARAMETER Pasta
    Caminho ou nome conhecido: Downloads, "Área de Trabalho", Documentos, Imagens, Vídeos, Músicas.
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File Analisar-Pasta.ps1 -Pasta Downloads
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Pasta,
    [int]$DiasAntigo = 365,
    [int]$DiasInstalador = 30,
    [int]$TopMaiores = 15,
    [switch]$SemDuplicados,
    [switch]$SemSalvar,
    [switch]$Silencioso
)

. "$PSScriptRoot\Common.ps1"
. "$PSScriptRoot\Catalogo.ps1"

$Pasta = Resolve-PastaConhecida $Pasta
if (-not (Test-Path -LiteralPath $Pasta -PathType Container)) { Write-Host "Pasta não encontrada: $Pasta"; exit 1 }
$Pasta = (Resolve-Path -LiteralPath $Pasta).ProviderPath.TrimEnd('\')
$raizLen = $Pasta.Length + 1
$agora = Get-Date

# ---------------------------------------------------------- inventário --
$extInteresse = @($Script:CategoriasArquivo['Instaladores']) + @($Script:CategoriasArquivo['Downloads Incompletos']) + @($Script:CategoriasArquivo['Compactados'])
$res = Get-ResumoPasta -Raiz $Pasta -MinInteresse 1MB -ExtInteresse $extInteresse -LimiteAntigo $agora.AddDays(-$DiasAntigo)

$porCat = @{}
foreach ($ext in @($res.PorExtensao.Keys)) {
    $v = $res.PorExtensao[$ext]
    $cat = Get-CategoriaArquivo $ext
    if (-not $porCat.ContainsKey($cat)) { $porCat[$cat] = @([int64]0, [int64]0) }
    $porCat[$cat][0] += $v[0]; $porCat[$cat][1] += $v[1]
}
$categorias = @($porCat.Keys | ForEach-Object { [pscustomobject]@{ Categoria = $_; Quantidade = $porCat[$_][0]; Bytes = $porCat[$_][1]; Tamanho = (Format-Tamanho $porCat[$_][1]) } } | Sort-Object Bytes -Descending)

$itensRaiz = @(Get-ChildItem -LiteralPath $Pasta -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin @('desktop.ini', 'Thumbs.db') })
$subpastas = @()
foreach ($sp in ($itensRaiz | Where-Object { $_.PSIsContainer })) {
    $v = $res.PorSubpasta[$sp.Name]
    $q = if ($v) { $v[0] } else { 0 }; $b = if ($v) { $v[1] } else { 0 }
    $ehProj = Test-PastaProjeto $sp.FullName
    $subpastas += [pscustomobject]@{ Subpasta = $sp.Name; Arquivos = $q; Bytes = [int64]$b; Tamanho = (Format-Tamanho $b); Modificada = $sp.LastWriteTime.ToString('yyyy-MM-dd'); Projeto = [bool]$ehProj }
}
$subpastas = @($subpastas | Sort-Object Bytes -Descending)
# Arquivos dentro de projetos/apps (detectados por package.json, .git, *.sln, exe+dll...) ficam fora das listas de candidatos.
$prefixosProjeto = @($subpastas | Where-Object { $_.Projeto } | ForEach-Object { (Join-Path $Pasta $_.Subpasta) + '\' })

$arquivos = @($res.Interessantes | Where-Object {
        $c = $_.FullName; $dentro = $false
        foreach ($p in $prefixosProjeto) { if ($c.StartsWith($p, [StringComparison]::OrdinalIgnoreCase)) { $dentro = $true; break } }
        -not $dentro
    } | ForEach-Object {
        $rel = $_.FullName.Substring($raizLen)
        [pscustomobject]@{
            Caminho = $_.FullName; Relativo = $rel; Nome = $_.Name; Base = $_.BaseName; Extensao = $_.Extension.ToLower()
            Pasta = $_.DirectoryName; Bytes = [int64]$_.Length; Modificado = $_.LastWriteTime
            Categoria = (Get-CategoriaArquivo $_.Extension); NaRaiz = (-not $rel.Contains('\'))
        }
    })

$maiores = @($arquivos | Sort-Object Bytes -Descending | Select-Object -First $TopMaiores | ForEach-Object {
        [pscustomobject]@{ Arquivo = $_.Relativo; Tamanho = (Format-Tamanho $_.Bytes); Bytes = $_.Bytes; Modificado = $_.Modificado.ToString('yyyy-MM-dd'); Categoria = $_.Categoria }
    })

# ------------------------------------------------------------ candidatos --
function New-Candidato {
    param($A, [string]$Motivo, [string]$Manter = '')
    [pscustomobject]@{ Caminho = $A.Caminho; Bytes = $A.Bytes; Tamanho = (Format-Tamanho $A.Bytes); Modificado = $A.Modificado.ToString('yyyy-MM-dd'); Categoria = $A.Categoria; Motivo = $Motivo; Manter = $Manter }
}

$cachePacote = @{}
function Test-EmPacote {
    # Arquivo dentro de uma subpasta-pacote (driver, app portátil, instalador extraído: a subpasta de topo
    # contém .dll/.inf/.sys/.cat/.cab em qualquer nível). Nunca vira candidato individual - quebraria o conjunto;
    # a decisão é sobre a pasta inteira.
    param($A)
    if ($A.NaRaiz) { return $false }
    $topo = Join-Path $Pasta ($A.Relativo.Split('\')[0])
    if ($cachePacote.ContainsKey($topo)) { return $cachePacote[$topo] }
    $eh = $false
    foreach ($ext in @('*.dll', '*.inf', '*.sys', '*.cat', '*.cab')) {
        if (Get-ChildItem -LiteralPath $topo -Filter $ext -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1) { $eh = $true; break }
    }
    $cachePacote[$topo] = $eh
    return $eh
}

$instaladores = @($arquivos | Where-Object { $_.Categoria -eq 'Instaladores' -and $_.Modificado -lt $agora.AddDays(-$DiasInstalador) -and -not (Test-EmPacote $_) } |
    Sort-Object Bytes -Descending | ForEach-Object { New-Candidato $_ "Instalador baixado há mais de $DiasInstalador dias (o programa já está instalado ou pode ser baixado de novo)" })
$incompletos = @($arquivos | Where-Object { $_.Categoria -eq 'Downloads Incompletos' } | ForEach-Object { New-Candidato $_ 'Download interrompido/incompleto' })
$extraidos = @()
foreach ($z in ($arquivos | Where-Object { $_.Categoria -eq 'Compactados' })) {
    if (Test-Path -LiteralPath (Join-Path $z.Pasta $z.Base) -PathType Container) { $extraidos += New-Candidato $z "Já existe a pasta extraída '$($z.Base)' ao lado" }
}
$antigos = @($arquivos | Where-Object { $_.Modificado -lt $agora.AddDays(-$DiasAntigo) -and $_.Categoria -ne 'Atalhos' } |
    Sort-Object Bytes -Descending | ForEach-Object { New-Candidato $_ "Sem modificação há mais de $DiasAntigo dias" })

# ------------------------------------------------------------- duplicados --
function Get-HashParcial {
    param([string]$Caminho)
    $fs = $null
    try {
        $fs = [IO.File]::Open($Caminho, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        $buf = New-Object byte[] 65536
        $n = $fs.Read($buf, 0, $buf.Length)
        return [BitConverter]::ToString([Security.Cryptography.MD5]::Create().ComputeHash($buf, 0, $n))
    } catch { return $null } finally { if ($fs) { $fs.Dispose() } }
}

$gruposDup = @()
$candidatosDup = @()
if (-not $SemDuplicados) {
    # Mesmo tamanho -> mesmo início (64 KB) -> mesmo SHA-256 completo. Só arquivos de 50 KB+ fora de pastas de projeto.
    $porTamanho = @($arquivos | Where-Object { $_.Bytes -ge 50KB -and -not (Test-EmPacote $_) } | Group-Object Bytes | Where-Object { $_.Count -gt 1 })
    foreach ($gt in $porTamanho) {
        $porParcial = @($gt.Group | ForEach-Object { $_ | Add-Member -NotePropertyName HP -NotePropertyValue (Get-HashParcial $_.Caminho) -Force -PassThru } |
            Where-Object { $_.HP } | Group-Object HP | Where-Object { $_.Count -gt 1 })
        foreach ($gp in $porParcial) {
            $porHash = @($gp.Group | ForEach-Object {
                    $h = (Get-FileHash -LiteralPath $_.Caminho -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
                    $_ | Add-Member -NotePropertyName Hash -NotePropertyValue $h -Force -PassThru
                } | Where-Object { $_.Hash } | Group-Object Hash | Where-Object { $_.Count -gt 1 })
            foreach ($gh in $porHash) {
                # Mantém: 1) nome "limpo" (sem "(1)", "- Cópia"); 2) a cópia que já está DENTRO de uma pasta
                # (a solta na raiz é a bagunça); 3) caminho mais curto; 4) a mais antiga.
                $ordenados = @($gh.Group | Sort-Object @{ Expression = { if ($_.Nome -match '\(\d+\)|- C[oó]pia|- Copy|^C[oó]pia de|^Copy of') { 1 } else { 0 } } }, @{ Expression = { if ($_.NaRaiz) { 1 } else { 0 } } }, @{ Expression = { $_.Caminho.Length } }, Modificado)
                $manter = $ordenados[0]
                $extras = @($ordenados | Select-Object -Skip 1)
                $gruposDup += [pscustomobject]@{ TamanhoCada = (Format-Tamanho $manter.Bytes); Copias = $ordenados.Count; Manter = $manter.Relativo; Extras = (($extras | ForEach-Object { $_.Relativo }) -join ' | ') }
                # Só vira candidato a cópia solta na raiz ou com nome de cópia; duplicados dentro de estruturas
                # organizadas (ex.: dois .zip extraídos com pastas repetidas) ficam só como informação.
                foreach ($e in $extras) {
                    if ($e.NaRaiz -or $e.Nome -match '\(\d+\)|- C[oó]pia|- Copy|^C[oó]pia de|^Copy of') { $candidatosDup += New-Candidato $e 'Cópia idêntica (mesmo conteúdo SHA-256)' $manter.Caminho }
                }
            }
        }
    }
}

function Get-Soma { param($L) [pscustomobject]@{ Quantidade = @($L).Count; Bytes = [int64](@($L) | Measure-Object Bytes -Sum).Sum } }
$resultado = [pscustomobject]@{
    Pasta = $Pasta; TotalArquivos = [int64]$res.Arquivos; TotalBytes = [int64]$res.Total; Tamanho = (Format-Tamanho $res.Total)
    ItensRaiz = $itensRaiz.Count; ArquivosRaiz = @($itensRaiz | Where-Object { -not $_.PSIsContainer }).Count; SubpastasRaiz = $subpastas.Count
    SoNaNuvem = [int64]$res.NaNuvem; Categorias = $categorias; Subpastas = $subpastas; Maiores = $maiores; GruposDuplicados = $gruposDup
    Resumo = [pscustomobject]@{
        InstaladoresAntigos = (Get-Soma $instaladores); Incompletos = (Get-Soma $incompletos); CompactadosExtraidos = (Get-Soma $extraidos)
        Duplicados = (Get-Soma $candidatosDup); Antigos = [pscustomobject]@{ Quantidade = [int64]$res.AntigosQtd; Bytes = [int64]$res.AntigosBytes }
    }
    Listas = [ordered]@{}
}

if (-not $SemSalvar) {
    $nomePasta = (Split-Path $Pasta -Leaf) -replace '[^\w\-]', '_'
    $dirSaida = Join-Path (Get-PastaDados 'relatorios') ("analise-$nomePasta-" + (New-Carimbo))
    New-Item -ItemType Directory -Path $dirSaida -Force | Out-Null
    $listas = [ordered]@{ 'instaladores-antigos' = $instaladores; 'downloads-incompletos' = $incompletos; 'compactados-ja-extraidos' = $extraidos; 'duplicados-copias-extras' = $candidatosDup; 'sem-uso-ha-muito-tempo' = $antigos }
    foreach ($k in $listas.Keys) {
        if (@($listas[$k]).Count -eq 0) { continue }
        $arq = Join-Path $dirSaida "$k.csv"
        $listas[$k] | Select-Object Caminho, Bytes, Tamanho, Modificado, Categoria, Motivo, Manter | Export-Csv -LiteralPath $arq -Delimiter ';' -NoTypeInformation -Encoding UTF8
        $resultado.Listas[$k] = $arq
    }
    Save-Json -Objeto $resultado -Caminho (Join-Path $dirSaida 'analise.json')
    $resultado | Add-Member -NotePropertyName PastaSaida -NotePropertyValue $dirSaida -Force
}

if ($Silencioso) { return $resultado }

# ------------------------------------------------------------ console --
Write-Titulo "ANÁLISE DA PASTA (somente leitura): $Pasta"
Write-Host "Total: $($res.Arquivos) arquivos, $(Format-Tamanho $res.Total) | Itens soltos na raiz: $($itensRaiz.Count) ($($resultado.ArquivosRaiz) arquivos, $($subpastas.Count) subpastas)"
if ($res.NaNuvem -gt 0) { Write-Host "Arquivos só na nuvem (OneDrive, não ocupam disco): $($res.NaNuvem)" }
Write-Secao 'Por categoria'
Write-Tabela $categorias @('Categoria', 'Quantidade', 'Tamanho')
Write-Secao "Maiores arquivos (top $TopMaiores)"
Write-Tabela $maiores @('Tamanho', 'Modificado', 'Categoria', 'Arquivo')
if ($subpastas.Count) {
    Write-Secao 'Subpastas na raiz (Projeto = código/app: mover a pasta inteira, nunca separar arquivos)'
    Write-Tabela ($subpastas | Select-Object -First 25) @('Subpasta', 'Arquivos', 'Tamanho', 'Modificada', 'Projeto')
}
Write-Secao 'Candidatos a remoção (nada foi apagado; pastas de projeto ficam de fora)'
$r = $resultado.Resumo
Write-Host (" Instaladores com mais de {0} dias : {1,5} arquivos  {2}" -f $DiasInstalador, $r.InstaladoresAntigos.Quantidade, (Format-Tamanho $r.InstaladoresAntigos.Bytes))
Write-Host (" Cópias duplicadas (extras)       : {0,5} arquivos  {1}" -f $r.Duplicados.Quantidade, (Format-Tamanho $r.Duplicados.Bytes))
Write-Host (" .zip/.rar já extraídos           : {0,5} arquivos  {1}" -f $r.CompactadosExtraidos.Quantidade, (Format-Tamanho $r.CompactadosExtraidos.Bytes))
Write-Host (" Downloads incompletos            : {0,5} arquivos  {1}" -f $r.Incompletos.Quantidade, (Format-Tamanho $r.Incompletos.Bytes))
Write-Host (" Sem modificação há {0}+ dias     : {1,5} arquivos  {2}  (só para revisão)" -f $DiasAntigo, $r.Antigos.Quantidade, (Format-Tamanho $r.Antigos.Bytes))
if ($gruposDup.Count) { Write-Secao 'Grupos de duplicados (até 15)'; Write-Tabela ($gruposDup | Select-Object -First 15) @('TamanhoCada', 'Copias', 'Manter', 'Extras') }
if (-not $SemSalvar) {
    Write-Secao 'Listas geradas (use com Remover-Arquivos.ps1 -Lista <arquivo>, após aprovação)'
    foreach ($k in $resultado.Listas.Keys) { Write-Host " $k : $($resultado.Listas[$k])" }
    Write-Host " Análise completa: $(Join-Path $resultado.PastaSaida 'analise.json')"
}
