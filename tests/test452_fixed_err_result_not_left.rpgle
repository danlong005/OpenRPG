      * The result field starts in position 52, not 50: RNF0262 on IBM i.
     D X               S              5P 0
     D Y               S              5P 0
     C                   Z-ADD     1             X
     C     X             ADD       1               Y
     C                   EVAL      *INLR = *ON
