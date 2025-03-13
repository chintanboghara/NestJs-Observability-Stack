# Stage 1: Build the application
FROM node:22-alpine AS builder

WORKDIR /app

# Copy dependency manifests and configuration files
COPY package*.json nest-cli.json tsconfig*.json ./

# Copy the source files
COPY src/ ./src

# Install dependencies and build the app
RUN npm ci && npm run build


# Stage 2: Create the production image
FROM node:22-alpine

WORKDIR /app

# Set the production environment variable
ENV NODE_ENV=production

# Copy production dependencies and built files from the builder stage
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist

# Expose the port the app will run on
EXPOSE 3000

# Add a health check
RUN apk add --no-cache curl
HEALTHCHECK --interval=30s --timeout=3s CMD curl -f http://localhost:3000/ || exit 1

# Start the application
CMD ["node", "dist/main.js"]
