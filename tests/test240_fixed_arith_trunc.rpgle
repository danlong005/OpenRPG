     H*FIXED-FORMAT ARITHMETIC TRUNCATES HIGH-ORDER DIGITS.
     H*ADD, SUB, MULT, DIV, Z-ADD AND Z-SUB DROP A RESULT'S EXCESS
     H*HIGH-ORDER DIGITS WITHOUT AN ERROR (SC09-2508); ONLY EVAL
     H*RAISES STATUS 103. THEY ARE TRANSPILED TO EVAL, SO THEY CARRY
     H*AN INTERNAL (T) EXTENDER TO KEEP THAT DIFFERENCE.
     HDFTACTGRP(*NO)
     DSMALL            S              3P 0
     DTWO              S              5P 2
     DR                S             30A  
     C                   Z-ADD     999           SMALL
     C                   ADD       1             SMALL
     C                   EVAL      R = 'RESULT:ADD=' + %CHAR(SMALL)
     C     R             DSPLY
     C                   Z-ADD     12345.67      TWO
     C                   EVAL      R = 'RESULT:ZADD=' + %CHAR(TWO)
     C     R             DSPLY
     C                   Z-ADD     123           SMALL
     C     SMALL         MULT      10            SMALL
     C                   EVAL      R = 'RESULT:MULT=' + %CHAR(SMALL)
     C     R             DSPLY
     C                   MONITOR   
     C                   EVAL      SMALL = 1000
     C                   EVAL      R = 'RESULT:EVAL=stored'
     C                   ON-ERROR  
     C                   EVAL      R = 'RESULT:EVAL=' + %CHAR(%STATUS())
     C                   ENDMON    
     C     R             DSPLY
     C                   RETURN    
