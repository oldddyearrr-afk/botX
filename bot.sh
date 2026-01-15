#!/bin/bash

# --- الإعدادات ---
TOKEN="8412705275:AAF3YfkURUCObv6iFavAe3fQI1Id81JihPs"
OWNER_ID="5747051433"
CONFIG_FILE="config.json"
NETSCAPE_COOKIES="cookies.txt"
URL_BASE="https://api.telegram.org/bot$TOKEN"

# تهيئة ملف البيانات إذا لم يكن موجوداً
if [ ! -f "$CONFIG_FILE" ]; then
    echo '{"pages": [], "last_tweets": {}}' > "$CONFIG_FILE"
fi

# --- وظائف التليجرام ---
send_api() {
    local method=$1
    shift
    curl -s -X POST "$URL_BASE/$method" "$@"
}

# --- وظيفة المراقبة (تعمل في الخلفية) ---
monitor_logic() {
    while true; do
        if [ -f "$NETSCAPE_COOKIES" ]; then
            PAGES=$(jq -r '.pages[]' "$CONFIG_FILE")
            for USERNAME in $PAGES; do
                # جلب البيانات باستخدام yt-dlp (أخف طريقة لجلب آخر تغريدة)
                # نستخدم --print لجلب الـ ID والنص
                TWEET_INFO=$(yt-dlp --cookies "$NETSCAPE_COOKIES" --get-id --get-description --max-downloads 1 "https://x.com/$USERNAME" 2>/dev/null)
                TWEET_ID=$(echo "$TWEET_INFO" | head -n 1)
                TWEET_TEXT=$(echo "$TWEET_INFO" | tail -n +2)
                
                LAST_ID=$(jq -r ".last_tweets.\"$USERNAME\"" "$CONFIG_FILE")

                if [ "$TWEET_ID" != "$LAST_ID" ] && [ ! -z "$TWEET_ID" ]; then
                    CAPTION="🚨 $USERNAME |"$'\n\n'"$TWEET_TEXT"$'\n\n'"🤍••✰ @RealMadridNews18 ✰••🤍"
                    TWEET_URL="https://x.com/$USERNAME/status/$TWEET_ID"
                    
                    # جلب رابط الميديا
                    MEDIA_URL=$(yt-dlp --cookies "$NETSCAPE_COOKIES" -g "$TWEET_URL" 2>/dev/null | head -n 1)

                    if [ ! -z "$MEDIA_URL" ]; then
                        send_api "sendVideo" -d "chat_id=$OWNER_ID" -d "video=$MEDIA_URL" -d "caption=$CAPTION"
                    else
                        send_api "sendMessage" -d "chat_id=$OWNER_ID" -d "text=$CAPTION"
                    fi

                    # تحديث الـ ID في ملف json
                    tmp=$(mktemp)
                    jq ".last_tweets.\"$USERNAME\" = \"$TWEET_ID\"" "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
                fi
            done
        fi
        sleep 180
    done
}

# --- وظيفة استقبال الأوامر (Long Polling) ---
handle_updates() {
    local OFFSET=0
    while true; do
        UPDATES=$(curl -s "$URL_BASE/getUpdates?offset=$OFFSET&timeout=30")
        echo "$UPDATES" | jq -c '.result[]' | while read -r update; do
            OFFSET=$(($(echo "$update" | jq '.update_id') + 1))
            USER_ID=$(echo "$update" | jq -r '.message.from.id')
            TEXT=$(echo "$update" | jq -r '.message.text')
            
            # التأكد من أن المستخدم هو الأونر
            if [ "$USER_ID" == "$OWNER_ID" ]; then
                # أمر إضافة صفحة
                if [[ "$TEXT" == "/add"* ]]; then
                    NEW_PAGE=$(echo "$TEXT" | cut -d' ' -f2 | tr -d '@')
                    tmp=$(mktemp)
                    jq ".pages += [\"$NEW_PAGE\"] | .pages |= unique" "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
                    send_api "sendMessage" -d "chat_id=$OWNER_ID" -d "text=✅ تم إضافة @$NEW_PAGE"
                
                # استقبال ملف الكوكيز
                elif echo "$update" | jq -e '.message.document' >/dev/null; then
                    FILE_NAME=$(echo "$update" | jq -r '.message.document.file_name')
                    FILE_ID=$(echo "$update" | jq -r '.message.document.file_id')
                    FILE_PATH=$(send_api "getFile" -d "file_id=$FILE_ID" | jq -r '.result.file_path')
                    
                    curl -s "https://api.telegram.org/file/bot$TOKEN/$FILE_PATH" -o "$NETSCAPE_COOKIES"
                    send_api "sendMessage" -d "chat_id=$OWNER_ID" -d "text=✅ تم تحديث ملف الكوكيز (Netscape)"
                fi
            fi
        done
    done
}

# تشغيل المراقبة في الخلفية
monitor_logic &
# تشغيل معالج الأوامر في الواجهة
handle_updates
