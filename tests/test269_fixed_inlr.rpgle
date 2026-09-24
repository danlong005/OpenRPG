     D n               S             10I 0 INZ(4)
     D r               S             10A
     C                   EVAL      n += 3
     C                   EVAL      *INLR = *ON
     C   LR              EVAL      r = 'LR is on'
     C   LRr             DSPLY
     C  NLR              EVAL      r = 'not shown'
     C  NLRr             DSPLY
     C                   EVAL      r = %CHAR(n)
     C     r             DSPLY
