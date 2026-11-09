# =============================================================================
#  Catalogo.ps1 - fonte única de verdade da skill "otimizador-windows".
#  Tudo que o diagnóstico mede e o que os scripts de execução podem fazer está
#  descrito aqui, com nível de risco e explicação em linguagem simples.
#  Apenas definições: nada é alterado ao carregar este arquivo.
# =============================================================================

# ------------------------------------------------- categorias de arquivo --

$Script:CategoriasArquivo = [ordered]@{
    'Imagens'               = @('.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.heic', '.heif', '.tif', '.tiff', '.raw', '.cr2', '.cr3', '.nef', '.arw', '.dng', '.svg', '.ico', '.psd', '.ai', '.xcf', '.jfif', '.avif')
    'Vídeos'                = @('.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.webm', '.m4v', '.mpg', '.mpeg', '.3gp', '.ts', '.m2ts', '.vob')
    'Músicas'               = @('.mp3', '.wav', '.flac', '.aac', '.ogg', '.m4a', '.wma', '.opus', '.mid', '.midi', '.aiff')
    'Documentos'            = @('.pdf', '.doc', '.docx', '.odt', '.rtf', '.txt', '.md', '.epub', '.mobi', '.pages', '.xps', '.oxps')
    'Planilhas'             = @('.xls', '.xlsx', '.xlsm', '.xlsb', '.ods', '.csv', '.numbers')
    'Apresentações'         = @('.ppt', '.pptx', '.pps', '.ppsx', '.odp', '.key')
    'Compactados'           = @('.zip', '.rar', '.7z', '.tar', '.gz', '.bz2', '.xz', '.tgz', '.cab')
    'Instaladores'          = @('.exe', '.msi', '.msix', '.msixbundle', '.appx', '.appxbundle', '.apk')
    'Imagens de Disco'      = @('.iso', '.img', '.vhd', '.vhdx', '.dmg', '.bin', '.cue')
    'Código'                = @('.py', '.js', '.ts', '.html', '.htm', '.css', '.json', '.xml', '.ps1', '.bat', '.cmd', '.sh', '.java', '.c', '.cpp', '.h', '.cs', '.sql', '.yml', '.yaml', '.ipynb', '.php', '.go', '.rs')
    'Fontes'                = @('.ttf', '.otf', '.woff', '.woff2')
    'Torrents'              = @('.torrent')
    'Atalhos'               = @('.lnk', '.url')
    'Downloads Incompletos' = @('.crdownload', '.part', '.partial', '.download', '.opdownload')
}

$Script:MapaExtensao = @{}
foreach ($k in $Script:CategoriasArquivo.Keys) { foreach ($e in $Script:CategoriasArquivo[$k]) { $Script:MapaExtensao[$e] = $k } }

function Get-CategoriaArquivo {
    param([string]$Extensao)
    $c = $Script:MapaExtensao[$Extensao.ToLower()]
    if ($c) { return $c }
    return 'Outros'
}

function Get-RegraDestino {
    # Decide para onde um arquivo vai na estrutura proposta (ver references/estrutura-pastas.md).
    param([string]$Categoria, [IO.FileInfo]$Arquivo, [hashtable]$Raizes, [string]$Estrategia)
    $ano = $Arquivo.LastWriteTime.ToString('yyyy')
    $porData = ($Estrategia -eq 'PorTipoEData')
    switch ($Categoria) {
        'Imagens' {
            if ($Arquivo.Name -match '^(Screenshot|Captura de tela|Captura|Screen ?Shot|Print|Snip|Recorte)') {
                return @{ Acao = 'Copiar'; Pasta = (Join-Path $Raizes.Imagens "Capturas de Tela\$ano") }
            }
            if ($Arquivo.Name -match '(wallpaper|papel de parede)') { return @{ Acao = 'Copiar'; Pasta = (Join-Path $Raizes.Imagens 'Papéis de Parede') } }
            if ($porData) { return @{ Acao = 'Copiar'; Pasta = (Join-Path $Raizes.Imagens $ano) } }
            return @{ Acao = 'Copiar'; Pasta = (Join-Path $Raizes.Imagens 'Diversas') }
        }
        'Vídeos' {
            if ($Arquivo.Name -match '(Grava[cç][aã]o de Tela|Screen Recording|Captura)') { return @{ Acao = 'Copiar'; Pasta = (Join-Path $Raizes.Videos "Gravações de Tela\$ano") } }
            if ($porData) { return @{ Acao = 'Copiar'; Pasta = (Join-Path $Raizes.Videos $ano) } }
            return @{ Acao = 'Copiar'; Pasta = (Join-Path $Raizes.Videos 'Diversos') }
        }
        'Músicas'               { return @{ Acao = 'Copiar'; Pasta = (Join-Path $Raizes.Musicas 'Importadas') } }
        'Documentos' {
            if ($Arquivo.Extension -ieq '.pdf') { return @{ Acao = 'Copiar'; Pasta = (Join-Path $Raizes.Documentos '_Triagem\PDFs') } }
            return @{ Acao = 'Copiar'; Pasta = (Join-Path $Raizes.Documentos '_Triagem\Textos') }
        }
        'Planilhas'             { return @{ Acao = 'Copiar'; Pasta = (Join-Path $Raizes.Documentos '_Triagem\Planilhas') } }
        'Apresentações'         { return @{ Acao = 'Copiar'; Pasta = (Join-Path $Raizes.Documentos '_Triagem\Apresentações') } }
        'Código'                { return @{ Acao = 'Copiar'; Pasta = (Join-Path $Raizes.Documentos '_Triagem\Código') } }
        'Compactados'           { return @{ Acao = 'Copiar'; Pasta = (Join-Path $Raizes.Downloads 'Compactados') } }
        'Instaladores'          { return @{ Acao = 'Copiar'; Pasta = (Join-Path $Raizes.Downloads 'Instaladores') } }
        'Imagens de Disco'      { return @{ Acao = 'Copiar'; Pasta = (Join-Path $Raizes.Downloads 'Imagens de Disco') } }
        'Fontes'                { return @{ Acao = 'Copiar'; Pasta = (Join-Path $Raizes.Downloads 'Fontes') } }
        'Torrents'              { return @{ Acao = 'Copiar'; Pasta = (Join-Path $Raizes.Downloads 'Torrents') } }
        'Atalhos'               { return @{ Acao = 'Manter'; Motivo = 'Atalhos ficam onde estão' } }
        'Downloads Incompletos' { return @{ Acao = 'Revisar'; Motivo = 'Download incompleto/interrompido - provavelmente pode ser apagado' } }
        default                 { return @{ Acao = 'Copiar'; Pasta = (Join-Path $Raizes.Documentos '_Triagem\Outros') } }
    }
}

# ------------------------------------------------------- itens de limpeza --
# Tipo: Arquivos (padrão) | Lixeira | CleanMgr | DISM | OtimizacaoEntrega
# Alvo: Caminho (aceita curinga *), DiasMinimos, Filtro, SemRecursao, Processo (app que precisa estar fechado), Admin

$Script:CatalogoLimpeza = @(
    @{ Id = 'TempUsuario'; Nome = 'Temporários do usuário (%TEMP%)'; Risco = 'Baixo'
        Explicacao = 'Arquivos que programas deixam para trás. Só apaga o que não é modificado há 2+ dias; arquivos em uso são pulados automaticamente.'
        Alvos = @(@{ Caminho = $env:TEMP; DiasMinimos = 2 }) },

    @{ Id = 'TempWindows'; Nome = 'Temporários do Windows (C:\Windows\Temp)'; Risco = 'Baixo'
        Explicacao = 'Temporários de instaladores e serviços do sistema. Mesma regra de 2+ dias.'
        Alvos = @(@{ Caminho = "$env:windir\Temp"; DiasMinimos = 2; Admin = $true }) },

    @{ Id = 'Lixeira'; Nome = 'Esvaziar a Lixeira'; Risco = 'Médio'; Tipo = 'Lixeira'
        Explicacao = 'Apaga DEFINITIVAMENTE o que está na Lixeira. Confira antes se não há nada que você queira recuperar.' },

    @{ Id = 'CacheNavegadores'; Nome = 'Cache dos navegadores (Chrome, Edge, Brave, Opera, Firefox)'; Risco = 'Baixo'
        Explicacao = 'Só cache de páginas, imagens e código. NÃO mexe em senhas, histórico, favoritos nem cookies (você continua logado). O navegador precisa estar FECHADO.'
        Alvos = @(
            @{ Caminho = "$env:LOCALAPPDATA\Google\Chrome\User Data\*\Cache"; Processo = 'chrome' },
            @{ Caminho = "$env:LOCALAPPDATA\Google\Chrome\User Data\*\Code Cache"; Processo = 'chrome' },
            @{ Caminho = "$env:LOCALAPPDATA\Google\Chrome\User Data\*\GPUCache"; Processo = 'chrome' },
            @{ Caminho = "$env:LOCALAPPDATA\Google\Chrome\User Data\ShaderCache"; Processo = 'chrome' },
            @{ Caminho = "$env:LOCALAPPDATA\Google\Chrome\User Data\GrShaderCache"; Processo = 'chrome' },
            @{ Caminho = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\*\Cache"; Processo = 'msedge' },
            @{ Caminho = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\*\Code Cache"; Processo = 'msedge' },
            @{ Caminho = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\*\GPUCache"; Processo = 'msedge' },
            @{ Caminho = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\ShaderCache"; Processo = 'msedge' },
            @{ Caminho = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\GrShaderCache"; Processo = 'msedge' },
            @{ Caminho = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\*\Cache"; Processo = 'brave' },
            @{ Caminho = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\*\Code Cache"; Processo = 'brave' },
            @{ Caminho = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\*\GPUCache"; Processo = 'brave' },
            @{ Caminho = "$env:LOCALAPPDATA\Opera Software\*\Cache"; Processo = 'opera' },
            @{ Caminho = "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles\*\cache2"; Processo = 'firefox' }
        ) },

    @{ Id = 'CacheApps'; Nome = 'Cache de apps (Discord, Teams clássico, Slack, Spotify, VS Code)'; Risco = 'Baixo'
        Explicacao = 'Caches que esses apps recriam sozinhos. O Spotify pode precisar baixar de novo as músicas salvas offline. Feche os apps antes.'
        Alvos = @(
            @{ Caminho = "$env:APPDATA\discord\Cache"; Processo = 'Discord' },
            @{ Caminho = "$env:APPDATA\discord\Code Cache"; Processo = 'Discord' },
            @{ Caminho = "$env:APPDATA\discord\GPUCache"; Processo = 'Discord' },
            @{ Caminho = "$env:APPDATA\Microsoft\Teams\Cache"; Processo = 'Teams' },
            @{ Caminho = "$env:APPDATA\Microsoft\Teams\Code Cache"; Processo = 'Teams' },
            @{ Caminho = "$env:APPDATA\Microsoft\Teams\GPUCache"; Processo = 'Teams' },
            @{ Caminho = "$env:APPDATA\Slack\Cache"; Processo = 'slack' },
            @{ Caminho = "$env:APPDATA\Slack\Code Cache"; Processo = 'slack' },
            @{ Caminho = "$env:APPDATA\Slack\GPUCache"; Processo = 'slack' },
            @{ Caminho = "$env:LOCALAPPDATA\Spotify\Data"; Processo = 'Spotify' },
            @{ Caminho = "$env:LOCALAPPDATA\Spotify\Storage"; Processo = 'Spotify' },
            @{ Caminho = "$env:APPDATA\Code\Cache"; Processo = 'Code' },
            @{ Caminho = "$env:APPDATA\Code\CachedData"; Processo = 'Code' },
            @{ Caminho = "$env:APPDATA\Code\CachedExtensionVSIXs"; Processo = 'Code' }
        ) },

    @{ Id = 'CacheMiniaturas'; Nome = 'Cache de miniaturas do Explorador'; Risco = 'Baixo'
        Explicacao = 'O Windows recria as miniaturas conforme você abre as pastas. Arquivos em uso pelo Explorador são pulados.'
        Alvos = @(@{ Caminho = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"; Filtro = 'thumbcache_*.db'; SemRecursao = $true }) },

    @{ Id = 'CacheShaders'; Nome = 'Cache de shaders da placa de vídeo (DirectX/NVIDIA/AMD/Intel)'; Risco = 'Baixo'
        Explicacao = 'Recriado automaticamente. Jogos podem engasgar um pouco nos primeiros minutos enquanto recompilam os shaders.'
        Alvos = @(
            "$env:LOCALAPPDATA\D3DSCache", "$env:LOCALAPPDATA\NVIDIA\DXCache", "$env:LOCALAPPDATA\NVIDIA\GLCache",
            "$env:USERPROFILE\AppData\LocalLow\NVIDIA\PerDriverVersion\DXCache", "$env:USERPROFILE\AppData\LocalLow\NVIDIA\PerDriverVersion\GLCache",
            "$env:LOCALAPPDATA\AMD\DxCache", "$env:LOCALAPPDATA\AMD\DxcCache", "$env:LOCALAPPDATA\AMD\GLCache", "$env:LOCALAPPDATA\AMD\VkCache",
            "$env:LOCALAPPDATA\Intel\ShaderCache"
        ) },

    @{ Id = 'RelatoriosErro'; Nome = 'Relatórios de erro e despejos de memória (crash dumps)'; Risco = 'Baixo'
        Explicacao = 'Registros de travamentos antigos. Só têm utilidade se você estiver investigando um problema junto com um suporte técnico.'
        Alvos = @(
            @{ Caminho = "$env:LOCALAPPDATA\CrashDumps" },
            @{ Caminho = "$env:LOCALAPPDATA\Microsoft\Windows\WER" },
            @{ Caminho = "$env:ProgramData\Microsoft\Windows\WER"; Admin = $true },
            @{ Caminho = "$env:windir\Minidump"; Admin = $true },
            @{ Caminho = "$env:windir\MEMORY.DMP"; Admin = $true },
            @{ Caminho = "$env:windir\LiveKernelReports"; Filtro = '*.dmp'; Admin = $true }
        ) },

    @{ Id = 'CacheWindowsUpdate'; Nome = 'Downloads antigos do Windows Update'; Risco = 'Baixo'
        Explicacao = 'Pacotes de atualização já instalados. O serviço Windows Update é parado durante a limpeza e religado logo depois.'
        Alvos = @(@{ Caminho = "$env:windir\SoftwareDistribution\Download"; Admin = $true })
        PararServicos = @('wuauserv', 'bits') },

    @{ Id = 'OtimizacaoEntrega'; Nome = 'Cache da Otimização de Entrega (Delivery Optimization)'; Risco = 'Baixo'; Tipo = 'OtimizacaoEntrega'
        Explicacao = 'Cópias de atualizações guardadas para compartilhar com outros PCs. Pode ser apagado com o comando oficial do Windows.'
        Alvos = @(@{ Caminho = "$env:windir\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache"; Admin = $true }) },

    @{ Id = 'InstaladoresDrivers'; Nome = 'Sobras de instaladores de driver (NVIDIA/AMD)'; Risco = 'Baixo'
        Explicacao = 'Pastas que os instaladores de driver extraem e esquecem. O driver instalado continua funcionando.'
        Alvos = @(
            @{ Caminho = "$env:ProgramData\NVIDIA Corporation\Downloader"; Admin = $true },
            @{ Caminho = "$env:SystemDrive\NVIDIA"; Admin = $true },
            @{ Caminho = "$env:SystemDrive\AMD"; Admin = $true }
        ) },

    @{ Id = 'CacheDev'; Nome = 'Cache de ferramentas de programação (npm, pip, Yarn, NuGet)'; Risco = 'Baixo'
        Explicacao = 'Pacotes baixados que as ferramentas baixam de novo quando precisarem.'
        Alvos = @("$env:LOCALAPPDATA\npm-cache", "$env:LOCALAPPDATA\pip\Cache", "$env:LOCALAPPDATA\Yarn\Cache", "$env:LOCALAPPDATA\NuGet\v3-cache", "$env:LOCALAPPDATA\NuGet\Cache") },

    @{ Id = 'LimpezaDiscoWindows'; Nome = 'Limpeza de Disco do Windows (arquivos de sistema)'; Risco = 'Baixo'; Tipo = 'CleanMgr'
        Explicacao = 'Usa a ferramenta oficial (cleanmgr) para remover sobras de atualizações, instalação anterior do Windows (Windows.old - impede voltar para a versão anterior), logs de upgrade e pacotes de driver antigos. NÃO remove a pasta Downloads, a Lixeira nem os arquivos de reinstalação do Windows.'
        Alvos = @(
            @{ Caminho = "$env:SystemDrive\Windows.old"; Admin = $true },
            @{ Caminho = "$env:SystemDrive\`$Windows.~BT"; Admin = $true },
            @{ Caminho = "$env:SystemDrive\`$Windows.~WS"; Admin = $true }
        ) },

    @{ Id = 'ComponentesWindows'; Nome = 'Limpeza dos componentes do Windows (WinSxS) via DISM'; Risco = 'Baixo'; Tipo = 'DISM'
        Explicacao = 'Remove versões substituídas de componentes com a ferramenta oficial DISM. Leva de 5 a 30 minutos. Não usa /ResetBase, então você continua podendo desinstalar atualizações.' }
)

# Handlers do cleanmgr usados no item LimpezaDiscoWindows (NUNCA incluir: DownloadsFolder, Recycle Bin, Windows ESD installation files, Language Pack)
$Script:HandlersCleanMgr = @(
    'Active Setup Temp Folders', 'Delivery Optimization Files', 'Device Driver Packages', 'Downloaded Program Files',
    'Internet Cache Files', 'Old ChkDsk Files', 'Previous Installations', 'Setup Log Files',
    'System error memory dump files', 'System error minidump files', 'Temporary Files', 'Temporary Setup Files',
    'Thumbnail Cache', 'Update Cleanup', 'Upgrade Discarded Files', 'Windows Error Reporting Files',
    'Windows Error Reporting Archive Files', 'Windows Error Reporting Queue Files', 'Windows Error Reporting System Archive Files',
    'Windows Error Reporting System Queue Files', 'Windows Upgrade Log Files', 'D3D Shader Cache'
)

function Get-ItemLimpeza {
    param([string]$Id)
    return ($Script:CatalogoLimpeza | Where-Object { $_.Id -eq $Id } | Select-Object -First 1)
}

function Get-AlvosExpandidos {
    param($Item)
    $saida = @()
    foreach ($a in @($Item.Alvos)) {
        if (-not $a) { continue }
        $h = if ($a -is [hashtable]) { $a } else { @{ Caminho = [string]$a } }
        if (-not $h.Caminho) { continue }
        $caminhos = if ($h.Caminho -match '[\*\?]') {
            @(Get-Item -Path $h.Caminho -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
        } else { @($h.Caminho) }
        foreach ($c in $caminhos) {
            $filtro = if ($h.Filtro) { $h.Filtro } else { '*' }
            $saida += [pscustomobject]@{
                Caminho = $c; DiasMinimos = [int]$h.DiasMinimos; Filtro = $filtro
                SemRecursao = [bool]$h.SemRecursao; Processo = $h.Processo; Admin = [bool]$h.Admin
            }
        }
    }
    return $saida
}

function Get-TamanhoLixeira {
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $tot = [int64]0
    foreach ($v in (Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction SilentlyContinue)) {
        $t = Get-TamanhoPasta -Caminho "$($v.DeviceID)\`$Recycle.Bin\$sid"
        $tot += $t.Bytes
    }
    return $tot
}

function Get-ItensLixeira {
    # Lista o conteúdo da Lixeira (maiores primeiro) para o usuário conferir antes de esvaziar.
    param([int]$Top = 15)
    try {
        $rb = (New-Object -ComObject Shell.Application).Namespace(10)
        $itens = @($rb.Items())
        $lista = foreach ($i in $itens) {
            [pscustomobject]@{ Nome = $i.Name; Bytes = [int64]$i.Size; Tamanho = $rb.GetDetailsOf($i, 3); Excluido = $rb.GetDetailsOf($i, 2); LocalOriginal = $rb.GetDetailsOf($i, 1) }
        }
        return [pscustomobject]@{ Quantidade = $itens.Count; Maiores = @($lista | Sort-Object Bytes -Descending | Select-Object -First $Top) }
    } catch { return [pscustomobject]@{ Quantidade = 0; Maiores = @() } }
}

function Measure-ItemLimpeza {
    param($Item, [bool]$EhAdmin)
    $tipo = if ($Item.Tipo) { $Item.Tipo } else { 'Arquivos' }
    $res = [pscustomobject]@{
        Id = $Item.Id; Nome = $Item.Nome; Risco = $Item.Risco; Tipo = $tipo; Bytes = [int64]0; Arquivos = 0
        RequerAdmin = ($tipo -in @('CleanMgr', 'DISM', 'OtimizacaoEntrega')); MedicaoCompleta = $true; Observacao = ''; Alvos = @()
    }
    switch ($tipo) {
        'Lixeira' { $res.Bytes = Get-TamanhoLixeira }
        'DISM' { $res.MedicaoCompleta = $false; $res.Observacao = 'Ganho típico entre 0,5 e 5 GB (a medição exata exige admin e leva ~2 min).' }
        default {
            foreach ($a in (Get-AlvosExpandidos $Item)) {
                if ($a.Admin) { $res.RequerAdmin = $true }
                $t = Get-TamanhoPasta -Caminho $a.Caminho -DiasMinimos $a.DiasMinimos -Filtro $a.Filtro -SemRecursao:$a.SemRecursao
                if (-not $t.Existe) { continue }
                $estado = 'OK'
                if ($t.Erros -gt 0 -and -not $EhAdmin) { $estado = 'Medição parcial (sem permissão)'; $res.MedicaoCompleta = $false }
                if ($a.Processo -and (Get-Process -Name $a.Processo -ErrorAction SilentlyContinue)) { $estado = "App aberto ($($a.Processo)) - feche antes" }
                $res.Bytes += $t.Bytes
                $res.Arquivos += $t.Arquivos
                $res.Alvos += [pscustomobject]@{ Caminho = $a.Caminho; Bytes = $t.Bytes; Tamanho = (Format-Tamanho $t.Bytes); Arquivos = $t.Arquivos; Admin = $(if ($a.Admin) { 'sim' } else { 'não' }); Estado = $estado }
            }
            if (-not $res.MedicaoCompleta -and -not $res.Observacao) { $res.Observacao = 'Valor real pode ser maior: parte das pastas só é legível como administrador.' }
        }
    }
    return $res
}

# --------------------------------------------------------------- serviços --
# Conservador de propósito: só serviços cuja desativação é amplamente segura.
# Condicao: SemImpressora | SemBluetooth. Corporativo: não recomendar em PC gerenciado pela empresa.

$Script:CatalogoServicos = @(
    @{ Nome = 'DiagTrack'; Exibicao = 'Telemetria (Experiências do Usuário Conectado)'; Recomendado = 'Disabled'; Risco = 'Baixo'; Corporativo = $true
        Motivo = 'Envia dados de uso à Microsoft; consome CPU, disco e rede em segundo plano.' },
    @{ Nome = 'dmwappushservice'; Exibicao = 'Roteamento de mensagens push WAP'; Recomendado = 'Disabled'; Risco = 'Médio'; Corporativo = $true
        Motivo = 'Auxiliar da telemetria. Necessário para gerenciamento corporativo (Intune/MDM).' },
    @{ Nome = 'MapsBroker'; Exibicao = 'Gerenciador de mapas baixados'; Recomendado = 'Disabled'; Risco = 'Baixo'
        Motivo = 'Só serve para mapas offline do app Mapas.' },
    @{ Nome = 'Fax'; Exibicao = 'Fax'; Recomendado = 'Disabled'; Risco = 'Baixo'
        Motivo = 'Só é necessário para enviar fax pelo PC.' },
    @{ Nome = 'RetailDemo'; Exibicao = 'Modo de demonstração de loja'; Recomendado = 'Disabled'; Risco = 'Baixo'
        Motivo = 'Usado apenas em PCs de vitrine.' },
    @{ Nome = 'RemoteRegistry'; Exibicao = 'Registro Remoto'; Recomendado = 'Disabled'; Risco = 'Baixo'; Corporativo = $true
        Motivo = 'Permite alterar o registro pela rede - melhor desligado por segurança.' },
    @{ Nome = 'WMPNetworkSvc'; Exibicao = 'Compartilhamento de rede do Windows Media Player'; Recomendado = 'Disabled'; Risco = 'Baixo'
        Motivo = 'Compartilha sua biblioteca de mídia na rede; raramente usado.' },
    @{ Nome = 'TrkWks'; Exibicao = 'Cliente de rastreamento de link distribuído'; Recomendado = 'Manual'; Risco = 'Baixo'; Corporativo = $true
        Motivo = 'Mantém atalhos para arquivos em outros PCs da rede; raramente necessário em uso doméstico.' },
    @{ Nome = 'Spooler'; Exibicao = 'Spooler de impressão'; Recomendado = 'Manual'; Risco = 'Médio'; Condicao = 'SemImpressora'
        Motivo = 'Nenhuma impressora física encontrada. Atenção: "Imprimir em PDF" também depende dele.' },
    @{ Nome = 'bthserv'; Exibicao = 'Serviço de Suporte Bluetooth'; Recomendado = 'Manual'; Risco = 'Baixo'; Condicao = 'SemBluetooth'
        Motivo = 'Nenhum adaptador Bluetooth encontrado.' }
)

# Serviços que parecem "otimizáveis" em guias da internet, mas devem ser mantidos (explicação para o usuário).
$Script:ServicosManter = @(
    @{ Nome = 'SysMain'; Motivo = 'Pré-carrega os apps que você mais usa. A Microsoft recomenda manter ativo, inclusive em SSD.' },
    @{ Nome = 'WSearch'; Motivo = 'Indexação: deixa a busca do Iniciar e do Explorador instantânea. Em SSD o custo é mínimo.' },
    @{ Nome = 'wuauserv'; Motivo = 'Windows Update: desativar deixa o PC sem correções de segurança.' },
    @{ Nome = 'WinDefend'; Motivo = 'Antivírus do Windows.' },
    @{ Nome = 'TabletInputService'; Motivo = 'Teclado virtual, painel de emojis (Win + .) e alguns métodos de entrada dependem dele.' }
)

# ------------------------------------------------ apps pré-instalados (Appx) --

$Script:CatalogoApps = @(
    # Risco Baixo: raramente usados, removíveis com segurança (reinstaláveis pela Microsoft Store)
    @{ Padrao = 'Microsoft.BingNews'; Nome = 'Notícias'; Risco = 'Baixo' },
    @{ Padrao = 'Microsoft.BingWeather'; Nome = 'Clima'; Risco = 'Baixo' },
    @{ Padrao = 'Microsoft.BingSearch'; Nome = 'Pesquisa Bing'; Risco = 'Baixo' },
    @{ Padrao = 'Microsoft.GetHelp'; Nome = 'Obter Ajuda'; Risco = 'Baixo' },
    @{ Padrao = 'Microsoft.Getstarted'; Nome = 'Dicas'; Risco = 'Baixo' },
    @{ Padrao = 'Microsoft.MicrosoftSolitaireCollection'; Nome = 'Microsoft Solitaire Collection'; Risco = 'Baixo' },
    @{ Padrao = 'Microsoft.People'; Nome = 'Pessoas'; Risco = 'Baixo' },
    @{ Padrao = 'Microsoft.WindowsFeedbackHub'; Nome = 'Hub de Feedback'; Risco = 'Baixo' },
    @{ Padrao = 'Microsoft.ZuneVideo'; Nome = 'Filmes e TV'; Risco = 'Baixo' },
    @{ Padrao = 'Microsoft.MixedReality.Portal'; Nome = 'Portal de Realidade Misturada'; Risco = 'Baixo' },
    @{ Padrao = 'Microsoft.Microsoft3DViewer'; Nome = 'Visualizador 3D'; Risco = 'Baixo' },
    @{ Padrao = 'Microsoft.Print3D'; Nome = 'Print 3D'; Risco = 'Baixo' },
    @{ Padrao = 'Microsoft.MSPaint'; Nome = 'Paint 3D (o Paint clássico não é afetado)'; Risco = 'Baixo' },
    @{ Padrao = 'Microsoft.SkypeApp'; Nome = 'Skype (app da Loja)'; Risco = 'Baixo' },
    @{ Padrao = 'Microsoft.MicrosoftOfficeHub'; Nome = 'Office / Microsoft 365 (atalho, não o Office instalado)'; Risco = 'Baixo' },
    @{ Padrao = 'Microsoft.Wallet'; Nome = 'Carteira'; Risco = 'Baixo' },
    @{ Padrao = 'Microsoft.Messaging'; Nome = 'Mensagens'; Risco = 'Baixo' },
    @{ Padrao = 'Microsoft.OneConnect'; Nome = 'Planos Móveis'; Risco = 'Baixo' },
    @{ Padrao = 'Microsoft.549981C3F5F10'; Nome = 'Cortana'; Risco = 'Baixo' },
    @{ Padrao = 'Microsoft.WindowsMaps'; Nome = 'Mapas'; Risco = 'Baixo' },
    @{ Padrao = 'Clipchamp.Clipchamp'; Nome = 'Clipchamp'; Risco = 'Baixo' },
    @{ Padrao = 'Microsoft.PowerAutomateDesktop'; Nome = 'Power Automate'; Risco = 'Baixo' },
    @{ Padrao = 'king.com.*'; Nome = 'Jogos King (Candy Crush etc.)'; Risco = 'Baixo' },
    @{ Padrao = '*CandyCrush*'; Nome = 'Candy Crush'; Risco = 'Baixo' },
    @{ Padrao = '*BubbleWitch*'; Nome = 'Bubble Witch'; Risco = 'Baixo' },
    @{ Padrao = '*MarchofEmpires*'; Nome = 'March of Empires'; Risco = 'Baixo' },
    @{ Padrao = '*Disney*'; Nome = 'Disney+ (pré-instalado)'; Risco = 'Baixo' },
    @{ Padrao = '*TikTok*'; Nome = 'TikTok (pré-instalado)'; Risco = 'Baixo' },
    @{ Padrao = '*Facebook*'; Nome = 'Facebook (pré-instalado)'; Risco = 'Baixo' },
    @{ Padrao = '*Instagram*'; Nome = 'Instagram (pré-instalado)'; Risco = 'Baixo' },
    @{ Padrao = 'AmazonVideo.PrimeVideo'; Nome = 'Prime Video (pré-instalado)'; Risco = 'Baixo' },
    # Risco Médio: muita gente usa - só remover se o usuário confirmar que não usa
    @{ Padrao = 'Microsoft.ZuneMusic'; Nome = 'Groove Música / Media Player'; Risco = 'Médio' },
    @{ Padrao = 'Microsoft.Office.OneNote'; Nome = 'OneNote para Windows 10'; Risco = 'Médio' },
    @{ Padrao = 'Microsoft.YourPhone'; Nome = 'Seu Telefone / Vincular ao Celular'; Risco = 'Médio' },
    @{ Padrao = 'microsoft.windowscommunicationsapps'; Nome = 'Email e Calendário'; Risco = 'Médio' },
    @{ Padrao = 'Microsoft.XboxApp'; Nome = 'Xbox Console Companion'; Risco = 'Médio' },
    @{ Padrao = 'MicrosoftTeams'; Nome = 'Teams pessoal (chat do Windows 11)'; Risco = 'Médio' },
    @{ Padrao = 'SpotifyAB.SpotifyMusic'; Nome = 'Spotify (versão da Loja)'; Risco = 'Médio' }
)

# Nunca remover (sistema, Loja, codecs, frameworks, componentes de jogos).
$Script:AppsProtegidos = @(
    'Microsoft.WindowsStore', 'Microsoft.StorePurchaseApp', 'Microsoft.DesktopAppInstaller', 'Microsoft.Windows.*', 'MicrosoftWindows.*',
    'Microsoft.WindowsCalculator', 'Microsoft.ScreenSketch', 'Microsoft.WindowsNotepad', 'Microsoft.Paint', 'Microsoft.SecHealthUI',
    'Microsoft.Xbox.TCUI', 'Microsoft.XboxIdentityProvider', 'Microsoft.XboxGameCallableUI', 'Microsoft.GamingServices', 'Microsoft.XboxGamingOverlay',
    'Microsoft.VCLibs*', 'Microsoft.NET.*', 'Microsoft.UI.Xaml*', 'Microsoft.WindowsAppRuntime*', 'Microsoft.Services.Store.Engagement',
    'Microsoft.*Extension', 'Microsoft.*VideoExtension*', 'Microsoft.*ImageExtension*', 'Microsoft.WebMediaExtensions',
    'Microsoft.AAD.BrokerPlugin', 'Microsoft.AccountsControl', 'Microsoft.LockApp', 'Microsoft.Win32WebViewHost', 'windows.immersivecontrolpanel',
    'Microsoft.MicrosoftEdge*', 'Microsoft.WindowsTerminal', 'Microsoft.WindowsCamera', 'Microsoft.WindowsAlarms', 'MSTeams', 'Microsoft.CompanyPortal',
    'Microsoft.MicrosoftStickyNotes', 'Microsoft.WindowsSoundRecorder', 'Microsoft.Todos', 'Microsoft.OutlookForWindows', 'Microsoft.Office.Desktop*'
)

function Test-AppProtegido {
    param([string]$NomePacote)
    foreach ($p in $Script:AppsProtegidos) { if ($NomePacote -like $p) { return $true } }
    return $false
}

# ---------------------------------------------------- recursos opcionais --

$Script:CatalogoRecursos = @(
    @{ Nome = 'SMB1Protocol'; Exibicao = 'SMB 1.0/CIFS (compartilhamento de arquivos antigo)'; Risco = 'Baixo'; Seguranca = $true; Prioridade = 1
        Motivo = 'Protocolo inseguro (explorado pelo ransomware WannaCry). Só necessário para NAS/impressoras muito antigos.' },
    @{ Nome = 'MicrosoftWindowsPowerShellV2Root'; Exibicao = 'Windows PowerShell 2.0'; Risco = 'Baixo'; Seguranca = $true; Prioridade = 2
        Motivo = 'Versão obsoleta usada por malware para burlar proteções. O PowerShell 5.1 continua funcionando normalmente.' },
    @{ Nome = 'Internet-Explorer-Optional-amd64'; Exibicao = 'Internet Explorer 11'; Risco = 'Médio'; Seguranca = $false; Prioridade = 3
        Motivo = 'Navegador descontinuado. Em empresas, confirme com o TI (sistemas legados podem depender dele).' },
    @{ Nome = 'WorkFolders-Client'; Exibicao = 'Pastas de Trabalho'; Risco = 'Baixo'; Seguranca = $false; Prioridade = 3
        Motivo = 'Recurso corporativo raramente usado.' },
    @{ Nome = 'Printing-XPSServices-Features'; Exibicao = 'Serviços XPS'; Risco = 'Baixo'; Seguranca = $false; Prioridade = 3
        Motivo = 'Formato XPS praticamente sem uso.' }
)

# ------------------------------------------- classificação da inicialização --
# Ordem importa: a primeira regra que casar vence (Essencial > Avaliar > Dispensável).

$Script:RegrasInicializacao = @(
    @{ Classe = 'Essencial'; Padrao = 'SecurityHealth|Windows Defender|MsMpEng|WindowsSecurity'; Motivo = 'Segurança do Windows' },
    @{ Classe = 'Essencial'; Padrao = 'avast|\bavg\b|kaspersky|bitdefender|norton|mcafee(?!.*webadvisor)|\beset\b|egui|malwarebytes|sophos|trend ?micro|crowdstrike|sentinel|symantec|webroot|panda'; Motivo = 'Antivírus / segurança' },
    @{ Classe = 'Essencial'; Padrao = 'GlobalProtect|AnyConnect|vpnui|FortiClient|Zscaler|Pulse ?Secure|Netskope|Forcepoint|Cisco Secure'; Motivo = 'VPN / segurança corporativa' },
    @{ Classe = 'Essencial'; Padrao = 'RtkAud|Realtek|RAVCpl|RAVBg|MaxxAudio|Nahimic|Dolby|SonicStudio|IntelliAudio'; Motivo = 'Driver/painel de áudio' },
    @{ Classe = 'Essencial'; Padrao = 'Synaptics|SynTP|ETDCtrl|\bElan\b|PrecisionTouch'; Motivo = 'Driver de touchpad' },
    @{ Classe = 'Essencial'; Padrao = 'igfx|IntelGraphics|Intel.*Graphics Command'; Motivo = 'Driver de vídeo Intel' },
    @{ Classe = 'Essencial'; Padrao = 'ctfmon|\bIME\b'; Motivo = 'Entrada de texto / teclado' },
    @{ Classe = 'Avaliar'; Padrao = 'vgtray|Vanguard'; Motivo = 'Anticheat da Riot (Valorant/LoL) - necessário se você joga esses títulos' },
    @{ Classe = 'Dispensável'; Padrao = 'Opera.*assistant|Browser Assistant'; Motivo = 'Assistente do navegador Opera (não é o navegador)' },
    @{ Classe = 'Avaliar'; Padrao = 'Auto ?update|Updater|Update ?Task|UpdateCore|UpdateMachine'; Motivo = 'Atualizador automático - desativar pode deixar o programa sem atualizações de segurança' },
    @{ Classe = 'Avaliar'; Padrao = 'OpenVPN|WireGuard|ProtonVPN|NordVPN|Surfshark|ExpressVPN'; Motivo = 'VPN - mantenha se você conecta todo dia' },
    @{ Classe = 'Avaliar'; Padrao = 'Microsoft\.GamingApp|XboxApp'; Motivo = 'App Xbox - mantenha se usa Game Pass' },
    @{ Classe = 'Avaliar'; Padrao = 'YourPhone|PhoneLink'; Motivo = 'Vincular ao Celular - mantenha se usa notificações do celular no PC' },
    @{ Classe = 'Avaliar'; Padrao = 'OneDrive'; Motivo = 'Sincroniza arquivos com a nuvem. Desative só se não usa o OneDrive' },
    @{ Classe = 'Avaliar'; Padrao = 'Teams|ms-teams'; Motivo = 'Necessário abrir junto se você usa Teams no trabalho' },
    @{ Classe = 'Avaliar'; Padrao = 'Dropbox|GoogleDrive|googledrivesync|DriveFS|Box Sync|MEGAsync|iCloud'; Motivo = 'Sincronização de arquivos - mantenha se usa' },
    @{ Classe = 'Avaliar'; Padrao = 'Logi|LGHUB|Razer|Synapse|iCUE|Corsair|SteelSeries|NGenuity|Armoury|\bROG\b|MSI ?Center|Dragon ?Center'; Motivo = 'Periféricos: perfis de mouse/teclado/RGB podem parar de funcionar' },
    @{ Classe = 'Avaliar'; Padrao = 'NvBackend|nvcontainer|NVIDIA|RadeonSoftware|AMD ?Software|cncmd'; Motivo = 'Painel/overlay da placa de vídeo - o driver continua funcionando sem ele' },
    @{ Classe = 'Avaliar'; Padrao = 'AnyDesk|TeamViewer|RustDesk'; Motivo = 'Acesso remoto - mantenha se alguém dá suporte a este PC' },
    @{ Classe = 'Avaliar'; Padrao = 'Docker|WSL|Slack'; Motivo = 'Ferramenta de trabalho - mantenha se usa diariamente' },
    @{ Classe = 'Avaliar'; Padrao = 'Lightshot|Greenshot|ShareX|Snagit|Flameshot'; Motivo = 'Ferramenta de captura de tela acionada por atalho' },
    @{ Classe = 'Avaliar'; Padrao = 'Wallpaper ?Engine|wallpaper(32|64)|Rainmeter|Lively'; Motivo = 'Cosmético; consome RAM/GPU continuamente' },
    @{ Classe = 'Avaliar'; Padrao = 'HPSupport|HP .*Assistant|SupportAssist|Lenovo ?Vantage|MyASUS|Dell'; Motivo = 'Ferramenta do fabricante (atualizações de driver/BIOS)' },
    @{ Classe = 'Dispensável'; Padrao = 'Spotify'; Motivo = 'Abre rápido quando você quiser ouvir música' },
    @{ Classe = 'Dispensável'; Padrao = 'Discord'; Motivo = 'Pode ser aberto manualmente quando for usar' },
    @{ Classe = 'Dispensável'; Padrao = '\bSteam\b|steam\.exe'; Motivo = 'Launcher de jogos - abre quando você for jogar' },
    @{ Classe = 'Dispensável'; Padrao = 'EpicGamesLauncher|Epic Games'; Motivo = 'Launcher de jogos' },
    @{ Classe = 'Dispensável'; Padrao = 'EADesktop|EA app|\bOrigin\b'; Motivo = 'Launcher de jogos' },
    @{ Classe = 'Dispensável'; Padrao = 'Battle\.net'; Motivo = 'Launcher de jogos' },
    @{ Classe = 'Dispensável'; Padrao = 'Ubisoft|upc\.exe|Uplay'; Motivo = 'Launcher de jogos' },
    @{ Classe = 'Dispensável'; Padrao = 'GalaxyClient|GOG Galaxy'; Motivo = 'Launcher de jogos' },
    @{ Classe = 'Dispensável'; Padrao = 'RiotClient'; Motivo = 'Launcher de jogos' },
    @{ Classe = 'Dispensável'; Padrao = 'Overwolf|Medal'; Motivo = 'Overlay/gravação de jogos' },
    @{ Classe = 'Dispensável'; Padrao = 'Skype|Zoom|WhatsApp|Telegram'; Motivo = 'Comunicador - pode ser aberto quando for usar' },
    @{ Classe = 'Dispensável'; Padrao = 'MicrosoftEdgeAutoLaunch|msedge.*--no-startup-window'; Motivo = 'Pré-carrega o Edge na memória' },
    @{ Classe = 'Dispensável'; Padrao = '^(Opera( GX)? (Stable|Browser))|Brave|Vivaldi|Google Chrome AutoLaunch'; Motivo = 'Abre o navegador junto com o Windows - ele abre igual quando você clicar' },
    @{ Classe = 'Dispensável'; Padrao = 'KeePass.*Pre ?Load'; Motivo = 'Só acelera a primeira abertura do KeePass' },
    @{ Classe = 'Dispensável'; Padrao = 'MicrosoftOfficeHub'; Motivo = 'Atalho do app Office/Microsoft 365 (o Office instalado não é afetado)' },
    @{ Classe = 'Dispensável'; Padrao = 'GoogleUpdate|Google Update'; Motivo = 'Atualizador - continua rodando pela tarefa agendada' },
    @{ Classe = 'Dispensável'; Padrao = 'CCleaner'; Motivo = 'Monitoramento em segundo plano desnecessário' },
    @{ Classe = 'Dispensável'; Padrao = 'uTorrent|BitTorrent|qBittorrent|Deluge|Vuze'; Motivo = 'Cliente torrent - abra quando for usar' },
    @{ Classe = 'Dispensável'; Padrao = 'Creative Cloud|CCXProcess|AdobeGCInvoker|AdobeGCClient|AdobeARM|AcroTray|Adobe.*Updater|AGSService'; Motivo = 'Serviços auxiliares da Adobe' },
    @{ Classe = 'Dispensável'; Padrao = 'jusched|Java Update'; Motivo = 'Verificador de atualização do Java' },
    @{ Classe = 'Dispensável'; Padrao = 'iTunesHelper'; Motivo = 'Auxiliar do iTunes' },
    @{ Classe = 'Dispensável'; Padrao = 'Cortana|549981C3F5F10'; Motivo = 'Assistente descontinuado' },
    @{ Classe = 'Dispensável'; Padrao = 'McAfee ?WebAdvisor'; Motivo = 'Extensão/propaganda de antivírus' }
)

function Get-ClassificacaoInicializacao {
    param([string]$Texto)
    foreach ($r in $Script:RegrasInicializacao) {
        if ($Texto -match $r.Padrao) { return [pscustomobject]@{ Classe = $r.Classe; Motivo = $r.Motivo } }
    }
    return [pscustomobject]@{ Classe = 'Avaliar'; Motivo = 'Não reconhecido - pesquise o nome antes de desativar' }
}
