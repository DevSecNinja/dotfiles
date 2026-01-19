#!/bin/bash
# Docker completion for Bash
# Generate completion dynamically if docker is available

if command -v docker >/dev/null 2>&1; then
	# Safely evaluate docker completion, suppressing any error messages
	# This prevents issues when Docker Desktop WSL integration is not properly configured
	eval "$(docker completion bash 2>/dev/null)" 2>/dev/null || true
fi
