     HDFTACTGRP(*NO)
      /COPY tests/fixed_copybook_nested_a.rpgle
     DTMPDSP           S             52A
     C                   EVAL      fieldA = 3
     C                   EVAL      fieldB = 4
     C                   EVAL      fieldA = fieldA + fieldB
     C                   EVAL      TMPDSP = %CHAR(fieldA)
     C     TMPDSP        DSPLY
     C                   RETURN
