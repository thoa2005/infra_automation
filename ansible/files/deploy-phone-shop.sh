#!/usr/bin/env bash
set -Eeuo pipefail

if [[ ${#} -ne 1 || ! "${1}" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Cach dung: deploy-phone-shop <git-commit-sha>" >&2
  exit 2
fi

readonly APP_COMMIT="${1}"
readonly APP_USER="vanthoa"
readonly INFRA_DIR="/home/${APP_USER}/infra_automation"
readonly INVENTORY="${INFRA_DIR}/ansible/inventory/hosts.ini"
readonly PLAYBOOK="${INFRA_DIR}/ansible/playbooks/phone-shop-deploy.yml"
readonly LOCK_FILE="/run/lock/phone-shop-deploy.lock"

export ANSIBLE_COLLECTIONS_PATH="/home/${APP_USER}/.ansible/collections:/usr/share/ansible/collections"

exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
  echo "Dang co mot lan trien khai Phone Shop khac dang chay." >&2
  exit 1
fi

sudo -H -u "${APP_USER}" git -C "${INFRA_DIR}" pull --ff-only

ansible-playbook \
  -i "${INVENTORY}" \
  "${PLAYBOOK}" \
  -e "phone_shop_version=${APP_COMMIT}"

curl --fail --silent --show-error http://127.0.0.1/ >/dev/null
curl --fail --silent --show-error http://127.0.0.1/api/products >/dev/null

echo "Da trien khai Phone Shop commit ${APP_COMMIT}."
