# OpenRPG

![OpenRPG logo](assets/openrpg_logo.svg)

OpenRPG is an open-source, clean-room compiler for IBM RPG IV free-format source code. The `rpgc` binary compiles `.rpgle` source into executables that run on macOS, Linux, or Windows — no IBM i required.

## Installation

Pre-built packages are available on the [Releases](../../releases) page.

### macOS

Download `openrpg-<version>.pkg` from the Releases page — it bundles both `rpgc` and `dspfc`. Two things must be present before installing. The **Xcode Command Line Tools** supply the `clang++` that `rpgc` invokes to build the programs it compiles, plus the ncurses headers display-file programs need:

```bash
xcode-select --install     # skip if `xcode-select -p` already prints a path
```

And the `unixodbc` library, which `rpgc` itself links against:

```bash
brew install unixodbc
```

Installing Homebrew pulls in the Command Line Tools, so if you already have `brew` you almost certainly have them.

Apple Silicon (arm64) only — GitHub's hosted macOS runners dropped Intel support, so there's no x86_64 build.

If you plan to use SQL or RLA features, see [Database Connectivity — macOS](#macos) for the additional SQLite driver registration step.

Because OpenRPG is not code-signed with an Apple Developer certificate, macOS Gatekeeper will block the installer. Clear the quarantine flag before opening it:

```bash
xattr -cr ~/Downloads/openrpg-*.pkg
```

Then double-click the `.pkg` to install. This puts `rpgc` on your PATH system-wide.

### Linux

Download the `.deb` (Debian/Ubuntu) or `.rpm` (RHEL/Fedora) from the Releases page — each is available for both x86_64 (`amd64`/`x86_64`) and ARM64 (`arm64`/`aarch64`, e.g. AWS Graviton, Raspberry Pi). The packages declare everything they need — the C++ compiler, the unixODBC headers and library, and the ncurses headers for display-file programs — so the package manager will pull it all in automatically.

**Debian/Ubuntu:**
```bash
sudo dpkg -i rpgc_*.deb
sudo apt-get install -f     # resolves any missing dependencies
```

**RHEL/Fedora:**
```bash
sudo dnf install ./rpgc-*.rpm
```

### Windows

Download `openrpg-<version>-windows-x64.exe` (x86_64) or `openrpg-<version>-windows-arm64.exe` (Windows on ARM, e.g. Surface Pro X, Snapdragon X devices) from the Releases page and run the installer. It adds `rpgc` to your PATH automatically.

**No other prerequisites needed.** The installer bundles a self-contained C++ compiler (a trimmed [llvm-mingw](https://github.com/mstorsjo/llvm-mingw) toolchain) that `rpgc`/`dspfc` use to build the programs they compile, plus a PDCurses build for WORKSTN/display-file programs — you don't need MSYS2, Visual Studio, or anything else installed first. (SQL/RLA features are the one exception: those still need a platform ODBC driver installed separately — see [Database Connectivity](#database-connectivity) below.)

> **ARM64 note:** among the ODBC drivers this guide covers, only Microsoft's ODBC Driver 18 for SQL Server (18.2+) publishes a native ARM64 Windows build. SQLite, PostgreSQL, and MySQL/MariaDB don't — their installers are x86_64-only — so SQL/RLA features against those three aren't available on Windows ARM64 without building a driver from source yourself. See [Database Connectivity](#database-connectivity) below.

---

## Quick Start

**hello.rpgle:**
```rpgle
**FREE
DCL-S msg VARCHAR(50);
msg = 'Hello from RPG!';
DSPLY msg;
*INLR = *ON;
```

```bash
rpgc hello.rpgle
./hello
```

**Output:**
```
Hello from RPG!
```

---

## Usage

```
rpgc <source-file> [options]
```

| Flag | Description |
|------|-------------|
| `-o file` | Output file |
| `-g` | Compile with debug symbols for source-level debugging |
| `-v` | Print version and exit |

```bash
rpgc program.rpgle              # produces ./program
rpgc program.rpgle -o myapp     # produces ./myapp
rpgc -v                         # print version
```

SQL programs (`.sqlrpgle`) are linked with ODBC automatically — no extra flags needed.

---

## Database Connectivity

SQL programs (`.sqlrpgle`) and RPG programs that use record-level access (RLA) connect to databases through ODBC. OpenRPG works with any database that has an ODBC driver — SQLite, PostgreSQL, MySQL, SQL Server, Db2, and more.

### Platform Setup

The steps below use SQLite as the example. Other database drivers follow the same install-and-register pattern.

#### macOS

Install the unixODBC runtime and the SQLite ODBC driver:

```bash
brew install unixodbc sqliteodbc
```

> **Important — manual driver registration required.**
> Homebrew installs the SQLite driver library but does **not** register it with unixODBC.
> Without this step `Driver={SQLite3}` silently fails — programs compile but produce no
> output from SQL or RLA operations.

Register the driver once after installation:

```bash
DRIVER=$(brew --prefix)/lib/libsqlite3odbc.dylib
printf '[SQLite3]\nDescription=SQLite3 ODBC Driver\nDriver=%s\nSetup=%s\n' \
  "$DRIVER" "$DRIVER" \
  | ODBCSYSINI=/opt/homebrew/etc odbcinst -i -d -f /dev/stdin
```

Also add `ODBCSYSINI` to your shell profile so unixODBC can find its configuration whenever you run a compiled program:

```bash
# add to ~/.zshrc or ~/.bash_profile
export ODBCSYSINI=/opt/homebrew/etc
```

Then reload your shell (`source ~/.zshrc`) or open a new terminal.

#### Linux — Ubuntu / Debian

```bash
sudo apt install unixodbc unixodbc-dev libsqliteodbc
```

`libsqliteodbc` registers the driver automatically. `unixodbc-dev` provides the ODBC headers that `rpgc` needs when it compiles generated C++ for SQL programs.

#### Linux — RHEL / Fedora

```bash
sudo dnf install unixODBC unixODBC-devel sqliteodbc
```

#### Windows

> x86_64 only — the ch-werner installer has no ARM64 build. On Windows ARM64, SQLite via ODBC isn't available unless you compile the driver yourself.

Download and run the SQLite ODBC installer from [www.ch-werner.de/sqliteodbc](https://www.ch-werner.de/sqliteodbc/) (`sqliteodbc_w64.exe` for 64-bit).

The installer registers the driver as `SQLite3 ODBC Driver`. To use the shorter `Driver={SQLite3}` form in connection strings (matching the examples in this guide), add a registry alias. Run the following in an **elevated PowerShell** prompt:

```powershell
$key     = "HKLM:\SOFTWARE\ODBC\ODBCINST.INI"
$dllPath = (Get-ItemProperty "$key\SQLite3 ODBC Driver" -Name Driver).Driver
New-Item         "$key\SQLite3"         -Force | Out-Null
New-ItemProperty "$key\SQLite3" -Name Driver -Value $dllPath -PropertyType String -Force | Out-Null
New-ItemProperty "$key\SQLite3" -Name Setup  -Value $dllPath -PropertyType String -Force | Out-Null
Set-ItemProperty "$key\ODBC Drivers"    -Name SQLite3 -Value Installed
```

Alternatively, skip the alias and use the full name in your connection strings:
`Driver={SQLite3 ODBC Driver}`.

---

### Connecting from RPG Source

**Option 1 — explicit `EXEC SQL CONNECT` in the source file:**

```rpgle
DCL-S connStr VARCHAR(200);
connStr = 'Driver={SQLite3};Database=/path/to/myapp.db;';
EXEC SQL CONNECT USING :connStr;
```

**Option 2 — `rpgc.conf` (no `EXEC SQL CONNECT` needed):**

Create a config file with your DSN and `rpgc` wires up the connection automatically at startup, exactly like an IBM i job environment:

```ini
# ~/.rpgc.conf       — applies to all programs for your user
# ./rpgc.conf        — project-specific, takes priority over ~/.rpgc.conf
# /etc/rpgc.conf     — system-wide default

DB_DSN=Driver={SQLite3};Database=/path/to/myapp.db;
```

**Option 3 — `RPGC_DSN` environment variable (highest priority, useful for CI):**

```bash
RPGC_DSN="Driver={SQLite3};Database=./test.db;" rpgc myprog.sqlrpgle
./myprog
```

---

### PostgreSQL Example

This complete example connects to PostgreSQL, runs an aggregate query, then iterates a cursor to print results. Save it as `pg_employees.sqlrpgle`.

**Setup** (one time):

```bash
# macOS — install and register the driver
brew install psqlodbc
DRIVER=$(brew --prefix)/lib/psqlodbcw.so
printf '[PostgreSQL Unicode]\nDescription=PostgreSQL ODBC Driver (Unicode)\nDriver=%s\nSetup=%s\n' \
  "$DRIVER" "$DRIVER" \
  | ODBCSYSINI=/opt/homebrew/etc odbcinst -i -d -f /dev/stdin

# Create a demo database and populate it
psql -U $USER postgres -c "CREATE DATABASE rpgdemo;"
psql -U $USER rpgdemo -c "
CREATE TABLE employees (
  id SERIAL PRIMARY KEY, name VARCHAR(50),
  dept VARCHAR(30), salary DECIMAL(9,2)
);
INSERT INTO employees (name, dept, salary) VALUES
  ('Alice Johnson', 'Engineering', 85000),
  ('Bob Martinez',  'Marketing',   62000),
  ('Carol Smith',   'Engineering', 91000),
  ('David Lee',     'HR',          58000);"
```

**pg_employees.sqlrpgle:**

```rpgle
**FREE

DCL-S connStr  VARCHAR(200);
DCL-S empName  VARCHAR(50);
DCL-S salary   PACKED(9:2);
DCL-S total    PACKED(11:2);
DCL-S rowCount INT(10);

connStr = 'Driver={PostgreSQL Unicode};Server=localhost;Port=5432;Database=rpgdemo;Uid=dlong;Pwd=;';
EXEC SQL CONNECT USING :connStr;

// Aggregate: headcount and total payroll for Engineering
EXEC SQL SELECT COUNT(*), SUM(salary)
         INTO   :rowCount, :total
         FROM   employees
         WHERE  dept = 'Engineering';

DSPLY ('Engineering headcount: ' + %CHAR(rowCount));
DSPLY ('Total payroll:         $' + %CHAR(total));
DSPLY '---';

// Cursor: list Engineering employees, highest salary first
EXEC SQL DECLARE c1 CURSOR FOR
  SELECT name, salary FROM employees
  WHERE  dept = 'Engineering'
  ORDER  BY salary DESC;

EXEC SQL OPEN c1;
DOW SQLCODE = 0;
  EXEC SQL FETCH c1 INTO :empName, :salary;
  IF SQLCODE = 0;
    DSPLY (empName + '  $' + %CHAR(salary));
  ENDIF;
ENDDO;
EXEC SQL CLOSE c1;

EXEC SQL DISCONNECT;
*INLR = *ON;
```

**Compile and run:**

```bash
rpgc pg_employees.sqlrpgle -o pg_employees
./pg_employees
```

**Output:**

```
Engineering headcount: 2
Total payroll:         $176000.00
---
Carol Smith  $91000.00
Alice Johnson  $85000.00
```

The full source is in [`examples/pg_employees.sqlrpgle`](examples/pg_employees.sqlrpgle).

---

### Supported Databases

| Database | macOS | Linux (apt) | Windows | Example DSN |
|----------|-------|-------------|---------|-------------|
| **SQLite** | `brew install sqliteodbc` + register (see above) | `apt install libsqliteodbc` | [ch-werner.de/sqliteodbc](https://www.ch-werner.de/sqliteodbc/) | `Driver={SQLite3};Database=/path/to/file.db;` |
| **PostgreSQL** | `brew install psqlodbc` | `apt install odbc-postgresql` | [psqlodbc.postgresql.org](https://psqlodbc.postgresql.org/) | `Driver={PostgreSQL Unicode};Server=localhost;Port=5432;Database=mydb;Uid=user;Pwd=pass;` |
| **MySQL / MariaDB** | `brew install mysql-connector-odbc` | `apt install odbc-mariadb` | [dev.mysql.com/downloads/connector/odbc](https://dev.mysql.com/downloads/connector/odbc/) | `Driver={MySQL ODBC 8.0 Unicode Driver};Server=localhost;Database=mydb;User=user;Password=pass;` |
| **SQL Server** | — | [Microsoft ODBC Driver](https://learn.microsoft.com/sql/connect/odbc/download-odbc-driver-for-sql-server) | [Microsoft ODBC Driver](https://learn.microsoft.com/sql/connect/odbc/download-odbc-driver-for-sql-server) | `Driver={ODBC Driver 18 for SQL Server};Server=localhost;Database=mydb;Uid=user;Pwd=pass;` |
| **IBM Db2** | — | [IBM Data Server Driver](https://www.ibm.com/support/pages/db2-odbc-cli-driver-download-and-installation-information) | [IBM Data Server Driver](https://www.ibm.com/support/pages/db2-odbc-cli-driver-download-and-installation-information) | `Driver={IBM DB2 ODBC DRIVER};Database=mydb;Hostname=localhost;Port=50000;Protocol=TCPIP;Uid=user;Pwd=pass;` |

> For RHEL/Fedora, substitute the equivalent `dnf` package name (e.g. `psqlodbc` → `postgresql-odbc`).

> **Windows ARM64:** of the drivers above, only SQL Server's Microsoft ODBC Driver (18.2+) ships a native ARM64 build. SQLite, PostgreSQL, and MySQL/MariaDB are x86_64-only on Windows.

---

### Compiling SQL Programs Manually

If you generate `.cpp` files with `rpgc -S` and compile them yourself (e.g., in a `Makefile`), link with the platform ODBC library. The flags must appear **after** the source file:

| Platform | Flags |
|----------|-------|
| macOS | `-I$(brew --prefix)/include -L$(brew --prefix)/lib -lodbc` |
| Linux | `-lodbc` |
| Windows (MinGW) | `-lodbc32` |

On Windows, the compiler `rpgc` itself uses is bundled with the installer at `<install-dir>\mingw\bin\<x86_64\|aarch64>-w64-mingw32-clang++.exe` (that directory is also on PATH after installing, so `clang++` resolves to it directly) — no separate MinGW/MSYS2 install needed to compile manually either.

```bash
# macOS example
clang++ -std=c++17 -I/usr/local/share/rpgc/runtime \
  myprog.cpp \
  -I$(brew --prefix)/include -L$(brew --prefix)/lib -lodbc \
  -o myprog
```

---

## Debugging in VS Code

`rpgc -g` compiles with full debug symbols and generates `.vscode/launch.json` for the **CodeLLDB** extension. The debugger maps execution back to your original `.rpgle` source.

**One-time setup** — install the VS Code extension for your platform:

| Platform | Extension |
|----------|-----------|
| macOS / Linux | [CodeLLDB](https://marketplace.visualstudio.com/items?itemName=vadimcn.vscode-lldb) (`vadimcn.vscode-lldb`) |
| Windows | [C/C++](https://marketplace.visualstudio.com/items?itemName=ms-vscode.cpptools) (`ms-vscode.cpptools`) |

**Per-program:**
```bash
rpgc -g program.rpgle -o program
```

Then open the folder in VS Code, set breakpoints in your `.rpgle` file, and press **F5**.

---

## Multi-Module Programs

OpenRPG supports splitting programs across multiple source files using `CTL-OPT NOMAIN` with `EXPORT`/`IMPORT` and `EXTPROC`:

```bash
rpgc -c module.rpgle          # compile module to module.o
rpgc main.rpgle module.o      # compile main and link with module
```

See the [User's Guide](docs/GUIDE.md#multi-module-programs) for details.

---

## Documentation

- **[User's Guide](https://github.com/danlong005/OpenRPG/wiki)** — Full language reference with examples, browsable on the wiki (source: [docs/GUIDE.md](docs/GUIDE.md))
- **[TODO.md](TODO.md)** — Feature tracker

### Highlights

- Full free-format RPG IV support (declarations, control flow, expressions)
- Fixed-format (column-based) source, mixable with free-format in one file
- Display files (WORKSTN) with subfiles, via the OpenDSPF compiler
- Program-described flat files (I-specs and O-specs)
- 90+ built-in functions
- Data structures (QUALIFIED, DIM, LIKEDS, OVERLAY, POS, PREFIX)
- Procedures with prototypes, optional parameters (*NOPASS, *OMIT)
- Enumerations (DCL-ENUM) and BOOLEAN type
- Varying-dimension arrays (DIM(*VAR), DIM(*AUTO))
- Date/time arithmetic with all format constants
- MONITOR/ON-ERROR error handling, *PSSR, ON-EXIT
- Multi-module support (NOMAIN, EXPORT, IMPORT, EXTPROC)
- Conditional compilation (/IF, /DEFINE, /COPY)
- Embedded SQL via ODBC (SQLite, PostgreSQL, MySQL, SQL Server, Db2)
- Record-level access (READ, WRITE, CHAIN, UPDATE, DELETE, SETLL, SETGT) via ODBC
- DATA-INTO / DATA-GEN for JSON parsing and generation
- Source-level debugging in VS Code (`rpgc -g`)

---

## Building from Source

If you prefer to build from source rather than using a pre-built package:

**Prerequisites:** C++17 compiler (clang++ or g++), Flex, Bison.

```bash
# macOS
brew install flex bison

# Linux (Debian/Ubuntu)
sudo apt install flex bison g++

# Windows (x86_64) — use MSYS2 MINGW64 shell
pacman -S mingw-w64-x86_64-gcc mingw-w64-x86_64-flex mingw-w64-x86_64-bison make

# Windows (ARM64) — use MSYS2 CLANGARM64 shell (no native gcc for this target)
pacman -S mingw-w64-clang-aarch64-toolchain flex bison make
```

```bash
git clone https://github.com/danlong005/OpenRPG.git
cd OpenRPG
make
sudo make install        # installs to /usr/local
```

---

## Trademarks

RPG, RPG IV, ILE, ILE RPG, RPG/400, IBM i, AS/400, and Db2 are trademarks
or registered trademarks of International Business Machines Corporation in
the United States, other countries, or both. Other product and service
names might be trademarks of IBM or other companies.

This project is an independent, clean-room implementation. It is not
affiliated with, endorsed by, sponsored by, or otherwise associated with
IBM. References to IBM products and technologies are made solely for the
purpose of describing compatibility and interoperability (nominative fair
use).

## License

MIT — see [LICENSE](LICENSE) for details.
