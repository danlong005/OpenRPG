     HDFTACTGRP(*NO)
     Dtotal            S             10I 0
     C                   EVAL      total = 1
     C     %CHAR(total)  DSPLY
      /INCLUDE tests/fixed_copybook_cspec.rpgle
     C                   EVAL      total = total + 1
     C     %CHAR(total)  DSPLY
     C                   RETURN
