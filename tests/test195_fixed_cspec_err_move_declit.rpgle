     H*A decimal literal reaches codegen as a double, having lost the
     H*trailing zeros that decide its digit count -- and that digit
     H*count is what the move aligns against ('1.00' and '1.0' move
     H*differently). Refused rather than guessed at.
     HDFTACTGRP(*NO)
     DP5               S              5P0
     C                   MOVE      1.00          P5
     C                   RETURN
