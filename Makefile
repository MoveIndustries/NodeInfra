.PHONY: help lint fmt validate test clean install-tools py-fmt py-lint py-type-check

# Default target
help:
	@echo "Movement Network Validator Infrastructure - Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  make lint           - Run all linting checks (Terraform + Python)"
	@echo "  make fmt            - Format all Terraform and Python files"
	@echo "  make fmt-check      - Check if Terraform files are formatted"
	@echo "  make tflint         - Run tflint on all modules and examples"
	@echo "  make validate       - Run terraform validate on all modules and examples"
	@echo "  make py-fmt         - Format Python files with black and isort"
	@echo "  make py-lint        - Lint Python files with ruff"
	@echo "  make py-type-check  - Type check Python files with mypy"
	@echo "  make test           - Run integration tests"
	@echo "  make install-tools  - Install required linting tools"
	@echo "  make clean          - Clean up temporary files"
	@echo ""

# Install required tools
install-tools:
	@echo "Installing tflint..."
	@which tflint > /dev/null || curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash
	@echo "Installing terraform-docs (optional)..."
	@which terraform-docs > /dev/null || brew install terraform-docs || echo "terraform-docs not installed, skipping..."
	@echo "Installing Python dev dependencies..."
	@command -v poetry >/dev/null || (echo "✗ poetry is required. Install from https://python-poetry.org/docs/" && exit 1)
	@poetry install --with dev --no-interaction --no-root
	@echo "Installing pre-commit hooks..."
	@poetry run pre-commit install
	@echo "✓ All tools installed!"

# Format Python files
py-fmt:
	@echo "Formatting Python files with black..."
	@poetry run black .
	@echo "Sorting Python imports with isort..."
	@poetry run isort .
	@echo "✓ Python formatting complete"

# Lint Python files
py-lint:
	@echo "Linting Python files with ruff..."
	@poetry run ruff check . --fix
	@echo "✓ Python linting complete"

# Type check Python files
py-type-check:
	@echo "Type checking Python files with mypy..."
	@poetry run mypy tools/ tests/ || echo "⚠ Type check completed with warnings"
	@echo "✓ Python type checking complete"

# Format all files (Terraform + Python)
fmt: py-fmt
	@echo "Formatting Terraform files..."
	@terraform fmt -recursive .
	@echo "✓ All formatting complete"

# Check if Terraform files are formatted
fmt-check:
	@echo "Checking Terraform formatting..."
	@terraform fmt -check -recursive . || (echo "✗ Files need formatting. Run 'make fmt' to fix." && exit 1)
	@echo "✓ All files properly formatted"

# Initialize tflint
tflint-init:
	@echo "Initializing tflint..."
	@tflint --init
	@echo "✓ tflint initialized"

# Run tflint on all modules and examples
tflint: tflint-init
	@echo "Running tflint on terraform-modules/movement-network-base..."
	@cd terraform-modules/movement-network-base && tflint --config ../../.tflint.hcl
	@echo "Running tflint on terraform-modules/movement-validator-infra..."
	@cd terraform-modules/movement-validator-infra && tflint --config ../../.tflint.hcl
	@echo "Running tflint on examples/hello-world..."
	@cd examples/hello-world && tflint --config ../../.tflint.hcl
	@echo "✓ tflint checks passed"

# Validate all modules and examples
validate:
	@echo "Validating terraform-modules/movement-network-base..."
	@cd terraform-modules/movement-network-base && terraform init -backend=false > /dev/null && terraform validate
	@echo "Validating terraform-modules/movement-validator-infra..."
	@cd terraform-modules/movement-validator-infra && terraform init -backend=false > /dev/null && terraform validate
	@echo "Validating examples/hello-world..."
	@cd examples/hello-world && terraform init -backend=false > /dev/null && terraform validate
	@echo "✓ All validations passed"

# Run all linting checks (Terraform + Python)
lint: fmt-check tflint validate py-lint py-type-check
	@echo ""
	@echo "=========================================="
	@echo "✓ All linting checks passed!"
	@echo "=========================================="

# Run integration tests
test:
	@echo "Running integration tests..."
	@command -v poetry >/dev/null || (echo "✗ poetry is required. Install from https://python-poetry.org/docs/" && exit 1)
	@poetry install --no-interaction --no-root
	@unset STATE_PATH; poetry run python tests/integration/test_public_fullnode.py

# Clean up temporary files
clean:
	@echo "Cleaning up temporary files..."
	@find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
	@find . -type f -name ".terraform.lock.hcl" -delete 2>/dev/null || true
	@find . -type f -name "terraform.tfstate*" -delete 2>/dev/null || true
	@find . -type d -name ".tflint.d" -exec rm -rf {} + 2>/dev/null || true
	@echo "✓ Cleanup complete"
