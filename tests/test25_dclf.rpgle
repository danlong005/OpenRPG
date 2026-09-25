**FREE
// DCL-F declares a file - we stub it as a placeholder.
// RPTFILE is a program-described printer file, PRINTER(132): a printer file
// with no DDS of its own. Externally described (PRINTER alone), its record
// format would take the file's own name, which RPG rejects (IBM: RNF2121).
DCL-F CUSTFILE DISK;
DCL-F RPTFILE PRINTER(132);

// We can still use other features alongside file declarations
DCL-S msg VARCHAR(50);
msg = 'File declarations parsed';
DSPLY msg;

*INLR = *ON;
