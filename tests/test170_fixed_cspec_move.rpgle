     HDFTACTGRP(*NO)
     Dsrc5                       5     A
     Dsrc12                     12     A
     Ddst                       10     A
     Dr                         20     A
     C                   EVAL      src5 = 'AB'
     C                   EVAL      src12 = 'ABCDEFGHIJKL'
     C                   EVAL      dst = 'ZZZZZZZZZZ'
     C                   MOVEL     src5          dst
     C                   EVAL      r = '[' + dst + ']'
     C     r             DSPLY
     C                   EVAL      dst = 'ZZZZZZZZZZ'
     C                   MOVE      src5          dst
     C                   EVAL      r = '[' + dst + ']'
     C     r             DSPLY
     C                   EVAL      dst = 'ZZZZZZZZZZ'
     C                   MOVEL(P)  src5          dst
     C                   EVAL      r = '[' + dst + ']'
     C     r             DSPLY
     C                   EVAL      dst = 'ZZZZZZZZZZ'
     C                   MOVE(P)   src5          dst
     C                   EVAL      r = '[' + dst + ']'
     C     r             DSPLY
     C                   EVAL      dst = 'ZZZZZZZZZZ'
     C                   MOVEL     src12         dst
     C                   EVAL      r = '[' + dst + ']'
     C     r             DSPLY
     C                   EVAL      dst = 'ZZZZZZZZZZ'
     C                   MOVE      src12         dst
     C                   EVAL      r = '[' + dst + ']'
     C     r             DSPLY
     C                   EVAL      dst = 'ZZZZZZZZZZ'
     C                   MOVEL     'XY'          dst
     C                   EVAL      r = '[' + dst + ']'
     C     r             DSPLY
     C                   RETURN
