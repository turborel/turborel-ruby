<!--
This description is the series' cover letter (CONTRIBUTING.md, Pull
requests). Each commit message still stands alone, in Linux's form.
Base the series on main, keep it rebased, and on revising say what
changed in a comment, not here.
-->

## What and why

<!-- The problem and its impact, then the approach and the choices made.
Link the issue: "Closes #N". -->

## The series

<!-- One line per commit, in order: what it does. Each passes
`bundle exec rake verify` on its own. -->

1.

## Testing

<!-- The tests added and what each verifies. For a change to the protocol's
handling, the byte-level, TLS and compatibility checks done. -->

- [ ] `bundle exec rake verify` passes
- [ ] `bundle exec rake coverage` passes

## Compatibility

<!-- What happens to programs using the driver, and what an older or a
newer server sees; "none" if nothing changes. -->

## Performance

<!-- If the change claims any: what was measured, how, and the numbers.
Otherwise "none claimed". -->

## Checklist (RULES.md §7)

- [ ] One logical change per commit, each passing `bundle exec rake verify`
- [ ] The protocol or turborel-client cited in the code (R-DOC-4) and in the tests (`# Verifies:`, R-TRACE-1)
- [ ] Normal, edge and robustness tests (R-TEST-2), a failing-first test for a fix (R-TEST-5)
- [ ] Every failure a `Turborel::Error`, no secret shown, nothing held without bound (R-ERR-1, R-SAFE-4, R-SAFE-1)
- [ ] Signatures in `sig/` for what changed in `lib/`, Steep passing (D6)
- [ ] No new dependency without a decision (R-SAFE-2)
- [ ] CONFORMANCE.md, RULES.md, TODO.md and `doc/` updated where they change
