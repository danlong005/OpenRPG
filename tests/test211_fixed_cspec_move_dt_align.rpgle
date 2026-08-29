     H*The date/time conversion produces a fixed-width text, and the
     H*SAME positional move the character form uses then places it:
     H*MOVE against the right end, MOVEL against the left, remainder
     H*unchanged unless (P). In the other direction, 'only the leftmost
     H*data (rightmost for the MOVE operation) is used' (p.406).
     HDFTACTGRP(*NO)
     HDATFMT(*ISO)
     DDFLD             S               D
     DC12              S             12A
     DC6               S              6A
     DDISP10           S             10A
     DR                S             40A
     C     *ISO          MOVE      '1996-04-15'  DFLD
     C*Result wider than the 10-character *ISO text.
     C                   EVAL      C12 = 'ZZZZZZZZZZZZ'
     C     *ISO          MOVEL     DFLD          C12
     C                   EVAL      R = '[' + C12 + ']'
     C     R             DSPLY
     C                   EVAL      C12 = 'ZZZZZZZZZZZZ'
     C     *ISO          MOVE      DFLD          C12
     C                   EVAL      R = '[' + C12 + ']'
     C     R             DSPLY
     C                   EVAL      C12 = 'ZZZZZZZZZZZZ'
     C     *ISO          MOVEL(P)  DFLD          C12
     C                   EVAL      R = '[' + C12 + ']'
     C     R             DSPLY
     C                   EVAL      C12 = 'ZZZZZZZZZZZZ'
     C     *ISO          MOVE(P)   DFLD          C12
     C                   EVAL      R = '[' + C12 + ']'
     C     R             DSPLY
     C*Result narrower: MOVEL keeps the leftmost 6 of the text,
     C*MOVE the rightmost 6.
     C                   EVAL      C6 = 'ZZZZZZ'
     C     *ISO          MOVEL     DFLD          C6
     C                   EVAL      R = '[' + C6 + ']'
     C     R             DSPLY
     C                   EVAL      C6 = 'ZZZZZZ'
     C     *ISO          MOVE      DFLD          C6
     C                   EVAL      R = '[' + C6 + ']'
     C     R             DSPLY
     C*Character wider than the format needs: same rule, other way.
     C                   EVAL      C12 = '1996-04-15XX'
     C     *ISO          MOVEL     C12           DFLD
     C     *ISO          MOVE      DFLD          DISP10
     C                   EVAL      R = '[' + DISP10 + ']'
     C     R             DSPLY
     C                   EVAL      C12 = 'XX1996-04-15'
     C     *ISO          MOVE      C12           DFLD
     C     *ISO          MOVE      DFLD          DISP10
     C                   EVAL      R = '[' + DISP10 + ']'
     C     R             DSPLY
     C                   RETURN
