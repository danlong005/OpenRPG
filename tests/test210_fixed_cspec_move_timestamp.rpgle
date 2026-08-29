     H*MOVE with a timestamp -- SC09-2508 Figure 289 (p.633). A date
     H*moved into a timestamp leaves its time and microseconds alone; a
     H*time leaves the date alone and zeroes the microseconds.
     HDFTACTGRP(*NO)
     HDATFMT(*ISO)
     DTMSTAMP          S               Z
     DDATEBEGIN        S               D
     DTIMEBEGIN        S               T
     DDATESTART        S               D
     DTIMESTART        S               T
     DSTAMPCHAR        S             26A
     DSTAMPCHR0        S             26A
     DDISP10           S             10A
     DDISP8            S              8A
     DR                S             40A
     C     *HMS          MOVE      '05:17:23'    TIMEBEGIN
     C     *ISO          MOVE      '1991-10-24'  DATEBEGIN
     C*Build the timestamp a piece at a time, factor 1 blank.
     C                   MOVE      TIMEBEGIN     TMSTAMP
     C                   MOVE      DATEBEGIN     TMSTAMP
     C                   MOVE      TMSTAMP       STAMPCHAR
     C                   EVAL      R = '[' + STAMPCHAR + ']'
     C     R             DSPLY
     C**ISO0 drops every separator: 20 digits right-adjusted in 26,
     C*with (P) blanking the six positions the move does not reach.
     C     *ISO0         MOVE(P)   TMSTAMP       STAMPCHR0
     C                   EVAL      R = '[' + STAMPCHR0 + ']'
     C     R             DSPLY
     C*...and back out of the timestamp into a date and a time.
     C                   MOVE      TMSTAMP       DATESTART
     C     *ISO          MOVE      DATESTART     DISP10
     C                   EVAL      R = '[' + DISP10 + ']'
     C     R             DSPLY
     C                   MOVE      TMSTAMP       TIMESTART
     C     *HMS          MOVE      TIMESTART     DISP8
     C                   EVAL      R = '[' + DISP8 + ']'
     C     R             DSPLY
     C                   RETURN
