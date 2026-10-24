FROM node:22-slim
WORKDIR /app
ENV NODE_ENV=production DATABASE_PATH=/data/playscribe.db PORT=8080
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY tsconfig.json ./
COPY src ./src
RUN mkdir -p /data && chown node:node /data
USER node
EXPOSE 8080
CMD ["node", "--import", "tsx", "--no-warnings=ExperimentalWarning", "src/index.ts"]
