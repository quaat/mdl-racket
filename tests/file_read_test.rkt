#lang racket/base
;; M4 S10 (issue #171; ADR-0055 amendment "Read-only allowlist"): OPEN "READ"
;; of the host's read-only allowlist, FILE-LENGTH, READSTRING from a file
;; CHANNEL, CLOSE. SEMANTICS: "M4 S10: read-only allowlist for OPEN "READ"".
;; Native evidence: docs/evidence/M4/HELP-INFO-REFERENCE.md
;; (file-read-probe.json).
;;
;; Fixture sessions run over a temporary game directory with MDL/<file>
;; granted by its computed sha256; the pinned-file section runs over the
;; pinned game directory with zork-read-only-files. Every OPEN here runs under
;; a recording security guard: no write or delete may be attempted, and every
;; path touched must be inside the session's root (denied OPENs touch nothing).
(require rackunit racket/file racket/port racket/list racket/string racket/path file/sha1
         "../mdl/loader.rkt"
         (only-in "../mdl/runtime/core.rkt" mdl-read-only-file mdl-read-only-file?
                  mdl-atom-pname mdl-truthy? mdl-string-snapshot)
         "../zork/game-files.rkt"
         (only-in "../zork/main.rkt" default-source-root))

(define original-guard (current-security-guard))

;; --- fixtures ------------------------------------------------------------------------
(define (make-root files)
  (define root (make-temporary-file "file-read-test-~a" 'directory))
  (for ([f (in-list files)])
    (define p (build-path root (car f)))
    (make-directory* (let-values ([(dir name _) (split-path p)]) dir))
    (call-with-output-file p (lambda (o) (write-bytes (cdr f) o)) #:exists 'truncate))
  root)
(define (sha bs) (bytes->hex-string (sha256-bytes bs)))
(define (grant n1 n2 bs #:device [dev "DSK"] #:directory [dir "MDL"])
  (mdl-read-only-file n1 n2 dev dir (sha bs) (bytes-length bs)))

(define text #"line one\nline two\nlast")            ; 22 bytes, no final LF
(define bang #"a!b!!c!\nde\n")                       ; 12 bytes
(define root (make-root (list (cons "MDL/T.TXT" text) (cons "MDL/BANG.TXT" bang)
                              (cons "MDL/OTHER.TXT" #"not granted"))))
(define grants (list (grant "T" "TXT" text) (grant "BANG" "TXT" bang)))

;; Every file-system access attempted while THUNK runs: (who path modes).
(define (accesses thunk)
  (define seen '())
  (define g (make-security-guard
             original-guard
             (lambda (who path modes) (set! seen (cons (list who path modes) seen)))
             (lambda (who host port mode) (error 'file-read-test "network access ~a" host))))
  (define v (parameterize ([current-security-guard g]) (thunk)))
  (values v (reverse seen)))
(define (inside? root p)
  (define r (path->string (simplify-path (path->complete-path root))))
  (string-prefix? (path->string (simplify-path (path->complete-path p))) r))

(define observed '())
(define (observer kind info) (set! observed (cons kind observed)))
(define roots (make-weak-hasheq))  ; session -> its root (for the access check)
(define (session [r root] [g grants] #:input [input ""] #:observer [obs observer])
  (define s (make-mdl-session r #:input-port (open-input-string input)
                              #:output-port (open-output-string)
                              #:read-only-files g #:input-observer obs))
  (hash-set! roots s (normalize-path r))
  s)
(define (c s name . args) (apply mdl-session-call s name args))
(define (tname s v) (mdl-atom-pname (c s "TYPE" v)))
(define (open s n1 n2 [dev "DSK"] [dir "MDL"])
  (define-values (v acc) (accesses (lambda () (c s "OPEN" (string-copy "READ") (string-copy n1)
                                                (string-copy n2) (string-copy dev)
                                                (string-copy dir)))))
  (for ([a (in-list acc)])
    (check-false (or (memq 'write (caddr a)) (memq 'delete (caddr a))) (format "~s" a))
    (when (cadr a) (check-true (inside? (hash-ref roots s) (cadr a)) (format "~s" a))))
  v)
(define (buf n) (make-string n #\nul))
(define (elements s ch) (for/list ([i (in-range 1 (add1 (c s "LENGTH" ch)))]) (c s "NTH" ch i)))

;; --- OPEN "READ" granted -------------------------------------------------------------
(test-case "OPEN READ of an allowlisted file returns a 19-element READ CHANNEL"
  (define s (session))
  (define ch (open s "T" "TXT"))
  (check-equal? (tname s ch) "CHANNEL")
  (check-equal? (c s "LENGTH" ch) 19)
  (define el (elements s ch))
  (check-equal? (take el 12) '(3 "READ" "T" "TXT" "DSK" "MDL" "T" "TXT" "DSK" "MDL" 0 0))
  (check-equal? (tname s (list-ref el 12)) "LOSE")
  (check-equal? (drop el 13) '(0 0 0 0 10 0))
  ;; element 10 is never a host path (decision (c))
  (check-false (regexp-match? #rx"/" (list-ref el 9)))
  (check-equal? (mdl-session-file-channels s) '(("MDL/T.TXT" open)))
  (check-equal? (mdl-session-open-records s) '()))

(test-case "channel numbers: lowest free from 3; distinct channels on one file"
  (define s (session))
  (define a (open s "T" "TXT"))
  (define b (open s "T" "TXT"))
  (check-equal? (c s "NTH" a 1) 3)
  (check-equal? (c s "NTH" b 1) 4)
  (check-false (mdl-truthy? (c s "==?" a b)))
  (c s "CLOSE" a)
  (check-equal? (c s "NTH" (open s "BANG" "TXT") 1) 3))

;; --- FILE-LENGTH ---------------------------------------------------------------------
(test-case "FILE-LENGTH is the length in characters, independent of reading"
  (define s (session))
  (define ch (open s "T" "TXT"))
  (check-equal? (c s "FILE-LENGTH" ch) 22)
  (c s "READSTRING" (buf 10) ch 5)
  (check-equal? (c s "FILE-LENGTH" ch) 22)
  (check-exn #rx"TOO-FEW-ARGUMENTS-SUPPLIED" (lambda () (c s "FILE-LENGTH")))
  (check-exn #rx"TOO-MANY-ARGUMENTS-SUPPLIED" (lambda () (c s "FILE-LENGTH" ch ch)))
  (check-exn #rx"^FILE-LENGTH: .*CHANNEL" (lambda () (c s "FILE-LENGTH" "MDL/T.TXT")))
  (check-exn #rx"FILE-LENGTH-UNAVAILABLE" (lambda () (c s "FILE-LENGTH" (mdl-session-global s "INCHAN"))))
  (c s "CLOSE" ch)
  (check-exn #rx"CHANNEL-CLOSED" (lambda () (c s "FILE-LENGTH" ch))))

;; --- READSTRING from a file ----------------------------------------------------------
(test-case "READSTRING by count stores exactly count characters; the rest is unchanged"
  (define s (session))
  (define ch (open s "T" "TXT"))
  (define b (buf 10))
  (check-equal? (c s "READSTRING" b ch 4) 4)
  (check-equal? b "line\0\0\0\0\0\0")
  (check-equal? (c s "READSTRING" b ch 0) 0)
  (check-equal? (c s "READSTRING" b ch 3) 3)
  (check-equal? b " one\0\0\0\0\0\0")
  (check-exn #rx"count" (lambda () (c s "READSTRING" b ch -1)))
  (check-exn #rx"count" (lambda () (c s "READSTRING" b ch 11)))
  ;; two arguments: until the buffer is full
  (check-equal? (c s "READSTRING" b ch) 10)
  (check-equal? b "e\nline two"))

(test-case "READSTRING with a stop STRING consumes the stop and does not store it"
  (define s (session))
  (define ch (open s "T" "TXT"))
  (define b (buf 20))
  (check-equal? (c s "READSTRING" b ch (string #\newline)) 8)
  (check-equal? (substring b 0 8) "line one")
  (check-equal? (c s "READSTRING" b ch (string #\newline)) 8)
  (check-equal? (substring b 0 9) "line two\0"))

(test-case "end of file: partial count, status element 11, then a strict error"
  (define s (session))
  (define ch (open s "T" "TXT"))
  (define b (buf 20))
  (check-equal? (c s "READSTRING" b ch 18) 18)
  (check-equal? (c s "NTH" ch 11) 0)
  (define breaks (string (integer->char 3) (integer->char 0)))
  (check-equal? (c s "READSTRING" b ch breaks) 4)
  (check-equal? (substring b 0 5) "last ")
  (check-equal? (c s "NTH" ch 11) 1)
  (define e (with-handlers ([values values]) (c s "READSTRING" b ch breaks)))
  (check-pred exn:fail? e)
  (check-false (exn:fail:mdl-input-exhausted? e))
  (check-regexp-match #rx"unexpected end of file" (exn-message e))
  (check-exn #rx"unexpected end of file" (lambda () (c s "READSTRING" b ch 1)))
  ;; a count read that crosses end of file returns the partial count
  (define ch2 (open s "T" "TXT"))
  (check-equal? (c s "READSTRING" (buf 30) ch2 30) 22)
  (check-equal? (c s "NTH" ch2 11) 1)
  ;; CLOSE still works after end of file
  (check-equal? (c s "NTH" (c s "CLOSE" ch) 1) 0))

(test-case "! escapes in file input as on the terminal; CR LF raw"
  (define s (session))
  (define ch (open s "BANG" "TXT"))
  (define b (buf 100))
  (check-equal? (c s "READSTRING" b ch 100) 8)
  (check-equal? (substring b 0 8) "ab!c\nde\n"))

;; --- CLOSE ---------------------------------------------------------------------------
(test-case "CLOSE returns the CHANNEL, clears slots, releases it; a second CLOSE returns it"
  (define s (session))
  (define ch (open s "T" "TXT"))
  (define v (c s "CLOSE" ch))
  (check-true (mdl-truthy? (c s "==?" v ch)))
  (define el (elements s ch))
  (check-equal? (car el) 0)
  (check-equal? (list-ref el 1) "READ")
  (check-equal? (take (drop el 6) 4) '("" "" "" ""))
  (check-true (mdl-truthy? (c s "==?" (c s "CLOSE" ch) ch)))
  (check-equal? (mdl-session-file-channels s) '(("MDL/T.TXT" closed)))
  (check-exn #rx"closed channel" (lambda () (c s "READSTRING" (buf 5) ch 1)))
  (check-exn #rx"CLOSE" (lambda () (c s "CLOSE")))
  (check-exn #rx"CLOSE" (lambda () (c s "CLOSE" ch ch)))
  (check-exn #rx"^CLOSE: .*CHANNEL" (lambda () (c s "CLOSE" "x")))
  (check-exn #rx"^CLOSE: .*terminal" (lambda () (c s "CLOSE" (mdl-session-global s "INCHAN"))))
  (check-exn #rx"^CLOSE: .*terminal" (lambda () (c s "CLOSE" (mdl-session-global s "OUTCHAN")))))

;; --- read-only -----------------------------------------------------------------------
(test-case "no output, RESET or TOP on a file CHANNEL"
  (define s (session))
  (define ch (open s "T" "TXT"))
  (check-exn #rx"output channel" (lambda () (c s "PRINC" "x" ch)))
  (check-exn #rx"output channel" (lambda () (c s "PRIN1" 1 ch)))
  (check-exn #rx"output channel" (lambda () (c s "PRINTSTRING" "x" ch)))
  (check-exn #rx"output channel" (lambda () (c s "CRLF" ch)))
  (check-exn #rx"output channel" (lambda () (c s "TERPRI" ch)))
  (check-exn #rx"output channel" (lambda () (c s "IMAGE" 65 ch)))
  (check-exn #rx"^RESET: .*file" (lambda () (c s "RESET" ch)))
  (check-exn exn:fail? (lambda () (c s "TOP" ch))))

;; --- denials -------------------------------------------------------------------------
(test-case "every OPEN READ off the allowlist is the strict error and touches nothing"
  (define s (session))
  (for ([args (in-list '(("OTHER" "TXT" "DSK" "MDL") ("t" "txt" "DSK" "MDL") ("T" "TXT" "dsk" "MDL")
                         ("T" "TXT" "FOO" "MDL") ("T" "TXT" "DSK" "mdl") ("T" "TXT" "DSK" "MDL/../MDL")
                         ("T" "TXT" "DSK" "") ("T" "TXT" "DSK" "/MDL") ("../MDL/T" "TXT" "DSK" "MDL")
                         ("T" "TXT" "DSK" "MDL/") ("T" "" "DSK" "MDL") ("NOSUCH" "FILE" "DSK" "MDL")))])
    (define-values (v acc)
      (accesses (lambda ()
                  (with-handlers ([exn:fail? exn-message])
                    (apply c s "OPEN" "READ" args)))))
    (check-pred string? v (format "~s" args))
    (check-regexp-match #rx"^OPEN: mode \"READ\" is not supported for .*allowlist" v)
    (check-equal? acc '() (format "~s" args)))
  ;; a session without an allowlist reads nothing
  (define s0 (session root '()))
  (check-exn #rx"^OPEN: mode \"READ\" is not supported" (lambda () (open s0 "T" "TXT")))
  ;; other arities and modes are unchanged
  (check-exn #rx"^OPEN: only the five-STRING form" (lambda () (c s "OPEN" "READ" "T" "TXT" "DSK")))
  (check-exn #rx"^OPEN: mode \"PRINTB\" is not supported" (lambda () (c s "OPEN" "PRINTB" "T" "TXT" "DSK" "MDL")))
  (check-equal? (mdl-session-file-channels s) '()))

;; --- integrity -----------------------------------------------------------------------
(test-case "pinned content: hash, size, missing file, links and non-files are strict errors"
  (define g (grant "T" "TXT" text))
  (define (try files [setup void])
    (define r (make-root files))
    (setup r)
    (with-handlers ([exn:fail? exn-message])
      (open (session r (list g)) "T" "TXT")
      'opened))
  ;; same size, one byte changed
  (check-regexp-match #rx"sha256" (try (list (cons "MDL/T.TXT" #"line one\nline two\nlasT"))))
  (check-regexp-match #rx"size" (try (list (cons "MDL/T.TXT" #"line one\n"))))
  (check-regexp-match #rx"size" (try (list (cons "MDL/T.TXT" (bytes-append text #"x")))))
  (check-regexp-match #rx"missing" (try (list (cons "MDL/X.TXT" #"x"))))
  (check-regexp-match #rx"missing" (try '()))
  (check-regexp-match #rx"regular file"
                      (try '() (lambda (r) (make-directory* (build-path r "MDL" "T.TXT")))))
  ;; a symbolic link to identical content outside the root
  (define outside (make-root (list (cons "MDL/T.TXT" text))))
  (check-regexp-match #rx"symbolic link"
                      (try '() (lambda (r) (make-directory* (build-path r "MDL"))
                                 (make-file-or-directory-link (build-path outside "MDL" "T.TXT")
                                                              (build-path r "MDL" "T.TXT")))))
  (check-regexp-match #rx"symbolic link"
                      (try '() (lambda (r) (make-file-or-directory-link (build-path outside "MDL")
                                                                        (build-path r "MDL")))))
  (check-equal? (try (list (cons "MDL/T.TXT" text))) 'opened))

(test-case "allowlist entries are validated"
  (for ([bad (in-list (list (lambda () (mdl-read-only-file "MA/D" "HELP" "DSK" "MDL" (sha text) 22))
                            (lambda () (mdl-read-only-file ".." "HELP" "DSK" "MDL" (sha text) 22))
                            (lambda () (mdl-read-only-file "" "HELP" "DSK" "MDL" (sha text) 22))
                            (lambda () (mdl-read-only-file "A.B" "HELP" "DSK" "MDL" (sha text) 22))
                            (lambda () (mdl-read-only-file "A" "HELP" "DSK" "M/DL" (sha text) 22))
                            (lambda () (mdl-read-only-file "A" "HELP" "DSK" "MDL" "00" 22))
                            (lambda () (mdl-read-only-file "A" "HELP" "DSK" "MDL" (string-upcase (sha text)) 22))
                            (lambda () (mdl-read-only-file "A" "HELP" "DSK" "MDL" (sha text) -1))
                            ;; size 0: the size pre-check could not keep out a FIFO
                            (lambda () (mdl-read-only-file "A" "HELP" "DSK" "MDL" (sha #"") 0))
                            (lambda () (mdl-read-only-file "A" "HELP" "DSK" "MDL" (sha text) (* 2 1048576)))
                            (lambda () (session root (list (grant "T" "TXT" text) (grant "T" "TXT" text))))
                            (lambda () (session root (list "MDL/T.TXT")))))])
    (check-exn exn:fail? bad)))

;; --- input observer, sessions --------------------------------------------------------
(test-case "file READSTRING never calls the input observer nor reads terminal input"
  (set! observed '())
  (define s (session #:input "x\n"))
  (define ch (open s "T" "TXT"))
  (c s "READSTRING" (buf 10) ch 10)
  (c s "READSTRING" (buf 10) ch (string #\newline))
  (c s "FILE-LENGTH" ch)
  (c s "CLOSE" ch)
  (check-equal? observed '())
  (define b (buf 5))
  (check-equal? (c s "READSTRING" b (mdl-session-global s "INCHAN") (string #\newline)) 1)
  (check-equal? (substring b 0 1) "x")
  (check-equal? (reverse observed) '(enter complete)))

(test-case "file CHANNELs belong to one session"
  (define a (session))
  (define b (session))
  (define ch (open a "T" "TXT"))
  (check-exn #rx"not open" (lambda () (c b "READSTRING" (buf 5) ch 1)))
  (check-exn #rx"not open" (lambda () (c b "CLOSE" ch)))
  (check-exn #rx"not open" (lambda () (c b "FILE-LENGTH" ch)))
  (check-equal? (mdl-session-file-channels b) '())
  (check-equal? (c a "READSTRING" (buf 5) ch 1) 1))

;; --- FILE-TO-TTY (77rooms.mud:960-985, verbatim) -------------------------------------
(define file-to-tty
  (string-append
   "<SETG DEV \"DSK\"> <SETG SNM \"MDL\"> <SETG INBUF <ISTRING 100>> "
   "<SETG BREAKS <STRING <ASCII 3> <ASCII 0>>> <SETG TELL-FLAG <>>\n"
   "<DEFINE FILE-TO-TTY (FILE1 FILE2 \"OPTIONAL\" (DEV <VALUE DEV>) (SNM <VALUE SNM>)
                     \"AUX\" (CH <OPEN \"READ\" .FILE1 .FILE2 .DEV .SNM>)
                           LEN
                           (BUF ,INBUF) (BUFLEN <LENGTH .BUF>)
                           ITER)
        #DECL ((BUF FILE1 FILE2 DEV SNM) STRING (CH) <OR CHANNEL FALSE>
               (ITER LEN BUFLEN) FIX)
        <COND (.CH
               <UNWIND
                <PROG ()
                      <SET LEN <FILE-LENGTH .CH>>
                      <SET ITER </ .LEN .BUFLEN>>
                      <OR <0? <MOD .LEN .BUFLEN>> <SET ITER <+ .ITER 1>>>
                      <CRLF ,OUTCHAN>
                      <SETG TELL-FLAG T>
                      <REPEAT (SLEN)
                              #DECL ((SLEN) FIX)
                              <COND (<1? .ITER>
                                     <SET SLEN <READSTRING .BUF .CH ,BREAKS>>)
                                    (<SET SLEN <READSTRING .BUF .CH .BUFLEN>>)>
                              <PRINTSTRING .BUF ,OUTCHAN .SLEN>
                              <COND (<0? <SET ITER <- .ITER 1>>>
                                     <CRLF ,OUTCHAN>
                                     <RETURN <CLOSE .CH>>)>>>
                <CLOSE .CH>>)
              (<TELL \"File not found.\">)>>\n"))

(test-case "the game's FILE-TO-TTY prints the file exactly (partial and exact last chunk)"
  (define c250 (apply bytes (for/list ([i 250]) (+ 97 (modulo i 26)))))
  (define c200 (apply bytes (for/list ([i 200]) (+ 65 (modulo i 26)))))
  (define r (make-root (list (cons "MDL/A.TXT" c250) (cons "MDL/B.TXT" c200)
                             (cons "ftt.mud" (string->bytes/utf-8 file-to-tty)))))
  (define out (open-output-string))
  (define s (make-mdl-session r #:input-port (open-input-string "") #:output-port out
                              #:read-only-files (list (grant "A" "TXT" c250) (grant "B" "TXT" c200))
                              #:input-observer observer))
  (set! observed '())
  (check-equal? (hash-ref (mdl-session-load! s "ftt.mud") 'status) "PASS")
  (define v (c s "FILE-TO-TTY" "A" "TXT"))
  (check-equal? (tname s v) "CHANNEL")
  (check-equal? (get-output-string out) (string-append "\n" (bytes->string/latin-1 c250) "\n"))
  (check-equal? (mdl-atom-pname (mdl-session-global s "TELL-FLAG")) "T")
  ;; the last chunk (50) left the previous chunk's tail in INBUF
  (check-equal? (mdl-string-snapshot (quote t) (mdl-session-global s "INBUF") "INBUF")
                (string-append (bytes->string/latin-1 (subbytes c250 200 250))
                               (bytes->string/latin-1 (subbytes c250 150 200))))
  (define out2-start (string-length (get-output-string out)))
  (c s "FILE-TO-TTY" "B" "TXT")
  (check-equal? (substring (get-output-string out) out2-start)
                (string-append "\n" (bytes->string/latin-1 c200) "\n"))
  (check-equal? (mdl-session-file-channels s) '(("MDL/A.TXT" closed) ("MDL/B.TXT" closed)))
  (check-equal? observed '()))

;; --- the pinned game files -----------------------------------------------------------
(test-case "zork-read-only-files is exactly the two pinned files"
  (check-equal? (length zork-read-only-files) 2)
  (check-true (andmap mdl-read-only-file? zork-read-only-files))
  (check-equal? zork-read-only-file-specs
                '(("MADADV" "HELP" "DSK" "MDL" "00fc24d63869f94d9715ca43d53018c5019ef051d9d6074e113cc5bdafbf2ae1" 4274)
                  ("MADADV" "INFO" "DSK" "MDL" "36e6eead79f88df939fbe15ef23856f6ba7e594753b994440c38ed1fb2434aa2" 1527))))

;; Pinned-source case: the smoke suite (scripts/test_racket.sh, CI without
;; `make sources`) never has the pinned game; `make test-historical` re-runs
;; this file with MDL_PINNED_SOURCES=1 after `make sources`, where a missing
;; source is a failure, never a skip.
(define pinned-required? (equal? (getenv "MDL_PINNED_SOURCES") "1"))
(unless pinned-required?
  (printf "file_read_test: pinned HELP/INFO case not run here (make test-historical runs it with MDL_PINNED_SOURCES=1)\n"))
(when pinned-required?
 (test-case "the pinned HELP and INFO read back byte for byte"
  (unless (directory-exists? default-source-root)
    (error 'file-read-test "pinned source missing: ~a" default-source-root))
  (define s (session default-source-root zork-read-only-files))
  (for ([name '("HELP" "INFO")] [len '(4274 1527)])
    (define ch (open s "MADADV" name))
    (check-equal? (c s "FILE-LENGTH" ch) len)
    (define b (buf 100))
    (define got
      (let loop ([acc '()])
        (define n (c s "READSTRING" b ch (string (integer->char 3) (integer->char 0))))
        (define acc* (cons (substring b 0 n) acc))
        (if (< n 100) (apply string-append (reverse acc*)) (loop acc*))))
    (check-equal? (string->bytes/latin-1 got)
                  (file->bytes (build-path default-source-root "MDL" (string-append "MADADV." name))))
    (c s "CLOSE" ch))
  ;; MADADV.SAVE is in the same directory and is not readable
  (check-exn #rx"not on this session's read-only allowlist" (lambda () (open s "MADADV" "SAVE")))))
