#!/usr/bin/env bash
# Run this ONCE, AFTER you've created a billing account (with a card) in the web console:
#   https://console.cloud.google.com/billing  →  "Add billing account"
# Project setup (project, Places API, restricted key, per-day quota caps) is already done.
# Quota caps already live: SearchNearby = 30/day (→ <=930/mo, inside the 1,000/mo free tier);
# every other Places endpoint = 1/day. So normal use is guaranteed £0; this script just links
# billing (so calls work) and adds a £1 budget alert as a second tripwire.
set -euo pipefail
PROJECT="radioactive-ratings-7743"

echo "Billing accounts on file:"
gcloud billing accounts list --format="table(name,displayName,open)"
read -rp "Paste your BILLING ACCOUNT ID (XXXXXX-XXXXXX-XXXXXX): " BILLING

echo "→ Linking billing to $PROJECT…"
gcloud billing projects link "$PROJECT" --billing-account="$BILLING"

echo "→ Enabling the budget API + creating a £1 alert (alerts only; the 30/day quota is the real brake)…"
gcloud services enable billingbudgets.googleapis.com --project="$PROJECT"
gcloud billing budgets create \
  --billing-account="$BILLING" \
  --display-name="RadioActive £1 tripwire" \
  --budget-amount=1GBP \
  --filter-projects="projects/$PROJECT" \
  --threshold-rule=percent=0.5 \
  --threshold-rule=percent=1.0 || echo "(budget create is optional; quota cap already protects you)"

echo "✅ Done. Billing linked, quota-capped. RadioActive will now pull real Google ratings."
