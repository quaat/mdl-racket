#lang racket/base
;; The read-only allowlist of the December 1977 Zork (M4 S10, issue #171;
;; ADR-0055 amendment, maintainer decision 2026-11-24 "Read-only allowlist").
;;
;; Host service data, not runtime semantics: the only files any game session
;; may OPEN "READ" are the two shipped text files that HELP and INFO print
;; through FILE-TO-TTY (77rooms.mud:954-985) as
;; <OPEN "READ" "MADADV" "HELP"|"INFO" "DSK" "MDL"> (DEV and SNM from SAVE-IT,
;; 77rooms.mud:20-21). Each is resolved inside the session's pinned game
;; directory as MDL/MADADV.HELP / MDL/MADADV.INFO and must have exactly the
;; pinned size and sha256 (docs/evidence/M4/HELP-INFO-REFERENCE.md); anything
;; else is a strict error. Hosts pass this list to make-mdl-session as
;; #:read-only-files (run-zork, the replay profile, the M4 scenario runner).
(require (only-in "../mdl/runtime/core.rkt" mdl-read-only-file))
(provide zork-read-only-files zork-read-only-file-specs)

;; (name1 name2 device directory sha256 size)
(define zork-read-only-file-specs
  '(("MADADV" "HELP" "DSK" "MDL" "00fc24d63869f94d9715ca43d53018c5019ef051d9d6074e113cc5bdafbf2ae1" 4274)
    ("MADADV" "INFO" "DSK" "MDL" "36e6eead79f88df939fbe15ef23856f6ba7e594753b994440c38ed1fb2434aa2" 1527)))

(define zork-read-only-files
  (for/list ([spec (in-list zork-read-only-file-specs)])
    (apply mdl-read-only-file spec)))
