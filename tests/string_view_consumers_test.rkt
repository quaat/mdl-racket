#lang racket/base
;; Shared STRING views as arguments to STRING consumers (review finding R7).
;;
;; `<REST "XABC" 1>' is a STRING that shares storage with its parent. Every
;; primitive that accepts a STRING must accept such a view; atom names are
;; created as immutable PNAME copies (later PUTs to the user's STRING never
;; change a PNAME or corrupt OBLIST lookup), while the user's STRING and its
;; views keep aliasing each other. Non-STRING arguments still fail.
;; Reference: docs/evidence/M3/review/r7-string-view-reference.json.
(require rackunit racket/port racket/file "../mdl/parser.rkt" "../mdl/compiler.rkt"
         "../mdl/loader.rkt" "../mdl/runtime/core.rkt")
(define-namespace-anchor anchor)
(define ns (namespace-anchor->namespace anchor))
(define (run source)
  (parameterize ([current-namespace ns]
                 [current-mdl-globals (make-hasheq)]
                 [current-mdl-locals (list (make-hasheq))]
                 [current-mdl-atom-space (make-mdl-atom-space)])
    (for/fold ([value #f]) ([expr (in-list (compile-program (parse-mdl source)))])
      (eval expr))))
(define (t? value) (and (mdl-atom? value) (string=? (mdl-atom-pname value) "T")))

;; --- LOOKUP / INSERT / REMOVE / ATOM ---------------------------------------
(test-case "LOOKUP accepts a REST view"
  (check-true (t? (run "<SETG A1 <INSERT \"RSEVABC\" <ROOT>>>
                        <==? <LOOKUP <REST \"XRSEVABC\" 1> <ROOT>> ,A1>")))
  (check-true (mdl-false? (run "<LOOKUP <REST \"XRSEVNOPE\" 1> <ROOT>>"))))

(test-case "INSERT accepts a REST view and copies the PNAME"
  (check-equal? (run "<SETG S <STRING \"XRSEVQRS\">>
                      <SPNAME <INSERT <REST ,S 1> <ROOT>>>")
                "RSEVQRS")
  ;; Mutating the parent after INSERT: the view still aliases the parent,
  ;; but the PNAME and the OBLIST entry are unaffected.
  (define parent-result
    (run "<SETG S <STRING \"XRSEVQRT\">> <SETG V <REST ,S 1>>
          <SETG A2 <INSERT ,V <ROOT>>> <PUT ,S 2 !\\Z>
          [<STRING ,S> <STRING ,V> <SPNAME ,A2> <==? <LOOKUP \"RSEVQRT\" <ROOT>> ,A2>
           <LOOKUP \"ZSEVQRT\" <ROOT>>]"))
  (check-equal? (mdl-nth parent-result 1) "XZSEVQRT")
  (check-equal? (mdl-nth parent-result 2) "ZSEVQRT")
  (check-equal? (mdl-nth parent-result 3) "RSEVQRT")
  (check-true (t? (mdl-nth parent-result 4)))
  (check-true (mdl-false? (mdl-nth parent-result 5)))
  ;; Mutating through the view reaches the parent but not the PNAME.
  (define view-result
    (run "<SETG S <STRING \"XRSEVQRU\">> <SETG V <REST ,S 1>>
          <SETG A2 <INSERT ,V <ROOT>>> <PUT ,V 1 !\\Y> [<STRING ,S> <SPNAME ,A2>]"))
  (check-equal? (mdl-nth view-result 1) "XYSEVQRU")
  (check-equal? (mdl-nth view-result 2) "RSEVQRU"))

(test-case "INSERT of a native mutable STRING also copies the PNAME"
  (define result
    (run "<SETG S <STRING \"RSEVDEF\">> <SETG A3 <INSERT ,S <ROOT>>>
          <PUT ,S 1 !\\Z> [<SPNAME ,A3> <==? <LOOKUP \"RSEVDEF\" <ROOT>> ,A3>]"))
  (check-equal? (mdl-nth result 1) "RSEVDEF")
  (check-true (t? (mdl-nth result 2))))

(test-case "ATOM accepts a REST view and copies the PNAME"
  (define result
    (run "<SETG S <STRING \"XRSEVGHI\">> <SETG A4 <ATOM <REST ,S 1>>>
          <SETG P1 <SPNAME ,A4>> <PUT ,S 2 !\\Z> [,P1 <OBLIST? ,A4> <SPNAME ,A4>]"))
  (check-equal? (mdl-nth result 1) "RSEVGHI")
  (check-true (mdl-false? (mdl-nth result 2)))
  (check-equal? (mdl-nth result 3) "RSEVGHI"))

(test-case "ATOM of a native mutable STRING copies the PNAME"
  (check-equal? (run "<SETG S <STRING \"RSEVMNO\">> <SETG A <ATOM ,S>>
                      <PUT ,S 1 !\\Z> <SPNAME ,A>")
                "RSEVMNO"))

(test-case "REMOVE with a REST view name"
  (define result
    (run "<SETG A5 <INSERT \"RSEVJKL\" <ROOT>>>
          [<==? <REMOVE <REST \"XRSEVJKL\" 1> <ROOT>> ,A5>
           <LOOKUP \"RSEVJKL\" <ROOT>>]"))
  (check-true (t? (mdl-nth result 1)))
  (check-true (mdl-false? (mdl-nth result 2))))

;; --- EVENT ------------------------------------------------------------------
(test-case "EVENT accepts a REST view name and names the same IHEADER"
  (check-true (t? (run "<SETG E <EVENT <REST \"XRSEVEVT\" 1> 3>>
                        <==? ,E <EVENT \"RSEVEVT\" 4>>")))
  ;; Mutating the user's STRING afterwards does not rename the event.
  (check-true (t? (run "<SETG S <STRING \"RSEVEVU\">> <SETG E <EVENT ,S 3>>
                        <PUT ,S 1 !\\Z> <==? ,E <EVENT \"RSEVEVU\" 4>>"))))

;; --- STRING, PRINTSTRING, comparisons ----------------------------------------
(test-case "STRING, =? and ==? read the visible range of views"
  (check-equal? (run "<STRING <REST \"XABC\" 1> !\\D <REST \"YEF\" 1>>") "ABCDEF")
  (check-true (t? (run "<=? <REST \"XABC\" 1> \"ABC\">")))
  (check-true (t? (run "<SETG S \"XABC\"> <==? <REST ,S 1> <REST ,S 1>>")))
  (check-true (mdl-false? (run "<SETG S \"XABC\"> <==? <REST ,S 1> \"ABC\">"))))

;; --- FLOAD ------------------------------------------------------------------
(test-case "FLOAD and PRINTSTRING accept REST views in a loader session"
  (define root (make-temporary-file "mdl-r7-fload~a" 'directory))
  (dynamic-wind
   void
   (lambda ()
     (with-output-to-file (build-path root "child.mud")
       (lambda () (display "<SETG CHILD-LOADED 42>\n")))
     (with-output-to-file (build-path root "outer.mud")
       (lambda ()
         (display "<FLOAD <REST \"Xchild.mud\" 1>>\n<SETG OUTER-SAW ,CHILD-LOADED>\n")
         (display "<SETG PS <PRINTSTRING <REST \"X<r7>\" 1>>>\n")))
     ;; S13 part B (ADR-0050): an explicit session output port.
     (define output (open-output-string))
     (define session (make-mdl-session root #:output-port output))
     (define report (mdl-session-load! session "outer.mud"))
     (check-equal? (hash-ref report 'status #f) "PASS" (format "~s" report))
     (check-equal? (mdl-session-global session "OUTER-SAW") 42)
     ;; PRINTSTRING writes only the view's visible characters.
     (check-equal? (mdl-session-global session "PS") 4)
     (check-regexp-match #rx"(^|[^X])<r7>" (get-output-string output)))
   (lambda () (delete-directory/files root))))

;; --- strict rejection -------------------------------------------------------
(test-case "STRING consumers reject non-STRING arguments"
  (for ([src (list "<LOOKUP 3 <ROOT>>" "<LOOKUP !\\A <ROOT>>"
                   "<INSERT !\\A <ROOT>>" "<INSERT 3 <ROOT>>"
                   "<ATOM 3>" "<ATOM !\\A>" "<ATOM [1]>"
                   "<EVENT 3 1>" "<EVENT !\\A 1>"
                   "<SPNAME <REST \"XABC\" 1>>" "<PNAME <REST \"XABC\" 1>>")])
    (check-exn exn:fail? (lambda () (run src)) src)))
