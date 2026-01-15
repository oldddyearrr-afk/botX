FROM alpine:latest

# تثبيت الأدوات: bash, curl, jq, yt-dlp, ffmpeg + translate-shell للترجمة
RUN apk add --no-cache bash curl jq yt-dlp ffmpeg translate-shell

WORKDIR /app
COPY . .

RUN chmod +x bot.sh

CMD ["./bot.sh"]
