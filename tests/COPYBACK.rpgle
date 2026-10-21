     H*Factor 2 on an *ENTRY PARM is copied into the parameter when the
     H*program returns to its caller (SC09-2508 p.929 step 4), however it
     H*returns. MODE picks the way out: 1 a RETURN in the calculations, 2
     H*a RETURN inside a subroutine, anything else the end of the
     H*calculations. Called by test205.
     HDFTACTGRP(*NO)
     DMODE             S              1A
     DN                S             10I 0
     DMSG              S             10A
     DOUT              S             10I 0
     C     *ENTRY        PLIST
     C                   PARM                    MODE
     C                   PARM      OUT           N
     C                   PARM      'returned'    MSG
     C                   EVAL      OUT = N * 10
     C*Overwritten by the copy from OUT when the program returns.
     C                   EVAL      N = -1
     C                   IF        MODE = '1'
     C                   RETURN
     C                   ENDIF
     C                   IF        MODE = '2'
     C                   EXSR      EXITSR
     C                   ENDIF
     C                   EVAL      OUT = OUT + 5
     C                   EVAL      *INLR = *ON
     C     EXITSR        BEGSR
     C                   EVAL      OUT = OUT + 1
     C                   RETURN
     C                   ENDSR
