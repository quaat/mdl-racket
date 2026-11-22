#lang racket/base
;; A source-located reader for a deliberately small but growing subset of MDL.
;; Does NOT claim to understand all of historical MDL syntax.
(require racket/port)
(provide parse-mdl make-mdl-node-reader mdl-node mdl-node? mdl-node-kind mdl-node-value
         mdl-node-line mdl-node-column
         exn:fail:mdl-reader? exn:fail:mdl-reader-line
         exn:fail:mdl-reader-column)

(struct mdl-node (kind value line column) #:transparent)
(struct exn:fail:mdl-reader exn:fail (line column) #:transparent)
(struct cursor (text [pos #:mutable] [line #:mutable] [column #:mutable]
                     source read-eval) #:transparent)

(define (peek c)
  (and (< (cursor-pos c) (string-length (cursor-text c)))
       (string-ref (cursor-text c) (cursor-pos c))))

(define (peek-next c)
  (and (< (add1 (cursor-pos c)) (string-length (cursor-text c)))
       (string-ref (cursor-text c) (add1 (cursor-pos c)))))

(define (advance! c)
  (define ch (peek c))
  (when ch
    (set-cursor-pos! c (add1 (cursor-pos c)))
    (if (char=? ch #\newline)
        (begin (set-cursor-line! c (add1 (cursor-line c)))
               (set-cursor-column! c 1))
        (set-cursor-column! c (add1 (cursor-column c)))))
  ch)

(define (parse-error c message)
  (raise (exn:fail:mdl-reader
          (format "mdl-reader: ~a:~a:~a: ~a" (cursor-source c)
                  (cursor-line c) (cursor-column c) message)
          (current-continuation-marks)
          (cursor-line c) (cursor-column c))))

(define (skip-comment! c)
  (advance! c) ; semicolon
  (skip-ws! c)
  (unless (peek c) (parse-error c "comment without an MDL object"))
  (read-node! c))

(define (skip-ws! c)
  (let loop ()
    (define ch (peek c))
    (cond
      [(not ch) (void)]
      [(or (char-whitespace? ch) (char=? ch (integer->char 0)))
       (advance! c) (loop)]
      [(char=? ch #\;) (skip-comment! c) (loop)]
      [else (void)])))

(define (delimiter? ch)
  (or (not ch)
      (char-whitespace? ch)
      (char=? ch (integer->char 0))
      (memv ch '(#\< #\> #\( #\) #\[ #\] #\{ #\} #\" #\; #\, #\'))))

(define (read-atom! c)
  ;; Returns (values pname escaped?) where escaped? is #t if any backslash
  ;; was consumed.  The caller may use escaped? to tag the resulting node as
  ;; 'escaped-atom so the compiler knows to skip numeric / # classification.
  (define out (open-output-string))
  (define escaped? #f)
  (let loop ()
    (define ch (peek c))
    (cond
      [(delimiter? ch) (values (get-output-string out) escaped?)]
      [(and (char=? ch #\!) (equal? (peek-next c) #\]))
       (values (get-output-string out) escaped?)]
      ;; `!>` terminates a SEGMENT payload (chapter 7: the trailing `!` is
      ;; part of the close, not of the atom in front of it).
      [(and (char=? ch #\!) (equal? (peek-next c) #\>))
       (values (get-output-string out) escaped?)]
      [(char=? ch #\\)
       (advance! c)
       (let ([escaped-char (advance! c)])
         (unless escaped-char (parse-error c "unterminated MDL escape"))
         ;; MDL chapter 15: `\` quotes the next character, making it a
         ;; literal constituent of the PNAME (backslash is dropped).
         ;; Confusion probe confirms: `A\!B` → PNAME "A!B",
         ;; `A\\B` → PNAME "A\B", `\!A` → PNAME "!A".
         ;; The !- trailer split (mdl-atom) operates on the processed
         ;; (backslash-stripped) string, so `A\!-B` → pname "A", oblist B
         ;; and `DEAD\!!-WORDS` → pname "DEAD!", oblist WORDS — both
         ;; matching pinned Confusion (I119).
         (set! escaped? #t)
         (write-char escaped-char out)
         (loop))]
      [else (write-char (advance! c) out) (loop)])))

(define (read-string! c)
  (define out (open-output-string))
  (advance! c) ; opening double quote
  (let loop ()
    (define ch (advance! c))
    (cond
      [(not ch) (parse-error c "unterminated string literal")]
      [(char=? ch #\") (get-output-string out)]
      [(char=? ch #\\)
       (let ([escaped (advance! c)])
         (unless escaped (parse-error c "unterminated string escape"))
         (write-char escaped out)
         (loop))]
      [else (write-char ch out) (loop)])))

;; `segment-payload?` marks the FORM currently being read as a SEGMENT
;; payload: `!` immediately before its closing `>` terminates it (chapter
;; 7, the optional trailing `!` of `!<FORM...!>`), while a plain `>` also
;; closes it. Nested forms inside the payload are read normally, so only
;; the payload's own `>` positions accept the digraph.
(define (read-delimited! c terminator [segment-payload? #f])
  (let loop ([acc '()])
    (skip-ws! c)
    (let ([ch (peek c)])
      (cond
        [(not ch) (parse-error c (format "unclosed delimiter, expected ~a" terminator))]
        [(and (eq? terminator 'uvector) (char=? ch #\!)
              (equal? (peek-next c) #\]))
         (advance! c) (advance! c) (reverse acc)]
        [(and segment-payload? (char? terminator) (char=? terminator #\>)
              (char? ch) (char=? ch #\!)
              (equal? (peek-next c) #\>))
         (advance! c) (advance! c) (reverse acc)]
        [(and (eq? terminator 'uvector) (char=? ch #\]))
         (advance! c) (reverse acc)]
        [(and (char? terminator) (char=? ch terminator))
         (advance! c) (reverse acc)]
        [else (loop (cons (read-node! c) acc))]))))

;; `segment-payload?` is true while reading a SEGMENT payload node, so its
;; own FORM delimiters accept the `!>` close. Nested reads start fresh.
(define (read-node! c [segment-payload? #f])
  (skip-ws! c)
  (let* ([line (cursor-line c)]
         [column (cursor-column c)]
         [ch (peek c)])
    (define (node kind value) (mdl-node kind value line column))
    (unless ch (parse-error c "unexpected end of file"))
    (case ch
      [(#\<) (advance! c) (node 'form (read-delimited! c #\> segment-payload?))]
      [(#\() (advance! c) (node 'list (read-delimited! c #\))) ]
      [(#\[) (advance! c) (node 'vector (read-delimited! c #\]))]
      [(#\{) (advance! c) (node 'brace (read-delimited! c #\}))]
      [(#\") (node 'string (read-string! c))]
      [(#\') (advance! c) (node 'quote (read-node! c))]
      [(#\,)
       (advance! c)
       (if (equal? (peek c) #\.)
           ;; The comma applies GVAL to the following expression. In
           ;; `,.FOO`, that expression is the local value of FOO, not an
           ;; ATOM whose PNAME begins with a period (manual chapter 4).
           (node 'global (read-node! c))
           (let-values ([(name _esc) (read-atom! c)])
             (node 'global (if (string=? name "") (read-node! c) name))))]
      [(#\.)
       (advance! c)
       ;; Record the raw character after `.` before read-atom! strips
       ;; escapes: `.\.5` has PNAME ".5" but its second `.` is escaped.
       (define first-raw (peek c))
       (let-values ([(name esc?) (read-atom! c)])
         (when (string=? name "") (parse-error c "empty local reference"))
         ;; `..X`: a literal (unescaped) second `.` is not a delimiter, so
         ;; read-atom! includes it. Confusion evaluates `..5` as LVAL of FLOAT
         ;; 0.5 → type mismatch; we raise a strict reader error rather than
         ;; producing a reachable LVAL. `.\.5` is the LVAL of ATOM ".5".
         (when (equal? first-raw #\.)
           (parse-error c "..name: LVAL argument must be an ATOM, not a compound form"))
         ;; A token `.X` where X consists entirely of digits and an optional
         ;; exponent (`[0-9]+([Ee][+-]?[0-9]+)?`) is a leading-dot FLOAT literal,
         ;; NOT an LVAL: `.5` → FLOAT 0.5, `.05` → FLOAT 0.05, `.5E1` → FLOAT 5.0.
         ;; Any other suffix means LVAL: `.5A` → LVAL atom "5A", `.5.` → LVAL atom
         ;; "5.", `.5.5` → LVAL atom "5.5", `.1ST` → LVAL atom "1ST".
         ;; The `(\.[0-9]*)?` group is intentionally absent: an embedded decimal
         ;; inside the suffix (`.5.`, `.5.5`) is NOT a FLOAT — Confusion yields
         ;; UNBOUND-VARIABLE LVAL "5."/"5.5" for those.
         ;; (MDL manual ch.7; Confusion probe I124.)
         ;; An escaped token is never numeric (I119): `.\5` is LVAL of ATOM "5".
         (if (and (not esc?) (regexp-match? #px"^[0-9]+([Ee][+-]?[0-9]+)?$" name))
             (node 'atom (string-append "." name))
             (node 'local name)))]
      [(#\!)
       (advance! c)
       (cond
         [(equal? (peek c) #\\)
          (advance! c)
          (define character (advance! c))
          (unless character (parse-error c "unterminated CHARACTER notation"))
          (node 'character character)]
         [(equal? (peek c) #\[)
          (advance! c)
          (node 'uvector (read-delimited! c 'uvector))]
         [else (node 'splice (read-node! c #t))])]
      [(#\%)
       (advance! c)
       (when (and (cursor-read-eval c) (equal? (peek c) #\%))
         (parse-error c "unsupported %% reader macro"))
       (define percent-node (node 'percent (read-node! c)))
       (if (cursor-read-eval c)
           ((cursor-read-eval c) percent-node)
           percent-node)]
      [(#\#)
       (let-values ([(name _esc) (read-atom! c)])
         (skip-ws! c)
         (cond
           [(string-ci=? name "#DECL")
            ;; The pinned original source also contains a doubled
            ;; `#DECL #DECL ((...))` payload (77act1.mud:110). Confusion's
            ;; generic #type reader re-types the inner DECL value, a no-op,
            ;; so extra #DECL tokens collapse into one declaration.
            (let loop ()
              (define-values (next _esc) (read-atom! c))
              (skip-ws! c)
              (cond
                [(string-ci=? next "#DECL") (loop)]
                [(string=? next "") (void)]
                [else (parse-error c "#DECL requires a parenthesized payload")]))
            (unless (equal? (peek c) #\()
              (parse-error c "#DECL requires a parenthesized payload"))
            (node 'decl (mdl-node-value (read-node! c)))]
           [(equal? (peek c) #\{)
            (node 'typed (cons name (read-node! c)))]
           [(and (string-ci=? name "#FALSE") (equal? (peek c) #\())
            (node 'false (mdl-node-value (read-node! c)))]
           [(and (regexp-match? #px"^#[A-Za-z]" name) (peek c)
                 (or (char-numeric? (peek c))
                     (memv (peek c) '(#\* #\- #\+ #\"))))
            (node 'typed (cons name (read-node! c)))]
           [else (node 'atom name)]))]
      [(#\> #\) #\] #\}) (parse-error c "unexpected closing delimiter")]
      [else
       (let-values ([(raw escaped?) (read-atom! c)])
         (when (string=? raw "") (parse-error c "invalid token"))
         ;; Tag the node 'escaped-atom when any backslash was consumed so the
         ;; compiler skips numeric / # classification (I119).
         (node (if escaped? 'escaped-atom 'atom) raw))])))

(define (make-mdl-node-reader text #:source [source "<string>"]
                              #:read-eval [read-eval #f])
  (define c (cursor text 0 1 1 source read-eval))
  (lambda ()
    (skip-ws! c)
    (and (peek c) (read-node! c))))

(define (parse-mdl text #:source [source "<string>"])
  (define next-node (make-mdl-node-reader text #:source source))
  (let loop ([acc '()])
    (define node (next-node))
    (if node (loop (cons node acc)) (reverse acc))))
