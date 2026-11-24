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
