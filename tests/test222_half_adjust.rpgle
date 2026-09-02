     HDFTACTGRP(*NO)
     D*REGRESSION: THE (H) EXTENDER ROUNDS AT THE RESULT FIELD'S OWN
     D*DECIMAL POSITION, NOT AT THE UNITS POSITION.  A 2-DECIMAL
     D*RESULT MUST KEEP ITS CENTS.
     DMONEY            S              9S 2
     DWHOLE            S              5S 0
     DRPTLIN           S             60A
     C*705.00 X 0.22 = 155.10 -- NOT 155.00
     C     705.00        MULT(H)   0.22          MONEY
     C                   EVAL      RPTLIN = 'MULT(H) 705.00 X 0.22 = ' +
     C                             %EDITC(MONEY:'1')
     C     RPTLIN        DSPLY
     C*10.00 / 3 ROUNDS UP AT THE CENT: 3.33
     C     10.00         DIV(H)    3             MONEY
     C                   EVAL      RPTLIN = 'DIV(H) 10.00 / 3 = ' +
     C                             %EDITC(MONEY:'1')
     C     RPTLIN        DSPLY
     C*HALF ROUNDS AWAY FROM ZERO IN BOTH DIRECTIONS.  EDIT CODE 3
     C*IS USED FOR THE NEGATIVE SO THE SIGN IS NOT SUPPRESSED.
     C                   Z-ADD(H)  10.126        MONEY
     C                   EVAL      RPTLIN = 'Z-ADD(H) 10.126 = ' +
     C                             %EDITC(MONEY:'1')
     C     RPTLIN        DSPLY
     C                   Z-ADD(H)  10.124        MONEY
     C                   EVAL      RPTLIN = 'Z-ADD(H) 10.124 = ' +
     C                             %EDITC(MONEY:'1')
     C     RPTLIN        DSPLY
     C                   Z-ADD(H)  -10.126       MONEY
     C                   EVAL      RPTLIN = 'Z-ADD(H) -10.126 = ' +
     C                             %EDITC(MONEY:'3')
     C     RPTLIN        DSPLY
     C*A 0-DECIMAL RESULT STILL ROUNDS AT THE UNITS POSITION
     C                   Z-ADD(H)  10.6          WHOLE
     C                   EVAL      RPTLIN = 'Z-ADD(H) 10.6 INTO 0-DEC = ' +
     C                             %EDITC(WHOLE:'1')
     C     RPTLIN        DSPLY
     C                   RETURN
