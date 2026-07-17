#!/bin/bash
# Automated release using semantic-release
# Usage: ./tools/release.sh [--dry-run]

set -e

cd "$(dirname "$0")/.."

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Hyperi Developer Environment - Automated Release${NC}"
echo ""

# Check if npm dependencies are installed
if [ ! -d "node_modules" ]; then
    echo -e "${YELLOW}📦 Installing semantic-release dependencies...${NC}"
    npm install
    echo ""
fi

# Check git status
if [ -n "$(git status --porcelain)" ]; then
    echo -e "${YELLOW}⚠️  Warning: You have uncommitted changes${NC}"
    echo "Please commit or stash your changes before releasing"
    git status --short
    exit 1
fi

# Run semantic-release
if [ "$1" = "--dry-run" ]; then
    echo -e "${YELLOW}🔍 Running in DRY-RUN mode (no changes will be made)${NC}"
    echo ""
    npm run release:dry-run
else
    echo -e "${GREEN}✨ Analyzing commits and creating release...${NC}"
    echo ""
    npm run release:no-ci
fi

echo ""
echo -e "${GREEN}✅ Release complete!${NC}"
