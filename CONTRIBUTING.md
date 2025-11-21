# Contributing to pi-gcode-server

Thank you for considering contributing to pi-gcode-server! This project aims to make 3D printing workflows smoother for makers and hobbyists.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [How Can I Contribute?](#how-can-i-contribute)
  - [Reporting Bugs](#reporting-bugs)
  - [Suggesting Features](#suggesting-features)
  - [Contributing Code](#contributing-code)
  - [Improving Documentation](#improving-documentation)
- [Development Setup](#development-setup)
- [Coding Standards](#coding-standards)
- [Testing](#testing)
- [Pull Request Process](#pull-request-process)

## Code of Conduct

This project and everyone participating in it is governed by our [Code of Conduct](CODE_OF_CONDUCT.md). By participating, you are expected to uphold this code.

## How Can I Contribute?

### Reporting Bugs

Before creating a bug report, please:

1. **Check existing issues** to see if the problem has already been reported
2. **Use the latest version** - the bug may already be fixed
3. **Collect debug information**:
   - Output from `./check_gcode_monitor.sh` (if applicable)
   - Relevant logs from `~/.gcode_sync.log`
   - System info: OS, Python version, printer model

**Good Bug Report Includes**:
- Clear, descriptive title
- Steps to reproduce the issue
- Expected vs actual behavior
- Log snippets or error messages
- Your configuration (redact sensitive info like IPs/hostnames)

### Suggesting Features

Feature requests are welcome! Before suggesting:

1. **Check if it already exists** in issues or documentation
2. **Explain your use case** - why is this feature needed?
3. **Describe the solution** - what would the ideal implementation look like?
4. **Consider alternatives** - are there workarounds or similar features?

### Contributing Code

We welcome code contributions! Here's how:

1. **Fork the repository** on GitHub
2. **Clone your fork** locally
3. **Create a feature branch** from `master`:
   ```bash
   git checkout -b feat/your-feature-name
   ```
4. **Make your changes** following our [Coding Standards](#coding-standards)
5. **Test your changes** thoroughly
6. **Commit with clear messages** (see below)
7. **Push to your fork** and **submit a Pull Request**

### Improving Documentation

Documentation improvements are highly valued! You can:

- Fix typos or clarify existing docs
- Add examples or troubleshooting tips
- Document new features
- Translate documentation (future)
- Add diagrams or screenshots

## Development Setup

### Prerequisites

- Python 3.7+
- `uv` or `pip` for dependency management
- Linux, macOS, or WSL2 (for testing)
- Optional: Raspberry Pi Zero W for full integration testing

### Setup Steps

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/pi-gcode-server.git
cd pi-gcode-server

# Install dependencies
pip install -r requirements.txt

# Create test configuration
cp config.example config.local
nano config.local  # Edit with your test values

# Run tests (if available)
./run_tests.sh
```

## Coding Standards

### Python Code

- **Follow PEP 8** style guide
- **Use type hints** where appropriate
- **Add docstrings** for public functions/classes
- **Keep functions focused** - single responsibility principle
- **Validate inputs** - especially user-provided paths and commands
- **Quote shell variables** - prevent injection attacks

### Bash Scripts

- **Use `set -euo pipefail`** for error handling
- **Quote all variables**: `"$VAR"` not `$VAR`
- **Validate user input** before using in commands
- **Add comments** for complex logic
- **Use meaningful variable names**

### Security Best Practices

This project prioritizes security. When contributing:

- **Never execute untrusted input**
- **Validate file paths** (check bounds, no symlinks, no traversal)
- **Use subprocess lists** instead of shell strings: `subprocess.run(["cmd", arg])` not `subprocess.run(f"cmd {arg}", shell=True)`
- **Check OWASP Top 10** vulnerabilities
- **Document security considerations** in PRs

### Code Style Examples

**Good**:
```python
def sync_file(file_path: Path) -> bool:
    """
    Sync a gcode file to the remote Pi.

    Args:
        file_path: Absolute path to the gcode file

    Returns:
        True if sync succeeded, False otherwise
    """
    # Validate file exists and is within watch directory
    if not file_path.exists() or not file_path.is_file():
        logging.error(f"File not found: {file_path}")
        return False

    # ... rest of implementation
```

**Bad**:
```python
def sync(f):  # No type hints, unclear name
    os.system(f"rsync {f} remote:/path")  # Shell injection risk!
```

## Testing

### Running Tests

```bash
# Run all tests
./run_tests.sh

# Run specific test category
python3 -m pytest tests/unit/
python3 -m pytest tests/security/
```

### Writing Tests

- **Add tests for new features** - unit tests at minimum
- **Test edge cases** - empty files, large files, permission errors
- **Security tests** - path traversal, command injection, etc.
- **Keep tests fast** - use mocks for network calls

### Test Coverage

- Aim for **>80% code coverage** for new code
- **100% coverage** for security-critical paths (validation, sanitization)

## Pull Request Process

### Before Submitting

- [ ] Code follows style guidelines
- [ ] Tests pass locally (`./run_tests.sh`)
- [ ] Documentation updated (if applicable)
- [ ] Commit messages are clear and descriptive
- [ ] No sensitive data in commits (IPs, passwords, keys)

### Commit Message Format

Use conventional commits format:

```
<type>: <short summary>

<optional detailed description>

<optional footer>
```

**Types**:
- `feat:` - New feature
- `fix:` - Bug fix
- `docs:` - Documentation changes
- `refactor:` - Code refactoring (no behavior change)
- `test:` - Adding or updating tests
- `chore:` - Tooling, dependencies, etc.
- `security:` - Security fixes or improvements

**Examples**:
```
feat: add retry logic for USB refresh failures

Adds exponential backoff retry (3 attempts) for USB gadget refresh
operations. Increases reliability from ~95% to ~99.5%.

Closes #42
```

```
fix: correct SHA256 hashes in requirements.txt

Line 12 had an invalid placeholder hash that caused installation
failures with hash verification enabled.
```

### PR Description Template

When opening a PR, include:

```markdown
## Summary
Brief description of changes

## Motivation
Why is this change needed?

## Changes
- List of specific changes made
- Can be bullet points

## Testing
How was this tested?
- [ ] Unit tests added/updated
- [ ] Integration tests pass
- [ ] Manually tested on [OS/setup]

## Checklist
- [ ] Code follows style guidelines
- [ ] Tests pass
- [ ] Documentation updated
- [ ] No security vulnerabilities introduced
```

### Review Process

1. **Automated checks** run (when CI/CD is set up)
2. **Maintainer review** - may request changes
3. **Discussion** if needed
4. **Approval** - maintainer approves changes
5. **Merge** - squash and merge to `master`

## Questions?

- **Check existing issues** - your question may be answered
- **Open a discussion** (GitHub Discussions if enabled)
- **Ask in your PR** if it's code-related

## Thank You!

Your contributions make this project better for the entire 3D printing community. Every bug report, feature suggestion, code contribution, and documentation improvement is valued.

Happy printing! 🖨️
