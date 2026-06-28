#!/usr/bin/env bash
# RadioActive — Google Places billing + quota finaliser (Phase 0). Idempotent.
#
# STATUS: ALREADY APPLIED on 2026-06-28 to project radioactive-ratings-7743
#   • billing linked (billingEnabled=True)
#   • SearchNearby raised to 500/day + 30/min ; GetPlace to 200/day + 10/min
#   • £5 GBP budget tripwire (notification only)
# Kept as the source of truth + a re-runner if the project is ever rebuilt.
#
# Spend model (why these numbers): in-app 45s/150m refetch gate → per-MINUTE quota
# (runaway brake) → per-DAY quota (bounded ceiling) → £5 budget alert (notification).
# The quota caps are the REAL spend ceiling; the budget is only an alert. Real heavy
# use lands well under 150 SearchNearby/day. Requesting `rating` bills Google's
# Enterprise SKU (1,000 free events/mo) — the caps bound a bug, not steady state.
set -euo pipefail

PROJECT="radioactive-ratings-7743"
PROJECT_NUMBER="963663958864"
BILLING="014EBB-DA6B45-9C4231"          # OPEN · GBP · ~£222 credit
CONSUMER="projects/${PROJECT_NUMBER}"
NEARBY="places.googleapis.com/SearchNearbyRequest"
GETPLACE="places.googleapis.com/GetPlaceRequest"

echo "→ Linking billing ${BILLING} to ${PROJECT}…"
gcloud billing projects link "$PROJECT" --billing-account="$BILLING"
gcloud billing projects describe "$PROJECT" --format="value(billingEnabled)"   # expect: True

echo "→ Raising the two endpoints the app actually calls…"
# If a metric id ever errors, rediscover it first (names vary by enablement):
#   gcloud alpha services quota list --service=places.googleapis.com --consumer=${CONSUMER}
# Service defaults are huge (Nearby 75000/day, GetPlace 125000/day, 600/min), so these
# overrides sit UNDER the default and are accepted. If a value is ever REJECTED for
# exceeding the service default, `gcloud alpha services quota delete …` that override
# and rely on the per-minute brake instead.
gcloud alpha services quota update --service=places.googleapis.com --consumer="$CONSUMER" \
  --metric="$NEARBY"   --unit="1/d/{project}"   --value=500 --force
gcloud alpha services quota update --service=places.googleapis.com --consumer="$CONSUMER" \
  --metric="$NEARBY"   --unit="1/min/{project}" --value=30  --force
gcloud alpha services quota update --service=places.googleapis.com --consumer="$CONSUMER" \
  --metric="$GETPLACE" --unit="1/d/{project}"   --value=200 --force
gcloud alpha services quota update --service=places.googleapis.com --consumer="$CONSUMER" \
  --metric="$GETPLACE" --unit="1/min/{project}" --value=10  --force
# Unused endpoints (Autocomplete, Photos, SearchMedia, TextSearch, ReviewPosts) stay at 1/day.

echo "→ £5 budget tripwire (NOTIFICATION ONLY — the quota caps above are the real ceiling)…"
gcloud services enable billingbudgets.googleapis.com --project="$PROJECT"
if gcloud billing budgets list --billing-account="$BILLING" \
     --format="value(displayName)" 2>/dev/null | grep -qx "RadioActive £5 tripwire"; then
  echo "  (budget 'RadioActive £5 tripwire' already exists — skipping)"
else
  gcloud billing budgets create --billing-account="$BILLING" \
    --display-name="RadioActive £5 tripwire" \
    --budget-amount=5GBP \
    --filter-projects="projects/${PROJECT}" \
    --threshold-rule=percent=0.5 --threshold-rule=percent=0.9 --threshold-rule=percent=1.0
fi

echo "✅ Phase 0 done. Billing linked · Nearby 500/30 · GetPlace 200/10 · £5 tripwire. Real ratings unthrottled for normal use."
