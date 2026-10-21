     H*Calls COPYBACK, whose *ENTRY PARMs have factor 2 entries: each is
     H*copied into the caller's field when COPYBACK returns, whether it
     H*returns from its calculations (MODE 1), from a subroutine (MODE 2)
     H*or by reaching their end (MODE 3).
     HDFTACTGRP(*NO)
     DMODE             S              1A
     DN                S             10I 0
     DMSG              S             10A
     DR                S             30A
     C                   EVAL      MODE = '1'
     C                   EXSR      CALLIT
     C                   EVAL      MODE = '2'
     C                   EXSR      CALLIT
     C                   EVAL      MODE = '3'
     C                   EXSR      CALLIT
     C                   RETURN
     C     CALLIT        BEGSR
     C                   EVAL      N = 4
     C                   EVAL      MSG = 'before'
     C                   CALL      'COPYBACK'
     C                   PARM                    MODE
     C                   PARM                    N
     C                   PARM                    MSG
     C                   EVAL      R = MODE + ' ' + %CHAR(N) + ' ' + MSG
     C     R             DSPLY
     C                   ENDSR
