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
  [int]$Qty = 6,
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
    "Cappuccino - GRAND - lait d'avoine - +2 shots - sirop caramel - extra chaud",
    "Latte - lait de soya - sirop vanille - DECA - 1 sucre",
    "Matcha latte - lait d'amande - sirop noisette - extra mousse",
    "Dirty chai - GRAND - +1 shot - lait d'avoine - extra epices",
    "Mocha - sans sucre - creme fouettee - extra chocolat",
    "Flat White - lait entier - double ristretto",
    "Chai latte - GRAND - lait d'avoine - sirop citrouille",
    "Bubble Tea - mangue - bulles tapioca - peu de glace",
    "Bagel - sesame - fromage a la creme + bacon + oeuf",
    "Americano - allonge - DECA - 2 cremes",
    "Espresso - double - DECA",
    "Macchiato - caramel - extra mousse",
    "Chemex - infusion lente - pour 2",
    "Flash Brew - sirop vanille - glace extra",
    "Long black - allonge - sans sucre",
    "Chocolat chaud - lait d'avoine - creme fouettee - guimauves",
    "Croissant - rechauffe - beurre + confiture",
    "Latte glace St-Valentin - lait d'amande - extra sirop",
    "Le donatello - lait de soya - extra",
    "Mini Beignets Pistache - douzaine - extra sucre"
  )
}
# -----------------------------------------

function Assert-Config {
  if ($MID   -eq "TON_MERCHANT_ID") { throw "Renseigne ton Merchant ID (variable CLOVER_MID)." }
  if ($TOKEN -eq "TON_API_TOKEN")   { throw "Renseigne ton API token (variable CLOVER_TOKEN)." }
}

function Invoke-Clover {
  param([string]$Method, [string]$Path, $BodyObj, [string]$Json)
  $uri = "$BASE$Path"
  $headers = @{ Authorization = "Bearer $TOKEN" }
  $body = $null; $ct = $null
  if ($Json) {
    $body = [System.Text.Encoding]::UTF8.GetBytes($Json)
    $ct   = "application/json; charset=utf-8"
  }
  elseif ($null -ne $BodyObj) {
    $j    = $BodyObj | ConvertTo-Json -Depth 6 -Compress
    $body = [System.Text.Encoding]::UTF8.GetBytes($j)
    $ct   = "application/json; charset=utf-8"
  }
  for ($attempt = 1; $attempt -le 6; $attempt++) {
    try {
      if ($body) { return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers -Body $body -ContentType $ct }
      else       { return Invoke-RestMethod -Method $Method -Uri $uri -Headers $headers }
    }
    catch {
      $code = $null
      try { $code = [int]$_.Exception.Response.StatusCode } catch {}
      if ($code -eq 429 -and $attempt -lt 6) {
        $wait = [math]::Min(16, [math]::Pow(2, $attempt))  # 2,4,8,16,16
        Write-Host ("  (429 trop d'appels - pause {0}s puis on reessaie...)" -f $wait) -ForegroundColor Yellow
        Start-Sleep -Seconds $wait
        continue
      }
      throw
    }
  }
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
            -BodyObj @{ state = "open"; title = "DOORDASH RAMASSAGE"; note = "*** DOORDASH - RAMASSAGE - A PREPARER MAINTENANT - LE CLIENT EST EN ROUTE ***" }
  $orderId = $order.id
  if (-not $orderId) { throw "Echec creation commande (verifie token / permissions Orders)." }
  Write-Host ("Commande creee : {0}" -f $orderId)

  # 2) Construire toutes les lignes (banniere + Qty x chaque article)
  $lines = New-Object System.Collections.ArrayList
  [void]$lines.Add(@{ name = ">>> DOORDASH RAMASSAGE - $Qty X TOUT <<<"; price = 0 })
  foreach ($it in $Items) {
    for ($i = 1; $i -le $Qty; $i++) { [void]$lines.Add(@{ name = $it; price = 0 }) }
  }
  Write-Host ("Ajout de {0} lignes par lots (anti rate-limit)..." -f $lines.Count)

  # 3) Envoi par lots via bulk_line_items (1 appel pour ~25 lignes)
  $batchSize = 25
  for ($start = 0; $start -lt $lines.Count; $start += $batchSize) {
    $end   = [math]::Min($start + $batchSize, $lines.Count) - 1
    $batch = @($lines[$start..$end])
    $itemsJson = ($batch | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 3 }) -join ","
    $json = '{"items":[' + $itemsJson + ']}'
    Invoke-Clover -Method Post -Path "/v3/merchants/$MID/orders/$orderId/bulk_line_items" `
      -Json $json | Out-Null
    Write-Host ("  ... {0}/{1} lignes ajoutees" -f ($end + 1), $lines.Count)
    Start-Sleep -Milliseconds 500
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
