     HDFTACTGRP(*NO)
     Dtotal                     10     I0
     C                   EVAL      total = 1
     C                   EXSR      addfive
     C                   EXSR      addfive
     C     %CHAR(total)  DSPLY
     C                   RETURN
     C     addfive       BEGSR
     C                   EVAL      total = total + 5
     C                   ENDSR
