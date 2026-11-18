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
(struct cursor (text [pos #:mutable] [line #:mutable] [column #:mutable] source) #:transparent)

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
  (define out (open-output-string))
  (let loop ()
    (define ch (peek c))
    (cond
      [(delimiter? ch) (get-output-string out)]
      [(and (char=? ch #\!) (equal? (peek-next c) #\]))
       (get-output-string out)]
      [(char=? ch #\\)
       (advance! c)
       (let ([escaped (advance! c)])
         (unless escaped (parse-error c "unterminated MDL escape"))
         ;; Retain both chars for now. MDL escape semantics are a later milestone.
         (write-char #\\ out)
         (write-char escaped out)
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

(define (read-delimited! c terminator)
  (let loop ([acc '()])
    (skip-ws! c)
    (let ([ch (peek c)])
      (cond
        [(not ch) (parse-error c (format "unclosed delimiter, expected ~a" terminator))]
        [(and (eq? terminator 'uvector) (char=? ch #\!)
              (equal? (peek-next c) #\]))
         (advance! c) (advance! c) (reverse acc)]
        [(and (eq? terminator 'uvector) (char=? ch #\]))
         (advance! c) (reverse acc)]
        [(and (char? terminator) (char=? ch terminator))
         (advance! c) (reverse acc)]
        [else (loop (cons (read-node! c) acc))]))))

(define (read-node! c)
  (skip-ws! c)
  (let* ([line (cursor-line c)]
         [column (cursor-column c)]
         [ch (peek c)])
    (define (node kind value) (mdl-node kind value line column))
    (unless ch (parse-error c "unexpected end of file"))
    (case ch
      [(#\<) (advance! c) (node 'form (read-delimited! c #\>))]
      [(#\() (advance! c) (node 'list (read-delimited! c #\))) ]
      [(#\[) (advance! c) (node 'vector (read-delimited! c #\]))]
      [(#\{) (advance! c) (node 'brace (read-delimited! c #\}))]
      [(#\") (node 'string (read-string! c))]
      [(#\') (advance! c) (node 'quote (read-node! c))]
      [(#\,)
       (advance! c)
       (let ([name (read-atom! c)])
         (node 'global (if (string=? name "") (read-node! c) name)))]
      [(#\.)
       (advance! c)
       (let ([name (read-atom! c)])
         (when (string=? name "") (parse-error c "empty local reference"))
         (node 'local name))]
      [(#\!)
       (advance! c)
       (if (equal? (peek c) #\[)
           (begin (advance! c) (node 'uvector (read-delimited! c 'uvector)))
           (node 'splice (read-node! c)))]
      [(#\%) (advance! c) (node 'percent (read-node! c))]
      [(#\#)
       (let ([name (read-atom! c)])
         (skip-ws! c)
         (cond
           [(equal? (peek c) #\{)
            (node 'typed (cons name (read-node! c)))]
           [(and (string-ci=? name "#FALSE") (equal? (peek c) #\())
            (node 'false (mdl-node-value (read-node! c)))]
           [(and (string-ci=? name "#WORD") (peek c)
                 (or (char-numeric? (peek c))
                     (memv (peek c) '(#\* #\- #\+))))
            (node 'typed (cons name (read-node! c)))]
           [else (node 'atom name)]))]
      [(#\> #\) #\] #\}) (parse-error c "unexpected closing delimiter")]
      [else
       (let ([raw (read-atom! c)])
         (when (string=? raw "") (parse-error c "invalid token"))
         (node 'atom raw))])))

(define (make-mdl-node-reader text #:source [source "<string>"])
  (define c (cursor text 0 1 1 source))
  (lambda ()
    (skip-ws! c)
    (and (peek c) (read-node! c))))

(define (parse-mdl text #:source [source "<string>"])
  (define next-node (make-mdl-node-reader text #:source source))
  (let loop ([acc '()])
    (define node (next-node))
    (if node (loop (cons node acc)) (reverse acc))))
