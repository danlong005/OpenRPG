     HDFTACTGRP(*NO)
     Dsrc5             S              5A
     Dsrc12            S             12A
     Ddst              S             10A
     Dr                S             20A
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
