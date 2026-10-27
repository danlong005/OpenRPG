      * A fixed-format data structure BASED on %ADDR(*IN): its length in
      * positions 33-39, the pointer given INZ(%ADDR(*IN)).
     D pInd            S               *   INZ(%ADDR(*IN))
     D inds            DS            99    BASED(pInd)
     D  exitKey                3      3N
     D  errs                  50     52
     C                   EVAL      *IN03 = *ON
     C                   IF        exitKey
     C     'exit'        DSPLY
     C                   ENDIF
     C                   EVAL      errs = '010'
     C     *IN51         DSPLY
     C                   EVAL      *INLR = *ON
