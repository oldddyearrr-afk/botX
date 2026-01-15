#!/bin/bash

# --- الإعدادات ---
TOKEN="8412705275:AAF3YfkURUCObv6iFavAe3fQI1Id81JihPs"
OWNER_ID="5747051433"
CONFIG_FILE="config.json"
COOKIES_FILE="cookies.txt"
URL_BASE="https://api.telegram.org/bot$TOKEN"

# تهيئة ملف الإعدادات
if [ ! -f "$CONFIG_FILE" ]; then
    echo '{"pages": [], "last_tweets": {}}' > "$CONFIG_FILE"
fi

# دالة التليجرام
send_api() {
    local method=$1
    shift
    curl -s -X POST "$URL_BASE/$method" "$@"
}

# --- وظيفة المراقبة والترجمة ---
monitor_logic() {
    while true; do
        if [ -f "$COOKIES_FILE" ]; then
            PAGES=$(jq -r '.pages[]' "$CONFIG_FILE")
            for USERNAME in $PAGES; do
                TWEET_INFO=$(yt-dlp --cookies "$COOKIES_FILE" --get-id --get-description --max-downloads 1 "https://x.com/$USERNAME" 2>/dev/null)
                TWEET_ID=$(echo "$TWEET_INFO" | head -n 1)
                TWEET_TEXT=$(echo "$TWEET_INFO" | tail -n +2)
                
                LAST_ID=$(jq -r ".last_tweets.\"$USERNAME\"" "$CONFIG_FILE")

                if [ "$TWEET_ID" != "$LAST_ID" ] && [ ! -z "$TWEET_ID" ]; then
                    # --- حيلة الترجمة التلقائية للعربية ---
                    # نستخدم trans للترجمة التلقائية من أي لغة إلى العربية
                    TRANSLATED_TEXT=$(trans -b -to ar "$TWEET_TEXT")
                    
                    CAPTION="🚨 $USERNAME |"$'\n\n'"$TRANSLATED_TEXT"$'\n\n'"🤍••✰ @RealMadridNews18 ✰••🤍"
                    TWEET_URL="https://x.com/$USERNAME/status/$TWEET_ID"
                    
                    MEDIA_URL=$(yt-dlp --cookies "$COOKIES_FILE" -g "$TWEET_URL" 2>/dev/null | head -n 1)

                    if [ ! -z "$MEDIA_URL" ]; then
                        send_api "sendVideo" -d "chat_id=$OWNER_ID" -d "video=$MEDIA_URL" -d "caption=$CAPTION"
                    else
                        send_api "sendMessage" -d "chat_id=$OWNER_ID" -d "text=$CAPTION"
                    fi

                    tmp=$(mktemp)
                    jq ".last_tweets.\"$USERNAME\" = \"$TWEET_ID\"" "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
                fi
            done
        fi
        sleep 180
    done
}

# --- استقبال الأوامر (إضافة، حذف، قائمة، كوكيز) ---
handle_updates() {
    local OFFSET=0
    while true; do
        UPDATES=$(curl -s "$URL_BASE/getUpdates?offset=$OFFSET&timeout=30")
        echo "$UPDATES" | jq -c '.result[]' | while read -r update; do
            OFFSET=$(($(echo "$update" | jq '.update_id') + 1))
            USER_ID=$(echo "$update" | jq -r '.message.from.id')
            TEXT=$(echo "$update" | jq -r '.message.text')
            
            if [ "$USER_ID" == "$OWNER_ID" ]; then
                # 1. إضافة صفحة: /add @user
                if [[ "$TEXT" == "/add"* ]]; then
                    PAGE=$(echo "$TEXT" | cut -d' ' -f2 | tr -d '@')
                    tmp=$(mktemp)
                    jq ".pages += [\"$PAGE\"] | .pages |= unique" "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
                    send_api "sendMessage" -d "chat_id=$OWNER_ID" -d "text=✅ تم إضافة @$PAGE للمراقبة والترجمة."

                # 2. حذف صفحة: /del @user
                elif [[ "$TEXT" == "/del"* ]]; then
                    PAGE=$(echo "$TEXT" | cut -d' ' -f2 | tr -d '@')
                    tmp=$(mktemp)
                    jq ".pages -= [\"$PAGE\"]" "$CONFIG_FILE" > "$tmp" && mv "$tmp" "$CONFIG_FILE"
                    send_api "sendMessage" -d "chat_id=$OWNER_ID" -d "text=🗑 تم حذف @$PAGE من القائمة."

                # 3. عرض القائمة: /list
                elif [[ "$TEXT" == "/list" ]]; then
                    LIST=$(jq -r '.pages[]' "$CONFIG_FILE" | sed 's/^/@/')
                    send_api "sendMessage" -d "chat_id=$OWNER_ID" -d "text=📋 الصفحات المتابعة حالياً:"$'\n'"$LIST"

                # 4. استقبال ملف الكوكيز
                elif echo "$update" | jq -e '.message.document' >/dev/null; then
                    FILE_ID=$(echo "$update" | jq -r '.message.document.file_id')
                    FILE_PATH=$(send_api "getFile" -d "file_id=$FILE_ID" | jq -r '.result.file_path')
                    curl -s "https://api.telegram.org/file/bot$TOKEN/$FILE_PATH" -o "$COOKIES_FILE"
                    send_api "sendMessage" -d "chat_id=$OWNER_ID" -d "text=✅ تم تحديث الكوكيز (Netscape) بنجاح!"
                fi
            fi
        done
    done
}

monitor_logic &
handle_updates
