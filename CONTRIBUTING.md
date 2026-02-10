# Contributing to Movement Network Validator Infrastructure

Thank you for your interest in contributing to the Movement Network Validator Infrastructure project! This guide will help you get started.

## Development Workflow

### Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.5.0
- [AWS CLI](https://aws.amazon.com/cli/) configured with valid credentials
- [TFLint](https://github.com/terraform-linters/tflint) for advanced linting
- [Pre-commit](https://pre-commit.com/) (optional but recommended)

### Quick Setup

1. **Clone the repository**
   ```bash
   git clone git@github.com:MoveIndustries/NodeInfra.git
   cd NodeInfra
   ```

2. **Install linting tools**
   ```bash
   make install-tools
   ```

3. **Set up pre-commit hooks (optional)**
   ```bash
   pip install pre-commit
   pre-commit install
   ```

## Code Quality Standards

### Linting

All code must pass linting checks before being merged. Run linting locally:

```bash
# Run all linting checks
make lint

# Or run individual checks
make fmt-check    # Check Terraform formatting
make tflint       # Run TFLint
make validate     # Run terraform validate
```

### Formatting

All Terraform files must be properly formatted:

```bash
# Format all files automatically
make fmt

# Check formatting without making changes
make fmt-check
```

### Pre-commit Hooks

Pre-commit hooks automatically run linting checks before each commit. This helps catch issues early:

```bash
# Install pre-commit
pip install pre-commit
pre-commit install

# Run manually on all files
pre-commit run --all-files
```

## Making Changes

### 1. Create a Branch

```bash
git checkout -b feature/your-feature-name
```

### 2. Make Your Changes

- Follow Terraform best practices
- Use snake_case for all resource names
- Add descriptions to all variables and outputs
- Update documentation as needed

### 3. Run Linting

```bash
# Format your code
make fmt

# Run all linting checks
make lint
```

### 4. Test Your Changes

```bash
# For module changes, test with hello-world example
cd examples/hello-world
terraform init
terraform plan

# Run integration tests
cd tests/integration
./test-hello-world.sh
```

### 5. Commit and Push

```bash
git add .
git commit -m "feat: add your feature description"
git push origin feature/your-feature-name
```

### 6. Create a Pull Request

- Open a PR against the `main` branch
- Fill out the PR template
- Ensure all CI checks pass
- Wait for code review

## Continuous Integration

All pull requests trigger automated CI checks:

- **Terraform Format Check** - Ensures code is properly formatted
- **TFLint** - Advanced linting with AWS best practices
- **Terraform Validate** - Syntax and configuration validation

CI must pass before merging. You can view the workflow in `.github/workflows/lint.yml`.

## Module Development Guidelines

### Directory Structure

```
terraform-modules/
└── your-module-name/
    ├── main.tf           # Primary resource definitions
    ├── variables.tf      # Input variables with descriptions
    ├── outputs.tf        # Output values with descriptions
    ├── versions.tf       # Terraform and provider versions
    ├── README.md         # Module documentation
    └── *.tf              # Additional logical groupings
```

### Best Practices

1. **Documentation**
   - All variables must have descriptions
   - All outputs must have descriptions
   - Include usage examples in README.md

2. **Naming Conventions**
   - Use snake_case for all names
   - Be descriptive but concise
   - Follow AWS naming patterns

3. **Variables**
   - Provide sensible defaults where possible
   - Use validation blocks for complex inputs
   - Group related variables together

4. **Outputs**
   - Export all useful resource attributes
   - Use consistent naming patterns
   - Add descriptions explaining the value

5. **Security**
   - Mark sensitive outputs appropriately
   - Follow least-privilege principles
   - Enable encryption by default

## Testing

### Unit Tests

For module changes, ensure existing examples still work:

```bash
cd examples/hello-world
terraform init
terraform plan
```

### Integration Tests

Run the full integration test suite:

```bash
cd tests/integration
./test-hello-world.sh
```

This will:
1. Deploy the infrastructure
2. Validate functionality
3. Clean up resources

## Getting Help

- Open an issue for bugs or feature requests
- Join our community discussions
- Review existing documentation in the `/docs` folder

## License

By contributing, you agree that your contributions will be licensed under the project's license.