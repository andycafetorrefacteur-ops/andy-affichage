<#
  fake-order.ps1 — Envoie une fausse commande sur l'imprimante Clover (version Windows / PowerShell)
  pour faire un tour a ton barista.

  Exemples :
    .\fake-order.ps1                 # menu interactif
    .\fake-order.ps1 -Joke 3         # lance directement la blague n3
    .\fake-order.ps1 -Random         # blague au hasard
    .\fake-order.ps1 -List           # liste les blagues
    .\fake-order.ps1 -Cleanup <id>   # supprime une commande creee (par son ID)
#>
param(
  [int]$Joke = 0,
  [switch]$List,
  [switch]$Random,
  [string]$Cleanup
)

# Force TLS 1.2 (necessaire pour l'API Clover sur Windows PowerShell 5.1)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ======================= CONFIG =======================
# Renseigne ici, OU via les variables d'environnement CLOVER_MID / CLOVER_TOKEN / CLOVER_BASE
$MID   = if ($env:CLOVER_MID)   { $env:CLOVER_MID }   else { "TON_MERCHANT_ID" }
$TOKEN = if ($env:CLOVER_TOKEN) { $env:CLOVER_TOKEN } else { "TON_API_TOKEN" }
# Prod: https://api.clover.com   |   Sandbox (test): https://sandbox.dev.clover.com
$BASE  = if ($env:CLOVER_BASE)  { $env:CLOVER_BASE }  else { "https://api.clover.com" }
# ======================================================

$jokes = @(
  @{ name = "Licorne Frappe 7 shots EXTRA paillettes";              note = "URGENT table 1 - le boss te teste" },
  @{ name = "Espresso deca... mais corse quand meme";               note = "Client: surprends-moi" },
  @{ name = "Latte art portrait du barista";                        note = "Demande speciale: ressemblance garantie" },
  @{ name = "Cafe comme d'habitude (devine)";                       note = "Le client refuse de preciser. Bonne chance !" },
  @{ name = "Macchiato noisette, lait d'avoine, 58C pile";          note = "Thermometre exige" },
  @{ name = "1 verre d'eau (facture 28$)";                          note = "Eau de source de torrefaction premium" },
  @{ name = "Affogato geant 5 boules";                              note = "Pour: LE BOSS - service immediat" }
)

function Assert-Config {
  if ($MID   -eq "TON_MERCHANT_ID") { throw "Renseigne ton Merchant ID (variable CLOVER_MID ou dans le script)." }
  if ($TOKEN -eq "TON_API_TOKEN")   { throw "Renseigne ton API token (variable CLOVER_TOKEN ou dans le script)." }
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

function Show-List {
  Write-Host "Blagues disponibles :"
  for ($i = 0; $i -lt $jokes.Count; $i++) {
    Write-Host ("  {0}) {1}" -f ($i + 1), $jokes[$i].name)
  }
}

function Send-Joke {
  param([int]$idx)
  Assert-Config
  $j = $jokes[$idx - 1]
  Write-Host ("Blague choisie : {0}" -f $j.name)

  $order = Invoke-Clover -Method Post -Path "/v3/merchants/$MID/orders" -BodyObj @{ state = "open" }
  $orderId = $order.id
  if (-not $orderId) { throw "Echec creation commande (verifie token / permissions Orders)." }
  Write-Host ("Commande creee : {0}" -f $orderId)

  Invoke-Clover -Method Post -Path "/v3/merchants/$MID/orders/$orderId/line_items" -BodyObj @{ name = $j.name; price = 0 } | Out-Null
  Invoke-Clover -Method Post -Path "/v3/merchants/$MID/orders/$orderId" -BodyObj @{ note = $j.note } | Out-Null
  Invoke-Clover -Method Post -Path "/v3/merchants/$MID/print_event" -BodyObj @{ orderRef = @{ id = $orderId } } | Out-Null

  Write-Host "Ticket envoye a l'imprimante !"
  Write-Host ("Pour annuler la commande : .\fake-order.ps1 -Cleanup {0}" -f $orderId)
}

# ----- Logique principale -----
try {
  if ($Cleanup) {
    Assert-Config
    Invoke-Clover -Method Delete -Path "/v3/merchants/$MID/orders/$Cleanup" | Out-Null
    Write-Host ("Commande {0} supprimee." -f $Cleanup)
    return
  }
  if ($List)   { Show-List; return }
  if ($Random) { Send-Joke -idx (Get-Random -Minimum 1 -Maximum ($jokes.Count + 1)); return }
  if ($Joke -ge 1 -and $Joke -le $jokes.Count) { Send-Joke -idx $Joke; return }

  # Menu interactif
  Show-List
  $choice = Read-Host "Numero de la blague (ou Entree pour au hasard)"
  if ([string]::IsNullOrWhiteSpace($choice)) {
    $choice = Get-Random -Minimum 1 -Maximum ($jokes.Count + 1)
  }
  $n = 0
  if (-not [int]::TryParse($choice, [ref]$n) -or $n -lt 1 -or $n -gt $jokes.Count) {
    throw "Choix invalide."
  }
  Send-Joke -idx $n
}
catch {
  Write-Host ("ERREUR: {0}" -f $_.Exception.Message) -ForegroundColor Red
  exit 1
}
