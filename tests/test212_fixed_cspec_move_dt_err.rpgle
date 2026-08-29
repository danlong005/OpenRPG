     H*'If factor 2 is not a valid representation of a date or time or
     H*its format does not match the format specified in factor 1, an
     H*error is generated' (p.406) -- status 112, result unchanged.
     HDFTACTGRP(*NO)
     HDATFMT(*ISO)
     DDFLD             S               D
     DC10              S             10A
     DC6               S              6A
     DDISP10           S             10A
     DR                S             30A
     C     *ISO          MOVE      '1996-04-15'  DFLD
     C*Month 13 and day 45 are not a date.
     C                   EVAL      C10 = '1996-13-45'
     C     *ISO          MOVE      C10           DFLD
     C                   EVAL      R = '[' + %char(%STATUS()) + ']'
     C     R             DSPLY
     C     *ISO          MOVE      DFLD          DISP10
     C                   EVAL      R = '[' + DISP10 + ']'
     C     R             DSPLY
     C*A separator where *ISO does not put one is equally invalid.
     C                   EVAL      C10 = '1996/04/15'
     C     *ISO          MOVE      C10           DFLD
     C                   EVAL      R = '[' + %char(%STATUS()) + ']'
     C     R             DSPLY
     C*Six characters cannot hold the ten an *ISO date needs.
     C                   EVAL      C6 = '960415'
     C     *ISO          MOVE      C6            DFLD
     C                   EVAL      R = '[' + %char(%STATUS()) + ']'
     C     R             DSPLY
     C     *ISO          MOVE      DFLD          DISP10
     C                   EVAL      R = '[' + DISP10 + ']'
     C     R             DSPLY
     C                   RETURN
