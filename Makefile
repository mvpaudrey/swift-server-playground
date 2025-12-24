.PHONY: help build run test clean proto redis setup install

MODULE_CACHE_DIR := $(CURDIR)/.build/module-cache
MODULE_CACHE_ENV := SWIFTPM_DISABLE_SANDBOX=1 CLANG_MODULE_CACHE_PATH=$(MODULE_CACHE_DIR) SWIFT_MODULE_CACHE_PATH=$(MODULE_CACHE_DIR)
SWIFT_BUILD_FLAGS := --disable-sandbox
SWIFT_RUN_FLAGS := --disable-sandbox
SWIFT_TEST_FLAGS := --disable-sandbox

# Default target
help:
	@echo "AFCON Middleware - Makefile Commands"
	@echo "====================================="
	@echo ""
	@echo "  make setup      - Install all dependencies and setup project"
	@echo "  make proto      - Generate Swift code from Protocol Buffers"
	@echo "  make build      - Build the project"
	@echo "  make run        - Run the server"
	@echo "  make test       - Run tests"
	@echo "  make redis      - Start Redis in background"
	@echo "  make stop-redis - Stop Redis"
	@echo "  make clean      - Clean build artifacts"
	@echo "  make clean-all  - Clean everything including generated files"
	@echo "  make client     - Build example client"
	@echo "  make run-client - Run example client"
	@echo ""

# Install dependencies
setup:
	@echo "🔧 Setting up AFCON Middleware..."
	@command -v protoc >/dev/null 2>&1 || (echo "❌ protoc not found. Run: brew install protobuf" && exit 1)
	@command -v protoc-gen-swift >/dev/null 2>&1 || (echo "❌ protoc-gen-swift not found. Run: brew install swift-protobuf" && exit 1)
	@command -v protoc-gen-grpc-swift >/dev/null 2>&1 || (echo "⚠️  protoc-gen-grpc-swift not found. See README for installation" && exit 1)
	@command -v redis-server >/dev/null 2>&1 || (echo "❌ redis-server not found. Run: brew install redis" && exit 1)
	@echo "✅ All dependencies installed"
	@cp .env.example .env 2>/dev/null || true
	@echo "✅ Environment file created"
	@make proto
	@echo "✅ Setup complete!"

# Generate protocol buffer code
proto:
	@echo "📝 Generating Swift code from Protocol Buffers..."
	@./generate-protos.sh

# Build the project
build:
	@echo "🔨 Building project..."
	@mkdir -p $(MODULE_CACHE_DIR)
	@$(MODULE_CACHE_ENV) swift build $(SWIFT_BUILD_FLAGS)

# Build in release mode
build-release:
	@echo "🔨 Building project (release)..."
	@mkdir -p $(MODULE_CACHE_DIR)
	@$(MODULE_CACHE_ENV) swift build -c release $(SWIFT_BUILD_FLAGS)

# Run the server
run:
	@echo "🚀 Starting AFCON Middleware..."
	@mkdir -p $(MODULE_CACHE_DIR)
	@$(MODULE_CACHE_ENV) swift run $(SWIFT_RUN_FLAGS)

# Run in release mode
run-release:
	@echo "🚀 Starting AFCON Middleware (release)..."
	@mkdir -p $(MODULE_CACHE_DIR)
	@$(MODULE_CACHE_ENV) swift run -c release $(SWIFT_RUN_FLAGS)

# Run tests
test:
	@echo "🧪 Running tests..."
	@mkdir -p $(MODULE_CACHE_DIR)
	@$(MODULE_CACHE_ENV) swift test $(SWIFT_TEST_FLAGS)

# Start Redis
redis:
	@echo "🗄️  Starting Redis..."
	@redis-server --daemonize yes
	@echo "✅ Redis started"

# Stop Redis
stop-redis:
	@echo "🛑 Stopping Redis..."
	@redis-cli shutdown
	@echo "✅ Redis stopped"

# Clean build artifacts
clean:
	@echo "🧹 Cleaning build artifacts..."
	@swift package clean
	@rm -rf .build
	@echo "✅ Clean complete"

# Clean everything including generated files
clean-all: clean
	@echo "🧹 Cleaning generated files..."
	@find Sources/App/gRPC/Generated -name "*.swift" -type f -delete 2>/dev/null || true
	@echo "✅ All clean"

# Build example client
client:
	@echo "🔨 Building example client..."
	@cd Examples/AFCONClient && mkdir -p $(MODULE_CACHE_DIR) && $(MODULE_CACHE_ENV) swift build $(SWIFT_BUILD_FLAGS)

# Run example client
run-client:
	@echo "🚀 Running example client..."
	@cd Examples/AFCONClient && mkdir -p $(MODULE_CACHE_DIR) && $(MODULE_CACHE_ENV) swift run $(SWIFT_RUN_FLAGS)

# Check code formatting
format:
	@echo "✨ Formatting code..."
	@command -v swift-format >/dev/null 2>&1 || (echo "⚠️  swift-format not found. Run: brew install swift-format" && exit 1)
	@swift-format format -i -r Sources/

# Lint code
lint:
	@echo "🔍 Linting code..."
	@command -v swiftlint >/dev/null 2>&1 || (echo "⚠️  swiftlint not found. Run: brew install swiftlint" && exit 1)
	@swiftlint

# Docker build
docker-build:
	@echo "🐳 Building Docker image..."
	@docker build -t afcon-middleware .

# Docker run
docker-run:
	@echo "🐳 Running Docker container..."
	@docker-compose up

# Show logs
logs:
	@tail -f /usr/local/var/log/redis.log 2>/dev/null || echo "No Redis logs found"

# Health check
health:
	@echo "🏥 Checking service health..."
	@curl -s http://localhost:8080/health || echo "❌ Service not responding"

# API status check
api-status:
	@echo "📊 Checking API Football status..."
	@curl -s http://localhost:8080/api/status | jq . || echo "❌ Service not responding"

# Get AFCON teams
teams:
	@echo "⚽ Fetching AFCON 2025 teams..."
	@curl -s http://localhost:8080/api/v1/league/6/season/2025/teams | jq '.[] | .team | {name, code, country}' || echo "❌ Service not responding"

# Get live matches
live:
	@echo "🔴 Fetching live matches..."
	@curl -s http://localhost:8080/api/v1/league/6/live | jq '.' || echo "❌ No live matches or service not responding"

# Flush Redis cache
flush-cache:
	@echo "🗑️  Flushing Redis cache..."
	@redis-cli FLUSHDB
	@echo "✅ Cache flushed"
.SUFFIXES:
# Development mode with auto-reload
dev:
	@echo "🔄 Running in development mode..."
	@mkdir -p $(MODULE_CACHE_DIR)
	@$(MODULE_CACHE_ENV) swift run $(SWIFT_RUN_FLAGS)

# Show Redis keys
redis-keys:
	@echo "🔑 Redis keys:"
	@redis-cli KEYS "afcon:*"

# Show Redis stats
redis-stats:
	@echo "📊 Redis stats:"
	@redis-cli INFO stats
