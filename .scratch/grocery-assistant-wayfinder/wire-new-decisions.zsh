#!/bin/zsh
set -euo pipefail

export GH_CONFIG_DIR=/Users/Aleksey_Sayenko/.config/gh-personal

gh api --silent --method POST repos/dniprodev/apple-foundation-models-rsrch/issues/1/sub_issues -F sub_issue_id=5064834466
gh api --silent --method POST repos/dniprodev/apple-foundation-models-rsrch/issues/1/sub_issues -F sub_issue_id=5064848703
gh api --silent --method POST repos/dniprodev/apple-foundation-models-rsrch/issues/9/dependencies/blocked_by -F issue_id=5064508923
gh api --silent --method POST repos/dniprodev/apple-foundation-models-rsrch/issues/10/dependencies/blocked_by -F issue_id=5064508923
gh api --silent --method POST repos/dniprodev/apple-foundation-models-rsrch/issues/10/dependencies/blocked_by -F issue_id=5064509769
gh api --silent --method POST repos/dniprodev/apple-foundation-models-rsrch/issues/8/dependencies/blocked_by -F issue_id=5064834466
gh api --silent --method POST repos/dniprodev/apple-foundation-models-rsrch/issues/8/dependencies/blocked_by -F issue_id=5064848703
