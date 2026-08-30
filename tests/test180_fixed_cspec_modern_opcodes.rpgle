     HDFTACTGRP(*NO)
     Djs               S            200A   VARYING
     Dr                S             60A   VARYING
     Dperson           DS                  QUALIFIED
     Dname                           40A   VARYING
     Dage                            10I 0
     C                   EVAL      js = '{"name":"Alice","age":30}'
     C                   DATA-INTO person %DATA(js :
     C                             'case=any')
     C                   EVAL      r = 'Name: ' + person.name
     C     r             DSPLY
     C                   EVAL      r = 'Age: ' + %CHAR(person.age)
     C     r             DSPLY
     C                   SND-MSG   *INFO 'from fixed C-spec'
     C                   RETURN
