# Policy proofs

The native CI suite runs `npm ci` and `npm test` in this directory after building
wBlockCoreService. To run just these checks against an existing signed Xcode build,
use `npm --prefix scripts/proofs ci --ignore-scripts` followed by
`npm --prefix scripts/proofs test`. Set `WBLOCK_CORE_PRODUCTS` to its
`Build/Products/Debug` directory if more than one build exists. Rebuild the core
framework after changing core sources; the standalone command does not build it.

`policies.mjs` states the contracts in GDP-wired's expression language. Every law
must be proven and kernel-checked. Concrete cross-checks exercise the expression
builders, and deliberately broken variants must produce a satisfiable
counterexample rather than merely fail to prove.

`verify.mjs` generates exhaustive Boolean combinations and time-boundary cases.
It also exercises state machines with exhaustive short traces, directed traces
that reach a named boundary, and seeded long traces. The seeded traces are drawn
from the same alphabets by a fixed-seed generator that reads the high bits of its
state, so every run produces the same traces. One Swift executable processes the
cases in a batch. The app policies compile from production source; core policies
run from the framework CI just built. Revision traces use actual files in isolated
temporary directories. Failures print the complete input trace. No fixture can
substitute a Swift policy.

The covered policies are menu action access, refresh scheduling, filter selection
rebasing, cloud tombstone reconciliation, local script identity decisions, remote filter
metadata, import metadata review, and user script frame authorization.
Stateful laws cover deferred uploads and per-key revision acknowledgment, along
with the apply phase rail under out-of-order reports and failure/completion events.
The info popover state machine covers click, selection, and dismissal sequences, with
each token's anchor visibility as an input.
The swipe-back gesture state machine covers macOS scroll-axis locking, momentum
rejection, live finger tracking without premature commit while held, post-release
tail snapping, Reduce Motion release commits, and single-commit isolation.
The foreground run gate covers its work count, run starts, and the queued resumes
that finishing a run hands back.
The headless rebuild gate's cooldowns, failure backoff and outcome recording are proven likewise, and
verify.mjs drives its real gate file through the production consume and record calls. Its clock may move
backwards in these traces, as it can in production: a consume before the last stamp is refused, and a
recorded outcome restamps the gate with the clock it is given.
The blocking pause store covers its component mask, legacy migration, resume requests, scoped reloads,
and the global and content-blocking pause queries, checked through the production API on a fresh
UserDefaults suite per trace.
The filter update popup lifecycle covers claims, request bits, acknowledgment, and every finish outcome.
A running claim more than 300 s old reads as expired. The popup's result counts are outside the model and
stay in `scripts/test_filter_update_popup_status.swift`, which also keeps the cross-process claim test.
Zero denotes an absent revision/trigger; real identities are encoded as positive
naturals. Rebase contracts operate on one record; the Swift comparisons additionally
exercise duplicate snapshot IDs and last-persisted-record precedence.

These are proofs of the models, not formal verification of Swift. The Swift link
is a finite differential test. Natural arithmetic does not prove Swift integer
overflow behavior, and normalized identity predicates do not prove URL parsing.
The separate Swift regressions retain normalization and migration checks. They
also cover serialization and real file failures. Progress text and floating-point
rendering stay in a compact Swift matrix rather than being claimed as proven.
Cross-process locking and crash-recovery tests remain unchanged.
