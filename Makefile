.PHONY: help localstack-start localstack-stop localstack-restart localstack-status localstack-logs localstack-health localstack-clean test-local test-aws test-all check-version

# Default target
.DEFAULT_GOAL := help

# Configuration
COMPOSE_FILE := docker-compose.localstack.yml
HEALTH_ENDPOINT := http://localhost:4566/_localstack/health
HEALTH_TIMEOUT := 60
HEALTH_INTERVAL := 2

help: ## Display this help message
	@echo "LocalStack Testing Makefile"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

localstack-start: ## Start LocalStack container with health check
	@echo "Starting LocalStack..."
	@docker-compose -f $(COMPOSE_FILE) up -d
	@echo "Waiting for LocalStack to be healthy..."
	@timeout=$(HEALTH_TIMEOUT); \
	elapsed=0; \
	while [ $$elapsed -lt $$timeout ]; do \
		if curl -sf $(HEALTH_ENDPOINT) > /dev/null 2>&1; then \
			echo "LocalStack is healthy!"; \
			exit 0; \
		fi; \
		echo "Waiting... ($$elapsed/$$timeout seconds)"; \
		sleep $(HEALTH_INTERVAL); \
		elapsed=$$((elapsed + $(HEALTH_INTERVAL))); \
	done; \
	echo "ERROR: LocalStack health check failed after $$timeout seconds"; \
	docker-compose -f $(COMPOSE_FILE) logs; \
	exit 1

localstack-stop: ## Stop LocalStack container gracefully
	@echo "Stopping LocalStack..."
	@docker-compose -f $(COMPOSE_FILE) stop
	@echo "LocalStack stopped"

localstack-restart: ## Restart LocalStack container
	@echo "Restarting LocalStack..."
	@$(MAKE) localstack-stop
	@$(MAKE) localstack-start

localstack-status: ## Show LocalStack container status
	@docker-compose -f $(COMPOSE_FILE) ps

localstack-logs: ## Tail LocalStack container logs
	@docker-compose -f $(COMPOSE_FILE) logs -f

localstack-health: ## Check LocalStack health endpoint
	@echo "Checking LocalStack health..."
	@curl -s $(HEALTH_ENDPOINT) | python3 -m json.tool || echo "LocalStack is not running or unhealthy"

localstack-clean: ## Stop container and remove volumes
	@echo "Cleaning up LocalStack..."
	@docker-compose -f $(COMPOSE_FILE) down -v
	@echo "LocalStack cleaned up"

test-local: ## Run Terraform tests with LocalStack
	@echo "Running tests with LocalStack..."
	@terraform test -var="use_localstack=true"

test-aws: ## Run Terraform tests against real AWS
	@echo "Running tests with AWS..."
	@terraform test -var="use_localstack=false"

test-all: test-local ## Default to LocalStack tests

check-version: ## Assert local.module_version matches the newest CHANGELOG heading
	@tf_ver=$$(sed -n 's/^  module_version = "\(.*\)"$$/\1/p' version.tf); \
	cl_ver=$$(sed -n 's/^## v\([0-9][0-9.]*\)$$/\1/p' CHANGELOG.md | head -1); \
	if [ -z "$$tf_ver" ]; then echo "ERROR: could not read module_version from version.tf"; exit 1; fi; \
	if [ -z "$$cl_ver" ]; then echo "ERROR: could not read a version heading from CHANGELOG.md"; exit 1; fi; \
	if [ "$$tf_ver" != "$$cl_ver" ]; then \
		echo "ERROR: version.tf says $$tf_ver, CHANGELOG.md says $$cl_ver."; \
		echo "  local.module_version is what every extension diagnostic reports."; \
		exit 1; \
	fi; \
	echo "version.tf and CHANGELOG.md agree: $$tf_ver"; \
	tag=$$(git describe --tags --abbrev=0 2>/dev/null); \
	if [ "$$tag" = "v$$tf_ver" ]; then \
		echo "NOTE: v$$tf_ver is already tagged — bump version.tf and CHANGELOG.md before the next release."; \
	fi
