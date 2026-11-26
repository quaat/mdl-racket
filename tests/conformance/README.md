# Manual example fixtures

Run `make install` to expose the checkout's `#lang mdl`, then run
`make test-manual` from the repository root. The dedicated suite leaves
the language and Zork CI targets independent. It requires a POSIX
environment with process resource limits. Results go to
`artifacts/l0/manual.json`.

Fixtures in `manifest.json` declare their manual section, setup, expression,
typed result, program output and optional side-effect observation. An
`origin` of `manual` preserves the MDL source of an example with transcript
prompts removed. `adapted` examples change the manual source or its setup.
`authored` cases test a documented rule with new source. An example without
a side-effect observation uses a constant FIX sentinel.

Each execution path starts a separate Racket process in a disposable
directory. The test worker observes the result via a synthetic `SETG`
and turns off the module host printer so explicit MDL writes can be
compared. This observation wrapper should not be used to prove exact
read-time interning order. An explicit known gap matches its issue-linked
diagnostic. For loader failures this includes the stage, construct and
location. A different failure is FAIL. An unexpected success is XPASS.
Both fail the Make target. A documented error can instead be an expected
result and pass only when its specific diagnostic matches.

Worker limits are 20 seconds wall time, 15 seconds CPU, 768 MiB address
space and 1 MiB per captured output file. Run checked-in fixtures only.
These are test limits for local processes.

The source is *The MDL Programming Language* by S. W. Galley and Greg
Pfister, transcribed by Mark Trapp and Tara McGrew. The corpus uses short
functional examples with documented attribution. Its source locations
use the pinned transcription's line numbers. [Published manual and rights notes](https://mdl-language.readthedocs.io/en/latest/)

## Evidence and observation protocol

The worker runs the reader and language module from this checkout. It
returns a versioned typed observation or an MDL diagnostic. Frontend
resolution, post-execution observation, invalid replies, resource failures
and timeouts remain harness failures. Matching a known gap requires exact
diagnostic text after normalizing the generated source filename. Loader
diagnostics also match classification, stage, construct and location.

The typed observation is sufficient for in-session predicates. Use an MDL
expression such as `<==? .A .B>` to test identity and assert its MDL result.
Host representations of two structures cannot establish aliasing. The
synthetic result and effect assignments add new atoms, forms and a module
or load context. They do not establish exact reader interning order,
namespace enumeration or unmodified top-level behavior. A future raw
output, reader trace or cross-session test should define its own worker
input and observation, with validation at the versioned protocol boundary.
No universal object serializer is required.

`make test-conformance-harness` exercises evidence validation, exact
diagnostics and structural source discovery. The dedicated conformance
workflow runs this target and `make test-manual`, and uploads the report and
runner log. Native captures use the separate `python -m scripts.probe_manual`
command and require the pinned Confusion build.
