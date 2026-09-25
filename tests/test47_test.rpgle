**FREE
// Test 47: TEST
// In free form TEST needs the E extender; %ERROR then says whether the value
// was valid. TEST(E) checks a date, time or timestamp field's own value.
// TEST(DE), (TE) and (ZE) check a character or numeric field as a date, time
// or timestamp, in the format given or *ISO. Tests 289-290 are the forms IBM
// i rejects.
DCL-S myDate DATE;
DCL-S isoText CHAR(10) INZ('2024-03-15');
DCL-S badText CHAR(10) INZ('2024-02-30');
DCL-S usaText CHAR(10) INZ('03/15/2024');
DCL-S ymdNum PACKED(6:0) INZ(240315);
DCL-S timeText CHAR(8) INZ('24.00.01');

myDate = %DATE('2024-03-15');
TEST(E) myDate;
IF NOT %ERROR;
  DSPLY 'Date field valid';
ENDIF;

TEST(DE) isoText;
IF NOT %ERROR;
  DSPLY '2024-03-15 is an *ISO date';
ENDIF;

TEST(DE) *ISO badText;
IF %ERROR;
  DSPLY '2024-02-30 is not a date';
ENDIF;

TEST(DE) *USA usaText;
IF NOT %ERROR;
  DSPLY '03/15/2024 is a *USA date';
ENDIF;

TEST(DE) *YMD ymdNum;
IF NOT %ERROR;
  DSPLY '240315 is a *YMD date';
ENDIF;

TEST(TE) *ISO timeText;
IF %ERROR;
  DSPLY '24.00.01 is not a time';
ENDIF;

DSPLY 'Test done';

*INLR = *ON;
