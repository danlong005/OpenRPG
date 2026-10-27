      * SETON and SETOFF: the indicators in positions 71-76 go on or off,
      * under a conditioning indicator too. LR can be one of them.
     D X               S              5P 0
     C                   SETON                                        5556
     C   55              Z-ADD     1             X
     C   55X             DSPLY
     C                   SETOFF                                         55
     C  N55              Z-ADD     2             X
     C     X             DSPLY
     C   56              SETOFF                                       56
     C  N56'off'         DSPLY
     C                   SETON                                        LR
