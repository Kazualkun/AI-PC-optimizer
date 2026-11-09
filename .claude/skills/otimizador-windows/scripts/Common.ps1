# =============================================================================
#  Common.ps1 - funções compartilhadas da skill "otimizador-windows"
#  Compatível com Windows PowerShell 5.1+. Salvo em UTF-8 com BOM.
#  Este arquivo NÃO altera nada no sistema: apenas define funções.
# =============================================================================

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

# ----------------------------------------------------------------- ambiente --

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-PodeElevar {
    # Membro do grupo Administradores (mesmo com token filtrado pelo UAC) => basta clicar "Sim".
    # Caso contrário, a elevação exige usuário/senha de outro administrador (comum em PC de empresa).
    try { return [bool]((whoami /groups) -match 'S-1-5-32-544') } catch { return $false }
}

function Get-PastaDados {
    param([string]$Sub)
    $base = if ($env:OTIMIZADOR_DADOS) { $env:OTIMIZADOR_DADOS } else { Join-Path $env:LOCALAPPDATA 'OtimizadorPC' }
    $p = if ($Sub) { Join-Path $base $Sub } else { $base }
    if (-not (Test-Path -LiteralPath $p)) { New-Item -ItemType Directory -Path $p -Force | Out-Null }
    return $p
}

function New-Carimbo { return (Get-Date -Format 'yyyyMMdd-HHmmss') }

# ------------------------------------------------------------- formatação --

function Format-Tamanho {
    param([double]$Bytes)
    if ($Bytes -ge 1TB) { return ('{0:N2} TB' -f ($Bytes / 1TB)) }
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N0} KB' -f ($Bytes / 1KB)) }
    return ('{0:N0} B' -f $Bytes)
}

function Split-Lista {
    # Aceita tanto arrays reais quanto "a,b,c" (necessário quando chamado via powershell -File).
    param([string[]]$Valores)
    if (-not $Valores) { return @() }
    return @($Valores | ForEach-Object { $_ -split '[,;]' } | ForEach-Object { $_.Trim().Trim("'").Trim('"') } | Where-Object { $_ })
}

function Write-Titulo {
    param([string]$Texto)
    Write-Host ''
    Write-Host ('=' * 78)
    Write-Host "  $Texto"
    Write-Host ('=' * 78)
}

function Write-Secao {
    param([string]$Texto)
    Write-Host ''
    Write-Host "--- $Texto ---"
}

function Write-Etapa {
    param([string]$Texto)
    Write-Host "-> $Texto"
}

function Write-Tabela {
    param($Dados, [string[]]$Propriedades)
    if (-not $Dados) { Write-Host '  (nenhum)'; return }
    $txt = if ($Propriedades) { $Dados | Format-Table -Property $Propriedades -AutoSize -Wrap | Out-String -Width 220 } else { $Dados | Format-Table -AutoSize -Wrap | Out-String -Width 220 }
    Write-Host ($txt.TrimEnd())
}

function Save-Json {
    param($Objeto, [string]$Caminho, [int]$Profundidade = 10)
    $Objeto | ConvertTo-Json -Depth $Profundidade | Out-File -LiteralPath $Caminho -Encoding utf8
}

# ---------------------------------------------------------------- pastas --

function Get-PastaDownloads {
    $v = Get-ValorRegistro 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders' '{374DE290-123F-4565-9164-39C4925E467B}'
    if ($v) { return [Environment]::ExpandEnvironmentVariables($v) }
    return (Join-Path $env:USERPROFILE 'Downloads')
}

function Resolve-PastaConhecida {
    # Permite passar "Downloads", "Área de Trabalho", "Documentos" etc. em vez do caminho completo.
    param([string]$Nome)
    switch -Regex ($Nome.Trim()) {
        '^(downloads?|transfer[eê]ncias)$'                  { return (Get-PastaDownloads) }
        '^(desktop|[aá]rea de trabalho|areadetrabalho)$'   { return [Environment]::GetFolderPath('Desktop') }
        '^(documentos?|documents|meus documentos)$'        { return [Environment]::GetFolderPath('MyDocuments') }
        '^(imagens|pictures|fotos)$'                       { return [Environment]::GetFolderPath('MyPictures') }
        '^(v[ií]deos?)$'                                   { return [Environment]::GetFolderPath('MyVideos') }
        '^(m[uú]sicas?|music)$'                            { return [Environment]::GetFolderPath('MyMusic') }
        default                                            { return $Nome }
    }
}

# ------------------------------------------- motor de varredura (C# + reserva) --
# Varrer centenas de milhares de arquivos em PowerShell puro leva minutos; o trecho em C#
# (compilado uma vez por sessão, ~0,5 s) faz o mesmo em segundos. Se Add-Type estiver bloqueado
# (ex.: PowerShell em modo restrito pela empresa), as funções usam a versão PowerShell.

$Script:CodigoFS = @'
using System;
using System.IO;
using System.Collections.Generic;

public static class OtimizadorFS {
    private const int NUVEM = 0x400000 | 0x1000 | 0x40000;
    private static readonly string[] PastasDev = new string[] {
        "\\node_modules\\", "\\.git\\", "\\.venv\\", "\\venv\\", "\\env\\", "\\site-packages\\", "\\__pycache__\\",
        "\\.next\\", "\\.gradle\\", "\\.idea\\", "\\.vs\\", "\\.nuget\\", "\\vendor\\", "\\.cache\\",
        "\\dist\\", "\\build\\", "\\_internal\\", "\\bin\\", "\\obj\\", "\\out\\", "\\target\\", "\\.pytest_cache\\", "\\coverage\\" };

    public class Medida { public long Bytes; public long Arquivos; public long BytesNuvem; public long Erros; }
    public class Varredura {
        public long Total; public long Arquivos;
        public Dictionary<string, long> PorPasta = new Dictionary<string, long>(StringComparer.OrdinalIgnoreCase);
        public List<FileInfo> Grandes = new List<FileInfo>();
    }
    public class Resumo {
        public long Total; public long Arquivos; public long NaNuvem; public long AntigosQtd; public long AntigosBytes;
        public Dictionary<string, long[]> PorExtensao = new Dictionary<string, long[]>(StringComparer.OrdinalIgnoreCase);
        public Dictionary<string, long[]> PorSubpasta = new Dictionary<string, long[]>(StringComparer.OrdinalIgnoreCase);
        public List<FileInfo> Interessantes = new List<FileInfo>();
    }

    private static bool EhNuvem(FileInfo f) { return (((int)f.Attributes) & NUVEM) != 0; }
    private static bool EhLink(DirectoryInfo d) { return (d.Attributes & FileAttributes.ReparsePoint) != 0; }
    private static void Somar(Dictionary<string, long[]> d, string k, long v) {
        long[] a;
        if (!d.TryGetValue(k, out a)) { a = new long[2]; d[k] = a; }
        a[0]++; a[1] += v;
    }
    public static bool EmPastaDev(string caminho) {
        string c = caminho.EndsWith("\\") ? caminho : caminho + "\\";
        foreach (string p in PastasDev) { if (c.IndexOf(p, StringComparison.OrdinalIgnoreCase) >= 0) return true; }
        return false;
    }

    public static Medida Medir(string caminho, string filtro, bool recursivo, int diasMinimos) {
        Medida m = new Medida();
        DateTime limite = DateTime.Now.AddDays(-diasMinimos);
        Stack<DirectoryInfo> pilha = new Stack<DirectoryInfo>();
        pilha.Push(new DirectoryInfo(caminho));
        while (pilha.Count > 0) {
            DirectoryInfo d = pilha.Pop();
            try {
                foreach (FileInfo f in d.EnumerateFiles(filtro)) {
                    if (diasMinimos > 0 && f.LastWriteTime > limite) continue;
                    if (EhNuvem(f)) { m.BytesNuvem += f.Length; continue; }
                    m.Bytes += f.Length; m.Arquivos++;
                }
                if (recursivo) { foreach (DirectoryInfo s in d.EnumerateDirectories()) { if (!EhLink(s)) pilha.Push(s); } }
            } catch { m.Erros++; }
        }
        return m;
    }

    // Soma por pasta do perfil (1 nível; AppData até 3 níveis) + lista de arquivos grandes.
    public static Varredura VarrerPerfil(string raiz, long limiteGrande) {
        Varredura v = new Varredura();
        raiz = raiz.TrimEnd('\\');
        int len = raiz.Length + 1;
        Stack<DirectoryInfo> pilha = new Stack<DirectoryInfo>();
        pilha.Push(new DirectoryInfo(raiz));
        while (pilha.Count > 0) {
            DirectoryInfo d = pilha.Pop();
            string chave;
            if (d.FullName.Length <= len) { chave = "(arquivos soltos no perfil)"; }
            else {
                string[] p = d.FullName.Substring(len).Split('\\');
                int n = p[0].Equals("AppData", StringComparison.OrdinalIgnoreCase) ? Math.Min(3, p.Length) : 1;
                chave = string.Join("\\", p, 0, n);
            }
            long soma = 0;
            try {
                foreach (FileInfo f in d.EnumerateFiles()) {
                    if (EhNuvem(f)) continue;
                    soma += f.Length; v.Arquivos++;
                    if (f.Length >= limiteGrande) v.Grandes.Add(f);
                }
                foreach (DirectoryInfo s in d.EnumerateDirectories()) { if (!EhLink(s)) pilha.Push(s); }
            } catch { }
            if (soma > 0) { long a; v.PorPasta.TryGetValue(chave, out a); v.PorPasta[chave] = a + soma; }
            v.Total += soma;
        }
        return v;
    }

    // Resumo de uma pasta para organização: totais por extensão e subpasta, arquivos "interessantes"
    // (>= minInteresse, soltos na raiz, ou de extensões de interesse), ignorando pastas de desenvolvimento.
    public static Resumo Resumir(string raiz, long minInteresse, string[] extInteresse, DateTime limiteAntigo) {
        Resumo r = new Resumo();
        HashSet<string> exts = new HashSet<string>(extInteresse, StringComparer.OrdinalIgnoreCase);
        raiz = raiz.TrimEnd('\\');
        int len = raiz.Length + 1;
        Stack<DirectoryInfo> pilha = new Stack<DirectoryInfo>();
        pilha.Push(new DirectoryInfo(raiz));
        while (pilha.Count > 0) {
            DirectoryInfo d = pilha.Pop();
            string sub = d.FullName.Length <= len ? "" : d.FullName.Substring(len).Split('\\')[0];
            bool dev = EmPastaDev(d.FullName);
            try {
                foreach (FileInfo f in d.EnumerateFiles()) {
                    string nome = f.Name;
                    if (nome.Equals("desktop.ini", StringComparison.OrdinalIgnoreCase) || nome.Equals("thumbs.db", StringComparison.OrdinalIgnoreCase)) continue;
                    if (EhNuvem(f)) { r.NaNuvem++; continue; }
                    long tam = f.Length;
                    r.Total += tam; r.Arquivos++;
                    Somar(r.PorExtensao, f.Extension, tam);
                    Somar(r.PorSubpasta, sub, tam);
                    if (dev) continue;
                    if (f.LastWriteTime < limiteAntigo) { r.AntigosQtd++; r.AntigosBytes += tam; }
                    if (tam >= minInteresse || sub.Length == 0 || exts.Contains(f.Extension)) r.Interessantes.Add(f);
                }
                foreach (DirectoryInfo s in d.EnumerateDirectories()) { if (!EhLink(s)) pilha.Push(s); }
            } catch { }
        }
        return r;
    }
}
'@

function Initialize-FS {
    if ($null -ne $Script:FSDisponivel) { return $Script:FSDisponivel }
    if ('OtimizadorFS' -as [type]) { $Script:FSDisponivel = $true; return $true }
    try { Add-Type -TypeDefinition $Script:CodigoFS -ErrorAction Stop; $Script:FSDisponivel = $true }
    catch { $Script:FSDisponivel = $false }
    return $Script:FSDisponivel
}

$Script:PadraoPastaDev = '\\(node_modules|\.git|\.venv|venv|env|site-packages|__pycache__|\.next|\.gradle|\.idea|\.vs|\.nuget|vendor|\.cache|dist|build|_internal|bin|obj|out|target|\.pytest_cache|coverage)\\'

function Test-PastaProjeto {
    # Projetos de código e apps portáteis devem ser tratados como um bloco: mover a pasta inteira,
    # nunca separar arquivos por tipo nem apagar "duplicados" internos.
    param([string]$Caminho)
    foreach ($marca in @('.git', 'package.json', 'pyproject.toml', 'requirements.txt', 'setup.py', 'pom.xml', 'build.gradle', 'Cargo.toml', 'go.mod', 'composer.json', '.vscode', 'node_modules', 'venv', '.venv', 'Dockerfile', 'Makefile')) {
        if (Test-Path -LiteralPath (Join-Path $Caminho $marca) -ErrorAction SilentlyContinue) { return $true }
    }
    foreach ($padrao in @('*.sln', '*.csproj', '*.spec')) {
        if (Get-ChildItem -LiteralPath $Caminho -Filter $padrao -File -ErrorAction SilentlyContinue | Select-Object -First 1) { return $true }
    }
    if ((Get-ChildItem -LiteralPath $Caminho -Filter '*.exe' -File -ErrorAction SilentlyContinue | Select-Object -First 1) -and
        (Get-ChildItem -LiteralPath $Caminho -Filter '*.dll' -File -ErrorAction SilentlyContinue | Select-Object -First 1)) { return $true }   # app portátil
    return $false
}

function Invoke-VarreduraPerfil {
    # Retorna Total, Arquivos, PorPasta (chave -> bytes) e Grandes (FileInfo >= LimiteGrande).
    param([string]$Raiz, [int64]$LimiteGrande = 300MB)
    if (Initialize-FS) { return [OtimizadorFS]::VarrerPerfil($Raiz, $LimiteGrande) }
    $v = [pscustomobject]@{ Total = [int64]0; Arquivos = [int64]0; PorPasta = @{}; Grandes = (New-Object System.Collections.Generic.List[object]) }
    $nuvem = 0x400000 -bor 0x1000 -bor 0x40000
    $Raiz = $Raiz.TrimEnd('\'); $len = $Raiz.Length + 1
    $pilha = New-Object 'System.Collections.Generic.Stack[System.IO.DirectoryInfo]'
    $pilha.Push((New-Object System.IO.DirectoryInfo -ArgumentList $Raiz))
    while ($pilha.Count -gt 0) {
        $dir = $pilha.Pop()
        if ($dir.FullName.Length -le $len) { $chave = '(arquivos soltos no perfil)' } else {
            $p = $dir.FullName.Substring($len).Split('\')
            $n = if ($p[0] -eq 'AppData') { [Math]::Min(3, $p.Count) } else { 1 }
            $chave = ($p[0..($n - 1)] -join '\')
        }
        $soma = [int64]0
        try {
            foreach ($f in $dir.EnumerateFiles()) {
                if (([int]$f.Attributes -band $nuvem) -ne 0) { continue }
                $soma += $f.Length; $v.Arquivos++
                if ($f.Length -ge $LimiteGrande) { $v.Grandes.Add($f) }
            }
            foreach ($s in $dir.EnumerateDirectories()) { if (([int]$s.Attributes -band 0x400) -eq 0) { $pilha.Push($s) } }
        } catch {}
        if ($soma -gt 0) { $v.PorPasta[$chave] = [int64]$v.PorPasta[$chave] + $soma }
        $v.Total += $soma
    }
    return $v
}

function Get-ResumoPasta {
    # Mesmo formato de [OtimizadorFS]::Resumir (ver acima).
    param([string]$Raiz, [int64]$MinInteresse = 1MB, [string[]]$ExtInteresse = @(), [datetime]$LimiteAntigo)
    if (Initialize-FS) { return [OtimizadorFS]::Resumir($Raiz, $MinInteresse, $ExtInteresse, $LimiteAntigo) }
    $r = [pscustomobject]@{ Total = [int64]0; Arquivos = [int64]0; NaNuvem = [int64]0; AntigosQtd = [int64]0; AntigosBytes = [int64]0; PorExtensao = @{}; PorSubpasta = @{}; Interessantes = (New-Object System.Collections.Generic.List[object]) }
    $nuvem = 0x400000 -bor 0x1000 -bor 0x40000
    $Raiz = $Raiz.TrimEnd('\'); $len = $Raiz.Length + 1
    $pilha = New-Object 'System.Collections.Generic.Stack[System.IO.DirectoryInfo]'
    $pilha.Push((New-Object System.IO.DirectoryInfo -ArgumentList $Raiz))
    while ($pilha.Count -gt 0) {
        $dir = $pilha.Pop()
        $sub = if ($dir.FullName.Length -le $len) { '' } else { $dir.FullName.Substring($len).Split('\')[0] }
        $dev = (($dir.FullName + '\') -match $Script:PadraoPastaDev)
        try {
            foreach ($f in $dir.EnumerateFiles()) {
                if ($f.Name -in @('desktop.ini', 'thumbs.db')) { continue }
                if (([int]$f.Attributes -band $nuvem) -ne 0) { $r.NaNuvem++; continue }
                $tam = $f.Length; $r.Total += $tam; $r.Arquivos++
                foreach ($par in @(@($r.PorExtensao, $f.Extension), @($r.PorSubpasta, $sub))) {
                    $h = $par[0]; $k = [string]$par[1]
                    if (-not $h.ContainsKey($k)) { $h[$k] = @([int64]0, [int64]0) }
                    $h[$k][0]++; $h[$k][1] += $tam
                }
                if ($dev) { continue }
                if ($f.LastWriteTime -lt $LimiteAntigo) { $r.AntigosQtd++; $r.AntigosBytes += $tam }
                if ($tam -ge $MinInteresse -or $sub -eq '' -or $ExtInteresse -contains $f.Extension) { $r.Interessantes.Add($f) }
            }
            foreach ($s in $dir.EnumerateDirectories()) { if (([int]$s.Attributes -band 0x400) -eq 0) { $pilha.Push($s) } }
        } catch {}
    }
    return $r
}

function Get-TamanhoPasta {
    # Soma rápida e tolerante a erros. Não segue junções/links (evita contagem dupla) e
    # NÃO conta arquivos do OneDrive que estão só na nuvem (não ocupam disco).
    param(
        [Parameter(Mandatory)][string]$Caminho,
        [int]$DiasMinimos = 0,
        [string]$Filtro = '*',
        [switch]$SemRecursao
    )
    $r = [pscustomobject]@{ Caminho = $Caminho; Existe = $false; Bytes = [int64]0; Arquivos = [int64]0; BytesNuvem = [int64]0; Erros = [int64]0 }
    if (-not $Caminho -or -not (Test-Path -LiteralPath $Caminho -ErrorAction SilentlyContinue)) { return $r }
    $r.Existe = $true
    $limite = (Get-Date).AddDays(-1 * $DiasMinimos)
    $nuvem = 0x400000 -bor 0x1000 -bor 0x40000
    try { $info = Get-Item -LiteralPath $Caminho -Force -ErrorAction Stop } catch { $r.Erros++; return $r }
    if (-not $info.PSIsContainer) { $r.Bytes = [int64]$info.Length; $r.Arquivos = 1; return $r }
    if (Initialize-FS) {
        $m = [OtimizadorFS]::Medir($info.FullName, $Filtro, [bool](-not $SemRecursao), $DiasMinimos)
        $r.Bytes = $m.Bytes; $r.Arquivos = $m.Arquivos; $r.BytesNuvem = $m.BytesNuvem; $r.Erros = $m.Erros
        return $r
    }
    $pilha = New-Object 'System.Collections.Generic.Stack[System.IO.DirectoryInfo]'
    $pilha.Push((New-Object System.IO.DirectoryInfo -ArgumentList $info.FullName))
    while ($pilha.Count -gt 0) {
        $d = $pilha.Pop()
        try {
            foreach ($f in $d.EnumerateFiles($Filtro)) {
                if ($DiasMinimos -gt 0 -and $f.LastWriteTime -gt $limite) { continue }
                if (([int]$f.Attributes -band $nuvem) -ne 0) { $r.BytesNuvem += $f.Length; continue }
                $r.Bytes += $f.Length
                $r.Arquivos++
            }
            if (-not $SemRecursao) {
                foreach ($s in $d.EnumerateDirectories()) {
                    if (([int]$s.Attributes -band [int][IO.FileAttributes]::ReparsePoint) -eq 0) { $pilha.Push($s) }
                }
            }
        } catch { $r.Erros++ }
    }
    return $r
}

function Get-InfoUnidade {
    param([string]$Letra)
    $Letra = $Letra.Substring(0, 1).ToUpper()
    $v = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($Letra):'" -ErrorAction SilentlyContinue
    if (-not $v) { return $null }
    return [pscustomobject]@{ Letra = $Letra; Total = [int64]$v.Size; Livre = [int64]$v.FreeSpace; Tipo = [int]$v.DriveType }
}

function Test-CaminhoProtegido {
    # Nunca permitir limpeza/remoção em raízes de unidade ou pastas vitais do sistema/perfil.
    param([string]$Caminho)
    if (-not $Caminho) { return $true }
    try { $c = [IO.Path]::GetFullPath($Caminho).TrimEnd('\') } catch { return $true }
    if ($c.Length -le 3) { return $true }
    $vitais = @(
        $env:windir, "$env:windir\System32", "$env:windir\SysWOW64", "$env:windir\WinSxS", "$env:windir\Installer",
        $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, "$env:SystemDrive\Users", $env:USERPROFILE,
        $env:APPDATA, $env:LOCALAPPDATA, [Environment]::GetFolderPath('MyDocuments'), [Environment]::GetFolderPath('Desktop'),
        [Environment]::GetFolderPath('MyPictures'), [Environment]::GetFolderPath('MyVideos'), [Environment]::GetFolderPath('MyMusic'),
        (Get-PastaDownloads)
    ) | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\') }
    return ($vitais -contains $c)
}

# --------------------------------------------------------------- registro --

function Get-ValorRegistro {
    param([string]$Chave, [string]$Nome)
    try {
        $k = Get-Item -LiteralPath $Chave -ErrorAction Stop
        return $k.GetValue($Nome, $null, 'DoNotExpandEnvironmentNames')
    } catch { return $null }
}

function Set-ValorRegistro {
    param([string]$Chave, [string]$Nome, $Valor, [string]$Tipo = 'DWord')
    if (-not (Test-Path -LiteralPath $Chave)) { New-Item -Path $Chave -Force | Out-Null }
    New-ItemProperty -LiteralPath $Chave -Name $Nome -Value $Valor -PropertyType $Tipo -Force -ErrorAction Stop | Out-Null
}

# ----------------------------------------------------------------- backup --

function New-Backup {
    param([string]$Nome)
    $arq = Join-Path (Get-PastaDados 'backups') ("$Nome-" + (New-Carimbo) + '.json')
    return [pscustomobject]@{
        Arquivo    = $arq
        Criado     = (Get-Date).ToString('s')
        Computador = $env:COMPUTERNAME
        Usuario    = $env:USERNAME
        Entradas   = (New-Object System.Collections.ArrayList)
    }
}

function Save-Backup { param($Backup) Save-Json -Objeto $Backup -Caminho $Backup.Arquivo }

function Add-BackupEntrada {
    param($Backup, [hashtable]$Dados)
    [void]$Backup.Entradas.Add([pscustomobject]$Dados)
    Save-Backup $Backup
}

function Add-BackupRegistro {
    # Guarda o valor atual (ou a ausência dele) ANTES de alterar.
    param($Backup, [string]$Chave, [string]$Nome, [string]$Descricao = '')
    $existia = $false; $valor = $null; $tipo = $null
    if (Test-Path -LiteralPath $Chave) {
        $k = Get-Item -LiteralPath $Chave
        if ($k.GetValueNames() -contains $Nome) {
            $existia = $true
            $valor = $k.GetValue($Nome, $null, 'DoNotExpandEnvironmentNames')
            $tipo = $k.GetValueKind($Nome).ToString()
        }
    }
    if ($valor -is [byte[]]) { $valor = [Convert]::ToBase64String($valor) }
    Add-BackupEntrada $Backup @{
        Tipo = 'Registro'; Descricao = $Descricao; Chave = $Chave; Nome = $Nome
        Existia = $existia; Valor = $valor; TipoValor = $tipo; Admin = ($Chave -like 'HKLM:*')
    }
}

function Set-RegistroComBackup {
    param($Backup, [string]$Chave, [string]$Nome, $Valor, [string]$Tipo = 'DWord', [string]$Descricao = '')
    Add-BackupRegistro -Backup $Backup -Chave $Chave -Nome $Nome -Descricao $Descricao
    Set-ValorRegistro -Chave $Chave -Nome $Nome -Valor $Valor -Tipo $Tipo
}

# ---------------------------------------------------------------- lixeira --

function Initialize-Lixeira {
    if ('OtimizadorLixeira' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class OtimizadorLixeira {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct SHFILEOPSTRUCT {
        public IntPtr hwnd;
        public uint wFunc;
        public string pFrom;
        public string pTo;
        public ushort fFlags;
        public bool fAnyOperationsAborted;
        public IntPtr hNameMappings;
        public string lpszProgressTitle;
    }
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SHFileOperation(ref SHFILEOPSTRUCT op);
    // FO_DELETE + ALLOWUNDO (Lixeira) + NOCONFIRMATION + NOERRORUI + SILENT + WANTNUKEWARNING
    // WANTNUKEWARNING: se o item NÃO couber na Lixeira, o Windows pergunta ao usuário antes de apagar de vez.
    public static int Enviar(string caminho) {
        SHFILEOPSTRUCT op = new SHFILEOPSTRUCT();
        op.wFunc = 3;
        op.pFrom = caminho + "\0\0";
        op.fFlags = (ushort)(0x0040 | 0x0010 | 0x0400 | 0x0004 | 0x4000);
        return SHFileOperation(ref op);
    }
}
'@
}

function Send-ParaLixeira {
    param([string]$Caminho)
    Initialize-Lixeira
    $completo = (Resolve-Path -LiteralPath $Caminho -ErrorAction Stop).ProviderPath
    $rc = [OtimizadorLixeira]::Enviar($completo)
    if ($rc -ne 0 -or (Test-Path -LiteralPath $completo)) { throw "Não foi possível enviar para a Lixeira (código $rc)" }
}

# -------------------------------------------------------------- elevação --

function Invoke-ComoAdmin {
    # Reexecuta um script desta skill em uma janela elevada (o Windows mostra o UAC ao usuário).
    # A saída é gravada em log e reimpressa aqui, para o Claude conseguir ler o resultado.
    param([Parameter(Mandatory)][string]$Script, [hashtable]$Parametros = @{})
    $log = Join-Path (Get-PastaDados 'logs') ('elevado-' + (New-Carimbo) + '.log')
    $aspas = { param($s) "'" + ([string]$s -replace "'", "''") + "'" }
    $partes = New-Object System.Collections.Generic.List[string]
    foreach ($k in $Parametros.Keys) {
        $v = $Parametros[$k]
        if ($null -eq $v) { continue }
        if ($v -is [bool] -or $v -is [System.Management.Automation.SwitchParameter]) {
            if ([bool]$v) { $partes.Add("-$k") }
            continue
        }
        $lista = @($v | ForEach-Object { & $aspas $_ })
        if ($lista.Count -gt 0) { $partes.Add("-$k " + ($lista -join ',')) }
    }
    $cmd = "`$env:OTIMIZADOR_DADOS = $(& $aspas (Get-PastaDados)); & $(& $aspas $Script) $($partes -join ' ') *> $(& $aspas $log)"
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
    Write-Host ''
    Write-Host '>> Abrindo janela de administrador. Confirme o aviso do Windows (UAC) para continuar...'
    try {
        $p = Start-Process -FilePath 'powershell.exe' -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $enc" -Verb RunAs -Wait -PassThru -ErrorAction Stop
    } catch {
        Write-Host ">> Elevação cancelada ou negada: $($_.Exception.Message)"
        Write-Host '>> Nenhuma ação de administrador foi executada.'
        return $false
    }
    Write-Host ">> Saída da janela de administrador (log: $log):"
    if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log | ForEach-Object { Write-Host "   $_" } }
    return ($p.ExitCode -eq 0)
}

# --------------------------------------------------------- inicialização --

function Test-AprovadoInicializacao {
    # Mesmo mecanismo do Gerenciador de Tarefas: 1º byte par = habilitado, ímpar = desabilitado.
    param([string]$Chave, [string]$Nome)
    $v = Get-ValorRegistro $Chave $Nome
    if ($v -is [byte[]] -and $v.Length -gt 0) { return (($v[0] -band 1) -eq 0) }
    return $true
}

function New-ItemInicializacao {
    param($Nome, $Comando, $Origem, $Escopo, [bool]$Ativo, [bool]$Admin, $ChaveAprov, $NomeAprov, $ChaveApp, $TarefaCaminho)
    $cls = Get-ClassificacaoInicializacao -Texto "$Nome $Comando"
    return [pscustomobject]@{
        Nome = $Nome; Ativo = $Ativo; Classificacao = $cls.Classe; Motivo = $cls.Motivo
        Origem = $Origem; Escopo = $Escopo; Admin = $Admin; Comando = $Comando
        ChaveAprov = $ChaveAprov; NomeAprov = $NomeAprov; ChaveApp = $ChaveApp; TarefaCaminho = $TarefaCaminho
    }
}

function Get-ItensInicializacao {
    $itens = New-Object System.Collections.ArrayList
    $runs = @(
        @{ Escopo = 'Usuário';           Chave = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run';             Aprov = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run';   Admin = $false },
        @{ Escopo = 'Todos os usuários'; Chave = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run';             Aprov = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run';   Admin = $true },
        @{ Escopo = 'Todos os usuários'; Chave = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Aprov = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32'; Admin = $true }
    )
    foreach ($r in $runs) {
        if (-not (Test-Path -LiteralPath $r.Chave)) { continue }
        $k = Get-Item -LiteralPath $r.Chave
        foreach ($n in $k.GetValueNames()) {
            if (-not $n) { continue }
            $ativo = Test-AprovadoInicializacao -Chave $r.Aprov -Nome $n
            [void]$itens.Add((New-ItemInicializacao -Nome $n -Comando ([string]$k.GetValue($n)) -Origem 'Registro' -Escopo $r.Escopo -Ativo $ativo -Admin $r.Admin -ChaveAprov $r.Aprov -NomeAprov $n))
        }
    }
    $pastas = @(
        @{ Escopo = 'Usuário';           Pasta = [Environment]::GetFolderPath('Startup');       Aprov = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'; Admin = $false },
        @{ Escopo = 'Todos os usuários'; Pasta = [Environment]::GetFolderPath('CommonStartup'); Aprov = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder'; Admin = $true }
    )
    foreach ($p in $pastas) {
        if (-not $p.Pasta -or -not (Test-Path -LiteralPath $p.Pasta)) { continue }
        foreach ($f in Get-ChildItem -LiteralPath $p.Pasta -File -Force -ErrorAction SilentlyContinue) {
            if ($f.Name -eq 'desktop.ini') { continue }
            $ativo = Test-AprovadoInicializacao -Chave $p.Aprov -Nome $f.Name
            [void]$itens.Add((New-ItemInicializacao -Nome $f.BaseName -Comando $f.FullName -Origem 'Pasta Inicializar' -Escopo $p.Escopo -Ativo $ativo -Admin $p.Admin -ChaveAprov $p.Aprov -NomeAprov $f.Name))
        }
    }
    $base = 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\SystemAppData'
    if (Test-Path -LiteralPath $base) {
        foreach ($pkg in Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue) {
            foreach ($t in Get-ChildItem -LiteralPath $pkg.PSPath -ErrorAction SilentlyContinue) {
                $st = $t.GetValue('State', $null)
                if ($null -eq $st) { continue }
                $nomePkg = ($pkg.PSChildName -split '_')[0]
                [void]$itens.Add((New-ItemInicializacao -Nome $nomePkg -Comando "$($pkg.PSChildName)\$($t.PSChildName)" -Origem 'App da Loja' -Escopo 'Usuário' -Ativo ($st -in 2, 4) -Admin $false -ChaveApp $t.PSPath))
            }
        }
    }
    try {
        foreach ($tk in Get-ScheduledTask -ErrorAction Stop) {
            if ($tk.TaskPath -like '\Microsoft\*') { continue }
            $gat = @($tk.Triggers | Where-Object { $_ } | ForEach-Object { $_.CimClass.CimClassName })
            if (-not ($gat -contains 'MSFT_TaskLogonTrigger' -or $gat -contains 'MSFT_TaskBootTrigger')) { continue }
            $cmd = (@($tk.Actions | ForEach-Object { ("$($_.Execute) $($_.Arguments)").Trim() }) -join ' ; ')
            $uid = [string]$tk.Principal.UserId
            $doUsuario = [bool]($uid -and ($uid -eq $env:USERNAME -or $uid -like "*\$env:USERNAME"))
            $escopo = if ($doUsuario) { 'Usuário' } else { 'Sistema' }
            [void]$itens.Add((New-ItemInicializacao -Nome $tk.TaskName -Comando $cmd -Origem 'Tarefa agendada' -Escopo $escopo -Ativo ([string]$tk.State -ne 'Disabled') -Admin (-not $doUsuario) -TarefaCaminho $tk.TaskPath))
        }
    } catch {}
    return $itens
}
