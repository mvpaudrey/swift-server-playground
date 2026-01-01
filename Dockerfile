# ============================================================================
# Multi-stage Dockerfile for AFCON Swift gRPC Server
# Optimized for production deployment with minimal image size
# ============================================================================

# ============================================================================
# Stage 1: Build Stage
# ============================================================================
FROM swift:6.0-jammy AS build

# Install system dependencies
RUN apt-get update && apt-get install -y \
    libssl-dev \
    libsqlite3-dev \
    zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /build

# Copy Package files first for better caching
COPY ./Package.* ./

# Resolve dependencies (cached layer if Package files haven't changed)
RUN swift package resolve

# Copy source code
COPY . .

# Build the project in release mode with optimizations
# Only build the Run product (excludes test targets like GRPCClient)
RUN swift build -c release --product Run

# ============================================================================
# Stage 2: Runtime Stage
# ============================================================================
FROM swift:6.0-jammy-slim

# Install runtime dependencies
RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    && apt-get -q update \
    && apt-get -q install -y \
    ca-certificates \
    libcurl4 \
    libssl3 \
    libxml2 \
    tzdata \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user for security
RUN useradd --user-group --create-home --system --skel /dev/null --home-dir /app afcon

# Set working directory
WORKDIR /app

# Copy built executable from build stage
COPY --from=build --chown=afcon:afcon /build/.build/release/Run /app/Run

# Copy proto files (needed for gRPC reflection if enabled)
COPY --from=build --chown=afcon:afcon /build/Protos /app/Protos

# Create directories for secrets and logs
RUN mkdir -p /app/secrets /app/logs && chown -R afcon:afcon /app

# Fetch AWS RDS CA bundle for TLS verification (override with build arg if needed)
ARG RDS_CA_BUNDLE_URL=https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
RUN curl -fsSL "${RDS_CA_BUNDLE_URL}" -o /app/secrets/rds-ca-bundle.pem \
    && chown afcon:afcon /app/secrets/rds-ca-bundle.pem

# Switch to non-root user
USER afcon:afcon

# Expose ports
# 8080 - HTTP REST API
# 50051 - gRPC Service
EXPOSE 8080 50051

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1

# Set environment variables
ENV ENVIRONMENT=production
ENV LOG_LEVEL=info

# Run the server
ENTRYPOINT ["./Run"]
CMD ["serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8080"]
