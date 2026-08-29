     H*Factor 2 on an *ENTRY PARM copies the parameter back when the
     H*program returns — a copy at every exit point, which this
     H*line-by-line transpiler cannot place.
     HDFTACTGRP(*NO)
     DN                S             10I0
     DOUT              S             10I0
     C     *ENTRY        PLIST
     C                   PARM      OUT           N
     C                   RETURN
