     H*A FIXED-FORMAT DS IS UNQUALIFIED BY DEFAULT: ITS SUBFIELDS ARE
     H*ORDINARY NAMES, WHICH IS HOW NEARLY ALL LEGACY CODE USES THEM.
     HDFTACTGRP(*NO)
     DREC              DS
     DCUSNO                           6A
     DCUSBAL                          9P 2
     DR                S             30A
     C                   EVAL      CUSNO = 'C1'
     C                   EVAL      CUSBAL = 250.759
     C                   EVAL      R = 'RESULT:CUSNO=[' + CUSNO + ']'
     C     R             DSPLY
     C                   EVAL      R = 'RESULT:CUSBAL=' + %CHAR(CUSBAL)
     C     R             DSPLY
     C                   RETURN    
