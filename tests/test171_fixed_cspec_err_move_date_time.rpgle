     H*Date and time are disjoint calendars: the manual's combination
     H*list has no Date-to-Time or Time-to-Date entry, only routes
     H*through a timestamp, which carries both.
     HDFTACTGRP(*NO)
     DDFLD             S               D
     DTFLD             S               T
     C                   MOVE      DFLD          TFLD
     C                   RETURN
