<#
.SYNOPSIS
    Gera um PLANO de organização (CSV origem -> destino) - SOMENTE LEITURA. Nada é copiado ou movido.
.DESCRIPTION
    Classifica os arquivos da pasta de origem por tipo e propõe destinos na estrutura padrão
    (references/estrutura-pastas.md). O plano é um CSV editável: o Claude pode refinar destinos
    (ex.: "Boleto*.pdf" -> Documentos\Financeiro) antes da execução.
    Executar o plano: Executar-Organizacao.ps1 -Plano <csv> (prévia) e depois com -Executar.
.PARAMETER Origem
    Pasta bagunçada (caminho ou nome conhecido: Downloads, "Área de Trabalho"...).
.PARAMETER DestinoBase
    Raiz alternativa para a estrutura (ex.: 'E:\Arquivos' em um HD, ou um disco externo).
    Sem ele, usa as bibliotecas do Windows (Documentos, Imagens, Vídeos, Músicas, Downloads).
.PARAMETER Estrategia
    PorTipoEData (padrão: fotos/vídeos em subpastas por ano) ou PorTipo.
.PARAMETER IncluirSubpastas
    Também classifica arquivos dentro de subpastas. Sem isso, subpastas viram linhas "Revisar".
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Origem,
    [string]$DestinoBase,
    [ValidateSet('PorTipoEData', 'PorTipo')][string]$Estrategia = 'PorTipoEData',
    [switch]$IncluirSubpastas,
    [string[]]$Categorias,
    [string[]]$Excluir
)

. "$PSScriptRoot\Common.ps1"
. "$PSScriptRoot\Catalogo.ps1"

$Origem = Resolve-PastaConhecida $Origem
if (-not (Test-Path -LiteralPath $Origem -PathType Container)) { Write-Host "Pasta de origem não encontrada: $Origem"; exit 1 }
$Origem = (Resolve-Path -LiteralPath $Origem).ProviderPath.TrimEnd('\')
$Categorias = Split-Lista $Categorias
$Excluir = Split-Lista $Excluir

if ($DestinoBase) {
    $DestinoBase = $DestinoBase.TrimEnd('\')
    $Raizes = @{
        Documentos = Join-Path $DestinoBase 'Documentos'; Imagens = Join-Path $DestinoBase 'Imagens'; Videos = Join-Path $DestinoBase 'Vídeos'
        Musicas = Join-Path $DestinoBase 'Músicas'; Downloads = Join-Path $DestinoBase 'Downloads'
    }
} else {
    $Raizes = @{
        Documentos = [Environment]::GetFolderPath('MyDocuments'); Imagens = [Environment]::GetFolderPath('MyPictures'); Videos = [Environment]::GetFolderPath('MyVideos')
        Musicas = [Environment]::GetFolderPath('MyMusic'); Downloads = (Get-PastaDownloads)
    }
}

$nuvem = 0x400000 -bor 0x1000 -bor 0x40000
$destinosUsados = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
$plano = New-Object System.Collections.Generic.List[object]

function Get-DestinoLivre {
    # Evita sobrescrever: "arquivo.pdf" -> "arquivo (2).pdf" se já existir (no disco ou no próprio plano).
    param([string]$Pasta, [string]$Nome)
    $base = [IO.Path]::GetFileNameWithoutExtension($Nome); $ext = [IO.Path]::GetExtension($Nome)
    $cand = Join-Path $Pasta $Nome; $n = 2
    while ($destinosUsados.Contains($cand) -or (Test-Path -LiteralPath $cand)) { $cand = Join-Path $Pasta "$base ($n)$ext"; $n++ }
    return $cand
}

function Add-Linha {
    param([string]$Tipo, [string]$Acao, [string]$Categoria, [string]$Orig, [string]$Dest, [int64]$Bytes, [datetime]$Mod, [string]$Motivo)
    if ($Dest) { [void]$destinosUsados.Add($Dest) }
    $plano.Add([pscustomobject]@{
            Tipo = $Tipo; Acao = $Acao; Categoria = $Categoria; Origem = $Orig; Destino = $Dest
            Bytes = $Bytes; Tamanho = (Format-Tamanho $Bytes); Modificado = $Mod.ToString('yyyy-MM-dd'); Motivo = $Motivo
        })
}

# ----------------------------------------------------------- arquivos --
$arquivos = @(Get-ChildItem -LiteralPath $Origem -File -Force -ErrorAction SilentlyContinue | ForEach-Object { [IO.FileInfo]$_.FullName })
$pastasProjeto = @()
if ($IncluirSubpastas) {
    foreach ($sp in (Get-ChildItem -LiteralPath $Origem -Directory -Force -ErrorAction SilentlyContinue)) {
        if (([int]$sp.Attributes -band [int][IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
        if (Test-PastaProjeto $sp.FullName) { $pastasProjeto += $sp; continue }
        $arquivos += @(Get-ChildItem -LiteralPath $sp.FullName -File -Force -Recurse -ErrorAction SilentlyContinue |
            Where-Object { ($_.FullName -notmatch $Script:PadraoPastaDev) } | ForEach-Object { [IO.FileInfo]$_.FullName })
    }
}

foreach ($f in $arquivos) {
    if ($f.Name -in @('desktop.ini', 'Thumbs.db')) { continue }
    if (([int]$f.Attributes -band [int][IO.FileAttributes]::Hidden) -ne 0 -and ([int]$f.Attributes -band [int][IO.FileAttributes]::System) -ne 0) { continue }
    $pular = $false
    foreach ($e in $Excluir) { if ($f.Name -like $e) { $pular = $true } }
    if ($pular) { Add-Linha 'Arquivo' 'Manter' '' $f.FullName '' $f.Length $f.LastWriteTime 'Excluído pelo filtro'; continue }
    if (([int]$f.Attributes -band $nuvem) -ne 0) { Add-Linha 'Arquivo' 'Manter' '' $f.FullName '' $f.Length $f.LastWriteTime 'Arquivo só na nuvem (OneDrive) - não mexer'; continue }

    $cat = Get-CategoriaArquivo $f.Extension
    if ($Categorias.Count -gt 0 -and $Categorias -notcontains $cat) { Add-Linha 'Arquivo' 'Manter' $cat $f.FullName '' $f.Length $f.LastWriteTime 'Categoria fora do filtro'; continue }

    $regra = Get-RegraDestino -Categoria $cat -Arquivo $f -Raizes $Raizes -Estrategia $Estrategia
    if ($regra.Acao -ne 'Copiar') { Add-Linha 'Arquivo' $regra.Acao $cat $f.FullName '' $f.Length $f.LastWriteTime $regra.Motivo; continue }

    # Se veio de subpasta, preserva a subpasta relativa dentro do destino (não mistura conteúdos).
    $pastaDest = $regra.Pasta
    if ($IncluirSubpastas -and $f.DirectoryName.Length -gt $Origem.Length) {
        $relDir = $f.DirectoryName.Substring($Origem.Length + 1)
        $pastaDest = Join-Path $pastaDest $relDir
    }
    if ($f.DirectoryName.TrimEnd('\') -ieq $pastaDest.TrimEnd('\')) { Add-Linha 'Arquivo' 'Manter' $cat $f.FullName '' $f.Length $f.LastWriteTime 'Já está no lugar certo'; continue }

    $alvoDireto = Join-Path $pastaDest $f.Name
    if ((Test-Path -LiteralPath $alvoDireto) -and -not $destinosUsados.Contains($alvoDireto)) {
        $ex = Get-Item -LiteralPath $alvoDireto -Force
        if ($ex.Length -eq $f.Length -and (Get-FileHash -LiteralPath $alvoDireto -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash) {
            Add-Linha 'Arquivo' 'JaExiste' $cat $f.FullName $alvoDireto $f.Length $f.LastWriteTime 'Cópia idêntica já existe no destino (o original pode ser apagado depois)'
            continue
        }
    }
    $dest = Get-DestinoLivre -Pasta $pastaDest -Nome $f.Name
    $motivo = if ($dest -ne $alvoDireto) { 'Nome já existia no destino - renomeado para não sobrescrever' } else { '' }
    Add-Linha 'Arquivo' 'Copiar' $cat $f.FullName $dest $f.Length $f.LastWriteTime $motivo
}

# ------------------------------------------------------ subpastas (raiz) --
$subRevisar = if ($IncluirSubpastas) { $pastasProjeto } else {
    @(Get-ChildItem -LiteralPath $Origem -Directory -Force -ErrorAction SilentlyContinue | Where-Object { ([int]$_.Attributes -band [int][IO.FileAttributes]::ReparsePoint) -eq 0 })
}
foreach ($sp in $subRevisar) {
    $t = Get-TamanhoPasta $sp.FullName
    $ehProj = Test-PastaProjeto $sp.FullName
    $motivo = if ($ehProj) { "Projeto/app com $($t.Arquivos) arquivos - mover a PASTA INTEIRA (ex.: Documentos\Projetos), nunca separar" }
              else { "Subpasta com $($t.Arquivos) arquivos - decidir destino (ex.: Documentos\Projetos) ou usar -IncluirSubpastas" }
    $cat = if ($ehProj) { 'Projeto' } else { 'Pasta' }
    Add-Linha 'Pasta' 'Revisar' $cat $sp.FullName '' $t.Bytes $sp.LastWriteTime $motivo
}

# ------------------------------------------------------------- saída --
$arqPlano = Join-Path (Get-PastaDados 'planos') ("plano-" + ((Split-Path $Origem -Leaf) -replace '[^\w\-]', '_') + '-' + (New-Carimbo) + '.csv')
$plano | Export-Csv -LiteralPath $arqPlano -Delimiter ';' -NoTypeInformation -Encoding UTF8

$copiar = @($plano | Where-Object { $_.Acao -eq 'Copiar' })
$bytesCopiar = [int64](($copiar | Measure-Object Bytes -Sum).Sum)

Write-Titulo "PLANO DE ORGANIZAÇÃO (prévia - nada foi copiado): $Origem"
Write-Host "Estratégia: $Estrategia | Destino: $(if ($DestinoBase) { $DestinoBase } else { 'bibliotecas do Windows' })"
Write-Secao 'Resumo por ação'
Write-Tabela ($plano | Group-Object Acao | ForEach-Object { [pscustomobject]@{ Acao = $_.Name; Itens = $_.Count; Tamanho = (Format-Tamanho ([int64](($_.Group | Measure-Object Bytes -Sum).Sum))) } }) @('Acao', 'Itens', 'Tamanho')
Write-Secao 'Para onde vão os arquivos (ação Copiar)'
$porDestino = $copiar | Group-Object { Split-Path $_.Destino -Parent } | ForEach-Object {
    [pscustomobject]@{ PastaDestino = $_.Name; Arquivos = $_.Count; Tamanho = (Format-Tamanho ([int64](($_.Group | Measure-Object Bytes -Sum).Sum))) }
} | Sort-Object PastaDestino
Write-Tabela $porDestino @('PastaDestino', 'Arquivos', 'Tamanho')

$revisar = @($plano | Where-Object { $_.Acao -eq 'Revisar' })
if ($revisar.Count) { Write-Secao 'Itens para o usuário decidir (Revisar)'; Write-Tabela ($revisar | Select-Object -First 30) @('Tipo', 'Tamanho', 'Origem', 'Motivo') }
$ja = @($plano | Where-Object { $_.Acao -eq 'JaExiste' })
if ($ja.Count) { Write-Host ''; Write-Host "$($ja.Count) arquivo(s) já têm cópia idêntica no destino (não serão copiados; o original pode ser apagado depois)." }

Write-Secao 'Espaço'
$mesmoVolume = $true
foreach ($grp in ($copiar | Group-Object { $_.Destino.Substring(0, 1).ToUpper() })) {
    $u = Get-InfoUnidade $grp.Name
    $need = [int64](($grp.Group | Measure-Object Bytes -Sum).Sum)
    if ($grp.Name -ne $Origem.Substring(0, 1).ToUpper()) { $mesmoVolume = $false }
    $ok = if ($u -and $u.Livre -gt ($need * 1.1)) { 'OK' } else { 'INSUFICIENTE' }
    Write-Host " Unidade $($grp.Name): precisa de $(Format-Tamanho $need) para COPIAR; livre $(if ($u) { Format-Tamanho $u.Livre } else { '?' }) -> $ok"
}
if ($mesmoVolume -and $copiar.Count) {
    Write-Host ' Origem e destino estão no MESMO disco: copiar ocupa espaço extra até os originais serem apagados.'
    Write-Host ' Alternativa (só com aprovação explícita): -Modo Mover = instantâneo e sem espaço extra, mas não mantém os originais.'
}
Write-Host ''
Write-Host "Plano salvo (CSV editável): $arqPlano"
Write-Host "Prévia da execução:  Executar-Organizacao.ps1 -Plano '$arqPlano'"
