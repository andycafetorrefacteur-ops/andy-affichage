<#
  doordash-panic.ps1 — Fausse grosse commande "DOORDASH" pour faire paniquer le barista.
  Cree une commande avec un titre/banniere DOORDASH bien visible et X exemplaires
  de chaque article, puis l'envoie a l'imprimante.

  Exemples :
    .\doordash-panic.ps1                       # utilise la liste et la quantite ci-dessous
    .\doordash-panic.ps1 -Qty 20               # 20 de chaque
    .\doordash-panic.ps1 -Cleanup <orderId>    # supprime la commande creee
#>
param(
  [int]$Qty = 15,
  [string[]]$Items,
  [string]$Cleanup
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ======================= CONFIG =======================
$MID   = if ($env:CLOVER_MID)   { $env:CLOVER_MID }   else { "TON_MERCHANT_ID" }
$TOKEN = if ($env:CLOVER_TOKEN) { $env:CLOVER_TOKEN } else { "TON_API_TOKEN" }
$BASE  = if ($env:CLOVER_BASE)  { $env:CLOVER_BASE }  else { "https://api.clover.com" }
# ======================================================

# ---- LISTE DES ARTICLES (modifiable) ----
# (sera remplacee par tes vrais articles)
if (-not $Items -or $Items.Count -eq 0) {
  $Items = @(
    "Cappuccino",
    "Latte",
    "Espresso",
    "Americano",
    "Chocolat chaud"
  )
}
# -----------------------------------------

function Assert-Config {
  if ($MID   -eq "TON_MERCHANT_ID") { throw "Renseigne ton Merchant ID (variable CLOVER_MID)." }
  if ($TOKEN -eq "TON_API_TOKEN")   { throw "Renseigne ton API token (variable CLOVER_TOKEN)." }
}

function Invoke-Clover {
  param([string]$Method, [string]$Path, $BodyObj)
  $uri = "$BASE$Path"
  $headers = @{ Authorization = "Bearer $TOKEN" }
  if ($null -ne $BodyObj) {
    $json  = $BodyObj | ConvertTo-Json -Depth 5 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers -Body $bytes -ContentType "application/json; charset=utf-8"
  }
  return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers
}

try {
  if ($Cleanup) {
    Assert-Config
    Invoke-Clover -Method Delete -Path "/v3/merchants/$MID/orders/$Cleanup" | Out-Null
    Write-Host ("Commande {0} supprimee." -f $Cleanup)
    return
  }

  Assert-Config

  Write-Host ("Creation de la commande DOORDASH ({0} x {1} articles)..." -f $Qty, $Items.Count)

  # 1) Commande avec titre DOORDASH
  $order = Invoke-Clover -Method Post -Path "/v3/merchants/$MID/orders" `
            -BodyObj @{ state = "open"; title = "DOORDASH"; note = "*** COMMANDE DOORDASH - A PREPARER MAINTENANT ***" }
  $orderId = $order.id
  if (-not $orderId) { throw "Echec creation commande (verifie token / permissions Orders)." }
  Write-Host ("Commande creee : {0}" -f $orderId)

  # 2) Banniere bien visible en haut des articles
  Invoke-Clover -Method Post -Path "/v3/merchants/$MID/orders/$orderId/line_items" `
    -BodyObj @{ name = ">>>>> DOORDASH - $Qty X TOUT <<<<<"; price = 0 } | Out-Null

  # 3) Qty exemplaires de chaque article
  foreach ($it in $Items) {
    for ($i = 1; $i -le $Qty; $i++) {
      Invoke-Clover -Method Post -Path "/v3/merchants/$MID/orders/$orderId/line_items" `
        -BodyObj @{ name = $it; price = 0 } | Out-Null
    }
    Write-Host ("  + {0} x {1}" -f $Qty, $it)
  }

  # 4) Impression
  Invoke-Clover -Method Post -Path "/v3/merchants/$MID/print_event" -BodyObj @{ orderRef = @{ id = $orderId } } | Out-Null

  Write-Host ""
  Write-Host "Ticket DOORDASH envoye a l'imprimante ! Bonne chance au barista :)"
  Write-Host ("Pour tout annuler : .\doordash-panic.ps1 -Cleanup {0}" -f $orderId)
}
catch {
  Write-Host ("ERREUR: {0}" -f $_.Exception.Message) -ForegroundColor Red
  exit 1
}
