# ベースとなるイメージ
FROM node:18-alpine AS base

# 必要なときだけ依存関係をインストール
FROM base AS deps
# libc6-compatが必要な理由を理解するには、https://github.com/nodejs/docker-node/tree/b4117f9333da4138b03a546ec926ef50a31506c3#nodealpine を確認してください。
RUN apk add --no-cache libc6-compat
WORKDIR /app

# 優先的なパッケージマネージャに基づいて依存関係をインストール
COPY package.json yarn.lock* package-lock.json* pnpm-lock.yaml* ./
RUN \
  if [ -f yarn.lock ]; then yarn --frozen-lockfile; \
  elif [ -f package-lock.json ]; then npm ci; \
  elif [ -f pnpm-lock.yaml ]; then yarn global add pnpm && pnpm i --frozen-lockfile; \
  else echo "Lockfile not found." && exit 1; \
  fi

# 必要なときだけソースコードを再ビルド
FROM base AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Next.jsは完全に匿名のテレメトリーデータを収集します。
# 詳細はこちら：https://nextjs.org/telemetry
# ビルド中にテレメトリーを無効にしたい場合は、以下の行のコメントを外してください。
# ENV NEXT_TELEMETRY_DISABLED 1

RUN yarn build

# npmを使用している場合は、上記をコメントアウトし、代わりに以下を使用してください
# RUN npm run build

# 本番イメージ、すべてのファイルをコピーしてnextを実行
FROM base AS runner
WORKDIR /app

ENV NODE_ENV production
# ランタイム中にテレメトリーを無効にしたい場合は、以下の行のコメントを外してください。
# ENV NEXT_TELEMETRY_DISABLED 1
# ENV NEXT_TELEMETRY_DISABLED 1

RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

COPY --from=builder /app/public ./public

# prerenderキャッシュの正しい権限を設定
RUN mkdir .next
RUN chown nextjs:nodejs .next

# 自動的に出力トレースを活用してイメージサイズを縮小
# https://nextjs.org/docs/advanced-features/output-file-tracing
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

USER nextjs

EXPOSE 3000

ENV PORT 3000
# ホスト名をlocalhostに設定
ENV HOSTNAME "0.0.0.0"

# server.jsは、standalone出力からnext buildによって作成されます
# https://nextjs.org/docs/pages/api-reference/next-config-js/output
CMD ["node", "server.js"]