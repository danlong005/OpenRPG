#ifndef RPG_FREE_BRIDGE_H
#define RPG_FREE_BRIDGE_H

#include <memory>
#include <string>
#include <vector>
#include "ast.h"

// Parses `text` (the raw body between /free and /end-free, NOT including
// those directive lines themselves) as ordinary free-format RPG
// statements, reusing the existing lexer/parser completely unchanged —
// this is the bridge that lets a fixed-format source member host modern
// statement syntax inside a C-spec /free block. Implemented in
// parser.y's C epilogue (it needs direct access to that file's internal
// g_program/yyparse() state).
//
// start_line is the physical line number of the first line of `text` in
// the whole compilation unit, so line numbers in the returned
// statements — and in any diagnostics raised while parsing them — stay
// correct relative to the original source file, not relative to `text`
// in isolation.
//
// Not reentrant (relies on flex/bison global state: yylineno, a
// file-scope g_program), matching get_parsed_program()'s own existing
// non-reentrancy — fine for this compiler's one-file-per-process model,
// but never call this from more than one thread/nested parse at a time.
std::vector<std::unique_ptr<rpg::Statement>>
parse_free_block(const std::string& text, int start_line);

// Reports a fixed-format-reader diagnostic through the same channel
// yyerror() uses (stderr, "Error at line N: ..." format) and increments
// the same global error count get_parse_error_count() reads — so a
// malformed D-spec, an unrecognized data-type letter, etc. gates
// compilation exactly like a free-format syntax error does, with no
// changes needed to main.cpp's existing `if (errors > 0)` check.
void report_fixed_format_error(int line, const std::string& msg);

// GOTO/TAG have no free-form syntax at all (SC09-2508 explicitly says so
// for both — "not allowed, use other operation codes"), so parser.y's
// goto_stmt/tag_stmt rules reject them unless this is true. Only the
// fixed-format reader's native C-spec transpiler (fixed_reader.cpp's
// flushCRun, via fixed_cspec.cpp) sets this true immediately around its
// own parse_free_block() call — genuine free-form text, whether the
// **FREE top-level entry point or an explicit /free...end-free block
// (even one embedded in an otherwise fixed-format file), always parses
// with this false, matching the manual exactly.
extern bool g_allow_goto_tag;

#endif // RPG_FREE_BRIDGE_H
