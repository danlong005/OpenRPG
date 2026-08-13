#ifndef RPG_FIXED_READER_H
#define RPG_FIXED_READER_H

#include <string>
#include "ast.h"

namespace rpg {
namespace fixed {

// Parses classic fixed-format (column-based) RPG source — Phase 1 scope:
// H-spec (control options), F-spec (externally-described DISK/WORKSTN/
// PRINTER files), D-spec (standalone fields and basic non-OCCURS
// DS/subfields), and C-spec limited to /free...end-free blocks (whose
// body is parsed by the existing free-format lexer/parser, unchanged,
// via parse_free_block() in free_bridge.h). See TODO.md's "Fixed-Format
// Source Support" entry for exactly what's in vs. out of scope.
//
// Errors are reported the same way the free-format parser's yyerror()
// does — via report_fixed_format_error() (free_bridge.h), incrementing
// the same global error count get_parse_error_count() reads, so
// main.cpp's existing error-handling path needs no changes.
Program* parseFixedFormat(const std::string& src_text, const std::string& filename);

} // namespace fixed
} // namespace rpg

#endif // RPG_FIXED_READER_H
