#!/bin/zsh
set -euo pipefail

export GH_CONFIG_DIR=/Users/Aleksey_Sayenko/.config/gh-personal

gh issue comment 2 --body-file .scratch/grocery-assistant-wayfinder/resolution-2.md
gh issue close 2
gh issue comment 3 --body-file .scratch/grocery-assistant-wayfinder/resolution-3.md
gh issue close 3
gh issue comment 4 --body-file .scratch/grocery-assistant-wayfinder/resolution-4.md
gh issue close 4
gh issue edit 1 --body-file .scratch/grocery-assistant-wayfinder/map.md
