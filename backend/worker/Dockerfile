FROM node:20-slim

WORKDIR /app

COPY package.worker.json ./package.json
RUN npm install

COPY tsconfig.json ./
COPY ingestion-worker.ts ./
COPY adapters/ ./adapters/
COPY lib/ ./lib/

RUN npx tsc --outDir dist
RUN npm prune --production

ENV NODE_ENV=production
ENV POLL_INTERVAL_MS=10000
ENV HEARTBEAT_INTERVAL_MS=30000
ENV MAX_CONCURRENT_JOBS=2
ENV HEARTBEAT_TIMEOUT_MINUTES=5
ENV HEALTH_PORT=8080

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://localhost:8080/health').then(r=>{if(!r.ok)throw 1}).catch(()=>process.exit(1))"

CMD ["node", "dist/ingestion-worker.js"]
