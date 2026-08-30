     HDFTACTGRP(*NO)
     Dtotal            S             10I 0
     DTMPDSP           S             52A
     C                   EVAL      total = 1
     C                   EVAL      TMPDSP = %CHAR(total)
     C     TMPDSP        DSPLY
      /INCLUDE tests/fixed_copybook_cspec.rpgle
     C                   EVAL      total = total + 1
     C                   EVAL      TMPDSP = %CHAR(total)
     C     TMPDSP        DSPLY
     C                   RETURN
