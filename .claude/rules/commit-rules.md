# Commit Rules

## Convention: Angular

All commits must follow the Angular commit convention:
`<type>(<scope>): <description>`

### Allowed Types
feat, fix, refactor, test, docs, chore, build, ci

### Scope Policy
Scope is **required** on every commit. Suggested scopes for this project:
`app`, `scanner`, `process`, `forward`, `ui`, `net`, `build`, `config`.

### Branch Naming
Pattern: `{type}/{ticket}-{description}`
Example: `feat/PORT-20-native-menubar`

### Co-Authorship
**Never** add `Co-Authored-By` lines to commits. All commits are authored solely by the committer.
