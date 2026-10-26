#!/usr/bin/env bash
set -u

readonly TELEGRAM_ENV_FILE="${PHONE_SHOP_TELEGRAM_ENV_FILE:-/home/vanthoa/.config/infra/telegram.env}"
readonly STATE_DIR="${PHONE_SHOP_MONITOR_STATE_DIR:-/var/lib/phone-shop-monitor}"
readonly LOCK_FILE="${PHONE_SHOP_MONITOR_LOCK_FILE:-/run/lock/phone-shop-monitor.lock}"

readonly CPU_THRESHOLD="${MONITOR_CPU_THRESHOLD:-90}"
readonly RAM_THRESHOLD="${MONITOR_RAM_THRESHOLD:-85}"
readonly SWAP_THRESHOLD="${MONITOR_SWAP_THRESHOLD:-85}"
readonly DISK_THRESHOLD="${MONITOR_DISK_THRESHOLD:-85}"
readonly FAILURE_COUNT_THRESHOLD="${MONITOR_FAILURE_COUNT:-2}"
readonly BACKUP_MAX_AGE_HOURS="${MONITOR_BACKUP_MAX_AGE_HOURS:-36}"
readonly WEB_URL="${MONITOR_WEB_URL:-http://127.0.0.1/}"
readonly API_URL="${MONITOR_API_URL:-http://127.0.0.1/api/products}"

if [[ -f "$TELEGRAM_ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$TELEGRAM_ENV_FILE"
  set +a
fi

readonly TELEGRAM_TOKEN_VALUE="${TELEGRAM_BOT_TOKEN:-${TELEGRAM_TOKEN:-}}"

if [[ -z "$TELEGRAM_TOKEN_VALUE" || -z "${TELEGRAM_CHAT_ID:-}" ]]; then
  echo "Thieu TELEGRAM_TOKEN (hoac TELEGRAM_BOT_TOKEN) / TELEGRAM_CHAT_ID trong $TELEGRAM_ENV_FILE" >&2
  exit 2
fi

mkdir -p "$STATE_DIR"
chmod 0700 "$STATE_DIR"

exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  echo "Bo qua: mot lan kiem tra he thong khac dang chay."
  exit 0
fi

new_alerts=""
recoveries=""
problem_count=0
new_alert_keys=()
recovery_keys=()

send_telegram() {
  local message="$1"
  curl --silent --show-error --fail \
    --request POST \
    "https://api.telegram.org/bot${TELEGRAM_TOKEN_VALUE}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=${message}" \
    >/dev/null
}

append_line() {
  local variable_name="$1"
  local value="$2"
  local current_value="${!variable_name:-}"

  if [[ -n "$current_value" ]]; then
    printf -v "$variable_name" '%s\n- %s' "$current_value" "$value"
  else
    printf -v "$variable_name" -- '- %s' "$value"
  fi
}

record_check() {
  local key="$1"
  local status="$2"
  local detail="$3"
  local count_file="$STATE_DIR/${key}.count"
  local alerted_file="$STATE_DIR/${key}.alerted"
  local previous_count=0
  local current_count

  if [[ "$status" == "ok" ]]; then
    rm -f "$count_file"
    if [[ -f "$alerted_file" ]]; then
      append_line recoveries "$detail"
      recovery_keys+=("$key")
    fi
    echo "OK: $detail"
    return
  fi

  problem_count=$((problem_count + 1))
  if [[ -f "$count_file" ]]; then
    read -r previous_count <"$count_file" || previous_count=0
  fi
  [[ "$previous_count" =~ ^[0-9]+$ ]] || previous_count=0
  current_count=$((previous_count + 1))
  printf '%s\n' "$current_count" >"$count_file"
  echo "CANH BAO lan $current_count/$FAILURE_COUNT_THRESHOLD: $detail"

  if (( current_count >= FAILURE_COUNT_THRESHOLD )) && [[ ! -f "$alerted_file" ]]; then
    append_line new_alerts "$detail"
    new_alert_keys+=("$key")
  fi
}

read_cpu_values() {
  local _ label user nice system idle iowait irq softirq steal guest guest_nice
  read -r label user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
  CPU_IDLE=$((idle + iowait))
  CPU_TOTAL=$((user + nice + system + idle + iowait + irq + softirq + steal))
}

cpu_usage_percent() {
  local first_idle first_total second_idle second_total delta_idle delta_total
  read_cpu_values
  first_idle=$CPU_IDLE
  first_total=$CPU_TOTAL
  sleep 2
  read_cpu_values
  second_idle=$CPU_IDLE
  second_total=$CPU_TOTAL
  delta_idle=$((second_idle - first_idle))
  delta_total=$((second_total - first_total))

  if (( delta_total <= 0 )); then
    printf '0\n'
  else
    printf '%s\n' "$((100 * (delta_total - delta_idle) / delta_total))"
  fi
}

memory_usage_percent() {
  awk '
    /MemTotal:/ { total=$2 }
    /MemAvailable:/ { available=$2 }
    END {
      if (total > 0) printf "%d\n", 100 * (total - available) / total
      else print 0
    }
  ' /proc/meminfo
}

swap_usage_percent() {
  awk '
    /SwapTotal:/ { total=$2 }
    /SwapFree:/ { free=$2 }
    END {
      if (total > 0) printf "%d\n", 100 * (total - free) / total
      else print 0
    }
  ' /proc/meminfo
}

check_threshold() {
  local key="$1"
  local label="$2"
  local value="$3"
  local threshold="$4"

  if (( value >= threshold )); then
    record_check "$key" fail "$label dang o muc ${value}% (nguong ${threshold}%)"
  else
    record_check "$key" ok "$label binh thuong: ${value}%"
  fi
}

check_service() {
  local service="$1"
  local label="$2"
  if systemctl is-active --quiet "$service"; then
    record_check "service-${service//[^a-zA-Z0-9]/-}" ok "$label dang chay"
  else
    record_check "service-${service//[^a-zA-Z0-9]/-}" fail "$label da dung ($(systemctl is-active "$service" 2>/dev/null || true))"
  fi
}

check_optional_service() {
  local service="$1"
  local label="$2"
  if systemctl cat "$service" >/dev/null 2>&1; then
    check_service "$service" "$label"
  fi
}

check_http() {
  local key="$1"
  local label="$2"
  local url="$3"
  local status_code
  status_code="$(curl --silent --show-error --max-time 10 --output /dev/null --write-out '%{http_code}' "$url" 2>/dev/null || true)"
  [[ -n "$status_code" ]] || status_code=000

  if [[ "$status_code" == "200" ]]; then
    record_check "$key" ok "$label tra HTTP 200"
  else
    record_check "$key" fail "$label tra HTTP $status_code tai $url"
  fi
}

check_backup() {
  local backup_dir=/var/backups/phone-shop
  local newest_backup newest_timestamp now_timestamp age_hours backup_result

  if systemctl cat phone-shop-backup.service >/dev/null 2>&1; then
    backup_result="$(systemctl show phone-shop-backup.service --property=Result --value 2>/dev/null || true)"
    if [[ -n "$backup_result" && "$backup_result" != "success" ]]; then
      record_check backup-service fail "Backup MySQL gan nhat that bai (Result=$backup_result)"
    else
      record_check backup-service ok "Service backup MySQL khong bao loi"
    fi
  fi

  newest_backup="$(find "$backup_dir" -maxdepth 1 -type f -name 'phoneshop-*.sql.gz' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n 1 || true)"
  if [[ -z "$newest_backup" ]]; then
    record_check backup-freshness fail "Khong tim thay file backup MySQL"
    return
  fi

  newest_timestamp="${newest_backup%% *}"
  newest_timestamp="${newest_timestamp%%.*}"
  now_timestamp="$(date +%s)"
  age_hours=$(((now_timestamp - newest_timestamp) / 3600))
  if (( age_hours > BACKUP_MAX_AGE_HOURS )); then
    record_check backup-freshness fail "Backup MySQL moi nhat da cu ${age_hours} gio (toi da ${BACKUP_MAX_AGE_HOURS} gio)"
  else
    record_check backup-freshness ok "Backup MySQL moi nhat cach day ${age_hours} gio"
  fi
}

check_e2e_result() {
  local e2e_result
  if ! systemctl cat phone-shop-e2e.service >/dev/null 2>&1; then
    return
  fi

  e2e_result="$(systemctl show phone-shop-e2e.service --property=Result --value 2>/dev/null || true)"
  if [[ "$e2e_result" == "exit-code" || "$e2e_result" == "failed" || "$e2e_result" == "timeout" ]]; then
    record_check e2e-result fail "Playwright gan nhat that bai (Result=$e2e_result)"
  else
    record_check e2e-result ok "Playwright khong co ket qua loi moi"
  fi
}

if [[ "${1:-}" == "--notification-test" ]]; then
  send_telegram "✅ Phone Shop Monitor: kết nối Telegram thành công từ $(hostname) lúc $(date '+%Y-%m-%d %H:%M:%S %Z')."
  echo "Da gui tin nhan thu cua bo giam sat."
  exit 0
fi

cpu_percent="$(cpu_usage_percent)"
ram_percent="$(memory_usage_percent)"
swap_percent="$(swap_usage_percent)"
disk_percent="$(df -P / | awk 'NR == 2 { gsub(/%/, "", $5); print $5 }')"

check_threshold cpu "CPU" "$cpu_percent" "$CPU_THRESHOLD"
check_threshold ram "RAM" "$ram_percent" "$RAM_THRESHOLD"
check_threshold swap "Swap" "$swap_percent" "$SWAP_THRESHOLD"
check_threshold disk "O dia /" "$disk_percent" "$DISK_THRESHOLD"

check_service nginx "Nginx"
check_service mysql "MySQL"
check_service phone-shop-backend "Spring Boot backend"
check_service phone-shop-frontend "Next.js frontend"
check_optional_service actions.runner.thoa2005-Phone-shop.phone-shop-vm.service "GitHub Actions runner"

check_http web-http "Website Phone Shop" "$WEB_URL"
check_http api-http "API Phone Shop" "$API_URL"
check_backup
check_e2e_result

checked_at="$(date '+%Y-%m-%d %H:%M:%S %Z')"
host_name="$(hostname)"

if [[ -n "$new_alerts" ]]; then
  if send_telegram "🚨 Phone Shop: PHÁT HIỆN SỰ CỐ
Máy: $host_name
Thời gian: $checked_at

$new_alerts"; then
    for alert_key in "${new_alert_keys[@]}"; do
      touch "$STATE_DIR/${alert_key}.alerted"
    done
  else
    echo "Khong gui duoc canh bao Telegram." >&2
  fi
fi

if [[ -n "$recoveries" ]]; then
  if send_telegram "✅ Phone Shop: ĐÃ PHỤC HỒI
Máy: $host_name
Thời gian: $checked_at

$recoveries"; then
    for recovery_key in "${recovery_keys[@]}"; do
      rm -f "$STATE_DIR/${recovery_key}.alerted"
    done
  else
    echo "Khong gui duoc thong bao phuc hoi Telegram." >&2
  fi
fi

echo "Hoan tat kiem tra: $problem_count van de hien tai; canh bao moi=$([[ -n "$new_alerts" ]] && echo co || echo khong); phuc hoi=$([[ -n "$recoveries" ]] && echo co || echo khong)."
