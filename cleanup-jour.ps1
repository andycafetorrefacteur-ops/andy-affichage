<#
  cleanup-jour.ps1 — Supprime UNIQUEMENT nos fausses commandes (blagues) creees aujourd'hui.

  SECURITE :
   - Par defaut = APERCU (ne supprime rien, affiche juste la liste).
   - Ajoute -Confirm pour supprimer reellement.
   - Ne cible QUE les commandes a 0$ ET contenant un de nos textes bidons.
     => les vraies commandes clients (avec un montant) ne sont jamais touchees.

  Exemples :
    .\cleanup-jour.ps1            # apercu : montre ce qui SERAIT supprime
    .\cleanup-jour.ps1 -Confirm   # supprime pour de vrai
    .\cleanup-jour.ps1 -Days 1    # depuis hier (apercu)
#>
param(
  [switch]$Confirm,
  [int]$Days = 0
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ======================= CONFIG =======================
$MID   = if ($env:CLOVER_MID)   { $env:CLOVER_MID }   else { "TON_MERCHANT_ID" }
$TOKEN = if ($env:CLOVER_TOKEN) { $env:CLOVER_TOKEN } else { "TON_API_TOKEN" }
$BASE  = if ($env:CLOVER_BASE)  { $env:CLOVER_BASE }  else { "https://api.clover.com" }
# ======================================================

# Textes qui identifient NOS fausses commandes (insensible a la casse)
$MARKERS = @(
  "DOORDASH",
  "genoux a jimmy",
  "Licorne",
  "Affogato",
  "Espresso deca",
  "Latte art portrait",
  "comme d'habitude",
  "verre d'eau",
  "double ristretto",
  "bulles tapioca",
  "fromage a la creme + bacon",
  "X TOUT"
)

function Assert-Config {
  if ($MID   -eq "TON_MERCHANT_ID") { throw "Renseigne ton Merchant ID (variable CLOVER_MID)." }
  if ($TOKEN -eq "TON_API_TOKEN")   { throw "Renseigne ton API token (variable CLOVER_TOKEN)." }
}

function Invoke-Clover {
  param([string]$Method, [string]$Path)
  $uri = "$BASE$Path"
  $headers = @{ Authorization = "Bearer $TOKEN" }
  for ($attempt = 1; $attempt -le 6; $attempt++) {
    try { return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers }
    catch {
      $code = $null
      try { $code = [int]$_.Exception.Response.StatusCode } catch {}
      if ($code -eq 429 -and $attempt -lt 6) {
        $wait = [math]::Min(16, [math]::Pow(2, $attempt))
        Write-Host ("  (429 - pause {0}s...)" -f $wait) -ForegroundColor Yellow
        Start-Sleep -Seconds $wait; continue
      }
      throw
    }
  }
}

function Is-Ours {
  param($order)
  # Doit etre a 0$ (les vraies ventes ont un montant) ...
  if ([int]$order.total -ne 0) { return $false }
  # ... ET contenir un de nos marqueurs (titre ou nom d'article)
  $texts = @()
  if ($order.title) { $texts += $order.title }
  if ($order.lineItems -and $order.lineItems.elements) {
    foreach ($li in $order.lineItems.elements) { if ($li.name) { $texts += $li.name } }
  }
  foreach ($t in $texts) {
    foreach ($m in $MARKERS) {
      if ($t -and $t.ToLower().Contains($m.ToLower())) { return $true }
    }
  }
  return $false
}

try {
  Assert-Config

  $start   = (Get-Date).Date.AddDays(-$Days)
  $startMs = [long]([DateTimeOffset]::new($start)).ToUnixTimeMilliseconds()
  Write-Host ("Recherche des commandes depuis le {0}..." -f $start.ToString("yyyy-MM-dd"))

  $path = "/v3/merchants/$MID/orders?filter=createdTime%3E%3D$startMs&expand=lineItems&limit=1000"
  $resp = Invoke-Clover -Method Get -Path $path
  $orders = @($resp.elements)
  Write-Host ("{0} commande(s) trouvee(s) sur la periode." -f $orders.Count)

  $ours = @($orders | Where-Object { Is-Ours $_ })
  if ($ours.Count -eq 0) {
    Write-Host "Aucune fausse commande a nettoyer. Rien a faire." -ForegroundColor Green
    return
  }

  Write-Host ""
  Write-Host ("=== {0} fausse(s) commande(s) identifiee(s) ===" -f $ours.Count) -ForegroundColor Cyan
  foreach ($o in $ours) {
    $dt = [DateTimeOffset]::FromUnixTimeMilliseconds([long]$o.createdTime).LocalDateTime
    $first = ""
    if ($o.lineItems -and $o.lineItems.elements -and $o.lineItems.elements.Count -gt 0) {
      $first = $o.lineItems.elements[0].name
    } elseif ($o.title) { $first = $o.title }
    Write-Host ("  {0}  {1}  total={2}$  -> {3}" -f $o.id, $dt.ToString("HH:mm"), ([int]$o.total/100), $first)
  }
  Write-Host ""

  if (-not $Confirm) {
    Write-Host "APERCU seulement - rien n'a ete supprime." -ForegroundColor Yellow
    Write-Host "Pour supprimer pour de vrai, relance avec :  .\cleanup-jour.ps1 -Confirm"
    return
  }

  Write-Host "Suppression en cours..." -ForegroundColor Red
  $n = 0
  foreach ($o in $ours) {
    Invoke-Clover -Method Delete -Path "/v3/merchants/$MID/orders/$($o.id)" | Out-Null
    $n++
    Write-Host ("  supprimee : {0} ({1}/{2})" -f $o.id, $n, $ours.Count)
    Start-Sleep -Milliseconds 300
  }
  Write-Host ("Termine. {0} fausse(s) commande(s) supprimee(s)." -f $n) -ForegroundColor Green
}
catch {
  Write-Host ("ERREUR: {0}" -f $_.Exception.Message) -ForegroundColor Red
  exit 1
}
