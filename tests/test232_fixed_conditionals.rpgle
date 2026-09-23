     HDFTACTGRP(*NO)
      * Conditional compilation in fixed-format source.
      *
      * /IF, /ELSEIF, /ELSE, /ENDIF, /DEFINE, /UNDEFINE and /EOF used to
      * be ignored in fixed-format source, so both branches of every /IF
      * compiled with no diagnostic. See tests/fixed_copybook_cond.rpgle,
      * whose /DEFINE must reach this member and whose /EOF must end only
      * itself.
      /DEFINE DEBUG
      /COPY tests/fixed_copybook_cond.rpgle
     Dmsg              S             12A  
     Dundef            S              5A  
     Dpick             S              5A  
     Dnest             S              5A  
     DfreeRes          S              5A  
      * A D-spec chosen by a symbol the copy member defined.
      /IF DEFINED(FROMCOPY)
     DfromIf           S             10A   INZ('reached')
      /ELSE
     DfromIf           S             10A   INZ('missed')
      /ENDIF
      * An inactive /COPY is never opened: this file does not exist.
      /IF DEFINED(NOPE)
      /COPY tests/no_such_copybook.rpgle
      /ENDIF
      * Both branches used to compile, and the second assignment won.
      /IF DEFINED(DEBUG)
     C                   EVAL      msg = 'debug on'
      /ELSE
     C                   EVAL      msg = 'debug off'
      /ENDIF
      /UNDEFINE DEBUG
      /IF NOT DEFINED(DEBUG)
     C                   EVAL      undef = 'yes'
      /ENDIF
      * The first true branch wins; a later true /ELSEIF does not.
      /IF DEFINED(NOPE)
     C                   EVAL      pick = 'A'
      /ELSEIF NOT DEFINED(ZZ)
     C                   EVAL      pick = 'C'
      /ELSEIF DEFINED(FROMCOPY)
     C                   EVAL      pick = 'X'
      /ELSE
     C                   EVAL      pick = 'D'
      /ENDIF
      * Inside an inactive branch, a nested group stays inactive whatever
      * its own conditions say.
      /IF DEFINED(NOPE)
      /IF NOT DEFINED(NOPE)
     C                   EVAL      nest = 'bad1'
      /ELSE
     C                   EVAL      nest = 'bad2'
      /ENDIF
      /ELSE
     C                   EVAL      nest = 'good'
      /ENDIF
      /free
       /IF DEFINED(FROMCOPY)
       freeRes = 'yes';
       /ELSE
       freeRes = 'no';
       /ENDIF
       DSPLY ('RESULT:MSG=' + %TRIM(msg));
       DSPLY ('RESULT:UNDEF=' + %TRIM(undef));
       DSPLY ('RESULT:PICK=' + %TRIM(pick));
       DSPLY ('RESULT:NEST=' + %TRIM(nest));
       DSPLY ('RESULT:FREE=' + %TRIM(freeRes));
       DSPLY ('RESULT:DSPEC=' + %TRIM(fromIf));
       DSPLY ('RESULT:COPY=' + %TRIM(fromCopy) + '/' + %CHAR(copyOnly));
       *INLR = *ON;
      /end-free
