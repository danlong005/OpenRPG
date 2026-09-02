     HDFTACTGRP(*NO)
     D*REGRESSION: %EDITC FORMATS AT THE ARGUMENT'S DECLARED DECIMAL
     D*POSITIONS.  IT ONCE ALWAYS PRINTED TWO, SO A WHOLE-NUMBER
     D*FIELD HOLDING 15 CAME OUT AS 15.00.
     DN0               S              5P 0
     DN2               S              9P 2
     DN3               S              9P 3
     DNEG              S              9P 2
     DRPTLIN           S             60A
     C                   Z-ADD     15            N0
     C                   Z-ADD     1250.75       N2
     C                   Z-ADD     4.5           N3
     C                   Z-ADD     -42           NEG
     C                   EVAL      RPTLIN = '0-DEC 15 = ' + %EDITC(N0:'1')
     C     RPTLIN        DSPLY
     C                   EVAL      RPTLIN = '2-DEC 1250.75 = ' + %EDITC(N2:'1')
     C     RPTLIN        DSPLY
     C                   EVAL      RPTLIN = '3-DEC 4.5 = ' + %EDITC(N3:'1')
     C     RPTLIN        DSPLY
     C                   EVAL      RPTLIN = '2-DEC -42 = ' + %EDITC(NEG:'3')
     C     RPTLIN        DSPLY
     C                   RETURN
