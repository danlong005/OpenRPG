     H*A CALL may name a PLIST defined later in the source, so an
     H*unknown name is only detectable once the run ends -- but it is
     H*detected, not silently emitted as a call with no arguments.
     HDFTACTGRP(*NO)
     DN                S             10I 0
     C                   CALL      'ADDONE'      NOSUCH
     C                   RETURN
