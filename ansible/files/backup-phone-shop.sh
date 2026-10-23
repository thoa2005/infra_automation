#!/usr/bin/env bash
set -euo pipefail

backup_dir=/var/backups/phone-shop
timestamp="$(date '+%Y%m%d-%H%M%S')"
backup_file="$backup_dir/phoneshop-$timestamp.sql.gz"
temporary_file="$backup_dir/.phoneshop-$timestamp.sql.gz.tmp"

umask 077
mkdir -p "$backup_dir"

mysqldump \
  --defaults-extra-file=/etc/phone-shop/backup.cnf \
  --no-tablespaces \
  --single-transaction \
  --routines \
  --triggers \
  phoneshop_db | gzip -9 >"$temporary_file"

mv "$temporary_file" "$backup_file"
find "$backup_dir" -type f -name 'phoneshop-*.sql.gz' -mtime +13 -delete

echo "Da tao backup: $backup_file"
