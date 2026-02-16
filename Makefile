.PHONY: help lint fmt validate test clean install-tools

# Default target
help:
	@echo "Movement Network Validator Infrastructure - Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  make lint           - Run all linting checks (fmt, tflint, validate)"
	@echo "  make fmt            - Format all Terraform files"
	@echo "  make fmt-check      - Check if Terraform files are formatted"
	@echo "  make tflint         - Run tflint on all modules and examples"
	@echo "  make validate       - Run terraform validate on all modules and examples"
	@echo "  make test           - Run integration tests"
	@echo "  make install-tools  - Install required linting tools (tflint)"
	@echo "  make clean          - Clean up temporary files"
	@echo ""

# Install required tools
install-tools:
	@echo "Installing tflint..."
	@which tflint > /dev/null || curl -s https://raw.githubusercontent.com/terraform-linters/tflint/master/install_linux.sh | bash
	@echo "Installing terraform-docs (optional)..."
	@which terraform-docs > /dev/null || brew install terraform-docs || echo "terraform-docs not installed, skipping..."
	@echo "Tools installed!"

# Format all Terraform files
fmt:
	@echo "Formatting Terraform files..."
	@terraform fmt -recursive .
	@echo "✓ Formatting complete"

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

# Run all linting checks
lint: fmt-check tflint validate
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
