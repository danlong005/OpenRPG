     HDFTACTGRP(*NO)
     Di                S             10I 0
     DTMPDSP           S             52A
     C                   FOR       i = 1 TO 3
     C                   EVAL      TMPDSP = %CHAR(i)
     C     TMPDSP        DSPLY
     C                   ENDFOR
     C                   FOR       i = 10 DOWNTO 6 BY 2
     C                   EVAL      TMPDSP = %CHAR(i)
     C     TMPDSP        DSPLY
     C                   ENDFOR
     C                   RETURN
