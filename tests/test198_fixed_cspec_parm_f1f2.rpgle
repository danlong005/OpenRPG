     H*PARM Factor 1 and Factor 2 (SC09-2508 p.929). On the call,
     H*factor 2 is copied into the result field; on return, the result
     H*field is copied into factor 1. Both operands are optional, and
     H*each move is an ordinary assignment bracketing the call itself.
     HDFTACTGRP(*NO)
     DSEEDN            S             10I 0
     DN                S             10I 0
     DOUTN             S             10I 0
     DSEEDMSG          S             10A
     DMSG              S             10A
     DOUTMSG           S             10A
     DR                S             30A
     C                   EVAL      SEEDN = 41
     C                   EVAL      N = 0
     C                   EVAL      OUTN = 0
     C                   EVAL      SEEDMSG = 'seeded'
     C                   EVAL      MSG = 'untouched'
     C                   EVAL      OUTMSG = 'none'
     C*Both operands: seed the parameter, then harvest it afterwards.
     C                   CALL      'ADDONE'
     C     OUTN          PARM      SEEDN         N
     C     OUTMSG        PARM      SEEDMSG       MSG
     C*Factor 2 is only read, so the seed fields are unchanged.
     C                   EVAL      R = '[' + %char(SEEDN) + ']'
     C     R             DSPLY
     C                   EVAL      R = '[' + %char(N) + ']'
     C     R             DSPLY
     C                   EVAL      R = '[' + %char(OUTN) + ']'
     C     R             DSPLY
     C                   EVAL      R = '[' + SEEDMSG + ']'
     C     R             DSPLY
     C                   EVAL      R = '[' + MSG + ']'
     C     R             DSPLY
     C                   EVAL      R = '[' + OUTMSG + ']'
     C     R             DSPLY
     C*Factor 2 only: seeded going in, nothing harvested, so OUTN
     C*keeps the value it already had.
     C                   EVAL      SEEDN = 100
     C                   EVAL      OUTN = -1
     C                   CALL      'ADDONE'
     C                   PARM      SEEDN         N
     C                   PARM                    MSG
     C                   EVAL      R = '[' + %char(N) + ']'
     C     R             DSPLY
     C                   EVAL      R = '[' + %char(OUTN) + ']'
     C     R             DSPLY
     C*Factor 1 only: whatever the parameter already holds is passed,
     C*and the returned value is copied out to factor 1.
     C                   CALL      'ADDONE'
     C     OUTN          PARM                    N
     C                   PARM                    MSG
     C                   EVAL      R = '[' + %char(N) + ']'
     C     R             DSPLY
     C                   EVAL      R = '[' + %char(OUTN) + ']'
     C     R             DSPLY
     C                   RETURN
