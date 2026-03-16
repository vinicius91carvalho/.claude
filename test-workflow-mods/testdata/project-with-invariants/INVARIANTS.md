# Project Invariants

## Permission String Format
- **Owner:** IAM module
- **Preconditions:** All consumers import permission constants from `src/permissions.ts`
- **Postconditions:** Every route guard uses a permission string matching `resource:action`
- **Invariants:** No hardcoded permission strings outside permissions.ts
- **Verify:** `test -f src/permissions.ts`
- **Fix:** Import permission constants from src/permissions.ts instead of hardcoding strings

## Entity Status Values
- **Owner:** Core domain
- **Preconditions:** Consumers use StatusType enum
- **Postconditions:** Only valid statuses: draft, active, archived, deleted
- **Invariants:** No raw status strings outside types.ts
- **Verify:** `true`
- **Fix:** Use StatusType enum from src/types.ts
