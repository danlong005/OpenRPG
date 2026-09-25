     H*AN *ISO DATE IS TEN CHARACTERS. IBM I REJECTS MOVING ONE INTO A
     H*SIX-CHARACTER FIELD WHEN THE PROGRAM IS COMPILED (RNF7512).
     HDFTACTGRP(*NO)
     DDFLD             S               D
     DC6               S              6A
     C     *ISO          MOVE      '1996-04-15'  DFLD
     C     *ISO          MOVEL     DFLD          C6
     C     C6            DSPLY
     C                   RETURN
