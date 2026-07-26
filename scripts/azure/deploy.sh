#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-plan}"
ROOT_DIR="${AZURE_BOOTSTRAP_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
TF_DIR="$ROOT_DIR/terraform-azure"
TFVARS_FILE="$TF_DIR/terraform.tfvars"

if [[ ! -f "$TFVARS_FILE" ]]; then
  echo "terraform.tfvars not found at $TFVARS_FILE" >&2
  echo "Run: bash scripts/azure/bootstrap.sh" >&2
  exit 1
fi

case "$ACTION" in
  plan)
    terraform -chdir="$TF_DIR" init
    terraform -chdir="$TF_DIR" plan -var-file="$TFVARS_FILE"
    ;;
  apply)
    terraform -chdir="$TF_DIR" init
    terraform -chdir="$TF_DIR" apply -var-file="$TFVARS_FILE"
    ;;
  destroy)
    terraform -chdir="$TF_DIR" destroy -var-file="$TFVARS_FILE"
    ;;
  *)
    echo "Unknown action: $ACTION" >&2
    echo "Expected one of: plan, apply, destroy" >&2
    exit 1
    ;;
esac
