     H*Calls ADDTWO, whose parameter list comes from its *ENTRY PLIST.
     HDFTACTGRP(*NO)
     DN                S             10I 0
     DMSG              S             10A
     DR                S             30A
     C                   EVAL      N = 40
     C                   EVAL      MSG = 'before'
     C                   CALL      'ADDTWO'
     C                   PARM                    N
     C                   PARM                    MSG
     C                   EVAL      R = '[' + %char(N) + ']'
     C     R             DSPLY
     C                   EVAL      R = '[' + MSG + ']'
     C     R             DSPLY
     C*Called again through a named PLIST, to show the two features
     C*meet: the list is defined below, after the CALL that uses it.
     C                   CALL      'ADDTWO'      ARGS
     C                   EVAL      R = '[' + %char(N) + ']'
     C     R             DSPLY
     C     ARGS          PLIST
     C                   PARM                    N
     C                   PARM                    MSG
     C                   RETURN
