FROM node:20-slim

WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm install --production

COPY . .

RUN npx tsc --outDir dist

ENV NODE_ENV=production
ENV POLL_INTERVAL_MS=10000
ENV HEARTBEAT_INTERVAL_MS=30000
ENV MAX_CONCURRENT_JOBS=2
ENV HEARTBEAT_TIMEOUT_MINUTES=5

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "process.exit(0)"

CMD ["node", "dist/ingestion-worker.js"]
