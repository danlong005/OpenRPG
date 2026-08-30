     H*A character factor 2 whose digit portion is not a valid digit
     H*is a data exception (status 907), not something to reinterpret:
     H*the moved digits become zeros and the program can test %STATUS.
     HDFTACTGRP(*NO)
     DCH3              S              3A
     DP5               S              5P 0
     DR                S             30A
     C                   EVAL      CH3 = 'A1'
     C                   EVAL      P5 = 77777
     C                   MOVE      CH3           P5
     C                   EVAL      R = '[' + %char(P5) + ']'
     C     R             DSPLY
     C                   EVAL      R = '[' + %char(%STATUS()) + ']'
     C     R             DSPLY
     C                   RETURN
