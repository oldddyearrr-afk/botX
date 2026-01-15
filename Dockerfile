FROM alpine:latest

# تثبيت الأدوات الضرورية فقط
RUN apk add --no-cache bash curl jq yt-dlp ffmpeg

WORKDIR /app
COPY . .

# إعطاء صلاحيات التنفيذ
RUN chmod +x bot.sh

# تشغيل البوت
CMD ["./bot.sh"]
