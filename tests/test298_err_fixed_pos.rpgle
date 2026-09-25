     H*POS IS THE FREE-FORM KEYWORD FOR A SUBFIELD'S START. A FIXED-FORM
     H*DEFINITION GIVES FROM AND TO POSITIONS INSTEAD; IBM I REJECTS POS
     H*THERE (RNF3555).
     HDFTACTGRP(*NO)
     DREC              DS                  QUALIFIED
     DID                             10I 0 POS(1)
     C                   EVAL      REC.ID = 1
     C                   RETURN
