     H*A date result field is still refused: MOVE/MOVEL date and time
     H*conversion is deferred, not implemented -- see TODO.md.
     HDFTACTGRP(*NO)
     DA                S             10A
     DDT               S               D
     C                   MOVE      A             DT
     C                   RETURN
