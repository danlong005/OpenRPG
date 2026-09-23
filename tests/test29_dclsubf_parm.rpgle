**FREE

// DCL-SUBF is an alternative syntax for data structure subfields
DCL-DS employee QUALIFIED;
  DCL-SUBF name VARCHAR(30);
  DCL-SUBF age INT(10);
  DCL-SUBF salary PACKED(9:2);
END-DS;

// DCL-PARM is an alternative syntax for procedure parameters
DCL-PR addNums INT(10);
  DCL-PARM p1 INT(10) VALUE;
  DCL-PARM p2 INT(10) VALUE;
END-PR;
DCL-S result INT(10);

employee.name = 'Alice';
employee.age = 30;
employee.salary = 75000.50;

DSPLY employee.name;
DSPLY %CHAR(employee.age);
DSPLY %CHAR(employee.salary);

result = addNums(10 : 20);
DSPLY %CHAR(result);

*INLR = *ON;

DCL-PROC addNums;
  DCL-PI addNums INT(10);
    DCL-PARM p1 INT(10) VALUE;
    DCL-PARM p2 INT(10) VALUE;
  END-PI;
  RETURN p1 + p2;
END-PROC;
