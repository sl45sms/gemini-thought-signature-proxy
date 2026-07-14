# Dockerfile for gemini-thought-signature-proxy
#
# A tiny proxy that injects skip_thought_signature_validator bypass
# into requests so Gemini models work with VS Code Copilot BYOK in Agent mode.
#
# Build from the gemini-proxy.skarvelis.gr directory:
#   docker build -t gemini-proxy:latest .
# Or:
#   docker build -t localhost:32000/gemini-proxy:latest .

FROM node:22-alpine

# Create a non-root user
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

# Copy package files and install dependencies
COPY package.json ./
RUN npm install --omit=dev

# Copy the local proxy source (includes fixes not yet in the npm package:
# - Strips "-customtools" suffix from model IDs before forwarding to Google
# - Supports all 7+ Gemini models, not just 3.1 Pro)
COPY proxy.js cli.js ./

# Switch to non-root user
RUN chown -R appuser:appgroup /app
USER appuser

# Expose the proxy port (default is 3000)
EXPOSE 3000

# Health check — the proxy forwards all requests to Google,
# so we use a simple TCP port check instead of HTTP.
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD nc -z localhost 3000 || exit 1

# Run the proxy, binding to all interfaces
ENTRYPOINT ["node", "proxy.js"]
