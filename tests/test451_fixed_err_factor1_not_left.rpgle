      * Factor 1 starts in position 14, not 12: RNF0262 on IBM i.
     D X               S              5P 0
     D Y               S              5P 0
     C                   Z-ADD     1             X
     C       X           ADD       1             Y
     C                   EVAL      *INLR = *ON
