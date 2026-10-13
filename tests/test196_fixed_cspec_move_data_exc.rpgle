     H*A character factor 2 moves the digit portion of each character:
     H*the low half of its EBCDIC code. 'A' is x'C1', so it moves as 1,
     H*and that is no data exception. A blank (x'40') moves as 0. A D
     H*zone in the rightmost character (J-R) makes the result negative.
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
     C                   EVAL      CH3 = '12N'
     C                   MOVE      CH3           P5
     C                   EVAL      R = '[' + %char(P5) + ']'
     C     R             DSPLY
     C                   RETURN
