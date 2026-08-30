     HDFTACTGRP(*NO)
     Da                S             10I 0
     Db                S             10I 0
     Dr                S             10I 0
     C                   EVAL      a = 5
     C                   EVAL      b = 3
     C     a             ADD       b             r
     C     %CHAR(r)      DSPLY
     C                   EVAL      r = 10
     C                   ADD       b             r
     C     %CHAR(r)      DSPLY
     C     a             SUB       b             r
     C     %CHAR(r)      DSPLY
     C                   EVAL      r = 10
     C                   SUB       b             r
     C     %CHAR(r)      DSPLY
     C     a             MULT      b             r
     C     %CHAR(r)      DSPLY
     C                   EVAL      r = 10
     C                   MULT      b             r
     C     %CHAR(r)      DSPLY
     C                   EVAL      a = 20
     C                   EVAL      b = 4
     C     a             DIV       b             r
     C     %CHAR(r)      DSPLY
     C                   EVAL      r = 40
     C                   DIV       b             r
     C     %CHAR(r)      DSPLY
     C                   RETURN
