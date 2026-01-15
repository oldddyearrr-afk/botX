FROM alpine:latest
RUN apk add --no-cache bash curl jq yt-dlp ffmpeg translate-shell
WORKDIR /app
COPY . .
RUN chmod +x bot.sh
CMD ["./bot.sh"]
