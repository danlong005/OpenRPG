# OpenRPG User's Guide

OpenRPG transpiles IBM RPG IV source code into portable C++17 and optionally compiles it to a native executable. Both free-format and classic column-based [fixed-format](#fixed-format-source) source are accepted, and the two can be mixed in one file. Programs can run on macOS, Linux, or any platform with a C++ compiler — no IBM i required.

---

## Table of Contents

1. [Installation](#installation)
2. [Quick Start](#quick-start)
3. [CLI Reference](#cli-reference)
4. [Language Basics](#language-basics)
5. [Data Types](#data-types)
6. [Variables and Constants](#variables-and-constants)
7. [Data Structures](#data-structures)
8. [Arrays](#arrays)
9. [Varying-Dimension Arrays](#varying-dimension-arrays)
10. [Control Flow](#control-flow)
11. [Procedures](#procedures)
12. [Procedure Overloading](#procedure-overloading)
13. [Built-In Functions](#built-in-functions)
14. [Error Handling](#error-handling)
15. [Operation Extenders](#operation-extenders)
16. [Enumerations](#enumerations)
17. [Program Status Data Structure](#program-status-data-structure)
18. [Data Areas](#data-areas)
19. [SND-MSG](#snd-msg)
20. [Embedded SQL](#embedded-sql)
21. [Record-Level Access](#record-level-access)
22. [Display Files (WORKSTN)](#display-files-workstn)
23. [Program-Described Files (I-Specs and O-Specs)](#program-described-files-i-specs-and-o-specs)
24. [DATA-INTO and DATA-GEN](#data-into-and-data-gen)
25. [XML-INTO](#xml-into)
26. [Fixed-Format Source](#fixed-format-source)
27. [Database Connections](#database-connections)
28. [Multi-Module Programs](#multi-module-programs)
29. [Environment Variables](#environment-variables)
30. [Testing](#testing)

---

## Installation

Download a prebuilt installer from the
[Releases page](https://github.com/danlong005/OpenRPG/releases). Each one puts
`rpgc` on your PATH and brings the runtime headers with it — there is nothing
to build and no compiler toolchain to set up first.

| Platform | Download | Architectures |
|----------|----------|---------------|
| macOS | `openrpg-<version>.pkg` | Apple Silicon (arm64) |
| Debian / Ubuntu | `rpgc_<version>_amd64.deb`, `rpgc_<version>_arm64.deb` | x86_64, ARM64 |
| RHEL / Fedora | `rpgc-<version>-1.x86_64.rpm`, `rpgc-<version>-1.aarch64.rpm` | x86_64, ARM64 |
| Windows | `openrpg-<version>-windows-x64.exe`, `openrpg-<version>-windows-arm64.exe` | x86_64, ARM64 |

If your machine is not on that list, [build from
source](#building-from-source) instead.

### macOS

The `.pkg` bundles both `rpgc` and the display file compiler `dspfc`.

Two things must be present first. **Xcode Command Line Tools** provide the
`clang++` that `rpgc` invokes to build the programs it compiles, and the
ncurses headers display file programs need:

```bash
xcode-select --install     # skip if `xcode-select -p` already prints a path
```

And **unixODBC**, which `rpgc` itself links against:

```bash
brew install unixodbc
```

(Installing Homebrew pulls in the Command Line Tools, so if you already have
`brew` you almost certainly have them.)

OpenRPG is not code-signed with an Apple Developer certificate, so Gatekeeper
will block the installer. Clear the quarantine flag, then open it:

```bash
xattr -cr ~/Downloads/openrpg-*.pkg
```

Double-click the `.pkg` and follow the prompts.

### Linux

The packages declare everything they need — the C++ compiler `rpgc` shells out
to, the unixODBC headers and library, and the ncurses headers display file
programs link against — so the package manager pulls all of it in for you.

**Debian / Ubuntu:**
```bash
sudo dpkg -i rpgc_*.deb
sudo apt-get install -f      # resolves any missing dependencies
```

**RHEL / Fedora:**
```bash
sudo dnf install ./rpgc-*.rpm
```

On Linux the display file compiler ships as its own `dspfc` package. `rpgc`
recommends it, so most package managers install it alongside — if you are
writing [display file programs](#display-files-workstn) and `dspfc` is not on
your PATH afterwards, install it the same way:

```bash
sudo dpkg -i dspfc_*.deb          # Debian/Ubuntu
sudo dnf install ./dspfc-*.rpm    # RHEL/Fedora
```

### Windows

Run the installer and follow the prompts. It adds `rpgc` to your PATH.

**No other prerequisites are needed.** The installer bundles a self-contained
C++ toolchain (a trimmed [llvm-mingw](https://github.com/mstorsjo/llvm-mingw))
for `rpgc` and `dspfc` to build the programs they compile, plus a PDCurses
build for display file programs. You do not need MSYS2 or Visual Studio.

Embedded SQL is the one exception: it needs a platform ODBC driver installed
separately — see [Database Connections](#database-connections).

> **ARM64 note:** of the ODBC drivers this guide covers, only Microsoft's ODBC
> Driver 18 for SQL Server (18.2+) ships a native ARM64 Windows build. The
> SQLite, PostgreSQL and MySQL/MariaDB installers are x86_64-only, so SQL and
> RLA features against those three are not available on Windows ARM64 without
> building a driver yourself.

### Checking the Install

```bash
rpgc -v          # prints the version
dspfc -v         # only if you installed the display file compiler
```

### Database Drivers

The installers cover the compiler itself. Embedded SQL and record-level access
additionally need an ODBC driver for whichever database you are using — see
[Database Connections](#database-connections) for per-database setup.

---

### Building from Source

Build from source if there is no prebuilt package for your machine — an Intel
Mac, a distribution that takes neither `.deb` nor `.rpm`, or any other
platform with a C++17 compiler.

**Prerequisites:**

- **C++17 compiler** (clang++ or g++) — `rpgc` also invokes it at runtime to
  build the programs it compiles, so it is needed after installation too
- **Flex** (lexer generator)
- **Bison** (parser generator)
- **unixODBC + a database driver** — only for embedded SQL and RLA
- **ncurses** — only for display file programs; on macOS it comes with the
  Command Line Tools, on Linux it is a separate `-dev`/`-devel` package

```bash
# macOS — clang++ and ncurses come from the Xcode Command Line Tools
xcode-select --install
brew install flex bison unixodbc

# Debian/Ubuntu
sudo apt install flex bison g++ unixodbc-dev libncurses-dev

# RHEL/Fedora
sudo dnf install flex bison gcc-c++ unixODBC-devel ncurses-devel
```

On Windows, install [MSYS2](https://www.msys2.org/) and build from the
**MINGW64** shell (or **CLANGARM64** on ARM64, which has no native gcc):

```bash
pacman -S mingw-w64-x86_64-gcc mingw-w64-x86_64-flex mingw-w64-x86_64-bison make
```

Windows has a built-in ODBC driver manager, so unixODBC is not needed there.

**Build:**

The display file compiler lives in a submodule, so clone recursively:

```bash
git clone --recursive https://github.com/danlong005/OpenRPG.git
cd OpenRPG
make
```

This produces the `rpgc` executable in the working directory. If you cloned
without `--recursive`, run `git submodule update --init` before building.

**Install:**

```bash
sudo make install-all               # rpgc + dspfc, into /usr/local
make install-all PREFIX=~/.local    # or a user-local prefix, no sudo
```

Use `make install` instead of `make install-all` to install `rpgc` on its own,
without the display file compiler.

This installs the `rpgc` binary to `$PREFIX/bin/` and the runtime headers to
`$PREFIX/share/rpgc/runtime/`. When compiling a program, OpenRPG finds those
headers automatically — it checks relative to the binary, then the current
directory, then the install prefix.

To remove it again:

```bash
sudo make uninstall
sudo make uninstall-dspf     # if you installed dspfc too
```

---

## Quick Start

**hello.rpgle:**
```rpgle
**FREE
DCL-S msg VARCHAR(50);
msg = 'Hello from RPG!';
DSPLY msg;
RETURN;
```

```bash
./rpgc hello.rpgle
./hello
# Output: Hello from RPG!
```

---

## CLI Reference

```
rpgc <source-file> [options]
```

| Flag | Description |
|------|-------------|
| `-o file` | Output file (executable by default, or C++ file with `-S`) |
| `-S` | Emit C++ source only, do not compile |
| `-c` | Compile to an object file, do not link |
| `-g` | Compile with debug info, for GDB/LLDB/VS Code |
| `--keep-cpp` | Keep the intermediate `.cpp` file after compiling |
| `-v`, `--version` | Print the version and exit |

Additional `.o` files listed after the source file are passed through to the
linker — see [Multi-Module Programs](#multi-module-programs).

### File Extensions

| Extension | Description |
|-----------|-------------|
| `.rpgle` | Standard RPG IV source |
| `.sqlrpgle` | RPG IV with embedded SQL (automatically links ODBC) |

When the input file has a `.sqlrpgle` extension, OpenRPG automatically adds ODBC include paths and linker flags during compilation. A program that declares a `WORKSTN` file likewise gets the screen runtime's linker flag added automatically — see [Display Files](#display-files-workstn).

The extension does **not** select the source format. Free-format and fixed-format are distinguished by the content of the source itself; see [Fixed-Format Source](#fixed-format-source).

### Examples

```bash
# Compile to executable (default)
./rpgc program.rpgle              # produces ./program
./rpgc program.rpgle -o myapp     # produces ./myapp

# Emit C++ source only
./rpgc program.rpgle -S           # produces ./program.cpp
./rpgc program.rpgle -S -o out.cpp

# Keep intermediate C++ file
./rpgc program.rpgle --keep-cpp   # produces ./program and ./program.cpp

# SQL program (auto-links ODBC)
./rpgc report.sqlrpgle            # produces ./report (linked with -lodbc)
```

---

## Language Basics

All programs begin with `**FREE` to indicate free-format RPG IV:

```rpgle
**FREE

// Declarations go here
DCL-S name VARCHAR(50);

// Executable statements
name = 'World';
DSPLY 'Hello, ' + %TRIM(name) + '!';

*INLR = *ON;
RETURN;
```

### Comments

```rpgle
// Single-line comment
```

### Statement Terminator

Statements end with a semicolon (`;`).

---

## Data Types

| RPG Type | Example | Description |
|----------|---------|-------------|
| `CHAR(n)` | `DCL-S x CHAR(10);` | Fixed-length string |
| `VARCHAR(n)` | `DCL-S x VARCHAR(50);` | Variable-length string |
| `INT(10)` | `DCL-S x INT(10);` | 32-bit integer |
| `INT(20)` | `DCL-S x INT(20);` | 64-bit integer |
| `UNS(10)` | `DCL-S x UNS(10);` | Unsigned 32-bit integer |
| `PACKED(n:d)` | `DCL-S x PACKED(9:2);` | Packed decimal (stored as double) |
| `ZONED(n:d)` | `DCL-S x ZONED(9:2);` | Zoned decimal (stored as double) |
| `FLOAT(4)` | `DCL-S x FLOAT(4);` | Single-precision float |
| `FLOAT(8)` | `DCL-S x FLOAT(8);` | Double-precision float |
| `IND` | `DCL-S x IND;` | Boolean indicator |
| `DATE` | `DCL-S x DATE;` | Date value |
| `TIME` | `DCL-S x TIME;` | Time value |
| `TIMESTAMP` | `DCL-S x TIMESTAMP;` | Timestamp value |
| `POINTER` | `DCL-S x POINTER;` | Memory pointer |
| `BOOLEAN` | `DCL-S x BOOLEAN;` | Boolean (true/false) |

---

## Variables and Constants

### Variables

```rpgle
DCL-S counter INT(10);
DCL-S name VARCHAR(50) INZ('Default');
DCL-S rate PACKED(7:2) INZ(15.50);
DCL-S isActive IND INZ(*ON);
```

### Named Constants

```rpgle
DCL-C MAX_SIZE 100;
DCL-C GREETING 'Hello';
DCL-C PI 3.14159;
```

### Figurative Constants

| Constant | Description |
|----------|-------------|
| `*BLANKS` | Empty string / spaces |
| `*ZEROS` | Numeric zero or string of zeros |
| `*HIVAL` | Maximum value for the type |
| `*LOVAL` | Minimum value for the type |
| `*ON` | Boolean true / '1' |
| `*OFF` | Boolean false / '0' |
| `*NULL` | Null pointer |
| `*ALL'x'` | Repeated character pattern |

---

## Data Structures

### Basic Data Structure

```rpgle
DCL-DS employee QUALIFIED;
  id INT(10);
  name VARCHAR(50);
  salary PACKED(9:2);
END-DS;

employee.id = 1;
employee.name = 'Alice';
employee.salary = 75000.00;
DSPLY employee.name;
```

### Array of Data Structures

```rpgle
DCL-DS item QUALIFIED DIM(10);
  code CHAR(5);
  description VARCHAR(50);
  price PACKED(7:2);
END-DS;

item(1).code = 'A001';
item(1).description = 'Widget';
item(1).price = 9.99;
```

### LIKEDS

```rpgle
DCL-DS address QUALIFIED;
  street VARCHAR(100);
  city VARCHAR(50);
  state CHAR(2);
END-DS;

DCL-DS shipping LIKEDS(address);
shipping.city = 'Springfield';
```

---

## Arrays

Arrays in RPG are **1-based** (the first element is index 1).

```rpgle
// Fixed-size array
DCL-S names VARCHAR(50) DIM(5);
names(1) = 'Alice';
names(2) = 'Bob';
DSPLY names(1);  // Alice

// Variable-size array
DCL-S items VARCHAR(50) DIM(*VAR: 100);
%ELEM(items) = 3;
items(1) = 'First';

// Array initialization
DCL-S scores INT(10) DIM(3) INZ(0);
```

### Array Operations

```rpgle
DCL-S names VARCHAR(20) DIM(5);
DCL-S idx INT(10);

names(1) = 'Charlie';
names(2) = 'Alice';
names(3) = 'Bob';

SORTA names;  // Sort ascending

idx = %LOOKUP('Bob' : names);
DSPLY %CHAR(idx);  // Position of 'Bob' after sort

// FOR-EACH loop
FOR-EACH name IN names;
  IF name <> '';
    DSPLY name;
  ENDIF;
ENDFOR;
```

---

## Control Flow

### IF / ELSEIF / ELSE

```rpgle
IF score >= 90;
  grade = 'A';
ELSEIF score >= 80;
  grade = 'B';
ELSE;
  grade = 'C';
ENDIF;
```

### SELECT / WHEN / OTHER

```rpgle
SELECT;
  WHEN status = 'A';
    DSPLY 'Active';
  WHEN status = 'I';
    DSPLY 'Inactive';
  OTHER;
    DSPLY 'Unknown';
ENDSL;
```

### DOW (Do While) / DOU (Do Until)

```rpgle
// Do while count < 10
DOW count < 10;
  count += 1;
ENDDO;

// Do until found
DOU %FOUND;
  // search logic
ENDDO;
```

### FOR Loop

```rpgle
FOR i = 1 TO 10;
  DSPLY %CHAR(i);
ENDFOR;

FOR i = 10 DOWNTO 1 BY 2;
  DSPLY %CHAR(i);
ENDFOR;
```

---

## Procedures

### Defining and Calling Procedures

```rpgle
**FREE

// Forward declaration (prototype)
DCL-PR Add INT(10);
  a INT(10) VALUE;
  b INT(10) VALUE;
END-PR;

// Call it
DCL-S result INT(10);
result = Add(3 : 5);
DSPLY %CHAR(result);  // 8

RETURN;

// Implementation
DCL-PROC Add;
  DCL-PI INT(10);
    a INT(10) VALUE;
    b INT(10) VALUE;
  END-PI;

  RETURN a + b;
END-PROC;
```

### Optional Parameters

```rpgle
DCL-PROC Greet;
  DCL-PI VARCHAR(100);
    name VARCHAR(50) VALUE;
    title VARCHAR(20) VALUE OPTIONS(*NOPASS);
  END-PI;

  IF %PARMS >= 2;
    RETURN 'Hello, ' + title + ' ' + name;
  ELSE;
    RETURN 'Hello, ' + name;
  ENDIF;
END-PROC;
```

---

## Built-In Functions

### String Functions

```rpgle
DCL-S s VARCHAR(100);

s = '  Hello World  ';
DSPLY %TRIM(s);         // 'Hello World'
DSPLY %LEN(s);          // 15
DSPLY %SUBST(s:3:5);    // 'Hello'
DSPLY %SCAN('World':s); // 9
DSPLY %REPLACE('RPG':'Hello World':1:5);  // 'RPG World'
DSPLY %LOWER('HELLO');  // 'hello'
DSPLY %UPPER('hello');  // 'HELLO'
```

### Numeric Functions

```rpgle
DSPLY %CHAR(%ABS(-42));     // 42
DSPLY %CHAR(%INT(3.7));     // 3
DSPLY %CHAR(%DEC(3.7:5:2)); // 3.70
DSPLY %CHAR(%REM(17:5));    // 2
DSPLY %CHAR(%SQRT(144));    // 12
```

### Date/Time Functions

```rpgle
DCL-S today DATE INZ(%DATE);
DCL-S now TIME INZ(%TIME);
DCL-S ts TIMESTAMP INZ(%TIMESTAMP);
DCL-S future DATE;

future = today + %DAYS(30);
DSPLY %CHAR(future);

DCL-S daysBetween INT(10);
daysBetween = %DIFF(future : today : *DAYS);
DSPLY %CHAR(daysBetween);  // 30
```

---

## Error Handling

### MONITOR / ON-ERROR

```rpgle
MONITOR;
  result = numerator / denominator;
ON-ERROR;
  DSPLY 'Division error!';
  result = 0;
ENDMON;
```

### *PSSR (Program Status Subroutine)

```rpgle
BEGSR *PSSR;
  DSPLY 'Unhandled error: ' + %CHAR(%STATUS);
ENDSR;
```

### ON-EXIT

```rpgle
DCL-PROC ProcessData;
  DCL-PI;
  END-PI;
  DCL-S abnormal IND;

  // ... processing ...

  ON-EXIT abnormal;
    IF abnormal;
      DSPLY 'Procedure ended abnormally';
    ENDIF;
    // cleanup code always runs
END-PROC;
```

---

## Embedded SQL

Programs using embedded SQL should use the `.sqlrpgle` file extension. This tells OpenRPG to automatically link the ODBC library.

### Basic SQL Operations

```rpgle
**FREE

DCL-S connStr VARCHAR(200);
DCL-S empName VARCHAR(50);
DCL-S empId   INT(10);

// Connect to database
connStr = 'Driver={SQLite3};Database=myapp.sqlite;';
EXEC SQL CONNECT USING :connStr;

// Create a table
EXEC SQL CREATE TABLE employees (
  id INTEGER PRIMARY KEY,
  name VARCHAR(50),
  salary DECIMAL(9,2)
);

// Insert data using host variables
empId = 1;
empName = 'Alice';
EXEC SQL INSERT INTO employees (id, name, salary)
  VALUES(:empId, :empName, 75000.00);

// Query data
EXEC SQL SELECT name INTO :empName
  FROM employees WHERE id = :empId;
DSPLY empName;

// Check SQLCODE after operations
IF SQLCOD <> 0;
  DSPLY 'SQL error: ' + %CHAR(SQLCOD);
ENDIF;

// Clean up
EXEC SQL DROP TABLE employees;
EXEC SQL DISCONNECT;

*INLR = *ON;
RETURN;
```

### Cursors

Use cursors to iterate over result sets:

```rpgle
**FREE

DCL-S connStr VARCHAR(200);
DCL-S name    VARCHAR(50);
DCL-S salary  PACKED(9:2);

connStr = 'Driver={SQLite3};Database=myapp.sqlite;';
EXEC SQL CONNECT USING :connStr;

// Declare a cursor
EXEC SQL DECLARE empCur CURSOR FOR
  SELECT name, salary FROM employees
  ORDER BY name;

// Open and fetch in a loop
EXEC SQL OPEN empCur;

EXEC SQL FETCH empCur INTO :name, :salary;
DOW SQLCOD = 0;
  DSPLY name + ': ' + %CHAR(salary);
  EXEC SQL FETCH empCur INTO :name, :salary;
ENDDO;

EXEC SQL CLOSE empCur;
EXEC SQL DISCONNECT;
```

### Cursors with Data Structures

You can fetch directly into a qualified data structure:

```rpgle
DCL-DS emp QUALIFIED;
  id   INT(10);
  name VARCHAR(50);
  salary PACKED(9:2);
END-DS;

EXEC SQL DECLARE c1 CURSOR FOR
  SELECT id, name, salary FROM employees ORDER BY id;

EXEC SQL OPEN c1;

EXEC SQL FETCH NEXT FROM c1 INTO :emp;
DOW SQLSTATE < '02000';
  DSPLY %CHAR(emp.id) + ' ' + %TRIM(emp.name);
  EXEC SQL FETCH NEXT FROM c1 INTO :emp;
ENDDO;

EXEC SQL CLOSE c1;
```

### Parameterized Cursors

Host variables in the WHERE clause are bound when the cursor is opened:

```rpgle
DCL-S minSalary PACKED(9:2);

EXEC SQL DECLARE salCur CURSOR FOR
  SELECT name, salary FROM employees
  WHERE salary > :minSalary;

minSalary = 70000.00;
EXEC SQL OPEN salCur;

EXEC SQL FETCH salCur INTO :name, :salary;
DOW SQLCOD = 0;
  DSPLY name;
  EXEC SQL FETCH salCur INTO :name, :salary;
ENDDO;

EXEC SQL CLOSE salCur;
```

### Dynamic SQL

```rpgle
DCL-S sqlStr VARCHAR(256);
DCL-S id     INT(10);
DCL-S name   VARCHAR(50);

// Execute Immediate — for DDL or one-off statements
sqlStr = 'CREATE TABLE temp (id INTEGER, name TEXT)';
EXEC SQL EXECUTE IMMEDIATE :sqlStr;

// Prepare + Execute — for repeated statements with parameters
sqlStr = 'INSERT INTO temp VALUES(?, ?)';
EXEC SQL PREPARE ins1 FROM :sqlStr;

id = 1;
name = 'Alice';
EXEC SQL EXECUTE ins1 USING :id, :name;

id = 2;
name = 'Bob';
EXEC SQL EXECUTE ins1 USING :id, :name;
```

### Multi-Row Operations

```rpgle
DCL-S ids      INT(10) DIM(10);
DCL-S names    VARCHAR(50) DIM(10);
DCL-S nRows    INT(10);

// Multi-row insert from arrays
ids(1) = 1;  names(1) = 'Alice';
ids(2) = 2;  names(2) = 'Bob';
ids(3) = 3;  names(3) = 'Charlie';

nRows = 3;
EXEC SQL INSERT INTO employees (id, name)
  VALUES(:ids, :names)
  FOR :nRows ROWS;

// Multi-row fetch into arrays
EXEC SQL DECLARE c1 CURSOR FOR
  SELECT id, name FROM employees ORDER BY id;
EXEC SQL OPEN c1;

nRows = 10;
EXEC SQL FETCH c1 FOR :nRows ROWS
  INTO :ids, :names;

EXEC SQL CLOSE c1;
```

### Transaction Control

```rpgle
EXEC SQL INSERT INTO accounts (id, balance) VALUES(1, 1000.00);
EXEC SQL INSERT INTO accounts (id, balance) VALUES(2, 500.00);

// Savepoint for partial rollback
EXEC SQL SAVEPOINT before_transfer;

EXEC SQL UPDATE accounts SET balance = balance - 200 WHERE id = 1;
EXEC SQL UPDATE accounts SET balance = balance + 200 WHERE id = 2;

// Something went wrong? Rollback to savepoint
EXEC SQL ROLLBACK TO SAVEPOINT before_transfer;

// Or commit everything
EXEC SQL COMMIT;
```

### GET DIAGNOSTICS

```rpgle
DCL-S rowCount INT(10);

EXEC SQL UPDATE employees SET salary = salary * 1.1
  WHERE department = 'ENG';

EXEC SQL GET DIAGNOSTICS :rowCount = ROW_COUNT;
DSPLY 'Updated ' + %CHAR(rowCount) + ' employees';
```

### SQLCODE and SQLSTATE

After each SQL statement, you can check:

| Variable | Description |
|----------|-------------|
| `SQLCOD` | Numeric return code (0 = success, 100 = not found, negative = error) |
| `SQLSTT` | 5-character SQLSTATE code ('00000' = success, '02000' = not found) |

```rpgle
EXEC SQL SELECT name INTO :empName FROM employees WHERE id = 999;

IF SQLCOD = 100;
  DSPLY 'Employee not found';
ELSEIF SQLCOD < 0;
  DSPLY 'SQL error: ' + %CHAR(SQLCOD);
ENDIF;
```

---

## Database Connections

OpenRPG uses ODBC for database access, making it portable across databases. You connect using a connection string with `EXEC SQL CONNECT USING`.

### Prerequisites

**macOS / Linux:**
1. Install **unixODBC** (the driver manager)
2. Install a **database-specific ODBC driver**
3. Register the driver in `/etc/odbcinst.ini` or (on macOS with Homebrew) `/opt/homebrew/etc/odbcinst.ini`

**Windows:**
1. ODBC driver manager is **built in** — no additional install needed
2. Install a **database-specific ODBC driver** (typically an MSI installer)
3. Drivers are registered automatically; manage them via the **ODBC Data Source Administrator** (search "ODBC" in the Start menu)

### SQLite

SQLite is ideal for local development and testing — no server required.

**Install:**
```bash
# macOS
brew install sqliteodbc

# Linux (Debian/Ubuntu)
sudo apt install libsqliteodbc
```

**Register driver** (macOS — add to `/opt/homebrew/etc/odbcinst.ini`):
```ini
[SQLite3]
Description=SQLite3 ODBC driver
Driver=/opt/homebrew/lib/libsqlite3odbc.dylib
Threading=2
```

**Register driver** (Linux — add to `/etc/odbcinst.ini`):
```ini
[SQLite3]
Description=SQLite3 ODBC driver
Driver=/usr/lib/x86_64-linux-gnu/odbc/libsqlite3odbc.so
Threading=2
```

**Connect:**
```rpgle
DCL-S connStr VARCHAR(200);
connStr = 'Driver={SQLite3};Database=/path/to/mydb.sqlite;';
EXEC SQL CONNECT USING :connStr;
```

**Windows:**

Download the SQLite ODBC driver from [http://www.ch-werner.de/sqliteodbc/](http://www.ch-werner.de/sqliteodbc/) and run the MSI installer. The driver is registered automatically. Use the same connection string as above.

The database file is created automatically if it doesn't exist.

### PostgreSQL

**Install:**
```bash
# macOS
brew install psqlodbc

# Linux (Debian/Ubuntu)
sudo apt install odbc-postgresql
```

**Register driver** (macOS — add to `/opt/homebrew/etc/odbcinst.ini`):
```ini
[PostgreSQL]
Description=PostgreSQL ODBC driver (ANSI)
Driver=/opt/homebrew/lib/psqlodbca.so
Threading=0

[PostgreSQL Unicode]
Description=PostgreSQL ODBC driver (Unicode)
Driver=/opt/homebrew/lib/psqlodbcw.so
Threading=0
```

**Register driver** (Linux — add to `/etc/odbcinst.ini`):
```ini
[PostgreSQL]
Description=PostgreSQL ODBC driver
Driver=/usr/lib/x86_64-linux-gnu/odbc/psqlodbca.so
Threading=0

[PostgreSQL Unicode]
Description=PostgreSQL ODBC driver (Unicode)
Driver=/usr/lib/x86_64-linux-gnu/odbc/psqlodbcw.so
Threading=0
```

**Windows:**

Download the PostgreSQL ODBC driver from [https://www.postgresql.org/ftp/odbc/versions/msi/](https://www.postgresql.org/ftp/odbc/versions/msi/) and run the MSI installer. The driver name is typically `PostgreSQL Unicode(x64)`.

**Connect:**
```rpgle
DCL-S connStr VARCHAR(300);

// Basic connection
connStr = 'Driver={PostgreSQL};Server=localhost;Port=5432;'
        + 'Database=mydb;Uid=myuser;Pwd=mypassword;';
EXEC SQL CONNECT USING :connStr;

// Windows (use the registered driver name)
connStr = 'Driver={PostgreSQL Unicode(x64)};Server=localhost;Port=5432;'
        + 'Database=mydb;Uid=myuser;Pwd=mypassword;';
EXEC SQL CONNECT USING :connStr;
```

### MySQL / MariaDB

**Install:**
```bash
# macOS
brew install mysql-connector-odbc

# Linux (Debian/Ubuntu)
sudo apt install libmyodbc
```

**Register driver** (macOS — find the .so path with `find /opt/homebrew -name "libmyodbc*"`):
```ini
[MySQL]
Description=MySQL ODBC driver
Driver=/opt/homebrew/lib/libmyodbc8a.so
Threading=0
```

**Windows:**

Download MySQL Connector/ODBC from [https://dev.mysql.com/downloads/connector/odbc/](https://dev.mysql.com/downloads/connector/odbc/) and run the MSI installer. The driver name is typically `MySQL ODBC 8.0 Unicode Driver`.

**Connect:**
```rpgle
DCL-S connStr VARCHAR(300);

// macOS / Linux
connStr = 'Driver={MySQL};Server=localhost;Port=3306;'
        + 'Database=mydb;User=myuser;Password=mypassword;';
EXEC SQL CONNECT USING :connStr;

// Windows
connStr = 'Driver={MySQL ODBC 8.0 Unicode Driver};Server=localhost;Port=3306;'
        + 'Database=mydb;User=myuser;Password=mypassword;';
EXEC SQL CONNECT USING :connStr;
```

### Microsoft SQL Server

**Install:**
```bash
# macOS
brew tap microsoft/mssql-release https://github.com/Microsoft/homebrew-mssql-release
brew install msodbcsql18

# Linux (Debian/Ubuntu) — see Microsoft's docs for repo setup
sudo apt install msodbcsql18
```

**Windows:**

Download "ODBC Driver 18 for SQL Server" from [Microsoft's download page](https://learn.microsoft.com/en-us/sql/connect/odbc/download-odbc-driver-for-sql-server) and run the MSI installer. SQL Server Express also installs the driver automatically.

**Connect:**
```rpgle
DCL-S connStr VARCHAR(300);
connStr = 'Driver={ODBC Driver 18 for SQL Server};'
        + 'Server=localhost,1433;Database=mydb;'
        + 'Uid=sa;Pwd=mypassword;TrustServerCertificate=yes;';
EXEC SQL CONNECT USING :connStr;
```

The connection string is the same on all platforms.

### IBM Db2

**Install (macOS / Linux):**
```bash
# Download IBM Data Server Driver from IBM's website
# Or use the IBM i Access ODBC driver for IBM i connections
```

**Install (Windows):**

Download the IBM Data Server Driver Package from [IBM Fix Central](https://www.ibm.com/support/fixcentral/) or install **IBM i Access Client Solutions** which includes the IBM i Access ODBC Driver. Run the installer and the driver is registered automatically.

**Connect:**
```rpgle
DCL-S connStr VARCHAR(300);

// Db2 on Linux/Windows
connStr = 'Driver={IBM DB2 ODBC DRIVER};'
        + 'Database=mydb;Hostname=localhost;Port=50000;'
        + 'Uid=db2admin;Pwd=mypassword;Protocol=TCPIP;';
EXEC SQL CONNECT USING :connStr;

// IBM i (via IBM i Access ODBC Driver)
connStr = 'Driver={IBM i Access ODBC Driver};'
        + 'System=myibmi.example.com;'
        + 'Uid=myuser;Pwd=mypassword;';
EXEC SQL CONNECT USING :connStr;
```

### Using Environment Variables for Connection Strings

Avoid hardcoding credentials. Use `%GETENV` to read connection details from the environment:

```rpgle
DCL-S connStr VARCHAR(300);

connStr = %GETENV('DATABASE_URL');
IF connStr = '';
  DSPLY 'DATABASE_URL not set!';
  RETURN;
ENDIF;

EXEC SQL CONNECT USING :connStr;
```

```bash
export DATABASE_URL="Driver={PostgreSQL};Server=localhost;Port=5432;Database=mydb;Uid=user;Pwd=pass;"
./myprogram
```

### Verifying Your ODBC Setup

**macOS / Linux** — list registered drivers:
```bash
odbcinst -q -d
```

Test a connection with `isql` (comes with unixODBC):
```bash
isql MyDSN myuser mypassword
```

**Windows** — open the **ODBC Data Source Administrator** (search "ODBC" in the Start menu). The **Drivers** tab lists all registered drivers. Use the **Test Connection** button when configuring a data source.

### Connection Lifecycle

```rpgle
// Connect
EXEC SQL CONNECT USING :connStr;

// ... do work ...

// Disconnect when done
EXEC SQL DISCONNECT;

// Or use CONNECT RESET (equivalent to DISCONNECT)
EXEC SQL CONNECT RESET;
```

**Note:** OpenRPG supports one database connection per program. You must disconnect before connecting to a different database.

---

## Multi-Module Programs

For larger applications, split code across modules:

**mathlib.rpgle** (module — no main):
```rpgle
**FREE
CTL-OPT NOMAIN;

DCL-PROC Add EXPORT;
  DCL-PI INT(10);
    a INT(10) VALUE;
    b INT(10) VALUE;
  END-PI;
  RETURN a + b;
END-PROC;
```

**main.rpgle** (main program):
```rpgle
**FREE

DCL-PR Add INT(10) EXTPROC('ADD');
  a INT(10) VALUE;
  b INT(10) VALUE;
END-PR;

DCL-S result INT(10);
result = Add(3 : 5);
DSPLY %CHAR(result);

RETURN;
```

**Build:**
```bash
rpgc -c mathlib.rpgle              # produces mathlib.o
rpgc main.rpgle mathlib.o -o myapp # compiles main and links with module
```

> **The `EXTPROC` name is case-sensitive, and procedure names are exported
> upper-cased.** `DCL-PROC Add EXPORT` exports the symbol `ADD`, so the caller
> must say `EXTPROC('ADD')` — `EXTPROC('Add')` compiles both sides cleanly and
> then fails at link time with an undefined symbol.

---

## Environment Variables

Read environment variables at runtime with `%GETENV`:

```rpgle
DCL-S home VARCHAR(200);
DCL-S dbUrl VARCHAR(300);

home = %GETENV('HOME');
DSPLY 'Home directory: ' + home;

dbUrl = %GETENV('DATABASE_URL');
IF dbUrl = '';
  DSPLY 'No database configured';
ENDIF;
```

`%GETENV` returns an empty string if the variable is not set.

---

## Testing

```bash
# Run all tests (validates runtime output)
make test

# Regenerate expected output baselines
make update-expected
```

The test suite includes 115 tests covering language features, built-in functions, error handling, embedded SQL, and record-level access. SQL and RLA tests use SQLite databases that are automatically created and cleaned up during testing.

---

## Varying-Dimension Arrays

### DIM(\*VAR) — Fixed Capacity, Variable Size

Declare an array with a maximum capacity but let the active size grow at runtime:

```rpgle
DCL-S scores INT(10) DIM(*VAR: 100);   // up to 100 elements

// Set the active size
%ELEM(scores) = 5;
scores(1) = 90;
scores(2) = 85;
// ...

DSPLY 'Count: ' + %CHAR(%ELEM(scores));   // 5
```

### DIM(\*AUTO) — Grows Automatically

`DIM(*AUTO: max)` behaves like `DIM(*VAR: max)` but the array expands as you assign to
higher indices — no explicit `%ELEM(arr) = n` required:

```rpgle
DCL-S tags VARCHAR(20) DIM(*AUTO: 50);

tags(1) = 'alpha';
tags(2) = 'beta';
tags(3) = 'gamma';
// %ELEM(tags) is now 3 automatically
DSPLY %CHAR(%ELEM(tags));    // 3
```

### %ELEM(\*ALLOC) and %ELEM(\*KEEP)

Control the underlying buffer capacity separately from the active element count:

```rpgle
DCL-S nums INT(10) DIM(*VAR: 10);

// Expand allocation beyond the declared max
%ELEM(nums : *ALLOC) = 50;
DSPLY %CHAR(%ELEM(nums : *ALLOC));   // 50 — capacity
DSPLY %CHAR(%ELEM(nums));            // 0  — active size unchanged

// Populate 5 elements
%ELEM(nums) = 5;
FOR i = 1 TO 5;
  nums(i) = i * 10;
ENDFOR;

// Shrink active count without releasing the buffer
%ELEM(nums : *KEEP) = 3;
DSPLY %CHAR(%ELEM(nums));            // 3  — active size
DSPLY %CHAR(%ELEM(nums : *ALLOC));   // 50 — capacity still intact
```

Use `*KEEP` when you want to reuse the same buffer across iterations without
repeated reallocations.

### Arrays of Data Structures

```rpgle
DCL-DS employee QUALIFIED DIM(*VAR: 50);
  id   INT(10);
  name VARCHAR(40);
END-DS;

%ELEM(employee) = 2;
employee(1).id = 101;
employee(1).name = 'Alice';
employee(2).id = 102;
employee(2).name = 'Bob';

DSPLY employee(1).name;
```

---

## Operation Extenders

Operation extenders modify the behavior of `EVAL`, `EVALR`, and `CALLP`. They are
written in parentheses after the opcode.

### (H) — Half-Adjust (Round)

Rounds the result to the target precision before assignment:

```rpgle
DCL-S a PACKED(7:1) INZ(7.0);
DCL-S b PACKED(7:0) INZ(2);
DCL-S result INT(10);

EVAL(H) result = a / b;   // 7.0 / 2 = 3.5, rounds to 4
DSPLY %CHAR(result);       // 4
```

### (R) — Round

Synonym for `(H)`:

```rpgle
EVAL(R) result = a / b;
```

### (E) — Error Capture

Prevents a runtime error from halting the program. After the operation, check
`%ERROR` to see if it failed:

```rpgle
CALLP(E) riskProc(arg);
IF %ERROR;
  DSPLY 'Call failed: ' + %CHAR(%STATUS);
ENDIF;

EVAL(E) x = someCalc();
IF %ERROR;
  DSPLY 'Calc error';
ENDIF;
```

### (M) — Move (multiple extenders)

Extenders can be combined — e.g., `EVAL(MH)` means move with half-adjust:

```rpgle
EVAL(MH) result = a / b;
```

### (P) — Pad

For string assignments, pads the target with blanks. For numeric, same as no
extender. Primarily a compatibility keyword; accepted and parsed:

```rpgle
EVAL(P) padStr = 'HELLO';
```

### (N) — No Lock

Accepted on file operations and `EVAL`; treated as a no-op outside record-level
access. Useful when porting code that uses `(N)` on READ/CHAIN:

```rpgle
EVAL(N) x = x + 1;
```

### EVALR with Extenders

`EVALR` right-adjusts the result into the target. Extenders work the same way:

```rpgle
DCL-S target CHAR(10);
DCL-S n PACKED(7:1) INZ(3.7);
EVALR(H) target = n;   // rounds to 4, right-justified in 10 chars
```

---

## Enumerations

`DCL-ENUM` defines a named set of constants. Use `QUALIFIED` so each value is
accessed with the enum name as a prefix.

```rpgle
DCL-ENUM Color QUALIFIED;
  Red;       // 0
  Green;     // 1
  Blue;      // 2
END-ENUM;

DCL-S paint INT(10);
paint = Color.Green;

SELECT;
  WHEN paint = Color.Red;
    DSPLY 'Red';
  WHEN paint = Color.Green;
    DSPLY 'Green';
  WHEN paint = Color.Blue;
    DSPLY 'Blue';
ENDSL;
```

### BOOLEAN Type

`BOOLEAN` is a built-in type that holds `*ON` or `*OFF`:

```rpgle
DCL-S isReady BOOLEAN INZ(*OFF);
DCL-S hasError BOOLEAN;

isReady = *ON;

IF isReady AND NOT hasError;
  DSPLY 'Ready and no errors';
ENDIF;
```

---

## Program Status Data Structure

The PSDS (`PSDS`) keyword on a `DCL-DS` declares the Program Status Data Structure.
OpenRPG populates it at startup with process and environment information, mirroring
the IBM i layout at the well-known POS offsets.

```rpgle
DCL-DS PgmInfo PSDS QUALIFIED;
  PgmName CHAR(10) POS(81);    // program name (source file stem)
  UserID  CHAR(10) POS(91);    // current OS user
  JobNum  CHAR(8)  POS(101);   // process ID (zero-padded)
  RunDate CHAR(8)  POS(109);   // YYYYMMDD
  RunTime CHAR(6)  POS(119);   // HHMMSS
END-DS;
```

| POS | Length | Content |
|-----|--------|---------|
| 1   | 10     | Current procedure name |
| 11  | 5      | Current status code (PACKED 5,0) |
| 81  | 10     | Program name |
| 91  | 10     | User profile / OS username |
| 101 | 8      | Job number (PID, zero-padded) |
| 109 | 8      | Run date (YYYYMMDD) |
| 119 | 6      | Run time (HHMMSS) |

```rpgle
IF %TRIM(PgmInfo.UserID) <> '';
  DSPLY 'Running as: ' + PgmInfo.UserID;
ENDIF;

DSPLY 'Started: ' + PgmInfo.RunDate + ' ' + PgmInfo.RunTime;
```

The PSDS also syncs before every `ON-ERROR` handler fires, so you can read
`StatusCode` inside `MONITOR` blocks to identify the error.

---

## Data Areas

Data areas are persistent named storage outside of any single program. On IBM i
they are system objects; in OpenRPG they are plain files on the local filesystem,
stored in `$TMPDIR` (typically `/tmp`).

### Declare a Data Area Variable

Add `DTAARA` to a `DCL-S` or `DCL-DS`:

```rpgle
// *LDA — the Local Data Area (one per job/process)
DCL-S LdaData CHAR(256) DTAARA(*LDA);

// Named data area
DCL-S Config CHAR(100) DTAARA(APPCONFIG);
```

### IN — Read from Data Area

```rpgle
IN LdaData;
DSPLY %TRIM(LdaData);
```

### OUT — Write to Data Area

```rpgle
LdaData = 'SESSION_ID=ABC123';
OUT LdaData;
```

### UNLOCK — Release the Lock

`IN` acquires an exclusive lock on the data area. `UNLOCK` releases it when you
are done reading so other programs can access it:

```rpgle
IN LdaData;
// ... use LdaData ...
UNLOCK LdaData;
```

### Round-Trip Example

```rpgle
DCL-S LdaData CHAR(20) DTAARA(*LDA);

LdaData = 'HELLO DATA AREA     ';
OUT LdaData;

LdaData = '';      // clear local copy
IN LdaData;        // read back from storage

DSPLY %TRIM(LdaData);   // HELLO DATA AREA
UNLOCK LdaData;
```

### Named Data Areas

```rpgle
DCL-S MyConfig CHAR(50) DTAARA(RPGCONFIG);

MyConfig = 'VERSION=2.0';
OUT MyConfig;

MyConfig = '';
IN MyConfig;
DSPLY %SUBST(MyConfig: 1: 11);   // VERSION=2.0
UNLOCK MyConfig;
```

> Data area files are created automatically on `OUT` if they do not exist.
> On IBM i the equivalent would be `CRTDTAARA`.

---

## SND-MSG

`SND-MSG` sends a message to the program message queue. In OpenRPG, `*INFO` and
`*DIAG` messages are written to stderr. `*ESCAPE` raises a catchable exception.

### Syntax

```rpgle
SND-MSG *INFO 'Informational message';
SND-MSG *DIAG 'Diagnostic detail';
SND-MSG *ESCAPE 'Fatal error text';

// TYPE() keyword form
SND-MSG TYPE(*INFO) 'Processing complete';

// Bare form — defaults to *INFO
SND-MSG 'Something happened';

// Variable message
DCL-S msg VARCHAR(100);
msg = 'Row count: ' + %CHAR(rowCount);
SND-MSG *DIAG msg;
```

### Catching \*ESCAPE with MONITOR

`*ESCAPE` is the only message type that can interrupt normal flow. Wrap it in a
`MONITOR` block to handle it gracefully:

```rpgle
MONITOR;
  SND-MSG *ESCAPE 'Validation failed';
ON-ERROR;
  DSPLY 'Caught: ' + %CHAR(%STATUS);
ENDMON;
```

---

## Record-Level Access

Record-Level Access (RLA) is RPG's native file I/O model. In OpenRPG, RLA is
implemented over ODBC — the file is actually a database table, and the RLA opcodes
translate to SQL operations transparently. Any ODBC-connected database works.

### Declaring a File

```rpgle
DCL-F filename DISK KEYED EXTDESC('tablename');
```

| Keyword | Meaning |
|---------|---------|
| `DISK` | Disk (database) file |
| `KEYED` | Key-based access (CHAIN, SETLL, READE) |
| `EXTDESC('name')` | Maps to the SQL table named `name` |

Omit `KEYED` for sequential-only access.

The table's columns become program-scope variables with the same names as the
column definitions. All names are uppercased to match RPG convention.

### CHAIN — Random Read by Key

```rpgle
DCL-F CUSTFL DISK KEYED EXTDESC('customers');
DCL-S key VARCHAR(10);

key = 'C001';
CHAIN key CUSTFL;
IF %FOUND(CUSTFL);
  DSPLY CUSTNO;
  DSPLY CUSTNAME;
ENDIF;
```

`%FOUND(filename)` is true when the last CHAIN found a record.

### READ — Sequential Read

```rpgle
DCL-F CUSTFL DISK EXTDESC('customers');

READ CUSTFL;
DOW NOT %EOF(CUSTFL);
  DSPLY CUSTNAME;
  READ CUSTFL;
ENDDO;
```

`%EOF(filename)` becomes true after a READ past the last record.

### WRITE — Insert a New Record

Assign values to the field variables, then WRITE:

```rpgle
CUSTNO   = 'C010';
CUSTNAME = 'New Customer';
CUSTBAL  = 0;
WRITE CUSTFL;
```

### UPDATE — Modify the Current Record

After a successful CHAIN or READ, modify fields and UPDATE:

```rpgle
key = 'C001';
CHAIN key CUSTFL;
IF %FOUND(CUSTFL);
  CUSTBAL = CUSTBAL + 500;
  UPDATE CUSTFL;
ENDIF;
```

### DELETE — Remove the Current Record

After a successful CHAIN or READ, DELETE removes that row:

```rpgle
key = 'C010';
CHAIN key CUSTFL;
IF %FOUND(CUSTFL);
  DELETE CUSTFL;
ENDIF;
```

### SETLL — Position to a Key

`SETLL` positions the file cursor so the next READ starts at the first record
with a key >= the argument:

```rpgle
DCL-F CUSTFL DISK KEYED EXTDESC('customers');
DCL-S key VARCHAR(10);

key = 'B000';
SETLL key CUSTFL;

READ CUSTFL;
DOW NOT %EOF(CUSTFL) AND CUSTNO <= 'B999';
  DSPLY CUSTNO + ' ' + CUSTNAME;
  READ CUSTFL;
ENDDO;
```

### READE — Read Equal Key

`READE` reads the next record only if its key matches the argument:

```rpgle
key = 'B002';
SETLL key CUSTFL;

READE key CUSTFL;
IF %FOUND(CUSTFL);
  DSPLY CUSTNAME;
ENDIF;
```

### Connection

RLA uses the same ODBC connection as embedded SQL. You can connect explicitly or
use `rpgc.conf` (see [Database Connections](#database-connections)):

```rpgle
DCL-F CUSTFL DISK KEYED EXTDESC('customers');
DCL-S connStr VARCHAR(200);

connStr = 'Driver={SQLite3};Database=myapp.db;';
EXEC SQL CONNECT USING :connStr;

key = 'C001';
CHAIN key CUSTFL;
```

Or with `rpgc.conf` — no `EXEC SQL CONNECT` needed at all:

```rpgle
DCL-F CUSTFL DISK KEYED EXTDESC('customers');
DCL-S key VARCHAR(10);

key = 'B002';
CHAIN key CUSTFL;
IF %FOUND(CUSTFL);
  DSPLY CUSTNAME;
ENDIF;
```

### Complete RLA Example

```rpgle
**FREE

DCL-F EMPFL DISK KEYED EXTDESC('employees');

DCL-S connStr VARCHAR(200);
DCL-S key     VARCHAR(10);

connStr = 'Driver={SQLite3};Database=company.db;';
EXEC SQL CONNECT USING :connStr;

EXEC SQL CREATE TABLE employees (
  EMPNO   VARCHAR(10) PRIMARY KEY,
  EMPNAME VARCHAR(50),
  SALARY  DECIMAL(9,2)
);
EXEC SQL INSERT INTO employees VALUES('E001','Alice',85000);
EXEC SQL INSERT INTO employees VALUES('E002','Bob',72000);
EXEC SQL INSERT INTO employees VALUES('E003','Carol',91000);

// Random read
key = 'E002';
CHAIN key EMPFL;
IF %FOUND(EMPFL);
  DSPLY 'Found: ' + EMPNAME;
ENDIF;

// Sequential scan
READ EMPFL;
DOW NOT %EOF(EMPFL);
  DSPLY EMPNO + ' ' + EMPNAME;
  READ EMPFL;
ENDDO;

// Write a new record
EMPNO   = 'E004';
EMPNAME = 'David';
SALARY  = 68000;
WRITE EMPFL;

// Update
key = 'E001';
CHAIN key EMPFL;
IF %FOUND(EMPFL);
  SALARY = SALARY + 5000;
  UPDATE EMPFL;
ENDIF;

// Delete
key = 'E004';
CHAIN key EMPFL;
IF %FOUND(EMPFL);
  DELETE EMPFL;
ENDIF;

EXEC SQL DROP TABLE employees;
EXEC SQL DISCONNECT;
*INLR = *ON;
```

---

## DATA-INTO and DATA-GEN

`DATA-INTO` parses structured data into a data structure.
`DATA-GEN` serializes a data structure to structured data.

The format is selected with the `%PARSER` BIF. Without `%PARSER`, JSON is the default.
Use `%PARSER('CSV')` for comma-separated values.

### DATA-INTO — Parse JSON

```rpgle
DCL-DS person QUALIFIED;
  name VARCHAR(40);
  age  INT(10);
  city VARCHAR(30);
END-DS;

DCL-S json VARCHAR(500);
json = '{"name":"Alice","age":30,"city":"Boston"}';

DATA-INTO person %DATA(json : 'doc=string case=any');

DSPLY person.name;              // Alice
DSPLY %CHAR(person.age);        // 30
DSPLY person.city;              // Boston
```

The `%DATA` BIF takes the data source and an options string:

| Option | Meaning |
|--------|---------|
| `doc=string` | The data is a string variable (not a file) |
| `case=any` | Case-insensitive field name matching |

Fields not present in the JSON default to zero (numeric) or blank (character).

### DATA-GEN — Generate JSON

```rpgle
DCL-DS item QUALIFIED;
  id    INT(10);
  price PACKED(9:2);
  label VARCHAR(30);
END-DS;

DCL-S json VARCHAR(300);

item.id    = 42;
item.price = 19.99;
item.label = 'Widget';

DATA-GEN item %DATA(json : 'doc=string');

DSPLY json;   // {"id":42,"price":19.99,"label":"Widget"}
```

### Numeric Types

PACKED, ZONED, INT, FLOAT, and UNS fields all round-trip correctly:

```rpgle
DCL-DS product QUALIFIED;
  id    INT(10);
  price PACKED(9:2);
  qty   INT(10);
END-DS;

json = '{"id":99,"price":4.50,"qty":10}';
DATA-INTO product %DATA(json : 'doc=string case=any');

DSPLY %CHAR(product.price);   // 4.50
```

### Special Characters in Strings

`DATA-GEN` escapes double-quotes and other JSON special characters automatically:

```rpgle
DCL-DS msg QUALIFIED;
  text VARCHAR(100);
END-DS;

msg.text = 'Price < $10 & "sale"';
DATA-GEN msg %DATA(json : 'doc=string');
// {"text":"Price < $10 & \"sale\""}
```

---

### CSV Format via %PARSER('CSV')

Use `%PARSER('CSV')` to parse or generate comma-separated values. The first row
is treated as a header row mapping column names to DS field names.

#### DATA-INTO — Parse CSV

```rpgle
DCL-DS person QUALIFIED;
  name VARCHAR(40);
  age  INT(10);
  city VARCHAR(30);
END-DS;

DCL-S csv VARCHAR(500);
csv = 'NAME,AGE,CITY' + X'0A' + 'Alice,30,Boston';

DATA-INTO person %DATA(csv : 'case=any') %PARSER('CSV');

DSPLY person.name;   // Alice
DSPLY %CHAR(person.age);   // 30
```

For array DS, each data row maps to one element:

```rpgle
DCL-DS emp DIM(*VAR:10) QUALIFIED;
  name VARCHAR(40);
  dept VARCHAR(20);
END-DS;

DCL-S csv VARCHAR(500);
csv = 'NAME,DEPT' + X'0A' + 'Bob,Engineering' + X'0A' + 'Carol,Marketing';

DATA-INTO emp %DATA(csv : 'case=any') %PARSER('CSV');
// %ELEM(emp) = 2
```

#### DATA-GEN — Generate CSV

```rpgle
DCL-DS person QUALIFIED;
  name VARCHAR(40);
  age  INT(10);
END-DS;

DCL-S csv VARCHAR(300);
person.name = 'Alice';
person.age  = 30;

DATA-GEN person %DATA(csv) %PARSER('CSV');
// csv = "NAME,AGE\nAlice,30"
```

#### CSV Options

| Option | Meaning |
|--------|---------|
| `case=any` | Case-insensitive header matching (DATA-INTO) |
| `header=no` | Skip header row on input / omit header row on output |
| `delimiter=<c>` | Use `<c>` as field delimiter instead of comma |

#### Hex String Literals (`X'...'`)

RPG does not have string escape sequences. Use hex literals to embed control
characters such as newline (`X'0A'`) or carriage-return (`X'0D'`) in strings:

```rpgle
DCL-C LF X'0A';
csv = 'NAME,AGE' + LF + 'Alice,30';
```

---

## XML-INTO

`XML-INTO` parses an XML string into a data structure or array of data structures.
It uses the `%XML` BIF to specify the data source and parsing options.

### Basic Usage

```rpgle
DCL-DS order QUALIFIED;
  id       INT(10);
  customer VARCHAR(50);
  qty      INT(10);
END-DS;

DCL-S xml VARCHAR(500);
xml = '<order><id>1001</id><customer>Acme</customer><qty>25</qty></order>';

XML-INTO order %XML(xml : 'case=any');

DSPLY %CHAR(order.id);        // 1001
DSPLY order.customer;          // Acme
DSPLY %CHAR(order.qty);        // 25
```

### Options

| Option | Meaning |
|--------|---------|
| `case=any` | Case-insensitive element-to-field matching |
| `path=a/b/c` | Navigate into the XML tree before mapping |

Missing elements default to zero or blank. Unknown elements are ignored.

### PATH Option

Use `path=` to navigate past wrapper elements:

```rpgle
DCL-DS rec QUALIFIED;
  id   INT(10);
  name VARCHAR(40);
END-DS;

xml = '<response><data><record><id>5</id><name>Alice</name></record></data></response>';

XML-INTO rec %XML(xml : 'case=any path=response/data/record');

DSPLY %CHAR(rec.id);    // 5
DSPLY rec.name;          // Alice
```

### Array Target

Map a repeating XML element into an array DS. Use `path=` to name the parent
element, and the target DS array receives one element per child:

```rpgle
DCL-DS item QUALIFIED DIM(5);
  name  VARCHAR(50);
  qty   INT(10);
  price PACKED(9:2);
END-DS;

xml = '<items>' +
      '<item><name>Widget</name><qty>5</qty><price>19.99</price></item>' +
      '<item><name>Gadget</name><qty>3</qty><price>29.50</price></item>' +
      '</items>';

XML-INTO item %XML(xml : 'case=any path=items');

DSPLY item(1).name + ' qty=' + %CHAR(item(1).qty);   // Widget qty=5
DSPLY item(2).name + ' qty=' + %CHAR(item(2).qty);   // Gadget qty=3
```

Use `DIM(*VAR: n)` to handle a variable number of elements:

```rpgle
DCL-DS emp QUALIFIED DIM(*VAR: 50);
  id   INT(10);
  name VARCHAR(40);
END-DS;

XML-INTO emp %XML(xml : 'case=any path=employees');

DSPLY 'Count: ' + %CHAR(%ELEM(emp));
```

### Nested Data Structures with LIKEDS

```rpgle
DCL-DS address QUALIFIED;
  street VARCHAR(50);
  city   VARCHAR(30);
  state  CHAR(2);
END-DS;

DCL-DS customer QUALIFIED;
  name VARCHAR(50);
  age  INT(10);
  addr LIKEDS(address);
END-DS;

xml = '<customer>' +
        '<name>Alice</name><age>30</age>' +
        '<addr><street>123 Main</street><city>Boston</city><state>MA</state></addr>' +
      '</customer>';

XML-INTO customer %XML(xml : 'case=any');

DSPLY customer.name;           // Alice
DSPLY customer.addr.city;      // Boston
DSPLY customer.addr.state;     // MA
```

---

## Procedure Overloading

`OVERLOAD` declares a generic procedure name that dispatches to one of several
typed implementations based on argument types at call time.

### Declaration

```rpgle
// Typed implementations
DCL-PR absInt INT(10);
  n INT(10) VALUE;
END-PR;

DCL-PR absFloat FLOAT(8);
  n FLOAT(8) VALUE;
END-PR;

// Generic overloaded name
DCL-PR abs OVERLOAD(absInt : absFloat);
END-PR;
```

### Calling

The compiler selects the implementation whose parameter types best match the
argument types at the call site:

```rpgle
DCL-S i INT(10);
DCL-S f FLOAT(8);

i = abs(-7);      // calls absInt
f = abs(-3.5);    // calls absFloat
```

### Full Example

```rpgle
**FREE

CTL-OPT MAIN(main);

DCL-PR formatInt   VARCHAR(30);
  n INT(10) VALUE;
END-PR;

DCL-PR formatFloat VARCHAR(30);
  n FLOAT(8) VALUE;
END-PR;

DCL-PR format OVERLOAD(formatInt : formatFloat);
END-PR;

DCL-PROC main;
  DCL-PI main; END-PI;

  DSPLY format(42);      // calls formatInt  → "INT:42"
  DSPLY format(3.14);    // calls formatFloat → "FLT:3"
END-PROC;

DCL-PROC formatInt EXPORT;
  DCL-PI formatInt VARCHAR(30);
    n INT(10) VALUE;
  END-PI;
  RETURN 'INT:' + %CHAR(n);
END-PROC;

DCL-PROC formatFloat EXPORT;
  DCL-PI formatFloat VARCHAR(30);
    n FLOAT(8) VALUE;
  END-PI;
  RETURN 'FLT:' + %CHAR(%INT(n));
END-PROC;
```

---

## Display Files (WORKSTN)

A WORKSTN file is an interactive 5250-style screen. The screen itself is
described in a separate `.dspf` source file and compiled by **dspfc** (the
OpenDSPF compiler); OpenRPG then reads the compiled descriptor and gives the
RPG program a variable for every field on the screen.

### The Two-Step Compile

```bash
dspfc CUSTMENU.dspf     # produces CUSTMENU.dspfd and CUSTMENU_dspf.h
rpgc  myprogram.rpgle   # reads CUSTMENU.dspfd, links the screen runtime
```

`rpgc` looks for `NAME.dspfd` in the same directory as the RPG source, trying
the uppercase name first and then the lowercase one. If it finds no descriptor
the program still compiles, but the screen opcodes become comments — check the
generated C++ if a screen silently does nothing.

Screen rendering uses curses, and `rpgc` adds the right linker flag for the
platform automatically (`-lncurses`, or `-lpdcurses` on Windows). You do not
pass anything extra on the command line.

### Declaring the File

```rpgle
DCL-F CUSTMENU WORKSTN;
```

Every field in every record format of the display file becomes a program-scope
variable with the field's own name. Character, date, time and timestamp fields
become strings; binary fields become integers; the rest become numeric.

Two things worth knowing about those variables:

- **`HIDDEN` fields get a variable too.** Hidden means "not rendered", not "no
  data" — `SFLRCDNBR` is the common case.
- **`DFTVAL('text')` seeds the initial value**, so the field displays that text
  before the program ever assigns to it.

### EXFMT — Write and Read in One Step

`EXFMT` displays a record format and waits for the user:

```rpgle
DCL-F CUSTMENU WORKSTN;
DCL-S choice CHAR(1);

EXFMT MAINMENU;

IF *IN03;
  DSPLY 'F3 pressed — exiting';
ELSE;
  choice = OPTION;
  DSPLY ('You selected option: ' + choice);
ENDIF;
```

Function keys defined in the display file set their indicators, so the program
tests `*IN03`, `*IN12` and so on after the `EXFMT` returns. Only input, both and
hidden fields are copied back — the program already knows what it sent out.

### WRITE and READ

`WRITE` renders a record format without waiting, and `READ` sends the current
field values to the screen and reads the user's input back. `EXFMT` is the
combination of the two and is what most programs use.

### Subfiles

A subfile is a scrollable list. It needs two record formats in the display
file — an `SFL` record holding one row's fields, and an `SFLCTL` record that
controls the display. The RPG side is three steps:

```rpgle
DCL-F CUSTLIST WORKSTN;
DCL-S i INT(10);

WRITE CUSTCTL;            // 1. clears the subfile

FOR i = 1 TO 5;           // 2. one WRITE per row
  CUSTNO   = ('C' + %CHAR(i));
  CUSTNAME = ('Customer ' + %CHAR(i));
  CUSTBAL  = (i * 1000.00);
  WRITE CUSTSFL;
ENDFOR;

EXFMT CUSTCTL;            // 3. displays it as a scrollable table

IF NOT *IN03 AND NOT *IN12;
  DSPLY ('You selected row: ' + %CHAR(SFLRCDNBR));
ENDIF;
```

| Step | Opcode | Effect |
|------|--------|--------|
| 1 | `WRITE` on the SFLCTL record | Clears the subfile's row store |
| 2 | `WRITE` on the SFL record | Appends one row |
| 3 | `EXFMT` on the SFLCTL record | Displays the scrollable list |

At runtime the user scrolls with the arrow keys and Page Up/Page Down, and
exits with Enter or any defined function key. If the SFLCTL record has a field
named `SFLRCDNBR`, the 1-based relative record number of the selected row is
written into it.

### READC — Read Changed Records

`READC` walks the rows the user actually modified:

```rpgle
READC CUSTSFL;
DOW NOT %EOF(CUSTSFL);
  IF OPTION = '4';
    DSPLY ('Deleting ' + %TRIM(CUSTNO));
  ENDIF;
  READC CUSTSFL;
ENDDO;
```

`%EOF(recordformat)` becomes true when there are no more changed rows. Unlike
`EXFMT`, `READC` copies back *every* field of the row including output-only
ones — that is how the program knows which row's option was typed into.

### UPDATE — Rewrite the Current Row

After a `READC`, `UPDATE` writes the field variables back into that same row:

```rpgle
READC CUSTSFL;
DOW NOT %EOF(CUSTSFL);
  OPTION = ' ';           // clear the option field
  UPDATE CUSTSFL;
  READC CUSTSFL;
ENDDO;
```

Unlike a DISK `UPDATE`, no key is involved — it targets whichever row `READC`
last returned.

For the display-file side of all this — record formats, field keywords,
literals, function keys, `SFLPAG`/`SFLSIZ`, conditioning indicators, `EDTCDE`
and `EDTWRD` — see the OpenDSPF User's Guide in `OpenDSPF/docs/GUIDE.md`.

---

## Fixed-Format Source

OpenRPG accepts classic column-based RPG IV source as well as free-format. This
is a second *parsing* frontend only — it builds the same AST, so every language
feature described elsewhere in this guide is reachable from fixed-format source.

### How the Format Is Chosen

The format is detected from the content of columns 1-6 of the first substantive
line, not from the file extension and not from a `**FREE` directive. A file can
also mix the two: H/F/D specs in columns with the calculations already
modernized inside `/free`...`/end-free` blocks is a common
incremental-modernization pattern and works as-is.

### Spec Types

Position 6 selects the spec type. Positions 1-5 are the sequence number and are
ignored; a `*` in position 7 makes the whole line a comment.

| Position 6 | Spec | Purpose |
|------------|------|---------|
| `H` | Control | Compile options — same set as `CTL-OPT` |
| `F` | File Description | File declarations — same as `DCL-F` |
| `D` | Definition | Standalone fields and data structures — same as `DCL-S` and `DCL-DS` |
| `I` | Input | Program-described input record layout (see next chapter) |
| `C` | Calculation | Executable statements |
| `O` | Output | Program-described output record layout (see next chapter) |

There is no `P`-spec support, so fixed-format source cannot declare a
procedure. Anything needing `DCL-PROC` — including `ON-EXIT` — has to live in a
`/free` block.

### H-Spec — Control Options

Positions 7-80 are a free keyword list, identical to what `CTL-OPT` accepts:

```rpgle
     HDFTACTGRP(*NO) DATFMT(*ISO) TIMFMT(*HMS)
```

### F-Spec — File Description

```rpgle
     FCUSTFL    IF   E             DISK    KEYED EXTDESC('customers')
     FCUSTMENU  CF   E             WORKSTN
     FTESTFL    O    F  25         DISK
```

| Positions | Field |
|-----------|-------|
| 7-16 | File name |
| 17 | File type (`I`/`O`/`U`/`C`) |
| 18 | File designation |
| 19 | End-of-file flag |
| 20 | Add flag |
| 21 | Sequence |
| 22 | File format (`E` externally described, `F` program described) |
| 23-27 | Record length (program-described files) |
| 28 | Process mode |
| 29-33 | Key field length |
| 34 | Record address type |
| 35 | File organization |
| 36-42 | Device — `DISK` and `WORKSTN` are implemented |
| 44-80 | Keyword tail, continuable across lines |

### D-Spec — Definitions

```rpgle
     DcustName         S             30A
     DorderDS          DS
     D  orderNo                       7P 0
     D  custName2                    30A   VARYING
     D  qty                           5P 0 DIM(12)
```

| Positions | Field |
|-----------|-------|
| 7-21 | Name — continuable with a trailing `...` |
| 22 | External-description flag |
| 23 | Data structure type |
| 24-25 | Definition type (blank, `C`, `DS`, `PR`, `PI`, `S`) |
| 26-32 | From position |
| 33-39 | To position or length |
| 40 | Data type |
| 41-42 | Decimal positions |
| 44-80 | Keyword tail, continuable across lines |

Only definition types `S` (standalone field), `DS` (data structure) and blank
(a subfield) are accepted. `C` for a named constant, and `PR`/`PI` for
prototypes and procedure interfaces, are rejected — declare those in a `/free`
block instead.

Supported in the keyword tail: `VARYING{(2|4)}` (which produces a `VARCHAR` —
free-format spells this `VARCHAR(n)` instead), `DIM(n)` on the data structure
itself for an array of elements, and per-subfield `OVERLAY(field)`,
`OVERLAY(field:pos)`, `POS(n)`, `LIKEDS(name)`, `LIKE(other)` and `DIM(n)`.

A subfield `DIM(n)` is an array *inside* the structure, and is subscripted with
the `ds.field(index)` form:

```rpgle
     DorderDS          DS
     D  qty                           5P 0 DIM(12)
      /free
  orderDS.qty(1) = 5;
      /end-free
```

A subfield `LIKE(other)` resolves against a field declared **earlier in the same
data structure**. Combining `LIKE` and `DIM` on one subfield is not supported,
and a subfield `DIM` is fixed-size only — no `DIM(*VAR)`/`DIM(*AUTO)`.

### C-Spec — Calculations

Calculations come in three shapes, and all three can be mixed freely in one
file.

| Positions | Field |
|-----------|-------|
| 7-8 | `SR`, or `AN`/`OR` for a multi-indicator group |
| 9-11 | Conditioning indicator |
| 12-25 | Factor 1 |
| 26-35 | Operation code, plus any `(extender)` |
| 36-49 | Factor 2 (traditional syntax) |
| 36-80 | The whole expression (extended factor 2) |
| 50-63 | Result (traditional syntax) |
| 71-76 | Resulting indicators — blank except on `COMP` |

Positions 64-70 (inline field length and decimals) must be blank; declare the
field on a D-spec instead.

**Extended factor 2** puts a normal free-format expression in positions 36-80,
and continues onto further lines that leave 7-35 blank:

```rpgle
     C                   IF        custBal > 1000 AND status = 'A'
     C                   EVAL      msg = 'Dear ' + %TRIM(firstName) +
     C                                   ', your account is current.'
     C                   ENDIF
```

**Traditional syntax** uses Factor 1, Factor 2 and Result:

```rpgle
     C     custKey       CHAIN     CUSTFL
     C                   EXSR      PRTLINE
     C     total         DSPLY
```

**`/free` blocks** hand their contents to the free-format parser unchanged:

```rpgle
      /free
  total = qty * price;
  DSPLY %CHAR(total);
      /end-free
```

### Supported Operation Codes

| Group | Opcodes |
|-------|---------|
| Block structure | `IF` `ELSEIF` `ELSE` `ENDIF` `DOW` `DOU` `ENDDO` `FOR` `FOR-EACH` `ENDFOR` `SELECT` `WHEN` `OTHER` `ENDSL` `MONITOR` `ON-ERROR` `ENDMON` `ITER` `LEAVE` |
| Subroutines | `BEGSR` `ENDSR` `EXSR` `LEAVESR` |
| Assignment | `EVAL` `EVALR` `EVAL-CORR` `CLEAR` `RESET` `MOVE` `MOVEL` `Z-ADD` `Z-SUB` |
| Arithmetic | `ADD` `SUB` `MULT` `DIV` |
| Comparison / branching | `COMP` `CASxx` `CABxx` `GOTO` `TAG` |
| Calls | `CALLP` `CALL` `PARM` `PLIST` `RETURN` |
| File I/O | `CHAIN` `READ` `READP` `READE` `READPE` `WRITE` `UPDATE` `DELETE` `SETLL` `SETGT` |
| Other | `DSPLY` `SORTA` `XML-INTO` `DATA-INTO` `DATA-GEN` `SND-MSG` |

Two notes on the file opcodes: none of them takes a data-structure result
operand, and `DELETE` takes no key — it deletes the last record read.
`SETLL` and `SETGT` do not accept an operation extender; the other file opcodes
do.

### Conditioning Indicators

Position 9 holds a blank or `N`, and positions 10-11 the indicator number. The
statement runs only when the indicator matches:

```rpgle
     C   10              EVAL      msg = 'Ten is on'
     C  N10              EVAL      msg = 'Ten is off'
```

Only self-contained statements can be conditioned — assignments, calls,
`ITER`/`LEAVE`/`LEAVESR`, the file opcodes, `GOTO`, `DSPLY`, and the arithmetic
set. Conditioning a block-structure opcode is a compile error, because the
wrapper would leave the block unbalanced; fold the test into the block's own
condition instead. `TAG` cannot be conditioned either.

A C-spec line has room for exactly one indicator, so `AN`/`OR` in positions 7-8
combine the indicators of consecutive lines. The operation code sits on the
last line of the group, and RPG relates the terms as an **OR of AND-groups**:

```rpgle
     C   10
     CAN 30
     COR 20              EVAL      msg = '(10 and 30) or 20'
```

Only `*IN01`-`*IN99` are supported. `LR`, `MR`, `RT`, `OV`, `1P`, `L1`-`L9`,
`H1`-`H9`, `U1`-`U8`, `KA`-`KY` and `OA`-`OG` are recognized by name so they get
a clear "not supported" message rather than being reported as a typo.

### Legacy Operation Codes

**`GOTO` and `TAG`** have no free-format equivalent at all, so they are accepted
only from fixed columns — writing either inside a `/free` block is an error.
Since subroutines generate as lambdas, a `GOTO` cannot cross a subroutine
boundary, which is RPG's own rule. Both take their label in **Factor 2**, and
leave Factor 1 and the Result field blank.

```rpgle
     C                   GOTO      SKIP
     C                   EVAL      msg = 'not reached'
     C                   TAG       SKIP
```

**`ADD`/`SUB`/`MULT`/`DIV`** use Factor 1 when it is present and accumulate into
the result when it is blank. `Z-ADD`/`Z-SUB` never use Factor 1.

| Written | Means |
|---------|-------|
| `C  a  ADD  b  c` | `c = a + b` |
| `C     ADD  b  c` | `c = c + b` |
| `C     Z-ADD b  c` | `c = b` |
| `C     Z-SUB b  c` | `c = -b` |

Extenders such as `(H)` half-adjust pass straight through.

**`MOVE` and `MOVEL`** are positional moves, not assignments. `MOVE` aligns
factor 2 against the right end of the result and `MOVEL` against the left, and
whatever part of the result the move does not reach is left **unchanged** — the
`(P)` extender blanks it instead. An over-long factor 2 truncates on the side
away from the alignment.

Numeric operands follow the same positional rule over the field's digits, and
both operands' decimal positions are ignored: moving `1.00` into a
three-position field with one decimal gives `10.0`.

A date, time or timestamp on either side converts first and then moves. Factor 1
carries the format of the *character or numeric* operand, never of the date
field, and must be blank when both sides are date/time types:

```rpgle
     C     *MDY          MOVE      chrDate       dateFld
```

Date-to-time and time-to-date are refused — go through a timestamp.

Because `MOVE`, `MOVEL`, `GOTO` and `TAG` are now lexer keywords, free-format
source can no longer use them as variable names.

**`COMP`** sets its three resulting indicators — high, low and equal — in
positions 71-72, 73-74 and 75-76. It is the only opcode for which those columns
may be non-blank.

**`CASxx` and `CABxx`** glue a comparison mnemonic (`EQ` `NE` `LT` `LE` `GT`
`GE`, or nothing for the unconditional form) onto the opcode. `CABxx` is a
comparison guarding a branch. `CASxx` lines chain like `SELECT`/`WHEN` — the
first true comparison runs its subroutine and the rest are skipped — and the
group is closed by `ENDCS`.

Both take the branch target — a label for `CABxx`, a subroutine name for
`CASxx` — in the **Result** field, with the two values being compared in
Factor 1 and Factor 2. The unconditional `CAS`/`CAB` forms leave both factors
blank.

```rpgle
     C     amt           CABGT     limit         OVER
     C     code          CASEQ     'A'           SUBA
     C     code          CASEQ     'B'           SUBB
     C                   CAS                     SUBOTHER
     C                   ENDCS
```

### Traditional Program Calls

`CALL` with its `PARM` lines names the program in Factor 2:

```rpgle
     C                   CALL      'ORD100'
     C                   PARM                    custNo
     C                   PARM                    total
```

There is no prototype, so the callee's signature is synthesized from the
`PARM` operands' declared types, every parameter passed by reference. If caller
and callee disagree, the link fails — an ugly error, but not a silent one.

A named `PLIST` can appear anywhere in the source, including after the calls
that use it:

```rpgle
     C                   CALL      'ORD100'      ORDPARMS
     C     ORDPARMS      PLIST
     C                   PARM                    custNo
     C                   PARM                    total
```

The one ordering rule is that the `PLIST` must be in the same run of C-spec
lines as its `CALL` or a later one — a `CALL` in an *earlier* run than its
`PLIST` is refused by name.

`PARM` also supports Factor 1 and Factor 2 operands, which move data into the
parameter before the call and out of it afterwards.

### Program Parameters — `*ENTRY PLIST`

A member with an `*ENTRY PLIST` does not compile to a `main()`. It becomes a
callable function taking each parameter by reference, which is exactly the
signature a caller's `CALL`/`PARM` synthesizes:

```rpgle
     C     *ENTRY        PLIST
     C                   PARM                    inCustNo
     C                   PARM                    outTotal
```

The function's name comes from the **source file name**, upper-cased with the
directory and extension stripped — `ORD100.rpgle` is reachable as
`CALL 'ORD100'`. A file name that is not a usable symbol is refused with a
message telling you to rename the file.

### `/COPY` and `/INCLUDE`

Both work outside `/free` blocks, as a line-splicing pass that runs before
anything else, so a copied H/F/D/C line is indistinguishable from one that was
physically present:

```rpgle
      /COPY custdefs.rpgleinc
```

The text after the directive is a literal filename opened relative to the
current working directory — there is no library or member catalog and no search
path. Nesting is capped at 10 levels. Line numbers after an expansion point
refer to the flattened line stream rather than the original file.

### Embedded SQL in Fixed Columns

`C/EXEC SQL` opens the statement, `C+` continues it, and `C/END-EXEC` closes it:

```rpgle
     C/EXEC SQL
     C+ SELECT COUNT(*) INTO :rowCount
     C+   FROM customers WHERE status = 'A'
     C/END-EXEC
```

The gathered text goes to the same SQL handling free-format `EXEC SQL` uses, so
everything in the [Embedded SQL](#embedded-sql) chapter applies unchanged.

### What Is Not Supported

The RPG cycle is not implemented and will not be. Concretely, in fixed-format
source that means:

| Rejected | Where | Note |
|----------|-------|------|
| Control levels `L0`, `L1`-`L9`, `LR` | C-spec positions 7-8 | Cycle-only |
| Resulting indicators | C-spec 71-76 | Except on `COMP` |
| Inline field length/decimals | C-spec 64-70 | Use a D-spec |
| `P`-specs | — | No procedure declaration; use a `/free` block |
| D-spec types `C`, `PR`, `PI` | D-spec 24-25 | Constants and prototypes; use a `/free` block |
| `DO` | — | Use `FOR` |
| Matching fields | I-spec 65-66 | Cycle-adjacent |
| Sequence checking | I-spec 17-20 | Must be blank |

Every one of these produces a distinct compile error naming the problem, rather
than being silently ignored.

---

## Program-Described Files (I-Specs and O-Specs)

Everything in the [Record-Level Access](#record-level-access) chapter runs
against a database table over ODBC. Program-described files are the other kind:
**flat files with a byte-position field layout**, described by I-specs and
O-specs rather than by an external descriptor. They are available from
fixed-format source only.

### The On-Disk Format

Real IBM i program-described files are pure fixed-width bytes on a
record-oriented file system, which has no equivalent on macOS, Linux or
Windows. OpenRPG uses a portable convention instead: **one record per line** —
exactly the declared record length in bytes, right-padded with spaces or
truncated to fit, followed by a newline. Fixed width makes byte-offset seeking
for `UPDATE` trivial.

Numeric fields are stored as plain ASCII digits, right-justified and
zero-padded, with an implied decimal point and an optional leading `-`. This is
an OpenRPG interchange format, not literal IBM i on-disk semantics.

### A Complete Example

```rpgle
     HDFTACTGRP(*NO)
     FTESTFL          25           DISK
     ITESTFL
     I                             A1    20     NAME
     I                             S21   25   0 AGE
     OTESTFL
     O                       NAME             20
     O                       AGE              25
      /free
  NAME = 'Alice';
  AGE = 30;
  WRITE TESTFL;
      /end-free
     C                   READ      TESTFL
     C                   DOW       NOT %EOF(TESTFL)
     C     %TRIM(NAME)   DSPLY
     C                   READ      TESTFL
     C                   ENDDO
     C                   RETURN
```

The F-spec gives the record length in positions 23-27 and leaves the file
format column blank (program-described). Field names from the I-spec become
ordinary program variables.

### I-Spec — Input Layout

An I-spec file has one **record identification** line per record type,
optionally followed by **field description** lines.

Record identification:

| Positions | Field |
|-----------|-------|
| 7-16 | File name |
| 21-22 | Record identifying indicator |
| 23-30, 31-38, 39-46 | Up to three identification code sets |

Each code set is a position, an optional `N`, a code part and a character —
which together say "the byte at this position is (or is not) this character".
Only code part `C` (character) is supported; the EBCDIC-era zone (`Z`) and digit
(`D`) tests are rejected.

Field description:

| Positions | Field |
|-----------|-------|
| 36 | Data format |
| 37-41 | From byte position |
| 42-46 | To byte position |
| 47-48 | Decimal positions |
| 49-62 | Field name |
| 63-64 | Control level (`L1`-`L9`) |
| 69-70 | Plus indicator |
| 71-72 | Minus indicator |
| 73-74 | Zero-or-blank indicator |

Date, time, timestamp, graphic and indicator formats (`D`/`T`/`Z`/`G`/`N`) are
rejected at parse time — a `CHAR` field still works fine for date text if you
do not need real date parsing.

Control levels in positions 63-64 parse and are accepted, but do not yet set
anything at run time.

### O-Spec — Output Layout

One record identification line per file, followed by one field or constant line
each:

| Positions | Field |
|-----------|-------|
| 30-43 | Field name — blank if a constant is given instead |
| 44 | Edit code |
| 45 | Blank-after (`B`) |
| 47-51 | End position |
| 53-80 | Constant or edit word |

Field width is inferred from the gap to the previous field's end position, not
from the field's own declared length. End positions must be absolute — the
relative `+n`/`-n` forms are not supported. Edit codes use the same engine as
`%EDITC`.

**A file may have exactly one O-spec record format.** A second one is rejected
with a clear error rather than silently overwriting the first, because
disambiguating them needs the record-type and `EXCEPT` mechanisms, which are
not implemented.

### Supported Operations

| Opcode | Behavior |
|--------|----------|
| `READ` | Sequential read, dispatching on record type |
| `WRITE` | Append a record |
| `UPDATE` | Rewrite the record just read, in place |

`CHAIN`, `SETLL`, `SETGT` and `DELETE` are **not** supported on
program-described files — keyed access needs F-spec key-field columns that are
not modeled for them. `EXCEPT`, O-spec spacing and skipping, and printer paging
are also unavailable; there is no PRINTER runtime in this compiler for any file
type.

A program just writes `READ MYFILE;` regardless of which kind of file `MYFILE`
is — the compiler picks the flat-file or the RLA path from the declaration.

---

## Complete Example: Employee Report

Here's a full program that connects to a database, queries employees, and displays a report:

**employee_report.sqlrpgle:**
```rpgle
**FREE

DCL-DS emp QUALIFIED;
  id     INT(10);
  name   VARCHAR(50);
  salary PACKED(9:2);
END-DS;

DCL-S connStr VARCHAR(200);
DCL-S total   PACKED(11:2) INZ(0);
DCL-S count   INT(10) INZ(0);

// Connect using environment variable or default
connStr = %GETENV('DATABASE_URL');
IF connStr = '';
  connStr = 'Driver={SQLite3};Database=company.sqlite;';
ENDIF;

EXEC SQL CONNECT USING :connStr;

IF SQLCOD < 0;
  DSPLY 'Failed to connect to database';
  RETURN;
ENDIF;

// Declare and open cursor
EXEC SQL DECLARE empCur CURSOR FOR
  SELECT id, name, salary FROM employees
  ORDER BY salary DESC;

EXEC SQL OPEN empCur;

// Fetch and display
DSPLY '--- Employee Report ---';
EXEC SQL FETCH empCur INTO :emp.id, :emp.name, :emp.salary;

DOW SQLCOD = 0;
  DSPLY %CHAR(emp.id) + '  ' + %TRIM(emp.name) + '  $' + %CHAR(emp.salary);
  total += emp.salary;
  count += 1;
  EXEC SQL FETCH empCur INTO :emp.id, :emp.name, :emp.salary;
ENDDO;

EXEC SQL CLOSE empCur;

DSPLY '-----------------------';
DSPLY 'Employees: ' + %CHAR(count);
DSPLY 'Total Payroll: $' + %CHAR(total);

EXEC SQL DISCONNECT;

*INLR = *ON;
RETURN;
```

```bash
./rpgc employee_report.sqlrpgle
./employee_report
```
