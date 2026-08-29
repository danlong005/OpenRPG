     H*MOVE/MOVEL between numeric fields (SC09-2508 p.633/884/905).
     H*These are DIGIT moves against declared digit counts, not value
     H*assignments: both operands decimal positions are ignored.
     HDFTACTGRP(*NO)
     DSRC32            S              3P2
     DDST31            S              3P1
     DSRC5             S              5P0
     DDST3             S              3P0
     DDST5             S              5P0
     DSRC2             S              2P0
     DR                S             30A
     C*The manual's own worked example: moving 1.00 into a 3-digit,
     C*1-decimal field gives 10.0 -- the digits move, the decimal
     C*point does not travel with them.
     C                   EVAL      SRC32 = 1.00
     C                   EVAL      DST31 = 0
     C                   MOVE      SRC32         DST31
     C                   EVAL      R = '[' + %char(DST31) + ']'
     C     R             DSPLY
     C*Same for MOVEL when the two are the same width.
     C                   EVAL      SRC32 = 1.00
     C                   EVAL      DST31 = 0
     C                   MOVEL     SRC32         DST31
     C                   EVAL      R = '[' + %char(DST31) + ']'
     C     R             DSPLY
     C*Factor 2's decimal places are ignored: 1.05 is the digits 105.
     C                   EVAL      SRC32 = 1.05
     C                   EVAL      DST3 = 0
     C                   MOVE      SRC32         DST3
     C                   EVAL      R = '[' + %char(DST3) + ']'
     C     R             DSPLY
     C*Factor 2 longer than the result: MOVE drops the excess
     C*LEFTmost digits ...
     C                   EVAL      SRC5 = 12345
     C                   EVAL      DST3 = 0
     C                   MOVE      SRC5          DST3
     C                   EVAL      R = '[' + %char(DST3) + ']'
     C     R             DSPLY
     C*... and MOVEL drops the excess RIGHTmost ones.
     C                   EVAL      SRC5 = 12345
     C                   EVAL      DST3 = 0
     C                   MOVEL     SRC5          DST3
     C                   EVAL      R = '[' + %char(DST3) + ']'
     C     R             DSPLY
     C*Factor 2 shorter: the result digits it does not reach are
     C*left unchanged -- the whole reason MOVE is not assignment.
     C                   EVAL      SRC2 = 42
     C                   EVAL      DST5 = 99999
     C                   MOVE      SRC2          DST5
     C                   EVAL      R = '[' + %char(DST5) + ']'
     C     R             DSPLY
     C                   EVAL      SRC2 = 42
     C                   EVAL      DST5 = 99999
     C                   MOVEL     SRC2          DST5
     C                   EVAL      R = '[' + %char(DST5) + ']'
     C     R             DSPLY
     C*(P) pads them instead -- with '0' for a numeric result, from
     C*the left for MOVE and from the right for MOVEL.
     C                   EVAL      SRC2 = 42
     C                   EVAL      DST5 = 99999
     C                   MOVE(P)   SRC2          DST5
     C                   EVAL      R = '[' + %char(DST5) + ']'
     C     R             DSPLY
     C                   EVAL      SRC2 = 42
     C                   EVAL      DST5 = 99999
     C                   MOVEL(P)  SRC2          DST5
     C                   EVAL      R = '[' + %char(DST5) + ']'
     C     R             DSPLY
     C*MOVE always moves factor 2's rightmost position, which is
     C*where the sign lives, so factor 2's sign always wins.
     C                   EVAL      SRC2 = -7
     C                   EVAL      DST5 = 99999
     C                   MOVE      SRC2          DST5
     C                   EVAL      R = '[' + %char(DST5) + ']'
     C     R             DSPLY
     C*MOVEL keeps the RESULT field sign while factor 2 is shorter,
     C*whichever sign that happens to be ...
     C                   EVAL      SRC2 = -7
     C                   EVAL      DST5 = 99999
     C                   MOVEL     SRC2          DST5
     C                   EVAL      R = '[' + %char(DST5) + ']'
     C     R             DSPLY
     C                   EVAL      SRC2 = 7
     C                   EVAL      DST5 = -99999
     C                   MOVEL     SRC2          DST5
     C                   EVAL      R = '[' + %char(DST5) + ']'
     C     R             DSPLY
     C*... and takes factor 2's once factor 2 is as long or longer.
     C                   EVAL      SRC5 = -12345
     C                   EVAL      DST5 = 11111
     C                   MOVEL     SRC5          DST5
     C                   EVAL      R = '[' + %char(DST5) + ']'
     C     R             DSPLY
     C                   RETURN
