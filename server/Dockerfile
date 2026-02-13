FROM node:22-slim

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --production

COPY src/ src/
COPY tsconfig.json ./

# Build TypeScript
RUN npx tsc --outDir dist

EXPOSE 3000

CMD ["node", "--import", "tsx", "src/index.ts"]
