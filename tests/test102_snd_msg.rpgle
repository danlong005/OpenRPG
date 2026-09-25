**FREE

// Test 102: SND-MSG — send messages to stderr

DCL-S msg VARCHAR(100);

// *INFO — informational message
SND-MSG *INFO 'Starting process';

// *DIAG — diagnostic message
msg = 'Diagnostic: value out of range';
SND-MSG *DIAG msg;

// *COMP — completion message, sent to the caller
SND-MSG *COMP 'Processing complete' %TARGET(*CALLER);

// Plain form — defaults to *INFO
SND-MSG 'Default info message';

// *ESCAPE inside MONITOR — should be caught
MONITOR;
  SND-MSG *ESCAPE 'Something went wrong';
ON-ERROR;
  DSPLY 'Caught escape message';
ENDMON;

DSPLY 'Done';

RETURN;
