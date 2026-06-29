FROM node:22-bookworm-slim

WORKDIR /app

RUN apt-get update \
  && apt-get install -y --no-install-recommends python3 make g++ \
  && rm -rf /var/lib/apt/lists/*

COPY package.json package-lock.json ./
RUN npm ci --omit=dev

COPY dist ./dist

ENV NODE_ENV=production
ENV HOST=0.0.0.0
ENV PORT=3003
ENV DATABASE_PATH=/data/feigong.db
ENV UPLOAD_DIR=/uploads
ENV CORS_ORIGIN=*

EXPOSE 3003

CMD ["node", "dist/index.js"]
