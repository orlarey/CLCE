;;\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/
;;/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\/\
;;
;;
;;                                  Chg-Score.lisp
;;
;;                                     � 1991, GRAME.
;;
;;
;;
;;                           TRANSFORMATION DE SEQUENCES MIDI
;;                  ------------------------------------------------
;;
;;  History :
;;  
;; MB 16-Sep : Ch-seq21.lisp
;;  10/01/92 : pgm remplace le mot-cle progc
;;  07-06-03 : nettoyage pour insertion dans CVS : enlev� require, in-package, export
;;             �limin� une ancienne d�finition de gen-name
;;  21-10-09 : 'type' renome en 'evtype'


(defvar internal-debug)
(setq internal-debug nil)

;; Liste des mots-cl�s (de l'utilisateur) et des types MidiShare associ�s
;; Tous les �v�nements MidiShare ont un port et un chan, ce qui explique que ceux-ci
;; soient dans les variables g�n�rales
;; ATTENTION : l'ordre de la liste est important (utilis� par sortmin()
; ---------------------------------------------------------------------------------
(defun init-keywords ()
  (let ((loto '(field2 field1 field0 fields)))
      
    (push 'date loto)
    (push 'ref  loto)
    (push 'evtype loto)
    (push 'chan loto)
    (push 'port loto)
    
    (setf (get 'types 'sex) (list typeSongPos typeSongSel typeClock
                             typeStart typeContinue typeStop typeTune
                             typeActiveSens typeReset typeSysEx))
    (push 'sex loto)
    
    (setf (get 'types 'sysex) (list typeSysEx))
    (push 'sysex loto)
    
    (setf (get 'types 'common) (list typeTune typeActiveSens typeReset))
    (push 'commonp loto)
    
    (setf (get 'types 'rtime) (list typeSongPos typeSongSel typeClock
                               typeStart typeContinue typeStop))
    (push 'rtime loto)
    
    (setf (get 'types 'chpress) (list typeChanPress))
    (push 'chpress loto)
    
    (setf (get 'types 'pgm) (list typeProgChange))
    (push 'pgm loto)
    
    (setf (get 'types 'ctrlc) (list typeCtrlChange))
    (push 'ctrlc loto)
    
    (setf (get 'types 'vol) (list typeCtrlChange))
    (push 'vol loto)
    
    (setf (get 'types 'bend) (list typePitchWheel))
    (push 'bend loto)
    
    (setf (get 'types 'pitch) (list typeNote typeKeyOn typeKeyOff typeKeyPress))
    (push 'pitch loto)
    
    (setf (get 'types 'vel) (list typeNote typeKeyOn typeKeyOff))
    (push 'vel loto)
    
    (setf (get 'types 'keyoff) (list typeKeyOff))
    (push 'keyoff loto)
    
    (setf (get 'types 'keyon) (list typeKeyOn))
    (push 'keyon loto)
    
    (setf (get 'types 'kpress) (list typeKeyPress))
    (push 'kpress loto)
    
    (setf (get 'types 'dur) (list typeNote))
    (push 'dur loto)
loto))

(defvar loto (init-keywords))
; (dolist (e loto)  (princ e) (princ "  ") (princ (get 'types e)) (terpri))
; (setq loto (init-keywords))

;; Analyse de liste : cr�e la liste 'lres' avec tous les �l�ments de la liste 'la' 
;; qui sont pr�sents dans la liste de r�f�rence 'lito'
;; --------------------------------------------------------------------------------
(defun analist (la lito lres)
   (cond
       ((null la)  lres)
       ((atom la)  (if (and (member la lito) (not (member la lres)))
                      (cons la lres)
                      lres))
       (t          (analist (cdr la) lito (analist (car la) lito lres))
)))


;; varmin() renvoie la variable 'mini' dans la hi�rarchie msh ou True
;;
;;        date evtype ref chan port field1 field2 fields
;;       +--------------------------------------------+
;;     pitch     chaft    ctrlc    pgm    pbend          sex
;;  +---------+                                    +------------------+
;;   vel  kaft                                      sysex common rtime
;;   dur
;;
;; lorsque pitch et vel sont dans la m�me liste d'une action, on �limine le 1er
;; de la liste qui correspond � l'affectation, car varmin sert pour l'extraction
;; --------------------------------------------------------------------------------
(defun varmin (la)
    (let ((vmin t) (lev 0) (newla nil))
      (if (and (member 'pitch la) (member 'vel la))
          (dolist (e la)
            (if (and vmin (or (eq 'pitch e) (eq 'vel e)))
                (setq vmin nil)
                (push e newla)))
          (setq newla la))
      (dolist (e newla)
         (cond
           ((and (member e '(dur kpress keyon keyoff)) (< lev 5))
                   (setq lev 5) (setq vmin e))
           ((and (equal e 'pitch)  (< lev 4))
                   (setq lev 4) (setq vmin e))
           ((and (equal e 'vel) (< lev 3))
                   (setq lev 3) (setq vmin e))           
           ((and (member e '(chpress pgm ctrlc bend vol)) (< lev 2))
                   (setq lev 2) (setq vmin e))
           ((and (member e '(sysex common rtime)) (< lev 1))
                   (setq lev 1) (setq vmin e))
           ((and (member e '(date evtype ref sex chan port field1 field2 fields t))
                 (= lev 0))
                   (setq vmin e))
           (t          nil)
         ))
      vmin))


;; analf (liste-de-transformations)
;; --------------------------------------------------------------------------------
;;     g�n�re une liste de mot-cl�s uniques (gentemp) pour chaque transformation
;;     chaque mot-cl� est porteur de propri�t�s qui d�crivent la transformation :
;;         name         lieu de l'affectation
;;         condition    condition �ventuelle impos�e par l'utilisateur
;;         formule      dont le r�sultat doit �tre affect�
;;         variables    liste des variables msh utilis�es
;;         varmin       variable msh minimale dans la hi�rarchie
;;                       sert � g�n�rer la condition msh

;; analf() utilise
;;         analist()   renvoie la liste des varibles msh (pitch, vel, dur, bend, ...)
;;         varmin()     renvoie la variable msh minimale ou t
;;         kresym()     cr�e un symbole unique (gentemp)
;;       setform-cond() chargent les propri�tes formule et condition
;;       setvariables() chargent les propri�t�s variables, varmin
;;       gen-name()     g�n�re un nom (avec un num�ro al�atoire)
;; --------------------------------------------------------------------------------

; cr�e un symbole associ� au mot-cl�
;(defun kresym (kw)
;      (intern (string-upcase (string-trim ":" kw)) :midishare))
; 07/06/03
(defun kresym (kw)
      (intern (string-upcase (string-trim ":" kw))))

;; varmin sert � positionner le code dans le cond
;; variables sert pour les extractions
(defun setvariables (kt l1 l2 lres)
    (when kt
        (setf (get 'variables kt)
                 (analist (cons l1 l2) loto nil))
        (setf (get 'varmin kt) (varmin (cons (get 'name kt) (get 'variables kt))))
        (if (not (equal (get 'name kt) 'when))  (push kt lres)))
     lres)


; charge les propri�t�s de 'formule et de 'condition sur le mot-cl�
(defun setform-cond (kt l1 l2 lres)
    (let ((kn (get 'name kt)))
        (cond
        ((or (equal kn 'print))
             (setf (get 'formule kt) nil)
             (if (not (member l1 loto))
                  (setf (get 'condition kt) l1)
                  (setf (get 'condition kt) nil)))
             ; on ne garde la condition que si elle est diff�rente d'un type
         (t
            (if (and (equal kn 'define) (null l2)) (setq l2 0))  ; 0 par d�faut ou
            (cond
               (l2  (setf (get 'condition kt) l1)
                    (setf (get 'formule kt) l2))
               (t   (setf (get 'condition kt) nil)
                    (setf (get 'formule kt) l1))
   )))
   (values kt lres)))


;(defun gen-name (kw)
;     (let ((knam (kresym kw)))
;           (setq kw (gentemp (string-upcase kw) :midishare))
;           (setf (get 'name kw) knam))
;     kw)
; 21/09/91 : on ne g�n�re plus de nouveau nom unique
(defun gen-name (kw)
     (setf (get 'name kw) (kresym kw))
     kw)


(defun analf (la)
     (let ((lres nil) (ktemp nil) (l1 nil) (l2 nil))
       (dolist (e la)
         (if e
           (if (keywordp e)
             (progn
               (when ktemp
                  (multiple-value-setq (ktemp lres)
                                (setform-cond (gen-name ktemp) l1 l2 lres))
                  (setq lres (setvariables ktemp l1 l2 lres))
                )
                (setq l1 nil)
                (setq l2 nil)
                (setq ktemp e))
             (if l1 (setq l2 e) (setq l1 e)))))
        (multiple-value-setq (ktemp lres)
                    (setform-cond (gen-name ktemp) l1 l2 lres))
        (setq lres (setvariables ktemp l1 l2 lres))
     lres))
; la liste est � l'envers, elle sera retourn�e d'office dans le prochain traitement


;; --------------------------------------------------------------------------------
;; verif()  permet de v�rifier le bon travail de analf() :calcul et chargement
;;             des formules, conditions et variables, par un affichage sympa.
;; --------------------------------------------------------------------------------
(defun verif (la)
    (terpri)
    (write-line (format nil " Affect  Formule                     Condition                   Variables     Varmin"))
    (dolist (e (reverse la))
       (write-line (format nil " ~7S ~27S ~27S ~13S ~7S"
              (get 'name e) (get 'formule e) (get 'condition e)
              (get 'variables e) (get 'varmin e)))
 ))



;; g�n�re une ligne de code du type (when condition formule)
;; --------------------------------------------------------------------------------
(defun make-code (kword)
    (let (code (condit (get 'condition kword)) (nam (get 'name kword))
                  (extrac nil) gencond)
;  (print "make-code : condit code") (print condit)

    ; extraction des variables MIDI
    (dolist (var (get 'variables kword))
       (push (list 'setq var (list var 'ev)) extrac))

    ; g�n�ration du code affectation
    (cond
       ((eq nam 'define) (setq code (list condit (get 'formule kword)))
                                  (setq condit nil))
       ((eq nam 'kpress) (setq code (list 'vel 'ev (get 'formule kword))))
       ((eq nam 'print)  (setq code '(print (midi-string-ev ev))))
       ((member nam loto)
               (if (get 'formule kword)
                         (setq code (list nam 'ev (get 'formule kword)))
                         (setq code '(setq ev nil))))
       ((eq nam 'calc)    (setq code (get 'formule kword)))
       (t                (setq nam (read-from-string (string-trim ":"
                                       (string-left-trim "MIDISHARE" (write-to-string nam)))))
                              (setq code (list 'setq nam (get 'formule kword))))
    )

     ; ajout de la condition utilisateur
     (if (and condit (not (equal condit 't))
              (not (member condit loto))
              (not (and (listp condit) (eq (car condit) 'not)
                        (member (cadr condit) loto))))
         (setq code (list 'when condit code)))

     ; ajout du code concernant l'extraction des variables MIDI
     (setq code (list code))
     ; si la cond est un type, alors condit = nil
     (unless (or (and (eq nam 'print) (null condit))
                 (and (listp condit) (eq (car condit) 'not)
                        (member (cadr condit) loto)))
        (dolist (ex extrac)
           (push ex code)))

     ; ajout de la condition d'ad�quation de type
     (let ((ty (get 'types (get 'varmin kword))))
     ; (print ty)
       (if ty
         (progn
           (if (> (length ty) 1)
             (setq gencond (list 'member '(evtype ev) (list 'quote (mapcar #'eval ty))))
             (setq gencond (list '= '(evtype ev) (car ty))))
           (if (and (listp condit) (eq (car condit) 'not) (member (cadr condit) loto))
             (setq gencond (list 'not gencond)))
           (push gencond code)
           (push 'when code))
         (if (eq (length code) 1)
           (setq code (car code))
           (push 'progn code))))

code))



;; G�n�ration du code des transformations
;; ltr contient d'abord la liste brute des transf, puis la m�me liste sous forme mot-cles
;; prcode1 : code annoncant le print avant la boucle (nil ou (write-line (date  P/C event)))
;; --------------------------------------------------------------------------------
(defun gencodev (ltr)
  (let (lamcode codlet (debug nil))

    (setq debug (member :debug ltr))             ; 1) positionnement du flag debug
    (setq ltr (delete :debug ltr))
    (when ltr                                    ; 2) teste si la liste n'est pas vide
      (setq ltr (analf ltr))                     ; 3) analyse de la liste des transformations
      ; la liste ne contient plus que les keywords porteurs de propri�t�s
      ; (analf) extrait les keywords
      ; (setform-cond) affecte les propri�t�s de formule et condition sur le keyword
      ; (setvariables) affecte les variables utilis�es sur le keyword
      (if debug (verif ltr))                     ; 4) affichage des transformations

      (dolist (e ltr)
        (dolist (var (get 'variables e))
           (unless (or (member var codlet) (and (eq e :print) (null (get 'condition e))))
              (push var codlet)))
      ;  (print (make-code e))
        (cond
           ((eq (get 'name e) 'print)
               (push (make-code e) lamcode))
           ((eq (get 'name e) 'define)
               (push (make-code e) codlet))
           (t  (push (make-code e) lamcode))))

      ; on ne peut pas utiliser prcod1 dans le cadre de midi-transf

      (if codlet
         (progn (push codlet lamcode)
                (push 'let lamcode))
         (push 'progn lamcode))
    )
    (if debug (pprint (subst (list 'lambda '(ev) (if lamcode lamcode 'ev)) 'l '#'l)))

    (subst (list 'lambda '(ev) (if lamcode lamcode 'ev)) 'l '#'l)
  ))
  

(defmacro change (&body ltr)
  (gencodev ltr))
