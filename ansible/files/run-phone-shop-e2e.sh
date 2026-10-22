#!/usr/bin/env bash
set -u

APP_DIR="${PHONE_SHOP_DIR:-/home/vanthoa/Phone-shop}"
ENV_FILE="${PHONE_SHOP_ENV_FILE:-/home/vanthoa/.config/infra/telegram.env}"
E2E_ENV_FILE="${PHONE_SHOP_E2E_ENV_FILE:-/home/vanthoa/.config/infra/e2e.env}"

for config_file in "$ENV_FILE" "$E2E_ENV_FILE"; do
  if [[ -f "$config_file" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$config_file"
    set +a
  fi
done

TELEGRAM_TOKEN="${TELEGRAM_BOT_TOKEN:-${TELEGRAM_TOKEN:-}}"

if [[ -z "$TELEGRAM_TOKEN" || -z "${TELEGRAM_CHAT_ID:-}" ]]; then
  echo "Thieu TELEGRAM_TOKEN (hoac TELEGRAM_BOT_TOKEN) / TELEGRAM_CHAT_ID trong $ENV_FILE" >&2
  exit 2
fi

send_telegram() {
  local message="$1"
  curl --silent --show-error --fail \
    --request POST \
    "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=${message}" \
    >/dev/null
}

if [[ "${1:-}" == "--notification-test" ]]; then
  send_telegram "✅ Phone Shop: kết nối Telegram thành công từ $(hostname) lúc $(date '+%Y-%m-%d %H:%M:%S %Z')."
  echo "Da gui tin nhan thu Telegram."
  exit 0
fi

if [[ ! -f "$APP_DIR/package.json" ]]; then
  send_telegram "❌ Phone Shop: không tìm thấy $APP_DIR/package.json trên $(hostname)."
  echo "Khong tim thay $APP_DIR/package.json" >&2
  exit 3
fi

log_file="$(mktemp)"
trap 'rm -f "$log_file"' EXIT

started_at="$(date '+%Y-%m-%d %H:%M:%S %Z')"
cd "$APP_DIR"

set +e
CI=true npm run test:e2e >"$log_file" 2>&1
test_status=$?
set -e

summary="$(grep -E '[0-9]+ (passed|failed|skipped)' "$log_file" | tail -n 3 || true)"
if [[ -z "$summary" ]]; then
  summary="$(tail -n 8 "$log_file")"
fi
summary="${summary:0:2500}"

if [[ $test_status -eq 0 ]]; then
  result="✅ THÀNH CÔNG"
else
  result="❌ THẤT BẠI (exit code $test_status)"
fi

message="Phone Shop E2E: $result
Máy: $(hostname)
Bắt đầu: $started_at

$summary"

if ! send_telegram "$message"; then
  echo "Khong gui duoc thong bao Telegram." >&2
fi

cat "$log_file"
exit "$test_status"
