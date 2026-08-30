     HDFTACTGRP(*NO)
     Dtotal            S             10I 0
     DTMPDSP           S             52A
     C                   EVAL      total = 1
     C                   EXSR      addfive
     C                   EXSR      addfive
     C                   EVAL      TMPDSP = %CHAR(total)
     C     TMPDSP        DSPLY
     C                   RETURN
     C     addfive       BEGSR
     C                   EVAL      total = total + 5
     C                   ENDSR
