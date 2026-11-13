<#
    run_tests.ps1 — execute les controles SQL du projet sur Neon et ecrit les sorties brutes.

    Utilisation (depuis la racine du projet, PowerShell) :

        $env:PGURL = '<chaine de connexion Neon>'
        .\preuves\run_tests.ps1                  # execute 001 -> 005
        .\preuves\run_tests.ps1 -Silver          # (re)cree d'abord les vues silver/001 -> 013
        .\preuves\run_tests.ps1 -Image postgres:18.6   # force l'image Docker

    Les sorties sont ecrites dans preuves\logs\ (UTF-8).
    La chaine de connexion n'est jamais ecrite sur disque ni dans les sorties.
    Si psql est installe localement il est utilise ; sinon le script passe par Docker.
#>
param([switch]$Silver, [string]$Image)

$ErrorActionPreference = 'Stop'

# Racine du projet : on remonte depuis l'emplacement du script jusqu'au dossier
# qui contient sql\tests. Le script fonctionne donc depuis sql\tests\ comme
# depuis preuves\, sans chemin code en dur.
$dir = Get-Item -LiteralPath $PSScriptRoot
while ($null -ne $dir -and -not (Test-Path (Join-Path $dir.FullName 'sql\tests'))) { $dir = $dir.Parent }
if ($null -eq $dir) { throw "Racine introuvable : aucun dossier parent de '$PSScriptRoot' ne contient 'sql\tests'." }
$root     = $dir.FullName
$testsDir = Join-Path $root 'sql\tests'

$out = Join-Path $root 'preuves\logs'
New-Item -ItemType Directory -Force -Path $out | Out-Null

if (-not $env:PGURL) {
    $sec = Read-Host 'Chaine de connexion Neon' -AsSecureString
    $env:PGURL = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
}

$hasPsql = $null -ne (Get-Command psql -ErrorAction SilentlyContinue)
if ($hasPsql) {
    Write-Host 'psql local detecte.' -ForegroundColor Green
} else {
    if (-not $Image) {
        # On reutilise une image postgres deja presente localement plutot que d'en telecharger une.
        $locales = @(& docker images --format '{{.Repository}}:{{.Tag}}' 2>$null |
                     Where-Object { $_ -like 'postgres:*' -and $_ -notmatch '<none>' })
        # @() est indispensable : Sort-Object sur un seul element renvoie une chaine,
        # et [0] sur une chaine renvoie son premier caractere.
        $triees = @($locales | Sort-Object -Descending)
        if ($triees.Count -gt 0) { $Image = $triees[0] }
        else {
            $Image = 'postgres:18.6'
            Write-Host "Aucune image postgres locale : $Image sera telechargee." -ForegroundColor Yellow
        }
    }
    Write-Host "psql absent : utilisation de Docker (image $Image)." -ForegroundColor Yellow
}

function Invoke-Sql([string]$relPath, [string]$logName) {
    $log = Join-Path $out $logName
    Write-Host "-> $relPath" -ForegroundColor Cyan
    # psql et docker ecrivent leurs avertissements sur stderr : avec
    # ErrorActionPreference = Stop, PowerShell en ferait une erreur bloquante.
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    if ($hasPsql) {
        $full = Join-Path $root $relPath
        $res = & psql $env:PGURL -v ON_ERROR_STOP=0 -P pager=off -a -f $full 2>&1
    } else {
        $res = & docker run --rm -v "${root}:/work" $Image `
            psql $env:PGURL -v ON_ERROR_STOP=0 -P pager=off -a -f "/work/$($relPath -replace '\\','/')" 2>&1
    }
    $ErrorActionPreference = $prev
    # Out-File en UTF-8 : la redirection *> produisait des logs UTF-16 illisibles.
    @("-- $relPath", "-- Execute le $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')", '--') + $res |
        Out-File -FilePath $log -Encoding utf8
    Write-Host "   sortie : preuves\logs\$logName"
}

if ($Silver) {
    Write-Host "`n== Creation des vues Silver ==" -ForegroundColor Magenta
    Get-ChildItem (Join-Path $root 'sql\silver') -Filter '*.sql' | Sort-Object Name | ForEach-Object {
        Invoke-Sql "sql\silver\$($_.Name)" "silver_$($_.BaseName).txt"
    }
}

Write-Host "`n== Controles ==" -ForegroundColor Magenta
Get-ChildItem $testsDir -Filter '0*.sql' | Sort-Object Name | ForEach-Object {
    Invoke-Sql "sql\tests\$($_.Name)" "$($_.BaseName).txt"
}

Write-Host "`nTermine. Toutes les sorties sont dans preuves\logs\." -ForegroundColor Green
Write-Host "Verifiez qu'aucune ne contient de mot de passe avant de les partager." -ForegroundColor Yellow