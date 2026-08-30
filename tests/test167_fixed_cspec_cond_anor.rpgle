     HDFTACTGRP(*NO)
     Dr                S             20A
     C                   EVAL      *IN10 = *ON
     C                   EVAL      *IN20 = *ON
     C                   EVAL      *IN30 = *OFF
     C   10
     CAN 20              EVAL      r = 'and-both-on'
     C     r             DSPLY
     C                   EVAL      r = 'unchanged'
     C   10
     CAN 30              EVAL      r = 'and-should-skip'
     C     r             DSPLY
     C   30
     COR 10              EVAL      r = 'or-taken'
     C     r             DSPLY
     C   10
     CAN 20
     COR 30              EVAL      r = 'mixed-and'
     C     r             DSPLY
     C   10
     CAN 30
     COR 20              EVAL      r = 'mixed-or'
     C     r             DSPLY
     C  N30
     CAN 10              EVAL      r = 'neg-and'
     C     r             DSPLY
     C   10
     CAN 20
     CANN30'three-term'  DSPLY
     C                   RETURN
