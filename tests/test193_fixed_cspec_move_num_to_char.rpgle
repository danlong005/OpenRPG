     H*MOVE/MOVEL from a numeric field into a character result.
     H*The value's digits become characters and move positionally.
     H*A negative sign goes into the zone of the rightmost digit, as
     H*in a zoned number: 5 becomes N, and 0 becomes a right brace.
     HDFTACTGRP(*NO)
     DP5               S              5P 0
     DP32              S              3P 2
     DCH8              S              8A
     DR                S             30A
     C*Right-aligned for MOVE, left-aligned for MOVEL, with the
     C*untouched characters of the result left as they were.
     C                   EVAL      P5 = 12345
     C                   EVAL      CH8 = 'ZZZZZZZZ'
     C                   MOVE      P5            CH8
     C                   EVAL      R = '[' + CH8 + ']'
     C     R             DSPLY
     C                   EVAL      P5 = 12345
     C                   EVAL      CH8 = 'ZZZZZZZZ'
     C                   MOVEL     P5            CH8
     C                   EVAL      R = '[' + CH8 + ']'
     C     R             DSPLY
     C*(P) pads a CHARACTER result with blanks, not with zeros.
     C                   EVAL      P5 = 12345
     C                   EVAL      CH8 = 'ZZZZZZZZ'
     C                   MOVE(P)   P5            CH8
     C                   EVAL      R = '[' + CH8 + ']'
     C     R             DSPLY
     C                   EVAL      P5 = 12345
     C                   EVAL      CH8 = 'ZZZZZZZZ'
     C                   MOVEL(P)  P5            CH8
     C                   EVAL      R = '[' + CH8 + ']'
     C     R             DSPLY
     C*The decimal point is not a digit and is not moved.
     C                   EVAL      P32 = 1.05
     C                   EVAL      CH8 = 'ZZZZZZZZ'
     C                   MOVE      P32           CH8
     C                   EVAL      R = '[' + CH8 + ']'
     C     R             DSPLY
     C*A negative value ends in N, its last digit with a D zone.
     C                   EVAL      P5 = -12345
     C                   EVAL      CH8 = 'ZZZZZZZZ'
     C                   MOVE      P5            CH8
     C                   EVAL      R = '[' + CH8 + ']'
     C     R             DSPLY
     C                   EVAL      P5 = -12340
     C                   EVAL      CH8 = 'ZZZZZZZZ'
     C                   MOVEL     P5            CH8
     C                   EVAL      R = '[' + CH8 + ']'
     C     R             DSPLY
     C*An integer literal carries its own digit count.
     C                   EVAL      CH8 = 'ZZZZZZZZ'
     C                   MOVE      210991        CH8
     C                   EVAL      R = '[' + CH8 + ']'
     C     R             DSPLY
     C                   RETURN
