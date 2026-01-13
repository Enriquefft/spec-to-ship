# Project Constitution

**Version**: 1.0.0 **Last Updated**: 2024-01-12

This constitution establishes the governing principles for all development on
this project. The build system will enforce these principles by default.

## Principles

1. **Dependency Discipline**: Max 3 new external dependencies per feature.
   Prefer standard library and existing dependencies over adding new ones.

2. **Test Coverage**: All public APIs must have tests before merge. Unit tests
   for logic, integration tests for workflows.

3. **Breaking Changes**: Require migration path and deprecation notice. No
   silent breaking changes to public APIs.

4. **Feature Flags**: New features behind flags for gradual rollout. Allows safe
   deployment and easy rollback.

5. **Documentation**: Public APIs documented before implementation. README
   updated for user-facing changes.

6. **Security First**: No secrets in code. Validate all external inputs. Use
   parameterized queries.

7. **Performance Budget**: Build commands complete in < 30 seconds. No
   unnecessary AI calls.

## Enforcement

- **Gate**: Build phase blocks on violations by default
- **Override**: `--force` flag with justification required
- **Audit**: All overrides logged for review

## Amendments

To propose changes to this constitution:

1. Create a PR with proposed changes
2. Document rationale in PR description
3. Requires team lead approval

---

_This constitution is enforced by `workflow build`. See
`docs/CONSTITUTION_GUIDE.md` for details._
