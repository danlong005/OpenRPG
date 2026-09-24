**FREE
DCL-S isActive IND;
DCL-S status INT(10);
DCL-S code CHAR(1) INZ('C');

// Each constant is a name and its value, as on IBM i
DCL-ENUM Colors QUALIFIED;
  RED 1;
  GREEN 2;
  BLUE CONST(3);
END-ENUM;

DCL-ENUM States QUALIFIED;
  isOpen 'O';
  isClosed 'C';
END-ENUM;

// An indicator holds *ON or *OFF
isActive = *ON;
IF isActive;
  DSPLY 'Active';
ENDIF;

isActive = *OFF;
IF NOT isActive;
  DSPLY 'Inactive';
ENDIF;

// Enum usage
status = 2;
IF status = Colors.GREEN;
  DSPLY 'Green';
ENDIF;

IF code = States.isClosed;
  DSPLY 'Closed';
ENDIF;

// IN tests a value against every constant of the enum
IF status IN Colors;
  DSPLY 'A color';
ENDIF;
code = 'X';
IF NOT (code IN States);
  DSPLY 'Not a state';
ENDIF;

*INLR = *ON;
