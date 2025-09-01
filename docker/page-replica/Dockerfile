# 1/ Build Stage: Install dependencies
FROM node:24.7.0-alpine3.21 AS build

WORKDIR /app

# Install system dependencies for Puppeteer
RUN apk add --no-cache \
    chromium \
    nss \
    freetype \
    freetype-dev \
    harfbuzz \
    ca-certificates \
    ttf-freefont \
    && rm -rf /var/cache/apk/*

# copy only repo files into the container
COPY package*.json ./
RUN npm install --omit=dev

COPY . ./

# 2/ Runtime Stage: Minimal runtime environment
FROM node:24.7.0-alpine3.21

# Set Puppeteer variables to use system-installed Chromium
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser \
    NODE_ENV=production

WORKDIR /app

# Copy node modules and app code from build stage
COPY --from=build /app ./

# Add system dependencies for runtime
RUN apk add --no-cache \
    chromium \
    nss \
    freetype \
    harfbuzz \
    ca-certificates \
    ttf-freefont \
    && rm -rf /var/cache/apk/*

# Expose port (adjust if app uses a different one)
EXPOSE 8080

# Start the app
CMD ["npm", "start"]
