     H*MOVE with date operands -- SC09-2508 Figure 287 (p.631).
     H*Factor 1 names the format of the CHARACTER or NUMERIC operand;
     H*it must be blank when both operands are date/time fields.
     HDFTACTGRP(*NO)
     HDATFMT(*ISO)
     DDATE_ISO         S               D
     DDATE_YMD         S               D   DATFMT(*YMD)
     DDATE_EUR         S               D   DATFMT(*EUR)
     DDATE_JIS         S               D   DATFMT(*JIS)
     DDATE_USA         S               D   DATFMT(*USA)
     DNUM_DATE1        S              6P0
     DNUM_DATE2        S              7P0
     DCHAR_DATE        S              8A
     DCHAR_LJ          S              8A
     DDISP10           S             10A
     DDISP8            S              8A
     DR                S             30A
     C*Seed a *YMD date from an *ISO character literal.
     C     *ISO          MOVE      '1992-03-24'  DATE_YMD
     C*Date to date: factor 1 blank. DATE_EUR is 24.03.1992.
     C                   MOVE      DATE_YMD      DATE_EUR
     C     *EUR          MOVE      DATE_EUR      DISP10
     C                   EVAL      R = '[' + DISP10 + ']'
     C     R             DSPLY
     C*A numeric ddmmyy literal, then the same value in a 6P0 field.
     C     *DMY          MOVE      210991        DATE_ISO
     C     *ISO          MOVE      DATE_ISO      DISP10
     C                   EVAL      R = '[' + DISP10 + ']'
     C     R             DSPLY
     C                   EVAL      NUM_DATE1 = 210991
     C     *DMY          MOVE      NUM_DATE1     DATE_ISO
     C     *ISO          MOVE      DATE_ISO      DISP10
     C                   EVAL      R = '[' + DISP10 + ']'
     C     R             DSPLY
     C*A character *MDY date with its separator named in factor 1.
     C     *MDY/         MOVE      '02/01/53'    DATE_JIS
     C     *JIS          MOVE      DATE_JIS      DISP10
     C                   EVAL      R = '[' + DISP10 + ']'
     C     R             DSPLY
     C                   EVAL      CHAR_DATE = '02/01/53'
     C     *MDY/         MOVE      CHAR_DATE     DATE_JIS
     C     *JIS          MOVE      DATE_JIS      DISP10
     C                   EVAL      R = '[' + DISP10 + ']'
     C     R             DSPLY
     C*Date back out to a character field, padded.
     C     *MDY/         MOVE(P)   DATE_JIS      CHAR_DATE
     C                   EVAL      R = '[' + CHAR_DATE + ']'
     C     R             DSPLY
     C*Date to a numeric field in *CMDY: c=2 for 2197, so 2082697.
     C     *ISO          MOVE      '2197-08-26'  DATE_EUR
     C     *CMDY         MOVE      DATE_EUR      NUM_DATE2
     C                   EVAL      R = '[' + %char(NUM_DATE2) + ']'
     C     R             DSPLY
     C*Error 114: 9999 is outside a 2-digit year format's 1940-2039
     C*range, so the *YMD result field is left unchanged.
     C     *ISO          MOVE      '9999-12-31'  DATE_USA
     C                   MOVE      DATE_USA      DATE_YMD
     C                   EVAL      R = '[' + %char(%STATUS()) + ']'
     C     R             DSPLY
     C     *YMD          MOVE      DATE_YMD      DISP8
     C                   EVAL      R = '[' + DISP8 + ']'
     C     R             DSPLY
     C*A *LONGJUL character date into a *YMD date field.
     C                   EVAL      CHAR_LJ = '2039/166'
     C     *LONGJUL      MOVE      CHAR_LJ       DATE_YMD
     C     *YMD          MOVE      DATE_YMD      DISP8
     C                   EVAL      R = '[' + DISP8 + ']'
     C     R             DSPLY
     C                   RETURN
