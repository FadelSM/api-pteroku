#!/bin/bash
# uninstall_joomoddss.sh – rollback penuh ke panel vanilla

PANEL_PATH="/var/www/pterodactyl"
BACKUP_DIR="/root/pterodactyl_backups"

echo "=== JooModdss Uninstall Rollback ==="

# 1. restore semua .bak terbaru (berdasarkan timestamp)
LATEST=$(ls -1 "$BACKUP_DIR"/*.bak 2>/dev/null | head -1 | xargs -n1 basename | sed 's/.*_\([0-9\-]*\)\.bak/\1/' | head -1)
[[ -z "$LATEST" ]] && { echo "Tidak ada backup ditemukan, keluar."; exit 1; }

for bak in "$BACKUP_DIR"/*_${LATEST}.bak; do
    FILE=$(basename "$bak" | sed "s/_${LATEST}\.bak//")
    TARGET="$PANEL_PATH/$FILE"
    [[ -f "$TARGET" ]] && cp "$bak" "$TARGET" && echo "✅ Restore $FILE"
done

# 2. hapus file tema
rm -f "$PANEL_PATH/public/assets/custom/joomoddss-theme.css" \
      "$PANEL_PATH/public/assets/custom/joomoddss-theme.js"
rmdir "$PANEL_PATH/public/assets/custom" 2>/dev/null

# 3. bersihkan baris tambahan di admin.blade.php
sed -i '/JooModdss Security & Theme/d;
        /joomoddss-theme\.css/d;
        /joomoddss-theme\.js/d' "$PANEL_PATH/resources/views/layouts/admin.blade.php"

# 4. cache clear
cd "$PANEL_PATH"
php artisan view:clear && php artisan config:clear && php artisan cache:clear && php artisan route:clear

echo "=== Rollback selesai – panel kembali vanilla ==="
