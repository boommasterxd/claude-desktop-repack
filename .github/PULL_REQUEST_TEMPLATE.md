<!--
PR title MUST follow Conventional Commits: type(scope): description
(e.g. fix(patches): re-anchor quick-entry-app-id, feat(build): add zsync)
It is squash-merged, so the title becomes the commit on main and drives the
grouped release-notes changelog. See the Contributing section in the README.
-->

## What & why

<!-- What this changes and why. Link related issues, e.g. Closes #123. -->

## Type of change

- [ ] Patch add/fix (`patches/*.mjs`)
- [ ] Packaging / build script
- [ ] CI / release workflow
- [ ] Docs
- [ ] Other

## Checklist

- [ ] PR title follows Conventional Commits (`type(scope): description`)
- [ ] Built locally (`bash scripts/build-local.sh`) and it succeeds
- [ ] The `CI` and `gitleaks` checks pass

### If this touches a patch (`patches/`)

- [ ] Matches **exactly one** occurrence (throws on 0 or 2+ matches)
- [ ] Uses `[\w$]+` for minified identifiers, no hardcoded names
- [ ] Anchors on stable string literals / public API names, not on expression shape
- [ ] Asserts the injected end-state after replacing, and throws on any mismatch
- [ ] Added a `### ...` subsection to the README Patches section
