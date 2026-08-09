#!/bin/zsh
set -euo pipefail

export GH_CONFIG_DIR=/Users/Aleksey_Sayenko/.config/gh-personal

gh api --method POST repos/dniprodev/apple-foundation-models-rsrch/issues/1/sub_issues -F sub_issue_id=5064507247
gh api --method POST repos/dniprodev/apple-foundation-models-rsrch/issues/1/sub_issues -F sub_issue_id=5064507617
gh api --method POST repos/dniprodev/apple-foundation-models-rsrch/issues/1/sub_issues -F sub_issue_id=5064507994
gh api --method POST repos/dniprodev/apple-foundation-models-rsrch/issues/1/sub_issues -F sub_issue_id=5064508923
gh api --method POST repos/dniprodev/apple-foundation-models-rsrch/issues/1/sub_issues -F sub_issue_id=5064509242
gh api --method POST repos/dniprodev/apple-foundation-models-rsrch/issues/1/sub_issues -F sub_issue_id=5064509769
gh api --method POST repos/dniprodev/apple-foundation-models-rsrch/issues/1/sub_issues -F sub_issue_id=5064510786

gh api --method POST repos/dniprodev/apple-foundation-models-rsrch/issues/5/dependencies/blocked_by -F issue_id=5064507247
gh api --method POST repos/dniprodev/apple-foundation-models-rsrch/issues/7/dependencies/blocked_by -F issue_id=5064507617
gh api --method POST repos/dniprodev/apple-foundation-models-rsrch/issues/8/dependencies/blocked_by -F issue_id=5064507247
gh api --method POST repos/dniprodev/apple-foundation-models-rsrch/issues/8/dependencies/blocked_by -F issue_id=5064507994
gh api --method POST repos/dniprodev/apple-foundation-models-rsrch/issues/8/dependencies/blocked_by -F issue_id=5064508923
gh api --method POST repos/dniprodev/apple-foundation-models-rsrch/issues/8/dependencies/blocked_by -F issue_id=5064509242
gh api --method POST repos/dniprodev/apple-foundation-models-rsrch/issues/8/dependencies/blocked_by -F issue_id=5064509769
