     HDFTACTGRP(*NO)
     Djs                        200    A   VARYING
     Dr                         60     A   VARYING
     Dperson           DS                  QUALIFIED
     Dname                      40     A   VARYING
     Dage                       10     I0
     C                   EVAL      js = '{"name":"Alice","age":30}'
     C                   DATA-INTO person %DATA(js :
     C                             'case=any')
     C                   EVAL      r = 'Name: ' + person.name
     C     r             DSPLY
     C                   EVAL      r = 'Age: ' + %CHAR(person.age)
     C     r             DSPLY
     C                   SND-MSG   *INFO 'from fixed C-spec'
     C                   RETURN
