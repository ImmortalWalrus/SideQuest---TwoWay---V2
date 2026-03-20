FROM node:20-bookworm-slim

WORKDIR /app

COPY backend/package.json ./package.json
RUN npm install --no-audit --no-fund

COPY backend/. ./

ENV NODE_ENV=production
ENV PORT=8080

EXPOSE 8080

CMD ["npm", "run", "start"]
