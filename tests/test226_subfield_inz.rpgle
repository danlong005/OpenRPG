     HDFTACTGRP(*NO)
     D* INZ on a DS subfield has nowhere to live on DSField, so it must be
     D* rejected rather than dropped -- dropping it silently is exactly the
     D* defect that made standalone INZ a no-op.
     DPART             DS                  QUALIFIED
     DKEY                            10A   INZ('X')
      /free
       DSPLY part.key;
       *INLR = *ON;
      /end-free
