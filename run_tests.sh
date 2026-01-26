#!/bin/bash
# Test runner for pi-gcode-server
# Runs unit, security, and integration tests

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Pi GCode Server Test Suite ===${NC}"
echo

# Check if Python 3 is available
if ! command -v python3 &>/dev/null; then
    echo -e "${RED}ERROR: Python 3 not found${NC}"
    exit 1
fi

# Track test results
UNIT_TESTS_PASSED=0
SECURITY_TESTS_PASSED=0
INTEGRATION_TESTS_PASSED=0

# Run unit tests
echo -e "${YELLOW}Running unit tests...${NC}"
if python3 -m unittest discover -s tests/unit -p "test_*.py" -v; then
    echo -e "${GREEN}✓ Unit tests passed${NC}"
    UNIT_TESTS_PASSED=1
else
    echo -e "${RED}✗ Unit tests failed${NC}"
fi
echo

# Run security tests
echo -e "${YELLOW}Running security tests...${NC}"
if python3 -m unittest discover -s tests/security -p "test_*.py" -v; then
    echo -e "${GREEN}✓ Security tests passed${NC}"
    SECURITY_TESTS_PASSED=1
else
    echo -e "${RED}✗ Security tests failed${NC}"
fi
echo

# Run integration tests
echo -e "${YELLOW}Running integration tests...${NC}"
if python3 -m unittest discover -s tests/integration -p "test_*.py" -v; then
    echo -e "${GREEN}✓ Integration tests passed${NC}"
    INTEGRATION_TESTS_PASSED=1
else
    echo -e "${RED}✗ Integration tests failed${NC}"
fi
echo

# Summary
echo -e "${GREEN}=== Test Summary ===${NC}"
echo "Unit tests:        $([ $UNIT_TESTS_PASSED -eq 1 ] && echo -e "${GREEN}PASSED${NC}" || echo -e "${RED}FAILED${NC}")"
echo "Security tests:    $([ $SECURITY_TESTS_PASSED -eq 1 ] && echo -e "${GREEN}PASSED${NC}" || echo -e "${RED}FAILED${NC}")"
echo "Integration tests: $([ $INTEGRATION_TESTS_PASSED -eq 1 ] && echo -e "${GREEN}PASSED${NC}" || echo -e "${RED}FAILED${NC}")"

# Exit with failure if any test suite failed
if [ $UNIT_TESTS_PASSED -eq 1 ] && [ $SECURITY_TESTS_PASSED -eq 1 ] && [ $INTEGRATION_TESTS_PASSED -eq 1 ]; then
    echo -e "\n${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "\n${RED}Some tests failed${NC}"
    exit 1
fi
