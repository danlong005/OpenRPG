     HDFTACTGRP(*NO)
      /COPY tests/fixed_copybook_nested_a.rpgle
     C                   EVAL      fieldA = 3
     C                   EVAL      fieldB = 4
     C                   EVAL      fieldA = fieldA + fieldB
     C     %CHAR(fieldA) DSPLY
     C                   RETURN
