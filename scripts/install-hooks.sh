#!/usr/bin/env bash
# Points git at the repo's hooks (gitleaks pre-commit). Run once after cloning.
set -euo pipefail
cd "$(dirname "$0")/.."
git config core.hooksPath .githooks
chmod +x .githooks/*
echo "Git hooks installed (core.hooksPath=.githooks)."
command -v gitleaks >/dev/null || echo "Note: install gitleaks first: brew install gitleaks"
