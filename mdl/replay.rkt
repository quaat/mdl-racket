#lang racket/base
;; Host-managed persistence by deterministic replay (ADR-0061; SEMANTICS
;; "M4 WP4: session clock modes and deterministic replay checkpoints").
;;
;; A host module beside loader.rkt. It is NOT an MDL primitive: nothing here
;; is reachable from MDL code, MDL gains no file access, and this module never
;; writes a file (a checkpoint is a detached byte string; storing it is the
;; caller's business). Game-specific rules (the save boundary, the selected
;; state) come from a replay-profile (zork/persistence.rkt for the 1977 game).
;;
;; A run boots a FRESH session from the unchanged sources (<FLOAD entry-file>,
;; then the host top-level loop applying entry-function, ADR-0049/0050), with
;;   * the session clock wrapped in a logging clock (recording, or replaying
;;     then resumed, mdl/runtime/clock.rkt),
;;   * a host-only READSTRING observer that logs exactly the characters MDL
;;     consumed and reports every READSTRING entry,
;;   * an output port that captures the transcript (for its digest) and
;;     forwards to the live port only in the live phase.
;; replay-record plays live from the start; replay-restore first replays a
;; checkpoint (output captured and discarded, input served only from the log,
;; the replaying clock), verifies the reconstructed state at the save point and
;; only then continues live in the same call. Any failure before that point
;; raises exn:fail:replay-restore and the fresh session is dropped.
(require racket/list racket/string file/sha1
         "loader.rkt" "runtime/clock.rkt"
         (only-in "runtime/random36.rkt" random36-state-words random36-state-draws))

(provide (struct-out replay-profile)
         (struct-out replay-result)
         (struct-out exn:fail:replay-restore)
         (struct-out exn:fail:replay-save-refused)
         replay-record replay-restore replay-validate-checkpoint
         replay-prompt? replay-prompt-turn replay-prompt-session
         replay-prompt-refusal replay-prompt-checkpoint replay-prompt-try-checkpoint
         replay-checkpoint-format replay-rng-version replay-rng-algorithm
         replay-limits replay-sessions-created
         canonical-json-bytes canonical-json-parse checkpoint-reseal)

;; --- profile and results ---------------------------------------------------------
;; name: profile id stored in the checkpoint. entry-file / entry-function: the
;; faithful boot. files: the game files the boot loads, in load order (a
;; checkpoint must list exactly these). upstream: (-> hash symbol -> string)
;; of upstream SHAs.
;; prompt-refusal: (session enter-info -> (or/c #f string)), the game's save
;; boundary rule. state: (session -> hash symbol -> string), the selected game
;; state. moves: (session -> exact-integer). seed: (observations time-zone ->
;; hash symbol -> (or string integer)), the RNG seed provenance.
;; read-only-files: the session's read-only allowlist (M4 S10, ADR-0055
;; amendment; make-mdl-session #:read-only-files). File reads are not input:
;; READSTRING from a file CHANNEL never reaches the observer, so they are
;; neither logged nor replayed; replay re-reads the hash-checked files.
(struct replay-profile (name entry-file entry-function files upstream prompt-refusal state moves
                                 seed read-only-files))
;; kind: 'quit, 'quit-after-mdl-error or 'input-exhausted (like zork-result).
;; host-errors: exn:fail values raised by the host's on-prompt/on-restored
;; callbacks, oldest first. They are caught at the callback boundary so a
;; failing host callback never unwinds the game (review L2).
(struct replay-result (kind mdl-errors message session host-errors) #:transparent)
;; stage: 'format 'checksum 'schema 'profile 'provenance 'boot 'replay
;; 'verification.
(struct exn:fail:replay-restore exn:fail (stage) #:transparent)
(struct exn:fail:replay-save-refused exn:fail () #:transparent)

(define replay-checkpoint-format "mdl-zork-replay/v1")
(define replay-rng-version "rng/v1")
(define replay-rng-algorithm "mdl-random36/v1")
(define replay-limits
  (hasheq 'bytes (* 4 1024 1024) 'input-units 100000 'observations 400000
          'string-chars 65536 'depth 8 'integer-digits 19 'state-entries 256 'source-files 64))
(define (limit k) (hash-ref replay-limits k))

;; Host-only test observation: how many replay sessions were created in this
;; process (a rejected checkpoint must not create one).
(define sessions-created 0)
(define (replay-sessions-created) sessions-created)

(define (restore-fail stage fmt . args)
  (raise (exn:fail:replay-restore
          (apply format (string-append "replay restore (" (symbol->string stage) "): " fmt) args)
          (current-continuation-marks) stage)))

;; --- canonical JSON ------------------------------------------------------------------
;; Values: hasheq with symbol keys (objects), lists (arrays), strings, exact
;; integers, #t, #f, 'null. Encoding: ASCII only, keys sorted by code point,
;; no whitespace; `"` and `\` escaped with a backslash, every other character
;; below 32 and DEL as \u00xx (lowercase hex); characters above 127 refused.
(define (canonical-json-bytes v)
  (define out (open-output-bytes))
  (let enc ([v v])
    (cond
      [(hash? v)
       (write-bytes #"{" out)
       (for ([k (in-list (sort (hash-keys v) string<? #:key symbol->string))]
             [i (in-naturals)])
         (unless (symbol? k) (error 'canonical-json "object key is not a symbol: ~e" k))
         (when (> i 0) (write-bytes #"," out))
         (enc (symbol->string k))
         (write-bytes #":" out)
         (enc (hash-ref v k)))
       (write-bytes #"}" out)]
      [(list? v)
       (write-bytes #"[" out)
       (for ([x (in-list v)] [i (in-naturals)])
         (when (> i 0) (write-bytes #"," out))
         (enc x))
       (write-bytes #"]" out)]
      [(string? v)
       (write-bytes #"\"" out)
       (for ([c (in-string v)])
         (define n (char->integer c))
         (cond [(> n 127) (error 'canonical-json "non-ASCII character in string: ~e" v)]
               [(memv c '(#\" #\\)) (write-bytes (bytes 92 n) out)]
               [(or (< n 32) (= n 127))
                (write-bytes (string->bytes/latin-1
                              (string-append "\\u00" (if (< n 16) "0" "")
                                             (number->string n 16)))
                             out)]
               [else (write-byte n out)]))
       (write-bytes #"\"" out)]
      [(exact-integer? v) (write-bytes (string->bytes/latin-1 (number->string v)) out)]
      [(eq? v #t) (write-bytes #"true" out)]
      [(eq? v #f) (write-bytes #"false" out)]
      [(eq? v 'null) (write-bytes #"null" out)]
      [else (error 'canonical-json "unsupported value: ~e" v)]))
  (get-output-bytes out))

;; Strict parser for exactly the canonical encoding above: anything else
;; (whitespace, unsorted or duplicate keys, other escapes, fractions,
;; exponents, leading zeros, -0, over-long numbers or strings, nesting deeper
;; than the limit, trailing bytes) is an error. Never uses `read`.
(define (canonical-json-parse bs)
  (unless (bytes? bs) (raise-argument-error 'canonical-json-parse "bytes?" bs))
  (define len (bytes-length bs))
  (define pos 0)
  (define (bad fmt . args)
    (apply error 'canonical-json (string-append "at byte ~a: " fmt) pos args))
  (define (peek) (if (< pos len) (bytes-ref bs pos) (bad "unexpected end")))
  (define (next!) (begin0 (peek) (set! pos (add1 pos))))
  (define (expect! b) (unless (= (next!) b) (bad "expected ~a" (integer->char b))))
  (define (digit? b) (<= 48 b 57))
  (define (hex-digit b)
    (cond [(digit? b) (- b 48)] [(<= 97 b 102) (- b 87)] [else (bad "bad hex digit")]))
  (define (parse-string)
    (expect! 34)
    (define out (open-output-string))
    (let loop ([n 0])
      (when (> n (limit 'string-chars)) (bad "string too long"))
      (define b (next!))
      (cond
        [(= b 34) (get-output-string out)]
        [(= b 92)
         (define e (next!))
         (cond
           [(memv e '(34 92)) (write-char (integer->char e) out)]
           [(= e 117)
            (unless (and (= (next!) 48) (= (next!) 48)) (bad "\\u escape out of range"))
            (define code (+ (* 16 (hex-digit (next!))) (hex-digit (next!))))
            (unless (or (< code 32) (= code 127)) (bad "non-canonical \\u escape"))
            (write-char (integer->char code) out)]
           [else (bad "non-canonical escape")])
         (loop (add1 n))]
        [(or (< b 32) (>= b 127)) (bad "unescaped control or non-ASCII byte")]
        [else (write-char (integer->char b) out) (loop (add1 n))])))
  (define (parse-integer)
    (define start pos)
    (define neg? (= (peek) 45))
    (when neg? (next!))
    (unless (and (< pos len) (digit? (peek))) (bad "expected a digit"))
    (define first (next!))
    (when (= first 48)
      (when (and (< pos len) (digit? (peek))) (bad "leading zero"))
      (when neg? (bad "negative zero")))
    (let loop () (when (and (< pos len) (digit? (peek))) (next!) (loop)))
    (when (and (< pos len) (memv (peek) '(46 101 69))) (bad "only integers are allowed"))
    (when (> (- pos start (if neg? 1 0)) (limit 'integer-digits)) (bad "integer too long"))
    (string->number (bytes->string/latin-1 (subbytes bs start pos))))
  (define (parse-literal word value)
    (for ([b (in-bytes word)]) (expect! b))
    value)
  (define (parse-value depth)
    (define b (peek))
    (when (and (memv b '(91 123)) (> depth (limit 'depth))) (bad "nesting too deep"))
    (cond
      [(= b 123)
       (next!)
       (if (= (peek) 125)
           (begin (next!) (hasheq))
           (let loop ([acc '()] [prev #f])
             (define k (parse-string))
             (when (and prev (not (string<? prev k))) (bad "object keys not strictly sorted"))
             (expect! 58)
             (define v (parse-value (add1 depth)))
             (define acc* (cons (cons (string->symbol k) v) acc))
             (case (next!)
               [(44) (loop acc* k)]
               [(125) (for/hasheq ([p (in-list acc*)]) (values (car p) (cdr p)))]
               [else (set! pos (sub1 pos)) (bad "expected , or }")])))]
      [(= b 91)
       (next!)
       (if (= (peek) 93)
           (begin (next!) '())
           (let loop ([acc '()])
             (define acc* (cons (parse-value (add1 depth)) acc))
             (case (next!)
               [(44) (loop acc*)]
               [(93) (reverse acc*)]
               [else (set! pos (sub1 pos)) (bad "expected , or ]")])))]
      [(= b 34) (parse-string)]
      [(or (= b 45) (digit? b)) (parse-integer)]
      [(= b 116) (parse-literal #"true" #t)]
      [(= b 102) (parse-literal #"false" #f)]
      [(= b 110) (parse-literal #"null" 'null)]
      [else (bad "unexpected byte ~a" b)]))
  (define v (parse-value 1))
  (unless (= pos len) (bad "trailing bytes"))
  ;; Belt and braces: the input must be exactly the canonical encoding.
  (unless (equal? (canonical-json-bytes v) bs) (bad "not the canonical encoding"))
  v)

(define (sha256-hex bs) (bytes->hex-string (sha256-bytes (open-input-bytes bs))))
(define (checksum-of doc) (sha256-hex (canonical-json-bytes (hash-remove doc 'checksum))))
;; Recompute the checksum of a parsed checkpoint (tests use it to build
;; tampered checkpoints whose only defect is the intended one).
(define (checkpoint-reseal doc)
  (canonical-json-bytes (hash-set doc 'checksum (checksum-of doc))))

;; --- schema ------------------------------------------------------------------------
(define (hex64? v) (and (string? v) (regexp-match? #px"^[0-9a-f]{64}$" v)))
(define (word36? v) (and (exact-integer? v) (<= 0 v (sub1 (expt 2 36)))))
(define (nat? v) (exact-nonnegative-integer? v))
(define (keys=? h ks) (and (hash? h) (equal? (sort (hash-keys h) symbol<?) (sort ks symbol<?))))
(define (schema-check! ok? fmt . args)
  (unless ok? (apply restore-fail 'schema fmt args)))
(define (string-map? h)
  (and (hash? h) (for/and ([(k v) (in-hash h)]) (string? v))))

(define (check-schema! doc)
  ;; review M3: whatever the shape of a field, a violation is a schema
  ;; rejection, never a contract error from an unchecked operation.
  (with-handlers ([(lambda (e) (and (exn:fail? e) (not (exn:fail:replay-restore? e))))
                   (lambda (e) (restore-fail 'schema "malformed field: ~a" (exn-message e)))])
    (check-schema-fields! doc)))

(define (check-schema-fields! doc)
  (schema-check! (keys=? doc '(checksum clock format input observations profile rng runtime
                                        source verification))
                 "unexpected top-level fields ~a" (and (hash? doc) (sort (hash-keys doc) symbol<?)))
  (define clock (hash-ref doc 'clock))
  (schema-check! (and (keys=? clock '(boot_clock time_zone)) (string? (hash-ref clock 'boot_clock))
                      (member (hash-ref clock 'time_zone) '("utc" "local")))
                 "bad clock block")
  (define input (hash-ref doc 'input))
  (schema-check! (and (list? input) (<= (length input) (limit 'input-units))) "bad input log")
  (define n-input (length input)) ; review M1: computed once
  (for ([u (in-list input)] [i (in-naturals)])
    (schema-check! (and (list? u) (= (length u) 2) (string? (car u))
                        (member (cadr u) '("stop" "full" "eof")))
                   "bad input unit ~a" i))
  (define obs (hash-ref doc 'observations))
  (schema-check! (and (list? obs) (<= (length obs) (limit 'observations))) "bad observation log")
  (define n-obs (length obs))
  (for ([o (in-list obs)] [i (in-naturals)])
    (schema-check! (and (list? o) (= (length o) 3)
                        (exact-integer? (car o)) (<= (- (expt 2 35)) (car o) (sub1 (expt 2 35)))
                        (exact-integer? (cadr o)) (<= 0 (cadr o) 999999)
                        (nat? (caddr o)) (<= (caddr o) n-input))
                   "bad observation ~a" i))
  (schema-check! (string? (hash-ref doc 'profile)) "bad profile")
  (define rng (hash-ref doc 'rng))
  (schema-check! (and (keys=? rng '(algorithm draws seed state version)) (nat? (hash-ref rng 'draws))
                      (hash? (hash-ref rng 'seed))
                      (for/and ([(k v) (in-hash (hash-ref rng 'seed))])
                        (or (string? v) (exact-integer? v)))
                      (list? (hash-ref rng 'state)) (= 2 (length (hash-ref rng 'state)))
                      (andmap word36? (hash-ref rng 'state)))
                 "bad rng block")
  (define runtime (hash-ref doc 'runtime))
  (schema-check! (and (keys=? runtime '(commit racket)) (string-map? runtime)) "bad runtime block")
  (define source (hash-ref doc 'source))
  (schema-check! (and (keys=? source '(entry_file entry_function files manifest_sha256 upstream))
                      (string? (hash-ref source 'entry_file))
                      (string? (hash-ref source 'entry_function))
                      (hex64? (hash-ref source 'manifest_sha256))
                      (string-map? (hash-ref source 'upstream))
                      (list? (hash-ref source 'files)) (pair? (hash-ref source 'files)))
                 "bad source block")
  ;; review M2: bounded and duplicate-free before anything is hashed
  (define files (hash-ref source 'files))
  (schema-check! (<= (length files) (limit 'source-files))
                 "~a source files listed (limit ~a)" (length files) (limit 'source-files))
  (schema-check! (for/and ([f (in-list files)])
                   (and (list? f) (= 2 (length f)) (string? (car f)) (hex64? (cadr f))))
                 "bad source file entry")
  (schema-check! (not (check-duplicates (map car files))) "duplicate source file entries")
  (define ver (hash-ref doc 'verification))
  (schema-check! (and (keys=? ver '(input_units moves observations state state_sha256
                                                transcript_bytes transcript_sha256))
                      (eqv? (hash-ref ver 'input_units) n-input)
                      (eqv? (hash-ref ver 'observations) n-obs)
                      (exact-integer? (hash-ref ver 'moves))
                      (string-map? (hash-ref ver 'state))
                      (<= (hash-count (hash-ref ver 'state)) (limit 'state-entries))
                      (hex64? (hash-ref ver 'state_sha256))
                      (nat? (hash-ref ver 'transcript_bytes))
                      (hex64? (hash-ref ver 'transcript_sha256)))
                 "bad verification block"))

;; --- source provenance -------------------------------------------------------------
(define (file-sha256 root rel)
  (call-with-input-file (build-path root rel) (lambda (in) (bytes->hex-string (sha256-bytes in)))))
(define (manifest-hash files) (sha256-hex (canonical-json-bytes files)))
(define (loaded-files report)
  (remove-duplicates (for/list ([e (in-list (hash-ref report 'events))]) (hash-ref e 'file))))

;; Validate a checkpoint without creating a session: size, canonical
;; encoding, format and RNG version, checksum, schema, profile, and source
;; provenance against the files under SOURCE-ROOT. Returns the parsed document.
(define (replay-validate-checkpoint profile bs #:source-root root)
  ;; review M3: every rejection is an exn:fail:replay-restore; an unexpected
  ;; failure inside validation is reported as a format rejection.
  (with-handlers ([(lambda (e) (and (exn:fail? e) (not (exn:fail:replay-restore? e))))
                   (lambda (e) (restore-fail 'format "invalid checkpoint: ~a" (exn-message e)))])
    (validate-checkpoint profile bs root)))

(define (validate-checkpoint profile bs root)
  (unless (bytes? bs) (restore-fail 'format "a checkpoint must be a byte string"))
  (when (> (bytes-length bs) (limit 'bytes))
    (restore-fail 'format "oversized checkpoint: ~a bytes (limit ~a)" (bytes-length bs) (limit 'bytes)))
  (define doc
    (with-handlers ([exn:fail? (lambda (e) (restore-fail 'format "malformed checkpoint: ~a"
                                                         (exn-message e)))])
      (canonical-json-parse bs)))
  (unless (and (hash? doc) (equal? (hash-ref doc 'format #f) replay-checkpoint-format))
    (restore-fail 'format "unsupported checkpoint format ~e (expected ~s)"
                  (and (hash? doc) (hash-ref doc 'format #f)) replay-checkpoint-format))
  (define rng (hash-ref doc 'rng #f))
  (unless (and (hash? rng) (equal? (hash-ref rng 'version #f) replay-rng-version)
               (equal? (hash-ref rng 'algorithm #f) replay-rng-algorithm))
    (restore-fail 'format "unsupported RNG contract ~e/~e (expected ~s/~s)"
                  (and (hash? rng) (hash-ref rng 'version #f)) (and (hash? rng) (hash-ref rng 'algorithm #f))
                  replay-rng-version replay-rng-algorithm))
  (unless (hex64? (hash-ref doc 'checksum #f))
    (restore-fail 'checksum "missing or malformed checksum"))
  (unless (equal? (checksum-of doc) (hash-ref doc 'checksum))
    (restore-fail 'checksum "checksum mismatch: the checkpoint was modified or corrupted"))
  (check-schema! doc)
  (unless (equal? (hash-ref doc 'profile) (replay-profile-name profile))
    (restore-fail 'profile "checkpoint profile ~s is not ~s" (hash-ref doc 'profile)
                  (replay-profile-name profile)))
  (define source (hash-ref doc 'source))
  (unless (and (equal? (hash-ref source 'entry_file) (replay-profile-entry-file profile))
               (equal? (hash-ref source 'entry_function) (replay-profile-entry-function profile)))
    (restore-fail 'provenance "entry ~a/~a differs from the profile's ~a/~a"
                  (hash-ref source 'entry_file) (hash-ref source 'entry_function)
                  (replay-profile-entry-file profile) (replay-profile-entry-function profile)))
  (unless (equal? (hash-ref source 'upstream) ((replay-profile-upstream profile)))
    (restore-fail 'provenance "upstream source SHAs ~s differ from this checkout's ~s"
                  (hash-ref source 'upstream) ((replay-profile-upstream profile))))
  (define files (hash-ref source 'files))
  ;; review M2: exactly the profile's game files, settled before any read
  (unless (equal? (map car files) (replay-profile-files profile))
    (restore-fail 'provenance "the listed files ~s are not the profile's game files ~s"
                  (map car files) (replay-profile-files profile)))
  (unless (equal? (manifest-hash files) (hash-ref source 'manifest_sha256))
    (restore-fail 'provenance "manifest hash does not match the listed files"))
  (define here
    (for/list ([f (in-list files)])
      (define rel (car f))
      (when (or (regexp-match? #rx"(^|/)\\.\\.(/|$)" rel) (absolute-path? rel))
        (restore-fail 'provenance "game file path ~s escapes the source root" rel))
      (list rel (with-handlers ([exn:fail? (lambda (e) (restore-fail 'provenance "game file ~a: ~a"
                                                                     rel (exn-message e)))])
                  (file-sha256 root rel)))))
  (unless (equal? (manifest-hash here) (hash-ref source 'manifest_sha256))
    (define differing (for/list ([a (in-list files)] [b (in-list here)] #:unless (equal? a b)) (car a)))
    (restore-fail 'provenance "game-source manifest mismatch: ~a differ from the checkpoint's sources"
                  (string-join differing ", ")))
  doc)

;; --- the run engine ----------------------------------------------------------------
(struct run (profile [session #:mutable] [clock #:mutable] time-zone boot-clock
                     [phase #:mutable]             ; 'boot 'replay 'live 'ended
                     [log #:mutable]               ; input units, newest first: (raw . reason)
                     [completed #:mutable] [last-reason #:mutable] [eof? #:mutable]
                     capture [live-output? #:mutable]
                     [files #:mutable] runtime-commit
                     [expected #:mutable]          ; restore: parsed checkpoint
                     [on-prompt #:mutable]
                     [expected-input #:mutable]    ; restore: vector of logged units
                     [host-errors #:mutable]))     ; newest first

(struct replay-prompt (run turn info [valid? #:mutable]))

;; Host callbacks run inside READSTRING (review L2). Their contract is not to
;; raise; an exn:fail they raise anyway is recorded in the result's
;; host-errors instead of unwinding the game's MDL frames. Breaks propagate.
(define (call-host-callback r thunk)
  (with-handlers ([exn:fail? (lambda (e) (set-run-host-errors! r (cons e (run-host-errors r))))])
    (thunk)))
(define (replay-prompt-session p) (run-session (replay-prompt-run p)))

;; The output port of a replay session: everything goes to the capture (for
;; the transcript digest); the live port sees it only in the live phase.
(define (make-tee-port r live)
  (make-output-port
   'replay-session-output always-evt
   (lambda (bs start end non-block? breakable?)
     (write-bytes bs (run-capture r) start end)
     (when (run-live-output? r)
       (if (= start end) (flush-output live) (write-bytes bs live start end)))
     (- end start))
   void))

;; Restore input: exactly the logged characters, then (after verification)
;; the live port. A read past the log during replay is a strict error and
;; never touches the live port.
(define (make-replay-input-port replay live)
  (define pos 0)
  (define len (bytes-length replay))
  (define live? #f)
  (values
   (make-input-port
    'replay-session-input
    (lambda (buf)
      (cond
        [live?
         (define n (read-bytes-avail!* buf live))
         (if (eqv? n 0) (wrap-evt live (lambda (_) 0)) n)]
        [(< pos len)
         (bytes-set! buf 0 (bytes-ref replay pos))
         (set! pos (add1 pos))
         1]
        [else (restore-fail 'replay "the replayed session read past the ~a recorded input bytes" len)]))
    #f void)
   (lambda () (- len pos))
   (lambda () (set! live? #t))))

(define (observer r on-replay-entry)
  (lambda (kind info)
    (case kind
      [(enter)
       (case (run-phase r)
         [(replay) (on-replay-entry info)]
         [(live)
          (define cb (run-on-prompt r))
          (when cb
            (define p (replay-prompt r (run-completed r) info #t))
            (dynamic-wind void (lambda () (call-host-callback r (lambda () (cb p))))
                          (lambda () (set-replay-prompt-valid?! p #f))))])]
      [(complete)
       (define raw (hash-ref info 'raw))
       (define reason (hash-ref info 'reason))
       (when (eq? (run-phase r) 'replay)
         (define expected (vector-ref (run-expected-input r) (run-completed r)))
         (unless (and (equal? raw (car expected)) (equal? (symbol->string reason) (cadr expected)))
           (restore-fail 'replay "input unit ~a diverged: consumed ~s (~a), recorded ~s (~a)"
                         (run-completed r) raw reason (car expected) (cadr expected))))
       (set-run-log! r (cons (cons raw reason) (run-log r)))
       (set-run-completed! r (add1 (run-completed r)))
       (set-run-last-reason! r reason)
       (when (eq? reason 'eof) (set-run-eof?! r #t))])))

;; The save-boundary rule: generic conditions first, then the profile's.
(define (boundary-refusal r info)
  (define s (run-session r))
  (cond
    [(pair? (mdl-session-mdl-errors s)) "an MDL ERROR was signalled in this session"]
    [(run-eof? r) "end of input was consumed; there is no command prompt to resume at"]
    [(eq? (run-last-reason r) 'full)
     "the previous READSTRING filled its buffer; the rest of that line is pending input"]
    [((replay-profile-prompt-refusal (run-profile r)) s info) => values]
    [else #f]))

(define (replay-prompt-refusal p)
  (define r (replay-prompt-run p))
  (cond [(not (replay-prompt-valid? p)) "this prompt is no longer current"]
        [(not (eq? (run-phase r) 'live)) "the session is not live"]
        [else (boundary-refusal r (replay-prompt-info p))]))

(define (rng-now s)
  (define snap (mdl-session-random-snapshot s))
  (values (random36-state-words snap) (random36-state-draws snap)))

;; The verification state, read without perturbing the session: the RNG
;; state and the logical storage ledger must be unchanged by the reads.
(define (verification-state r)
  (define s (run-session r))
  (define profile (run-profile r))
  (define-values (words0 draws0) (rng-now s))
  (define ledger0 (mdl-session-storage-stats s))
  (define state ((replay-profile-state profile) s))
  (define moves ((replay-profile-moves profile) s))
  (define-values (words draws) (rng-now s))
  (unless (and (equal? words words0) (= draws draws0)
               (equal? (mdl-session-storage-stats s) ledger0))
    (error 'replay "reading the verification state perturbed the session (RNG or storage ledger)"))
  (define transcript (get-output-bytes (run-capture r)))
  (hasheq 'rng-state words 'rng-draws draws 'moves moves 'state state
          'state_sha256 (sha256-hex (canonical-json-bytes state))
          'transcript_bytes (bytes-length transcript)
          'transcript_sha256 (sha256-hex transcript)))

(define (obs->json o)
  (list (clock-observation-seconds o) (clock-observation-micros o) (clock-observation-turn o)))

;; The non-raising form: the checkpoint bytes, or the refusal reason string.
(define (replay-prompt-try-checkpoint p)
  (with-handlers ([exn:fail:replay-save-refused?
                   (lambda (e) (regexp-replace #rx"^replay checkpoint refused: " (exn-message e) ""))])
    (replay-prompt-checkpoint p)))

(define (replay-prompt-checkpoint p)
  (define refusal (replay-prompt-refusal p))
  (when refusal
    (raise (exn:fail:replay-save-refused
            (string-append "replay checkpoint refused: " refusal) (current-continuation-marks))))
  (define r (replay-prompt-run p))
  (define profile (run-profile r))
  (define v (verification-state r))
  (define observations (mdl-clock-observations (run-clock r)))
  (define input (for/list ([u (in-list (reverse (run-log r)))])
                  (list (car u) (symbol->string (cdr u)))))
  (define files (run-files r))
  (define doc
    (hasheq
     'format replay-checkpoint-format
     'profile (replay-profile-name profile)
     'rng (hasheq 'version replay-rng-version 'algorithm replay-rng-algorithm
                  'state (hash-ref v 'rng-state) 'draws (hash-ref v 'rng-draws)
                  'seed ((replay-profile-seed profile) observations (run-time-zone r)))
     'source (hasheq 'upstream ((replay-profile-upstream profile))
                     'entry_file (replay-profile-entry-file profile)
                     'entry_function (replay-profile-entry-function profile)
                     'files files 'manifest_sha256 (manifest-hash files))
     'runtime (hasheq 'commit (run-runtime-commit r)
                      'racket (format "Racket ~a (~a)" (version) (system-type 'vm)))
     'clock (hasheq 'time_zone (symbol->string (run-time-zone r)) 'boot_clock (run-boot-clock r))
     'observations (map obs->json observations)
     'input input
     'verification (hasheq 'input_units (length input) 'observations (length observations)
                           'moves (hash-ref v 'moves) 'state (hash-ref v 'state)
                           'state_sha256 (hash-ref v 'state_sha256)
                           'transcript_bytes (hash-ref v 'transcript_bytes)
                           'transcript_sha256 (hash-ref v 'transcript_sha256))))
  (define bs (checkpoint-reseal doc))
  (when (> (bytes-length bs) (limit 'bytes))
    (raise (exn:fail:replay-save-refused
            (format "replay checkpoint refused: ~a bytes exceed the ~a-byte limit"
                    (bytes-length bs) (limit 'bytes))
            (current-continuation-marks))))
  bs)

;; A guard refusing file writes/deletes and network use during the run
;; (ADR-0055 defense in depth, as in zork/main.rkt). Reads are allowed.
(define (no-write-guard parent)
  (make-security-guard
   parent
   (lambda (who path modes)
     (when (and path (or (memq 'write modes) (memq 'delete modes)))
       (error 'replay "refused ~a of ~a during a replay session (no-file policy)" modes path)))
   (lambda (who host port mode)
     (error 'replay "refused network access during a replay session"))))

(define (check-ports who in out)
  (unless (input-port? in) (raise-argument-error who "input-port?" in))
  (unless (output-port? out) (raise-argument-error who "output-port?" out)))

;; Boot and run one session. MAKE-INPUT: the session's input port.
;; AFTER-LOAD: checks on the load report. Returns a replay-result or raises.
(define (run-session! r #:root root #:input in #:output out #:after-load after-load)
  (define profile (run-profile r))
  (parameterize ([current-security-guard (no-write-guard (current-security-guard))])
    (define s (make-mdl-session root #:input-port in #:output-port (make-tee-port r out)
                                #:clock (run-clock r) #:time-zone (run-time-zone r)
                                #:input-observer (observer r (lambda (info) (replay-entry! r info)))
                                #:read-only-files (replay-profile-read-only-files profile)))
    (set! sessions-created (add1 sessions-created))
    (set-run-session! r s)
    (define report (mdl-session-load! s (replay-profile-entry-file profile)))
    (unless (equal? (hash-ref report 'status) "PASS")
      (restore-fail 'boot "loading ~a did not PASS (status ~a)" (replay-profile-entry-file profile)
                    (hash-ref report 'status)))
    (define files (for/list ([f (in-list (loaded-files report))]) (list f (file-sha256 root f))))
    (set-run-files! r files)
    (after-load files)
    (begin0
      (with-handlers ([exn:fail:mdl-input-exhausted?
                       (lambda (e) (replay-result 'input-exhausted '() (exn-message e) s
                                                  (reverse (run-host-errors r))))])
        (define outcome (mdl-session-run-interactive s (replay-profile-entry-function profile)))
        (replay-result (mdl-session-outcome-kind outcome) (mdl-session-outcome-mdl-errors outcome)
                       #f s (reverse (run-host-errors r))))
      (set-run-phase! r 'ended))))

;; Overridden per restore (the replay-entry hook needs restore-only state).
(define current-replay-entry (make-parameter #f))
(define (replay-entry! r info) ((current-replay-entry) r info))

;; Play live from the start on a recording clock over SOURCE.
(define (replay-record profile
                       #:source-root root
                       #:input [in (current-input-port)]
                       #:output [out (current-output-port)]
                       #:clock [source real-mdl-clock]
                       #:boot-clock [boot-clock (if (eq? source real-mdl-clock) "real" "host")]
                       #:time-zone [tz 'local]
                       #:on-prompt [on-prompt #f]
                       #:runtime-commit [commit "unknown"])
  (check-ports 'replay-record in out)
  (unless (mdl-clock? source) (raise-argument-error 'replay-record "mdl-clock?" source))
  (define r (run profile #f #f tz boot-clock 'boot '() 0 #f #f (open-output-bytes) #t #f commit #f
                 on-prompt #f '()))
  (set-run-clock! r (make-recording-mdl-clock source #:turn (lambda () (run-completed r))))
  (parameterize ([current-replay-entry (lambda (r info) (error 'replay "no replay in a recording run"))])
    (run-session! r #:root root #:input in #:output out
                  #:after-load (lambda (files) (set-run-phase! r 'live)))))

;; Restore CHECKPOINT (bytes) into a fresh session, verify it at the save
;; point, then continue live on IN/OUT with the resumed clock over WALL.
;; ON-RESTORED (session -> any) runs once, right after verification, before
;; any live input is read (read-only introspection for hosts and tests).
(define (replay-restore profile checkpoint
                        #:source-root root
                        #:input [in (current-input-port)]
                        #:output [out (current-output-port)]
                        #:wall-clock [wall real-mdl-clock]
                        #:on-restored [on-restored void]
                        #:on-prompt [on-prompt #f]
                        #:runtime-commit [commit "unknown"])
  (check-ports 'replay-restore in out)
  (unless (mdl-clock? wall) (raise-argument-error 'replay-restore "mdl-clock?" wall))
  (define doc (replay-validate-checkpoint profile checkpoint #:source-root root))
  (define input (hash-ref doc 'input))
  (define n (length input))
  (define replay-bytes (string->bytes/latin-1 (apply string-append (map car input))))
  (define-values (port remaining go-live!) (make-replay-input-port replay-bytes in))
  (define r (run profile #f #f (string->symbol (hash-ref (hash-ref doc 'clock) 'time_zone))
                 (hash-ref (hash-ref doc 'clock) 'boot_clock)
                 'boot '() 0 #f #f (open-output-bytes) #f #f commit doc on-prompt
                 (list->vector input) '()))
  (set-run-clock! r (make-replaying-mdl-clock
                     (for/list ([o (in-list (hash-ref doc 'observations))]) (apply clock-observation o))
                     #:turn (lambda () (run-completed r))))
  (define (verify-and-resume! r info)
    (when (= (run-completed r) n)
      (define (vfail fmt . args) (apply restore-fail 'verification fmt args))
      (unless (zero? (remaining))
        (vfail "~a recorded input bytes were not consumed" (remaining)))
      (define refusal (boundary-refusal r info))
      (when refusal (vfail "the replayed save point is not a valid save boundary: ~a" refusal))
      (define v (verification-state r))
      (define expected-rng (hash-ref doc 'rng))
      (define ver (hash-ref doc 'verification))
      (unless (equal? (hash-ref v 'rng-state) (hash-ref expected-rng 'state))
        (vfail "this runtime does not reproduce the saved game: RANDOM state words ~a, saved ~a"
               (hash-ref v 'rng-state) (hash-ref expected-rng 'state)))
      (unless (= (hash-ref v 'rng-draws) (hash-ref expected-rng 'draws))
        (vfail "this runtime does not reproduce the saved game: ~a RANDOM draws, saved ~a"
               (hash-ref v 'rng-draws) (hash-ref expected-rng 'draws)))
      (unless (= (hash-ref v 'moves) (hash-ref ver 'moves))
        (vfail "this runtime does not reproduce the saved game: MOVES ~a, saved ~a"
               (hash-ref v 'moves) (hash-ref ver 'moves)))
      (unless (and (equal? (hash-ref v 'state_sha256) (hash-ref ver 'state_sha256))
                   (equal? (hash-ref v 'state) (hash-ref ver 'state)))
        (define ours (hash-ref v 'state))
        (define saved (hash-ref ver 'state))
        (define keys (remove-duplicates (append (hash-keys ours) (hash-keys saved))))
        (vfail "this runtime does not reproduce the saved game: state differs in ~a"
               (string-join (for/list ([k (in-list (sort keys symbol<?))]
                                       #:unless (equal? (hash-ref ours k #f) (hash-ref saved k #f)))
                              (format "~a (~s, saved ~s)" k (hash-ref ours k #f) (hash-ref saved k #f)))
                            "; ")))
      (unless (and (= (hash-ref v 'transcript_bytes) (hash-ref ver 'transcript_bytes))
                   (equal? (hash-ref v 'transcript_sha256) (hash-ref ver 'transcript_sha256)))
        (vfail "this runtime does not reproduce the saved game: transcript ~a bytes ~a, saved ~a bytes ~a"
               (hash-ref v 'transcript_bytes) (hash-ref v 'transcript_sha256)
               (hash-ref ver 'transcript_bytes) (hash-ref ver 'transcript_sha256)))
      ;; The clock log must be exactly consumed; then it resumes on WALL.
      (with-handlers ([exn:fail:mdl-clock-replay?
                       (lambda (e) (restore-fail 'replay "~a" (exn-message e)))])
        (mdl-clock-finish-replay! (run-clock r) #:wall wall))
      ;; Verified: go live.
      (set-run-phase! r 'live)
      (set-run-live-output?! r #t)
      (go-live!)
      (call-host-callback r (lambda () (on-restored (run-session r))))
      ;; This entry is now a live prompt (a restored game can be saved again).
      ((observer r void) 'enter info)))
  (parameterize ([current-replay-entry verify-and-resume!])
    (with-handlers ([(lambda (e) (and (not (eq? (run-phase r) 'live)) (not (eq? (run-phase r) 'ended))
                                      (exn:fail? e) (not (exn:fail:replay-restore? e))))
                     (lambda (e)
                       (restore-fail (if (eq? (run-phase r) 'boot) 'boot 'replay)
                                     "the session failed during replay: ~a" (exn-message e)))])
      (define result
        (run-session! r #:root root #:input port #:output out
                      #:after-load
                      (lambda (files)
                        (unless (equal? files (hash-ref (hash-ref doc 'source) 'files))
                          (restore-fail 'provenance "the session loaded ~a, the checkpoint lists ~a"
                                        (map car files)
                                        (map car (hash-ref (hash-ref doc 'source) 'files))))
                        (set-run-phase! r 'replay))))
      (unless (run-live-output? r)
        (restore-fail 'replay "the session ended (~a) before reaching the save point after ~a of ~a input units"
                      (replay-result-kind result) (run-completed r) n))
      result)))
