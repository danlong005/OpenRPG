     H*MOVE/MOVEL from a character field into a numeric result.
     H*The digit portion of each character moves positionally; the
     H*RESULT field's decimal places reinterpret what lands there.
     HDFTACTGRP(*NO)
     DCH5              S              5A
     DCH3              S              3A
     DDST5             S              5P0
     DDST52            S              5P2
     DR                S             30A
     C*Same width: every digit moves, either direction.
     C                   EVAL      CH5 = '00123'
     C                   EVAL      DST5 = 0
     C                   MOVE      CH5           DST5
     C                   EVAL      R = '[' + %char(DST5) + ']'
     C     R             DSPLY
     C                   EVAL      CH5 = '00123'
     C                   EVAL      DST5 = 0
     C                   MOVEL     CH5           DST5
     C                   EVAL      R = '[' + %char(DST5) + ']'
     C     R             DSPLY
     C*"Blanks are transferred as zeros" -- CH5 is declared 5A, so
     C*'123' is really '123  ', which is the digits 12300.
     C                   EVAL      CH5 = '123'
     C                   EVAL      DST5 = 0
     C                   MOVE      CH5           DST5
     C                   EVAL      R = '[' + %char(DST5) + ']'
     C     R             DSPLY
     C*The result's own decimal places apply to the moved digits.
     C                   EVAL      CH5 = '00123'
     C                   EVAL      DST52 = 0
     C                   MOVE      CH5           DST52
     C                   EVAL      R = '[' + %char(DST52) + ']'
     C     R             DSPLY
     C*Factor 2 shorter than the result.
     C                   EVAL      CH3 = '456'
     C                   EVAL      DST5 = 99999
     C                   MOVE      CH3           DST5
     C                   EVAL      R = '[' + %char(DST5) + ']'
     C     R             DSPLY
     C                   EVAL      CH3 = '456'
     C                   EVAL      DST5 = 99999
     C                   MOVEL     CH3           DST5
     C                   EVAL      R = '[' + %char(DST5) + ']'
     C     R             DSPLY
     C*A shorter factor 2 leaves the result sign alone on MOVEL,
     C*character factor 2 included.
     C                   EVAL      CH3 = '456'
     C                   EVAL      DST5 = -99999
     C                   MOVEL     CH3           DST5
     C                   EVAL      R = '[' + %char(DST5) + ']'
     C     R             DSPLY
     C*(P) pads the untouched digits with '0'.
     C                   EVAL      CH3 = '456'
     C                   EVAL      DST5 = 99999
     C                   MOVE(P)   CH3           DST5
     C                   EVAL      R = '[' + %char(DST5) + ']'
     C     R             DSPLY
     C                   EVAL      CH3 = '456'
     C                   EVAL      DST5 = 99999
     C                   MOVEL(P)  CH3           DST5
     C                   EVAL      R = '[' + %char(DST5) + ']'
     C     R             DSPLY
     C                   RETURN
