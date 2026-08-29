     H*'Time format *USA is not allowed for movement between Time and
     H*numeric fields' (p.405) -- its AM/PM suffix is not a digit.
     HDFTACTGRP(*NO)
     DTFLD             S               T
     DN6               S              6P0
     C     *USA          MOVE      TFLD          N6
     C                   RETURN
