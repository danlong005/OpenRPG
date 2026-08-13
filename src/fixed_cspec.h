#ifndef RPG_FIXED_CSPEC_H
#define RPG_FIXED_CSPEC_H

#include <string>
#include <vector>

namespace rpg {
namespace fixed {

// Accumulates a contiguous run of native (column-based) C-spec lines,
// transpiling each into free-form-equivalent text so the whole run can be
// handed to parse_free_block() exactly once — the same bridge Phase 1
// already uses for explicit /free...end-free blocks (see free_bridge.h).
// This lets traditional and extended-factor-2 C-spec reuse 100% of the
// free-format lexer/parser/AST: no new grammar, no hand-rolled expression
// parser. See the SC09-2508 citations in fixed_columns.h's CSpec
// namespace and TODO.md's "Fixed-Format Source Support" entry for the
// manual references behind each opcode's field mapping.
//
// bufLines holds exactly one entry per physical C-spec line consumed
// (continuation lines contribute text to an earlier entry, not a new
// one) so parse_free_block's line numbers stay aligned with the
// original source.
struct CSpecRunState {
    std::vector<std::string> bufLines;
    int startLine = 0;
    bool pendingExt = false; // mid-way through an extended-factor-2 statement
    int pendingLineIdx = -1; // bufLines index of that statement's most recent line
};

// Feeds one physical native C-spec line (spec type already confirmed 'C',
// and not a /FREE directive line) into the run. lineNo is the 1-based
// physical line number in the whole source file. Errors are reported via
// report_fixed_format_error (free_bridge.h) and the run continues
// (best-effort recovery, matching the rest of this fixed-format reader).
void feedCSpecLine(CSpecRunState& state, const std::string& line, int lineNo);

// Closes any still-open extended-factor-2 statement, joins the run's
// buffered lines into one string suitable for parse_free_block(), and
// resets `state` for reuse. `outStartLine` receives the run's starting
// physical line number. Call when the run ends: a non-'C' spec-type line
// appears, an explicit /FREE directive is hit, or EOF is reached.
std::string flushCSpecRun(CSpecRunState& state, int& outStartLine);

} // namespace fixed
} // namespace rpg

#endif // RPG_FIXED_CSPEC_H
