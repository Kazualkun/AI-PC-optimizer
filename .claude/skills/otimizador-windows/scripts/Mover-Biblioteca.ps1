<#
.SYNOPSIS
    Move uma biblioteca do Windows (Documentos, Imagens, Vídeos, Músicas, Downloads, Área de Trabalho)
    para outro disco - o mesmo efeito da aba "Local" nas Propriedades da pasta, com verificação.
.DESCRIPTION
    Uso típico em PCs com SSD + HD. Etapas:
      1) Prévia (sem -Executar): tamanhos, espaço, checagens de segurança.
      2) -Executar: copia com robocopy, verifica (quantidade + bytes), só então aponta o Windows para o
         novo local (registro, com backup). Os ORIGINAIS são mantidos.
      3) Depois de perguntar ao usuário, -RemoverOriginal (prévia) e -RemoverOriginal -Executar
         apagam a pasta antiga (Lixeira por padrão).
    Recusa: pastas gerenciadas pelo OneDrive, destino no mesmo disco, destino removível/USB/rede,
    destino não vazio.
.EXAMPLE
    Mover-Biblioteca.ps1 -Biblioteca Videos -Destino 'E:\Vídeos'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Biblioteca,
    [string]$Destino,
    [switch]$RemoverOriginal,
    [ValidateSet('Lixeira', 'Definitivo')][string]$Modo = 'Lixeira',
    [switch]$Executar
)

. "$PSScriptRoot\Common.ps1"

$chaveNorm = $Biblioteca.ToLower() -replace '[íì]', 'i' -replace '[úù]', 'u' -replace '[áàâã]', 'a' -replace '\s', ''
$mapa = @{
    documentos = @{ Id = 'documentos'; Nome = 'Documentos'; Valor = 'Personal'; Alt = '{F42EE2D3-909F-4907-8871-4C22FC0BF756}' }
    imagens    = @{ Id = 'imagens'; Nome = 'Imagens'; Valor = 'My Pictures'; Alt = '{0DDD015D-B06C-45D5-8C4C-F59713854639}' }
    videos     = @{ Id = 'videos'; Nome = 'Vídeos'; Valor = 'My Video'; Alt = '{35286A68-3C57-41A1-BBB1-0EAE73D76C95}' }
    musicas    = @{ Id = 'musicas'; Nome = 'Músicas'; Valor = 'My Music'; Alt = '{A0C69A99-21C8-4671-8703-7934162FCF1D}' }
    downloads  = @{ Id = 'downloads'; Nome = 'Downloads'; Valor = '{374DE290-123F-4565-9164-39C4925E467B}'; Alt = '{7D83EE9B-2244-4E70-B1F5-5393042AF1E4}' }
    desktop    = @{ Id = 'desktop'; Nome = 'Área de Trabalho'; Valor = 'Desktop'; Alt = '{754AC886-DF64-4CBA-86B5-F7FBF4FBCEF5}' }
}
$aliases = @{ documents = 'documentos'; pictures = 'imagens'; fotos = 'imagens'; video = 'videos'; music = 'musicas'; musica = 'musicas'; areadetrabalho = 'desktop' }
if ($aliases.ContainsKey($chaveNorm)) { $chaveNorm = $aliases[$chaveNorm] }
if (-not $mapa.ContainsKey($chaveNorm)) { Write-Host "Biblioteca desconhecida: $Biblioteca (use Documentos, Imagens, Videos, Musicas, Downloads ou Desktop)"; exit 1 }
$B = $mapa[$chaveNorm]

$usf = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
$sf = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders'
$atual = [Environment]::ExpandEnvironmentVariables([string](Get-ValorRegistro $usf $B.Valor)).TrimEnd('\')

# =================================================== REMOVER ORIGINAL ==
if ($RemoverOriginal) {
    $bk = Get-ChildItem -LiteralPath (Get-PastaDados 'backups') -Filter "biblioteca-$($B.Id)-*.json" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $bk) { Write-Host 'Nenhuma movimentação desta biblioteca foi registrada pela skill. Nada a remover.'; exit 1 }
    $info = @((Get-Content -LiteralPath $bk.FullName -Raw | ConvertFrom-Json).Entradas) | Where-Object { $_.Tipo -eq 'Info' } | Select-Object -First 1
    $orig = [string]$info.Origem; $dest = [string]$info.Destino
    Write-Titulo "$(if ($Executar) { 'REMOVER PASTA ANTIGA - EXECUÇÃO' } else { 'REMOVER PASTA ANTIGA - PRÉVIA (nada será apagado)' }): $($B.Nome)"
    Write-Host "Pasta antiga: $orig"
    Write-Host "Novo local:   $dest (registro atual: $atual)"
    if ($atual -ine $dest.TrimEnd('\')) { Write-Host 'RECUSADO: o Windows não está apontando para o novo local. A pasta antiga ainda é a ativa.'; exit 2 }
    if (-not (Test-Path -LiteralPath $orig)) { Write-Host 'A pasta antiga já não existe. Nada a fazer.'; exit 0 }
    $tO = Get-TamanhoPasta $orig; $tD = Get-TamanhoPasta $dest
    Write-Host "Antiga: $($tO.Arquivos) arquivos, $(Format-Tamanho $tO.Bytes) | Nova: $($tD.Arquivos) arquivos, $(Format-Tamanho $tD.Bytes)"
    if ($tD.Arquivos -lt $tO.Arquivos -or $tD.Bytes -lt $tO.Bytes) { Write-Host 'RECUSADO: o novo local tem menos conteúdo que a pasta antiga. Verifique antes de apagar.'; exit 2 }
    Write-Host "Modo: $Modo $(if ($Modo -eq 'Lixeira') { '(se não couber na Lixeira, o Windows pede confirmação antes de apagar de vez)' } else { '(IRREVERSÍVEL)' })"
    if (-not $Executar) { Write-Host 'Para apagar após aprovação explícita do usuário, repita com -Executar.'; exit 0 }
    $livreAntes = (Get-InfoUnidade $orig).Livre
    if ($Modo -eq 'Lixeira') { Send-ParaLixeira $orig } else { Remove-Item -LiteralPath $orig -Recurse -Force -ErrorAction Stop }
    Write-Host "OK: pasta antiga removida ($Modo). Livre em $($orig.Substring(0,2)): $(Format-Tamanho $livreAntes) -> $(Format-Tamanho (Get-InfoUnidade $orig).Livre)"
    exit 0
}

# ============================================================== MOVER ==
if (-not $Destino) { Write-Host 'Informe -Destino (ex.: E:\Vídeos).'; exit 1 }
$Destino = [IO.Path]::GetFullPath($Destino).TrimEnd('\')
$problemas = @()
if ($atual -match 'OneDrive') { $problemas += 'A pasta é gerenciada pelo OneDrive (backup de pastas). Altere pelas configurações do OneDrive.' }
$uDest = Get-InfoUnidade $Destino
if (-not $uDest) { $problemas += "Unidade $($Destino.Substring(0,2)) não existe." }
elseif ($uDest.Tipo -ne 3) { $problemas += 'O destino não é um disco interno fixo (removível/rede). Bibliotecas não devem ficar em discos que podem ser desconectados.' }
if ($Destino.Substring(0, 1) -ieq $atual.Substring(0, 1)) { $problemas += 'O destino está no mesmo disco da pasta atual - mover não liberaria espaço.' }
if ($Destino.StartsWith($atual + '\', [StringComparison]::OrdinalIgnoreCase) -or $atual.StartsWith($Destino + '\', [StringComparison]::OrdinalIgnoreCase)) { $problemas += 'Destino e origem estão um dentro do outro.' }
if ((Test-Path -LiteralPath $Destino) -and @(Get-ChildItem -LiteralPath $Destino -Force -ErrorAction SilentlyContinue).Count -gt 0) { $problemas += 'A pasta de destino já existe e não está vazia. Escolha uma pasta nova/vazia.' }
$t = Get-TamanhoPasta $atual
if ($uDest -and $uDest.Livre -lt ($t.Bytes * 1.1)) { $problemas += "Espaço insuficiente no destino: precisa de $(Format-Tamanho ($t.Bytes * 1.1))." }

Write-Titulo "$(if ($Executar) { 'MOVER BIBLIOTECA - EXECUÇÃO' } else { 'MOVER BIBLIOTECA - PRÉVIA (nada será alterado)' }): $($B.Nome)"
Write-Host "Local atual: $atual ($($t.Arquivos) arquivos, $(Format-Tamanho $t.Bytes))"
Write-Host "Novo local:  $Destino (livre: $(if ($uDest) { Format-Tamanho $uDest.Livre } else { '?' }))"
Write-Host 'Etapas: 1) copiar com robocopy  2) verificar quantidade e bytes  3) apontar o Windows para o novo local (com backup)  4) originais MANTIDOS até você decidir.'
Write-Host 'Programas que usam a pasta (jogos que salvam em Documentos, por exemplo) passam a usar o novo local automaticamente.'
if ($problemas.Count) { Write-Secao 'BLOQUEADO'; $problemas | ForEach-Object { Write-Host " ! $_" }; exit 2 }
if (-not $Executar) { Write-Host ''; Write-Host 'Feche programas que estejam usando arquivos desta pasta. Para executar após aprovação do usuário, repita com -Executar.'; exit 0 }

$log = Join-Path (Get-PastaDados 'logs') ("robocopy-$($B.Id)-" + (New-Carimbo) + '.log')
Write-Host ''
Write-Host 'Copiando (pode demorar para pastas grandes)...'
$null = robocopy $atual $Destino /E /COPY:DAT /DCOPY:DAT /R:1 /W:1 /XJ /MT:8 /NP /NFL /NDL "/LOG:$log"
$rc = $LASTEXITCODE
if ($rc -ge 8) { Write-Host "FALHA na cópia (robocopy código $rc). Nada foi alterado no Windows. Veja o log: $log"; exit 3 }
$tD = Get-TamanhoPasta $Destino
if ($tD.Arquivos -lt $t.Arquivos -or $tD.Bytes -lt $t.Bytes) {
    Write-Host "VERIFICAÇÃO FALHOU: origem $($t.Arquivos) arq/$(Format-Tamanho $t.Bytes), destino $($tD.Arquivos) arq/$(Format-Tamanho $tD.Bytes)."
    Write-Host "Nada foi alterado no Windows. Arquivos em uso podem não ter sido copiados. Log: $log"
    exit 3
}
Write-Host "Cópia verificada: $($tD.Arquivos) arquivos, $(Format-Tamanho $tD.Bytes)."

$bk = New-Backup "biblioteca-$($B.Id)"
Add-BackupEntrada $bk @{ Tipo = 'Info'; Descricao = "Biblioteca $($B.Nome) movida de '$atual' para '$Destino'. Para voltar: restaure este backup e copie os arquivos de volta."; Origem = $atual; Destino = $Destino; Admin = $false }
foreach ($ch in @($usf, $sf)) {
    foreach ($nome in @($B.Valor, $B.Alt)) {
        $existe = (Get-Item -LiteralPath $ch).GetValueNames() -contains $nome
        if ($nome -eq $B.Valor -or $existe) {
            $tipo = if ($ch -eq $usf) { 'ExpandString' } else { 'String' }
            Set-RegistroComBackup -Backup $bk -Chave $ch -Nome $nome -Valor $Destino -Tipo $tipo -Descricao "Local da biblioteca $($B.Nome)"
        }
    }
}
Write-Host "OK: o Windows agora usa $Destino para $($B.Nome)."
Write-Host 'Saia e entre na conta (ou reinicie) para o Explorador e os programas assumirem o novo local.'
Write-Host "Backup: $($bk.Arquivo)"
Write-Host "Os originais continuam em $atual."
Write-Host 'PERGUNTA OBRIGATÓRIA AO USUÁRIO: "Deseja apagar o arquivo original antigo ou mantê-lo?"'
Write-Host "Se apagar (após sair/entrar na conta): Mover-Biblioteca.ps1 -Biblioteca $($B.Id) -RemoverOriginal (prévia) e depois -Executar."
