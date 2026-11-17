#lang racket/base
;; A source-located reader for a deliberately small but growing subset of MDL.
;; Does NOT claim to understand all of historical MDL syntax.
(require racket/port)
(provide parse-mdl mdl-node mdl-node? mdl-node-kind mdl-node-value
         mdl-node-line mdl-node-column)

(struct mdl-node (kind value line column) #:transparent)
(struct cursor (text [pos #:mutable] [line #:mutable] [column #:mutable] source) #:transparent)

(define (peek c)
  (and (< (cursor-pos c) (string-length (cursor-text c)))
       (string-ref (cursor-text c) (cursor-pos c))))

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
  (error 'mdl-reader "~a:~a:~a: ~a" (cursor-source c)
         (cursor-line c) (cursor-column c) message))

(define (skip-comment! c)
  (let loop ()
    (define ch (peek c))
    (when (and ch (not (char=? ch #\newline)))
      (advance! c)
      (loop))))

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
         (write-char
          (case escaped
            [(#\n) #\newline]
            [(#\t) #\tab]
            [else escaped])
          out)
         (loop))]
      [else (write-char ch out) (loop)])))

(define (read-delimited! c terminator)
  (let loop ([acc '()])
    (skip-ws! c)
    (let ([ch (peek c)])
      (cond
        [(not ch) (parse-error c (format "unclosed delimiter, expected ~a" terminator))]
        [(char=? ch terminator) (advance! c) (reverse acc)]
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
         (when (string=? name "") (parse-error c "empty global reference"))
         (node 'global name))]
      [(#\.)
       (advance! c)
       (let ([name (read-atom! c)])
         (when (string=? name "") (parse-error c "empty local reference"))
         (node 'local name))]
      [(#\!)
       (advance! c)
       (if (equal? (peek c) #\[)
           (begin (advance! c) (node 'uvector (read-delimited! c #\])))
           (node 'splice (read-node! c)))]
      [(#\%) (advance! c) (node 'percent (read-node! c))]
      [(#\#)
       (let ([name (read-atom! c)])
         (skip-ws! c)
         (if (equal? (peek c) #\{)
             (node 'typed (cons name (read-node! c)))
             (node 'atom name)))]
      [(#\> #\) #\] #\}) (parse-error c "unexpected closing delimiter")]
      [else
       (let ([raw (read-atom! c)])
         (when (string=? raw "") (parse-error c "invalid token"))
         (node 'atom raw))])))

(define (parse-mdl text #:source [source "<string>"])
  (define c (cursor text 0 1 1 source))
  (let loop ([acc '()])
    (skip-ws! c)
    (if (peek c)
        (loop (cons (read-node! c) acc))
        (reverse acc))))
