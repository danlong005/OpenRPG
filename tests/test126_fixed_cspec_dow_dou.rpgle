     HDFTACTGRP(*NO)
     Di                S             10I 0
     DTMPDSP           S             52A
     C                   EVAL      i = 0
     C                   DOW       i < 3
     C                   EVAL      TMPDSP = %CHAR(i)
     C     TMPDSP        DSPLY
     C                   EVAL      i = i + 1
     C                   ENDDO
     C                   EVAL      i = 0
     C                   DOU       i >= 3
     C                   EVAL      i = i + 1
     C                   EVAL      TMPDSP = %CHAR(i)
     C     TMPDSP        DSPLY
     C                   ENDDO
     C                   RETURN
