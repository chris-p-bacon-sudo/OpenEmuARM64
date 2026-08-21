Review and test a pull request locally.

Arguments: $PR_NUMBER

1. Check out the PR branch:
   gh pr checkout $PR_NUMBER --repo OpenEmu-Silicon/OpenEmu-Silicon

2. Run the build check and report the result.

3. If the PR touches a core, reinstall and re-sign the plugin before testing.

4. Read the PR description and list the specific behaviors to verify.

5. Report:
   - Build result
   - Plugin reinstalled (yes/no, which core)
   - Test behaviors from the PR and whether each passed or needs manual verification
