     HDFTACTGRP(*NO)
     Dn                S             10I 0
     C                   EVAL      n = 1
     C                   EXSR      dispatch
     C                   EVAL      n = 2
     C                   EXSR      dispatch
     C                   EVAL      n = 9
     C                   EXSR      dispatch
     C                   EVAL      n = 4
     C                   EXSR      dispatch
     C                   EVAL      n = 2
     C     n             CABEQ     2             skip
     C     'not skipped' DSPLY
     C     skip          TAG
     C     'after cabeq' DSPLY
     C                   CAB                     done
     C     'not reached' DSPLY
     C     done          TAG
     C     'after cab'   DSPLY
     C                   RETURN
     C     subone        BEGSR
     C     'one'         DSPLY
     C                   ENDSR
     C     subtwo        BEGSR
     C     'two'         DSPLY
     C                   ENDSR
     C     subbig        BEGSR
     C     'big'         DSPLY
     C                   ENDSR
     C     subdflt       BEGSR
     C     'dflt'        DSPLY
     C                   ENDSR
     C     dispatch      BEGSR
     C     n             CASEQ     1             subone
     C     n             CASEQ     2             subtwo
     C     n             CASGT     5             subbig
     C                   CAS                     subdflt
     C                   ENDCS
     C                   ENDSR
