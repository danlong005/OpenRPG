     H*A named PLIST (SC09-2508 p.930) supplies the parameter list for
     H*a CALL that names it in the Result field. The PLIST here is
     H*defined AFTER both CALLs that use it, which is legal and is why
     H*the transpiler resolves these at flush rather than in line order.
     HDFTACTGRP(*NO)
     DN                S             10I0
     DMSG              S             10A
     DR                S             30A
     C                   EVAL      N = 10
     C                   EVAL      MSG = 'before'
     C*Both calls share one parameter list.
     C                   CALL      'ADDONE'      MYLIST
     C                   EVAL      R = '[' + %char(N) + ']'
     C     R             DSPLY
     C                   CALL      'ADDONE'      MYLIST
     C                   EVAL      R = '[' + %char(N) + ']'
     C     R             DSPLY
     C*The name is matched case-insensitively, as RPG names are.
     C                   CALL      'ADDONE'      MyList
     C                   EVAL      R = '[' + %char(N) + ']'
     C     R             DSPLY
     C*A conditioning indicator still wraps the whole call.
     C                   EVAL      *IN10 = *OFF
     C   10              CALL      'ADDONE'      MYLIST
     C                   EVAL      R = '[' + %char(N) + ']'
     C     R             DSPLY
     C                   EVAL      *IN10 = *ON
     C   10              CALL      'ADDONE'      MYLIST
     C                   EVAL      R = '[' + %char(N) + ']'
     C     R             DSPLY
     C                   EVAL      R = '[' + MSG + ']'
     C     R             DSPLY
     C*The definition itself, after every CALL that uses it.
     C     MYLIST        PLIST
     C                   PARM                    N
     C                   PARM                    MSG
     C                   RETURN
