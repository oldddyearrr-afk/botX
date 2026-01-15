#!/bin/bash

# --- الإعدادات ---
TOKEN="8412705275:AAF3YfkURUCObv6iFavAe3fQI1Id81JihPs"
OWNER_ID="5747051433"
CONFIG_FILE="config.json"
COOKIES_FILE="cookies.txt"
URL_BASE="https://api.telegram.org/bot$TOKEN"
PORT=${PORT:-10000}

# تهيئة الملفات لضمان عدم وجود أخطاء
[[ ! -f "$CONFIG_FILE" ]] && echo '{"pages": [], "last_tweets": {}}' > "$CONFIG_FILE"

# --- 1. الخادم الوهمي (لحل مشكلة Render) ---
dummy_server() {
    echo "🌐 Dummy Server started on port $PORT"
    while true; do
        { echo -ne "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK"; } | nc -l -p $PORT
    done
}

send_api() {
    curl -s -X POST "$URL_BASE/$1" "${@:2}" > /dev/null
}

# --- 2. وظيفة المراقبة والترجمة (القلب النابض) ---
monitor_logic() {
    while true; do
        if [[ -f "$COOKIES_FILE" ]]; then
            PAGES=$(jq -r '.pages[]' "$CONFIG_FILE" 2>/dev/null)
            for USERNAME in $PAGES; do
                # جلب آخر تغريدة
                TWEET_INFO=$(yt-dlp --cookies "$COOKIES_FILE" --get-id --get-description --max-downloads 1 "https://x.com/$USERNAME" 2>/dev/null)
                TWEET_ID=$(echo "$TWEET_INFO" | head -n 1)
                TWEET_TEXT=$(echo "$TWEET_INFO" | tail -n +2)
                
                LAST_ID=$(jq -r ".last_tweets.\"$USERNAME\"" "$CONFIG_FILE")

                if [[ ! -z "$TWEET_ID" && "$TWEET_ID" != "$LAST_ID" ]]; then
                    # ترجمة النص للعربية
                    TRANSLATED=$(trans -b -to ar "$TWEET_TEXT")
                    CAPTION="🚨 $USERNAME |"$'\n\n'"$TRANSLATED"$'\n\n'"🤍••✰ @RealMadridNews18 ✰••🤍"
                    
                    # جلب رابط الميديا
                    MEDIA_URL=$(yt-dlp --cookies "$COOKIES_FILE" -g "https://x.com/$USERNAME/status/$TWEET_ID" 2>/dev/null | head -n 1)

                    if [[ ! -z "$MEDIA_URL" ]]; then
                        send_api "sendVideo" -d "chat_id=$OWNER_ID" -d "video=$MEDIA_URL" -d "caption=$CAPTION"
                    else
                        send_api "sendMessage" -d "chat_id=$OWNER_ID" -d "text=$CAPTION"
                    fi
                    
                    # تحديث السجل فوراً
                    tmp=$(mktemp)
                    jq ".last_tweets.\"$USERNAME\" = \"$TWEET_ID\"" "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
                fi
            done
        fi
        sleep 180 # فحص كل 3 دقائق
    done
}

# --- 3. استقبال الأوامر (حل مشكلة التكرار) ---
handle_updates() {
    # تصفير الرسائل القديمة عند التشغيل
    local OFFSET=$(curl -s "$URL_BASE/getUpdates" | jq '.result[-1].update_id // 0' | awk '{print $1 + 1}')
    
    echo "🚀 Bot is Online. Ready for commands..."
    while true; do
        UPDATES=$(curl -s "$URL_BASE/getUpdates?offset=$OFFSET&timeout=60")
        
        echo "$UPDATES" | jq -c '.result[]' 2>/dev/null | while read -r update; do
            OFFSET=$(($(echo "$update" | jq '.update_id') + 1))
            MSG=$(echo "$update" | jq -r '.message')
            USER_ID=$(echo "$MSG" | jq -r '.from.id')
            TEXT=$(echo "$MSG" | jq -r '.text')

            if [[ "$USER_ID" == "$OWNER_ID" ]]; then
                # إضافة صفحة
                if [[ "$TEXT" == "/add"* ]]; then
                    PAGE=$(echo "$TEXT" | awk '{print $2}' | tr -d '@')
                    [[ ! -z "$PAGE" ]] && {
                        tmp=$(mktemp)
                        jq ".pages += [\"$PAGE\"] | .pages |= unique" "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
                        send_api "sendMessage" -d "chat_id=$OWNER_ID" -d "text=✅ تم إضافة @$PAGE للمراقبة والترجمة."
                    }
                # حذف صفحة
                elif [[ "$TEXT" == "/del"* ]]; then
                    PAGE=$(echo "$TEXT" | awk '{print $2}' | tr -d '@')
                    tmp=$(mktemp)
                    jq ".pages -= [\"$PAGE\"]" "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
                    send_api "sendMessage" -d "chat_id=$OWNER_ID" -d "text=🗑 تم حذف @$PAGE من القائمة."
                # القائمة
                elif [[ "$TEXT" == "/list" ]]; then
                    LIST=$(jq -r '.pages[]' "$CONFIG_FILE" | sed 's/^/@/' | paste -sd $'\n' -)
                    send_api "sendMessage" -d "chat_id=$OWNER_ID" -d "text=📋 القائمة الحالية:"$'\n'"${LIST:-فارغة}"
                # الكوكيز
                elif echo "$MSG" | jq -e '.document' >/dev/null; then
                    FILE_ID=$(echo "$MSG" | jq -r '.document.file_id')
                    FILE_PATH=$(curl -s "$URL_BASE/getFile?file_id=$FILE_ID" | jq -r '.result.file_path')
                    curl -s "https://api.telegram.org/file/bot$TOKEN/$FILE_PATH" -o "$COOKIES_FILE"
                    send_api "sendMessage" -d "chat_id=$OWNER_ID" -d "text=✅ تم استلام ملف الكوكيز بنجاح!"
                fi
            fi
        done
        sleep 1
    done
}

# تشغيل كل شيء في الخلفية
dummy_server & 
monitor_logic &
handle_updates
