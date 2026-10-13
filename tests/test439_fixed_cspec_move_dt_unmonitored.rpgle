     H*A MOVE that cannot make a date, with no MONITOR around it, ends
     H*the program in error (RNX0112), as on IBM i. MOVE has no (E).
     HDFTACTGRP(*NO)
     HDATFMT(*ISO)
     DDFLD             S               D
     DC10              S             10A
     C                   EVAL      C10 = '1996-13-45'
     C     'before'      DSPLY
     C     *ISO          MOVE      C10           DFLD
     C     'not shown'   DSPLY
     C                   RETURN
