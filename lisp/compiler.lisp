(%special '*package*)

;; props to http://norstrulde.org/ilge10/
(set! qq
      (lambda (x)
        (if (consp x)
            (if (eq 'qq-unquote (car x))
                (cadr x)
                (if (eq 'quasiquote (car x))
                    (qq (qq (cadr x)))
                    (if (consp (car x))
                        (if (eq 'qq-splice (caar x))
                            (list 'append (cadar x) (qq (cdr x)))
                            (list 'cons (qq (car x)) (qq (cdr x))))
                        (list 'cons (qq (car x)) (qq (cdr x))))))
            (list 'quote x))))

(defmacro quasiquote (thing)
  (qq thing))

;;;; let the show begin

(defmacro defun (name args . body)
  `(%set-function-name (set! ,name (lambda ,args ,@body)) ',name))

(defmacro when (pred . body)
  `(if ,pred (progn ,@body)))

(defmacro unless (pred . body)
  `(if ,pred nil (progn ,@body)))

(defun map (func lst)
  (when lst
    (cons (func (car lst)) (map func (cdr lst)))))

(defmacro labels (defs . body)
  `(let ,(map (lambda (x) (car x)) defs)
     ,@(map (lambda (x)
              `(set! ,(car x) (%set-function-name
                               (lambda ,(cadr x) ,@(cddr x))
                               ',(car x)))) defs)
     ,@body))

(defun foreach (lst func)
  (when lst
    (func (car lst))
    (foreach (cdr lst) func)))

(defmacro prog1 (exp . body)
  (let ((ret (gensym)))
    `(let ((,ret ,exp))
       ,@body
       ,ret)))

(defmacro prog2 (exp1 exp2 . body)
  `(progn
     ,exp1
     (prog1 ,exp2 ,@body)))

(defmacro flet (defs . body)
  `(let ,(map (lambda (x)
                `(,(car x) (%set-function-name
                            (lambda ,(cadr x) ,@(cddr x))
                            ',(car x)))) defs)
     ,@body))

(defmacro or exps
  (when exps
    (let ((x (gensym "OR")))
      `(let ((,x ,(car exps)))
         (if ,x ,x (or ,@(cdr exps)))))))

(defmacro and exprs
  (if exprs
      (let ((x (gensym "AND")))
        `(let ((,x ,(car exprs)))
           (when ,x
             ,(if (cdr exprs) `(and ,@(cdr exprs)) x))))
      t))

(defmacro cond cases
  (if cases
      `(if ,(caar cases)
           (progn ,@(cdar cases))
           (cond ,@(cdr cases)))))

(defmacro member (item lst)
  `(%memq ,item ,lst))

(defmacro case (expr . cases)
  (let ((vexpr (gensym "CASE")))
    `(let ((,vexpr ,expr))
       ,(labels ((recur (cases)
                        (when cases
                          (if (listp (caar cases))
                              `(if (member ,vexpr ',(caar cases))
                                   (progn ,@(cdar cases))
                                   ,(recur (cdr cases)))
                              (if (and (not (cdr cases))
                                       (member (caar cases) '(otherwise t)))
                                  `(progn ,@(cdar cases))
                                  `(if (eq ,vexpr ',(caar cases))
                                       (progn ,@(cdar cases))
                                       ,(recur (cdr cases))))))))
                (recur cases)))))

(defmacro mapcar (func . lists)
  (let ((rec (gensym))
        (fname (gensym))
        (args (map (lambda (el) (gensym)) lists)))
    `(let ((,fname ,func))
       (labels ((,rec (,@args)
                  (when (and ,@args)
                    (cons (,fname ,@(map (lambda (l)
                                           `(car ,l)) args))
                          (,rec ,@(map (lambda (l)
                                         `(cdr ,l)) args))))))
         (,rec ,@lists)))))

(defmacro call/cc (func)
  `(,func (c/c)))

(defmacro with-cc (name . body)
  `((lambda (,name) ,@body) (c/c)))

(defmacro awhen (cond . body)
  `(let ((it ,cond))
     (when it ,@body)))

(defmacro aif (cond . rest)
  `(let ((it ,cond))
     (if it ,@rest)))

(defmacro %incf (var)
  `(set! ,var (+ ,var 1)))

(defmacro %decf (var)
  `(set! ,var (- ,var 1)))


(defmacro push (obj place)
  `(set! ,place (cons ,obj ,place)))

(defmacro pushnew (obj place)
  (let ((sym (gensym)))
    `(let ((,sym ,obj))
       (unless (member ,sym ,place)
         (push ,sym ,place)))))

(defmacro error (msg)
  `(%error ,msg))

(defun macroexpand (form)
  (if (and (consp form)
           (symbolp (car form))
           (%macrop (car form)))
      (macroexpand (macroexpand-1 form))
      form))

(defun macroexpand-all (form)
  (if (consp form)
      (let ((form (macroexpand form)))
        (map macroexpand-all form))
      form))

;; this is `once-only' from Practical Common Lisp
(defmacro with-rebinds (names . body)
  (let ((gensyms (mapcar (lambda (_) (gensym)) names)))
    `(let (,@(mapcar (lambda (g) `(,g (gensym))) gensyms))
       `(let (,,@(mapcar (lambda (g n) ``(,,g ,,n)) gensyms names))
          ,(let (,@(mapcar (lambda (n g) `(,n ,g)) names gensyms))
                ,@body)))))

;;; amb

(set! *amb-fail* (lambda (arg)
                   (clog "TOTAL FAILURE")))

(defmacro amb alternatives
  (if alternatives
      `(let ((+prev-amb-fail *amb-fail*))
         (with-cc +sk
           ,@(map (lambda (alt)
                    `(with-cc +fk
                       (set! *amb-fail* +fk)
                       (+sk ,alt)))
                  alternatives)
           (set! *amb-fail* +prev-amb-fail)
           (+prev-amb-fail nil)))
      `(*amb-fail* nil)))

(defmacro while (cond . body)
  (let ((rec (gensym "while")))
    `(let (,rec)
       ((set! ,rec (lambda ()
                     (when ,cond
                       ,@body
                       (,rec))))))))

;;;; destructuring-bind

(defmacro %next (lst)
  `(prog1 (car ,lst)
     (set! ,lst (cdr ,lst))))

(defun %fn-destruct (args values body)
  (let (optional? rest? key? aux? names decls)
    (let ((topv (gensym)) rec)
      ((set! rec
             (lambda (args values i)
               (when args
                 (let ((thisarg (car args)))
                   (cond
                     ((symbolp thisarg)
                      (case thisarg
                        (&whole
                         (when (> i 0) (error "Misplaced &WHOLE"))
                         (let ((thisarg (cadr args)))
                           (unless (and thisarg (symbolp thisarg))
                             (error "Missing variable name for &WHOLE"))
                           (push `(,thisarg ,values) decls))
                         (rec (cddr args) values i))

                        (&optional
                         (when (or optional? rest? key? aux?)
                           (error "Invalid &OPTIONAL"))
                         (set! optional? t)
                         (rec (cdr args) values i))

                        ((&rest &body)
                         (when (or rest? key? aux?)
                           (error "Invalid &REST/&BODY"))
                         (set! rest? t)
                         (set! optional? nil)
                         (let ((thisarg (cadr args)))
                           (unless (and thisarg (symbolp thisarg))
                             (error "Missing variable name for &REST"))
                           (push `(,thisarg ,values) decls))
                         (rec (cddr args) values i))

                        (&key
                         (when (or key? aux?)
                           (error "Invalid &KEY"))
                         (set! key? t)
                         (set! optional? nil)
                         (set! rest? nil)
                         (rec (cdr args) values i))

                        (&aux
                         (when aux?
                           (error "Invalid &AUX"))
                         (set! aux? t)
                         (set! optional? nil)
                         (set! rest? nil)
                         (set! key? nil)
                         (rec (cdr args) values i))

                        (t
                         (when (member thisarg names)
                           (error (strcat "Argument seen twice: " thisarg)))
                         (push thisarg names)
                         (cond
                           (optional?
                            (push `(,thisarg (%next ,values)) decls))
                           (aux?
                            (push thisarg decls))
                           (key?
                            (push `(,thisarg (%getf ,values ,(%intern (%symbol-name thisarg) (%find-package "KEYWORD")))) decls))
                           (t
                            (push `(,thisarg (if ,values
                                                 (%next ,values)
                                                 (error ,(strcat "Missing required argument: " thisarg))))
                                  decls)))
                         (rec (cdr args) values (+ i 1)))))

                     ((consp thisarg)
                      (cond
                        ((or optional? key?)
                         (let ((thisarg (car thisarg))
                               (default (cadr thisarg))
                               (thisarg-p (caddr thisarg)))
                           (when thisarg-p
                             (push `(,thisarg-p (if ,values t nil)) decls))
                           (push `(,thisarg ,(if key?
                                                 (let ((val (gensym)))
                                                   `(let ((,val (%getf ,values ,(%intern (%symbol-name thisarg) (%find-package "KEYWORD")) 'not-found)))
                                                      (if (eq ,val 'not-found) ,default ,val)))
                                                 `(if ,values (%next ,values) ,default)))
                                 decls)))
                        (aux? (let ((thisarg (car thisarg))
                                    (value (cadr thisarg)))
                                (push `(,thisarg ,value) decls)))
                        (rest? (error "Invalid argument list following &REST/&BODY"))
                        (t
                         (let ((sublist (gensym)))
                           (push `(,sublist (if ,values (%next ,values) (error "Missing sublist"))) decls)
                           (rec thisarg sublist 0))))
                      (rec (cdr args) values (+ i 1))))))))
       args topv 0)
      `(let* ((,topv ,values) ,@(reverse decls))
         ,@body))))

(defmacro destructuring-bind (args values . body)
  (%fn-destruct args values body))

;;;; parser/compiler

(defun lisp-reader (text eof)
  (let ((input (%make-input-stream text))
        (in-qq 0))
    (labels
        ((peek ()
           (%stream-peek input))

         (next ()
           (%stream-next input))

         (read-while (pred)
           (let ((out (%make-output-stream))
                 (ch))
             (while (and (set! ch (peek))
                         (pred ch))
               (%stream-put out (next)))
             (%stream-get out)))

         (croak (msg)
           (error (strcat msg ", line: " (%stream-line input) ", col: " (%stream-col input))))

         (skip-ws ()
           (read-while (lambda (ch)
                         (member ch '(#\Space
                                      #\Newline
                                      #\Tab
                                      #\Page
                                      #\Line_Separator
                                      #\Paragraph_Separator)))))

         (skip (expected)
           (unless (eq (next) expected)
             (croak (strcat "Expecting " expected))))

         (read-escaped (start end inces)
           (skip start)
           (let ((out (%make-output-stream)))
             (labels ((rec (ch escaped)
                        (cond
                          ((not ch)
                           (croak "Unterminated string or regexp"))
                          ((eq ch end)
                           (%stream-get out))
                          (escaped
                           (%stream-put out ch)
                           (rec (next) nil))
                          ((eq ch #\\)
                           (if inces (%stream-put out #\\))
                           (rec (next) t))
                          (t (%stream-put out ch)
                             (rec (next) nil)))))
               (rec (next) nil))))

         (read-string ()
           (read-escaped #\" #\" nil))

         (read-regexp ()
           (let ((str (read-escaped #\/ #\/ t))
                 (mods (downcase (read-while (lambda (ch)
                                               (member ch '(#\g #\m #\i #\y)))))))
             (make-regexp str mods)))

         (skip-comment ()
           (read-while (lambda (ch)
                         (not (eq ch #\Newline)))))

         (read-symbol ()
           (let ((str (read-while
                       (lambda (ch)
                         (or
                          (char<= #\a ch #\z)
                          (char<= #\A ch #\Z)
                          (char<= #\0 ch #\9)
                          (member ch
                                  '(#\% #\$ #\_ #\- #\: #\. #\+ #\*
                                    #\@ #\! #\? #\& #\= #\< #\>
                                    #\[ #\] #\{ #\} #\/ #\^ #\# )))))))
             (set! str (upcase str))
             (if (regexp-test #/^[0-9]*\.?[0-9]*$/ str)
                 (parse-number str)
                 (aif (regexp-exec #/^(.*?)::?(.*)$/ str)
                      (let ((pak (elt it 1))
                            (sym (elt it 2)))
                        (set! pak (%find-package (if (zerop (length pak))
                                                     "KEYWORD"
                                                     pak)))
                        (%intern sym pak))
                      (%intern str *package*)))))

         (read-char ()
           (let ((name (strcat (next)
                               (read-while (lambda (ch)
                                             (or (char<= #\a ch #\z)
                                                 (char<= #\A ch #\Z)
                                                 (char<= #\0 ch #\9)
                                                 (eq ch #\-)
                                                 (eq ch #\_)))))))
             (if (regexp-test #/^U[0-9a-f]{4}$/i name)
                 (code-char (parse-integer (substr name 1) 16))
                 (name-char name))))

         (read-sharp ()
           (skip #\#)
           (case (peek)
             (#\\ (next) (read-char))
             (#\/ (read-regexp))
             (#\( `(vector ,(read-list)))
             (otherwise (croak (strcat "Unsupported sharp syntax #" (peek))))))

         (read-quote ()
           (skip #\')
           `(quote ,(read-token)))

         (read-quasiquote ()
           (skip #\`)
           (skip-ws)
           (if (member (peek) '(#\( #\`))
               (prog2
                   (%incf in-qq)
                   (list 'quasiquote (read-token))
                 (%decf in-qq))
               `(quote ,(read-token))))

         (read-comma ()
           (when (zerop in-qq) (croak "Comma outside quasiquote"))
           (skip #\,)
           (skip-ws)
           (prog2
               (%decf in-qq)
               (if (eq (peek) #\@)
                   (progn (next)
                          (list 'qq-splice (read-token)))
                   (list 'qq-unquote (read-token)))
             (%incf in-qq)))

         (read-list ()
           (let ((ret nil)
                 (p nil))
             (labels ((rec ()
                        (skip-ws)
                        (case (peek)
                          (#\) ret)
                          (#\; (skip-comment) (rec))
                          (#\. (next)
                               (rplacd p (read-token))
                               (skip-ws)
                               ret)
                          (nil (croak "Unterminated list"))
                          (otherwise (let ((cell (cons (read-token) nil)))
                                       (set! p (if ret
                                                   (rplacd p cell)
                                                   (set! ret cell))))
                                     (rec)))))
               (prog2
                   (skip #\()
                   (rec)
                 (skip #\))))))

         (read-token ()
           (skip-ws)
           (case (peek)
             (#\; (skip-comment) (read-token))
             (#\" (read-string))
             (#\( (read-list))
             (#\# (read-sharp))
             (#\` (read-quasiquote))
             (#\, (read-comma))
             (#\' (read-quote))
             (nil eof)
             (otherwise (read-symbol)))))

      read-token)))

(labels
    ((assert (p msg)
       (unless p (%error msg)))

     (arg-count (x min max)
       (assert (<= min (- (length x) 1) max) "Wrong number of arguments"))

     (gen cmd
       #( (as-vector cmd) ))

     (find-var (name env)
       (with-cc return
         (labels ((position (lst i j)
                    (when lst
                      (if (eq name (car lst)) (return (cons i j))
                          (position (cdr lst) i (+ j 1)))))
                  (frame (env i)
                    (when env
                      (position (car env) i 0)
                      (frame (cdr env) (+ i 1)))))
           (frame env 0))))

     (gen-var (name env)
       (if (%specialp name)
           (gen "GVAR" name)
           (aif (find-var name env)
                (gen "LVAR" (car it) (cdr it))
                (gen "GVAR" name))))

     (gen-set (name env)
       (if (%specialp name)
           (gen "GSET" name)
           (aif (find-var name env)
                (gen "LSET" (car it) (cdr it))
                (gen "GSET" name))))

     (mklabel ()
       (gensym "label"))

     (comp (x env val? more?)
       (cond
         ((symbolp x) (cond
                        ((eq x nil) (comp-const nil val? more?))
                        ((eq x t) (comp-const t val? more?))
                        ((keywordp x) (comp-const x val? more?))
                        (t (comp-var x env val? more?))))
         ((atom x) (comp-const x val? more?))
         (t (case (car x)
              (quote (arg-count x 1 1)
                     (comp-const (cadr x) val? more?))
              (progn (comp-seq (cdr x) env val? more?))
              (set! (arg-count x 2 2)
                    (assert (symbolp (cadr x)) "Only symbols can be SET!")
                    (%seq (comp (caddr x) env t t)
                          (gen-set (cadr x) env)
                          (unless val? (gen "POP"))
                          (unless more? (gen "RET"))))
              (if (arg-count x 2 3)
                  (comp-if (cadr x) (caddr x) (cadddr x) env val? more?))
              (not (arg-count x 1 1)
                   (if val?
                       (%seq (comp (cadr x) env t t)
                             (gen "NOT")
                             (if more? nil (gen "RET")))
                       (comp (cadr x) env val? more?)))
              (c/c (arg-count x 0 0)
                   (if val? (%seq (gen "CC"))))
              (defmacro
                  (assert (symbolp (cadr x)) "DEFMACRO requires a symbol name")
                  (comp-defmac (cadr x) (caddr x) (cdddr x) env val? more?))
              (let (comp-let (cadr x) (cddr x) env val? more?))
              (let* (comp-let* (cadr x) (cddr x) env val? more?))
              (lambda (if val?
                          (%seq (comp-lambda (cadr x) (cddr x) env)
                                (if more? nil (gen "RET")))))
              (t (if (and (symbolp (car x))
                          (%macrop (car x)))
                     (comp-macroexpand (car x) (cdr x) env val? more?)
                     (comp-funcall (car x) (cdr x) env val? more?)))))))

     (comp-const (x val? more?)
       (if val? (%seq (gen "CONST" x)
                      (if more? nil (gen "RET")))))

     (comp-var (x env val? more?)
       (if val? (%seq (gen-var x env)
                      (if more? nil (gen "RET")))))

     (comp-seq (exps env val? more?)
       (cond
         ((not exps) (comp-const nil val? more?))
         ((not (cdr exps)) (comp (car exps) env val? more?))
         (t (%seq (comp (car exps) env nil t)
                  (comp-seq (cdr exps) env val? more?)))))

     (comp-list (exps env)
       (when exps
         (%seq (comp (car exps) env t t)
               (comp-list (cdr exps) env))))

     (comp-if (pred then else env val? more?)
       (let ((l1 (mklabel))
             (l2 (mklabel)))
         (%seq (comp pred env t t)
               (gen "FJUMP" l1)
               (comp then env val? more?)
               (if more? (gen "JUMP" l2))
               #( l1 )
               (comp else env val? more?)
               (if more? #( l2 )))))

     (comp-funcall (f args env val? more?)
       (cond
         ((and (symbolp f)
               (%primitivep f)
               (not (find-var f env)))
          (%seq (comp-list args env)
                (gen "PRIM" f (length args))
                (if more? nil (gen "RET"))))

         ((and (consp f)
               (eq (car f) 'lambda)
               (not (cadr f)))
          (assert (not args) "Too many arguments")
          (comp-seq (cddr f) env val? more?))

         (more? (let ((k (mklabel)))
                  (%seq (gen "SAVE" k)
                        (comp-list args env)
                        (comp f env t t)
                        (gen "CALL" (length args))
                        #( k )
                        (if val? nil (gen "POP")))))

         (t (%seq (comp-list args env)
                  (comp f env t t)
                  (gen "CALL" (length args))))))

     (gen-args (args n)
       (cond
         ((not args) (gen "ARGS" n))
         ((symbolp args) (gen "ARG_" n))
         ((and (consp args) (symbolp (car args)))
          (gen-args (cdr args) (+ n 1)))
         (t (error "Illegal argument list"))))

     (make-true-list (l)
       (when l
         (if (atom l)
             (list l)
             (cons (car l) (make-true-list (cdr l))))))

     (comp-lambda (args body env)
       (gen "FN"
            (%seq (gen-args args 0)
                  (let (dyn (i 0) (args (make-true-list args)))
                    (foreach args (lambda (x)
                                    (when (%specialp x)
                                      (push #("BIND" x i) dyn))
                                    (%incf i)))
                    (%seq dyn
                          (comp-seq body (cons args env) t nil))))))

     (get-bindings (bindings)
       (let (names vals specials (i 0))
         (foreach bindings (lambda (x)
                             (if (consp x)
                                 (progn (push (cadr x) vals)
                                        (set! x (car x)))
                                 (push nil vals))
                             (when (member x names)
                               (error "Duplicate name in LET"))
                             (push x names)
                             (when (%specialp x) (push (cons x i) specials))
                             (%incf i)))
         (list (reverse names) (reverse vals) (reverse specials) i)))

     (comp-let (bindings body env val? more?)
       (if bindings
           (destructuring-bind (names vals specials len) (get-bindings bindings)
             (%seq (%prim-apply '%seq (map (lambda (x)
                                             (comp x env t t))
                                           vals))
                   (gen "ARGS" len)
                   (%prim-apply '%seq (map (lambda (x)
                                             (gen "BIND" (car x) (cdr x)))
                                           specials))
                   (comp-seq body (cons names env) val? t)
                   (gen "UNFR" 1 (length specials))
                   (if more? nil (gen "RET"))))
           (comp-seq body env val? more?)))

     (comp-let* (bindings body env val? more?)
       (if bindings
           (destructuring-bind (names vals specials len &aux newargs (i 0))
               (get-bindings bindings)
             (%seq (%prim-apply
                    '%seq (mapcar (lambda (name x)
                                    (prog1
                                        (%seq (comp x env t t)
                                              (gen (if newargs "FRV2" "FRV1"))
                                              (when (%specialp name)
                                                (gen "BIND" name i)))
                                      (%incf i)
                                      (let ((cell (cons name nil)))
                                        (if newargs
                                            (rplacd newargs cell)
                                            (set! env (cons cell env)))
                                        (set! newargs cell))))
                                  names vals))
                   (comp-seq body env val? true)
                   (gen "UNFR" 1 (length specials))
                   (if more? nil (gen "RET"))))
           (comp-seq body env val? more?))))

  (defun compile args
    (destructuring-bind (exp &key environment) args
      (assert (and (consp exp)
                   (eq (car exp) 'lambda))
              "Expecting (LAMBDA (...) ...) in COMPILE")
      (%assemble-closure (comp exp environment t nil)))))

;;;;;;

(let ((reader (lisp-reader
               (%js-eval "window.CURRENT_FILE")
               ;;"(a b . c)"
               ;;"#\\Newline mak"
               'EOF)))
  (labels ((rec (q)
             (let ((tok (reader)))
               (if (eq tok 'EOF)
                   q
                   (rec (cons tok q))))))
    (reverse (rec nil))))

(let ((f (compile '(lambda (a b)
                     (let* ((a (* a a))
                            (b (* b b))
                            (c (+ a b)))
                       (list a b c))))))
  (clog (%disassemble f))
  (f 3 4))
