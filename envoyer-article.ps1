<#
  envoyer-article.ps1 — Envoie UN seul article (texte libre) sur l'imprimante Clover.

  Exemples :
    .\envoyer-article.ps1                                  # envoie le nom par defaut ci-dessous
    .\envoyer-article.ps1 -Name "autre chose rigolote"    # autre texte
    .\envoyer-article.ps1 -Name "cafe" -Qty 3             # 3 exemplaires
    .\envoyer-article.ps1 -Cleanup <orderId>             # supprime la commande creee
#>
param(
  [string]$Name = "le genoux a jimmy extra papa",
  [int]$Qty = 1,
  [string]$Cleanup
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ======================= CONFIG =======================
$MID   = if ($env:CLOVER_MID)   { $env:CLOVER_MID }   else { "TON_MERCHANT_ID" }
$TOKEN = if ($env:CLOVER_TOKEN) { $env:CLOVER_TOKEN } else { "TON_API_TOKEN" }
$BASE  = if ($env:CLOVER_BASE)  { $env:CLOVER_BASE }  else { "https://api.clover.com" }
# ======================================================

function Assert-Config {
  if ($MID   -eq "TON_MERCHANT_ID") { throw "Renseigne ton Merchant ID (variable CLOVER_MID)." }
  if ($TOKEN -eq "TON_API_TOKEN")   { throw "Renseigne ton API token (variable CLOVER_TOKEN)." }
}

function Invoke-Clover {
  param([string]$Method, [string]$Path, $BodyObj)
  $uri = "$BASE$Path"
  $headers = @{ Authorization = "Bearer $TOKEN" }
  $body = $null; $ct = $null
  if ($null -ne $BodyObj) {
    $j    = $BodyObj | ConvertTo-Json -Depth 5 -Compress
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
        $wait = [math]::Min(16, [math]::Pow(2, $attempt))
        Write-Host ("  (429 - pause {0}s puis on reessaie...)" -f $wait) -ForegroundColor Yellow
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

  $order = Invoke-Clover -Method Post -Path "/v3/merchants/$MID/orders" -BodyObj @{ state = "open" }
  $orderId = $order.id
  if (-not $orderId) { throw "Echec creation commande (verifie token / permissions Orders)." }
  Write-Host ("Commande creee : {0}" -f $orderId)

  for ($i = 1; $i -le $Qty; $i++) {
    Invoke-Clover -Method Post -Path "/v3/merchants/$MID/orders/$orderId/line_items" `
      -BodyObj @{ name = $Name; price = 0 } | Out-Null
  }
  Write-Host ("Article ajoute : {0} (x{1})" -f $Name, $Qty)

  Invoke-Clover -Method Post -Path "/v3/merchants/$MID/print_event" -BodyObj @{ orderRef = @{ id = $orderId } } | Out-Null

  Write-Host "Ticket envoye a l'imprimante !"
  Write-Host ("Pour annuler : .\envoyer-article.ps1 -Cleanup {0}" -f $orderId)
}
catch {
  Write-Host ("ERREUR: {0}" -f $_.Exception.Message) -ForegroundColor Red
  exit 1
}
