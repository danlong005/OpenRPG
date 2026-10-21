     H*A character whose EBCDIC digit portion is above 9 ('.' is x'4B')
     H*is a decimal data error (907) in MOVE and MOVEL. It ends the
     H*program unless MONITOR handles it, and the result is unchanged.
     HDFTACTGRP(*NO)
     DCH3              S              3A
     DP5               S              5P 0
     DR                S             30A
     C                   EVAL      CH3 = '1.3'
     C                   EVAL      P5 = 77777
     C                   MONITOR
     C                   MOVE      CH3           P5
     C                   ON-ERROR
     C                   EVAL      R = '[' + %char(%STATUS()) + ']'
     C     R             DSPLY
     C                   ENDMON
     C                   EVAL      R = '[' + %char(P5) + ']'
     C     R             DSPLY
     C                   EVAL      CH3 = '9+3'
     C                   MONITOR
     C                   MOVEL     CH3           P5
     C                   ON-ERROR
     C                   EVAL      R = '[' + %char(%STATUS()) + ']'
     C     R             DSPLY
     C                   ENDMON
     C                   EVAL      R = '[' + %char(P5) + ']'
     C     R             DSPLY
     C*Unhandled, the error ends the program.
     C                   EVAL      CH3 = '1*3'
     C                   MOVE      CH3           P5
     C     'not shown'   DSPLY
     C                   RETURN
