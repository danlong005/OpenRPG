     H*MOVE with date and time formats written without separators --
     H*SC09-2508 Figure 288 (p.632). A zero at the end of a format
     H*(*MDY0) means the character field carries no separators at all.
     HDFTACTGRP(*NO)
     HDATFMT(*ISO)
     DDATE_USA         S               D   DATFMT(*USA)
     DDATEFLD          S               D
     DTIMEFLD          S               T
     DCHR_DATEA        S              6A
     DCHR_DATEB        S              7A
     DCHR_TIME         S              6A
     DDISP10           S             10A
     DR                S             30A
     C                   EVAL      TIMEFLD = %time('14:23:10')
     C**MDY0: a 6-character mmddyy date with no separators.
     C                   EVAL      CHR_DATEA = '041596'
     C     *MDY0         MOVE      CHR_DATEA     DATEFLD
     C     *ISO          MOVE      DATEFLD       DISP10
     C                   EVAL      R = '[' + DISP10 + ']'
     C     R             DSPLY
     C**EUR0: the result character field gets no separators either.
     C     *EUR0         MOVE      TIMEFLD       CHR_TIME
     C                   EVAL      R = '[' + CHR_TIME + ']'
     C     R             DSPLY
     C**CYMD0: cyymmdd, c=0 for 1900-1999, so 0610807 is 1961-08-07.
     C                   EVAL      CHR_DATEB = '0610807'
     C     *CYMD0        MOVE      CHR_DATEB     DATE_USA
     C     *USA          MOVE      DATE_USA      DISP10
     C                   EVAL      R = '[' + DISP10 + ']'
     C     R             DSPLY
     C                   RETURN
