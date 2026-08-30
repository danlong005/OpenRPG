     H*"MOVE and MOVEL are not allowed for float fields or literals"
     H*-- SC09-2508 p.633.
     HDFTACTGRP(*NO)
     DP5               S              5P 0
     DF8               S              8F
     C                   MOVE      P5            F8
     C                   RETURN
