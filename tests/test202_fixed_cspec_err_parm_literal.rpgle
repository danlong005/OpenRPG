     H*RPG passes parameters by address, so the Result field of a PARM
     H*must be a field with storage -- not a literal.
     HDFTACTGRP(*NO)
     DN                S             10I 0
     C                   CALL      'ADDONE'
     C                   PARM                    'abc'
     C                   RETURN
