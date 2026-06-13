#!/usr/bin/env bash
#
# fake-order.sh — Envoie une fausse commande sur l'imprimante Clover
# pour faire un tour à ton barista. 🖨️☕
#
# Usage:
#   ./fake-order.sh                # menu interactif
#   ./fake-order.sh 3              # lance directement la blague n°3
#   ./fake-order.sh -r             # blague au hasard
#   ./fake-order.sh -l             # liste les blagues
#   ./fake-order.sh --cleanup ID   # supprime une commande créée (par son ID)
#
set -euo pipefail

# ======================= CONFIG À REMPLIR =======================
MID="${CLOVER_MID:-TON_MERCHANT_ID}"
TOKEN="${CLOVER_TOKEN:-TON_API_TOKEN}"
# Prod: https://api.clover.com   |   Sandbox (test): https://sandbox.dev.clover.com
BASE="${CLOVER_BASE:-https://api.clover.com}"
# ================================================================

# Liste des blagues : "Nom de l'article|Note imprimée sur le ticket"
JOKES=(
  "Licorne Frappé 7 shots EXTRA paillettes|⚠️ URGENT table 1 — le boss te teste 😎☕"
  "Espresso déca... mais corsé quand même|Client: « surprends-moi » 🤔"
  "Latte art portrait du barista|Demande spéciale: ressemblance garantie 🎨"
  "Café 'comme d'habitude' (devine)|Le client refuse de préciser. Bonne chance ! 😈"
  "Macchiato à la noisette, lait d'avoine, 58°C pile|Thermomètre exigé 🌡️"
  "1 verre d'eau (facturé 28\$)|Note: c'est de l'eau de source de torréfaction premium 💧"
  "Affogato géant 5 boules|Pour: LE BOSS — service immédiat 🍨"
)

auth=(-H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json")

die() { echo "❌ $*" >&2; exit 1; }

check_deps() {
  command -v curl >/dev/null || die "curl est requis."
  command -v jq   >/dev/null || die "jq est requis (brew install jq / apt install jq)."
}

check_config() {
  [[ "$MID"   != "TON_MERCHANT_ID" ]] || die "Renseigne ton Merchant ID (MID ou \$CLOVER_MID)."
  [[ "$TOKEN" != "TON_API_TOKEN"   ]] || die "Renseigne ton API token (TOKEN ou \$CLOVER_TOKEN)."
}

list_jokes() {
  echo "Blagues disponibles :"
  local i=1
  for j in "${JOKES[@]}"; do
    printf "  %d) %s\n" "$i" "${j%%|*}"
    i=$((i+1))
  done
}

cleanup() {
  local id="$1"
  check_deps; check_config
  curl -s "${auth[@]}" -X DELETE "$BASE/v3/merchants/$MID/orders/$id" >/dev/null
  echo "🧹 Commande $id supprimée."
}

send_joke() {
  local idx="$1"
  local entry="${JOKES[$((idx-1))]}"
  local name="${entry%%|*}"
  local note="${entry#*|}"

  check_deps; check_config

  echo "🎯 Blague choisie : $name"

  local order_id
  order_id=$(curl -s "${auth[@]}" -X POST "$BASE/v3/merchants/$MID/orders" \
    -d '{"state":"open"}' | jq -r '.id // empty')
  [[ -n "$order_id" ]] || die "Échec création commande (vérifie token/permissions Orders)."
  echo "🧾 Commande créée : $order_id"

  curl -s "${auth[@]}" -X POST "$BASE/v3/merchants/$MID/orders/$order_id/line_items" \
    -d "$(jq -n --arg n "$name" '{name:$n, price:0}')" >/dev/null

  curl -s "${auth[@]}" -X POST "$BASE/v3/merchants/$MID/orders/$order_id" \
    -d "$(jq -n --arg note "$note" '{note:$note}')" >/dev/null

  curl -s "${auth[@]}" -X POST "$BASE/v3/merchants/$MID/print_event" \
    -d "$(jq -n --arg id "$order_id" '{orderRef:{id:$id}}')" >/dev/null

  echo "🖨️  Ticket envoyé à l'imprimante !"
  echo "👉 Pour annuler la commande : ./fake-order.sh --cleanup $order_id"
}

main() {
  case "${1:-}" in
    -l|--list) list_jokes; exit 0 ;;
    --cleanup) [[ -n "${2:-}" ]] || die "Donne l'ID : --cleanup <orderId>"; cleanup "$2"; exit 0 ;;
    -r|--random)
      send_joke "$(( (RANDOM % ${#JOKES[@]}) + 1 ))"; exit 0 ;;
    "" )
      list_jokes
      read -rp "Numéro de la blague (ou Entrée pour au hasard) : " choice
      [[ -z "$choice" ]] && choice="$(( (RANDOM % ${#JOKES[@]}) + 1 ))"
      [[ "$choice" =~ ^[0-9]+$ && "$choice" -ge 1 && "$choice" -le ${#JOKES[@]} ]] \
        || die "Choix invalide."
      send_joke "$choice" ;;
    *)
      [[ "$1" =~ ^[0-9]+$ && "$1" -ge 1 && "$1" -le ${#JOKES[@]} ]] \
        || die "Argument invalide. Voir : ./fake-order.sh -l"
      send_joke "$1" ;;
  esac
}

main "$@"
