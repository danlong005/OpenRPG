      * Fixed format: DIM subfields of a BASED data structure laid over
      * it with OVERLAY(ds:pos), an indicator array and a character one.
     D pInd            S               *   INZ(%ADDR(*IN))
     D inds            DS            99    BASED(pInd)
     D  fkey                          1N   DIM(24) OVERLAY(inds:1)
     D  errs                          1A   DIM(5) OVERLAY(inds:50)
     D i               S             10I 0
     C                   EVAL      *IN07 = *ON
     C                   EVAL      errs(2) = '1'
     C                   FOR       i = 1 TO 24
     C                   IF        fkey(i)
     C     i             DSPLY
     C                   ENDIF
     C                   ENDFOR
     C     *IN51         DSPLY
     C                   EVAL      *INLR = *ON
