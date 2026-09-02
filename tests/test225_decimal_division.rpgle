     HDFTACTGRP(*NO)
     D*REGRESSION: RPG DIVISION PRODUCES A DECIMAL QUOTIENT WHATEVER
     D*THE OPERANDS ARE.  TWO INTEGER OPERANDS ONCE DIVIDED AS C++
     D*INTS, SO 10 / 3 CAME OUT AS 3.
     DNUMER            S             10I 0 INZ(10)
     DDENOM            S             10I 0 INZ(3)
     DQUOT             S             11P 4
     DRPTLIN           S             70A
     C*TWO INTEGER LITERALS
     C                   EVAL      QUOT = 10 / 3
     C                   EVAL      RPTLIN = '10 / 3 = ' + %EDITC(QUOT:'1')
     C     RPTLIN        DSPLY
     C*TWO INTEGER FIELDS
     C                   EVAL      QUOT = NUMER / DENOM
     C                   EVAL      RPTLIN = 'NUMER / DENOM = ' +
     C                             %EDITC(QUOT:'1')
     C     RPTLIN        DSPLY
     C*A QUOTIENT SMALLER THAN ONE MUST NOT COLLAPSE TO ZERO
     C                   EVAL      QUOT = 1 / 8
     C                   EVAL      RPTLIN = '1 / 8 = ' + %EDITC(QUOT:'1')
     C     RPTLIN        DSPLY
     C*THE FIXED C-SPEC DIV OPCODE TAKES THE SAME PATH
     C     7             DIV       2             QUOT
     C                   EVAL      RPTLIN = 'DIV 7 / 2 = ' + %EDITC(QUOT:'1')
     C     RPTLIN        DSPLY
     C                   RETURN
