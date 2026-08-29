#ifndef RPG_FIXED_CSPEC_H
#define RPG_FIXED_CSPEC_H

#include <map>
#include <string>
#include <vector>

namespace rpg {
namespace fixed {

// One PARM line. SC09-2508 p.929 gives the Result field as the parameter
// itself — the field whose *address* is passed — and Factor 1/Factor 2 as
// optional move operands around the call: on the call, factor 2 is copied
// into the result field; on return, the result field is copied into
// factor 1. Both moves are "in the same way as data is moved using the
// EVAL operation code", so each is one plain assignment.
struct CSpecParm {
    std::string target; // Factor 1 — receives the parameter after the call
    std::string source; // Factor 2 — copied into the parameter before it
    std::string name;   // Result — the parameter passed by reference
    int line = 0;       // the PARM's own source line, for diagnostics
};

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
    // Text appended after the terminating ';' when that statement finally
    // closes — " ENDIF;" when a conditioning indicator (positions 9-11)
    // opened an IF wrapper around it, empty otherwise.
    std::string pendingSuffix;
    // Conditioning indicators accumulated from an AND/OR group (`AN`/`OR`
    // in positions 7-8) that is still waiting for the line carrying its
    // operation code. Outer vector = AND-groups, ORed together; inner =
    // the terms of one AND-group. Empty whenever no group is open.
    std::vector<std::vector<std::string>> condGroups;
    int condLine = 0; // physical line the open group started on, for diagnostics
    // A CALL whose PARM lines have not all been seen yet. The assembled
    // statement is written back into the CALL's own buffer line (index
    // callLineIdx) once the run of PARM lines ends, so each physical line
    // still owns exactly one buffer entry.
    bool pendingCall = false;
    int callLineIdx = -1;
    int callLine = 0;                     // for diagnostics
    std::string callProgram;              // factor 2 literal, quotes included
    std::string callCond;                 // conditioning indicator on the CALL line
    std::vector<CSpecParm> callParms;     // PARM lines following it, in order
    // A named PLIST gathering its own PARM lines. PLIST is declarative —
    // it emits no statement — so unlike CALL it owns no buffer line.
    bool inPlist = false;
    std::string plistName;
    int plistLine = 0;
    // Set when a PLIST line was rejected. Its PARM lines are then swallowed
    // silently rather than each reporting itself an orphan — one diagnostic
    // for one mistake. Cleared by the next non-PARM operation.
    bool plistSuppress = false;
    // Whether the open PLIST has seen a PARM line at all, valid or not.
    // A PARM that was itself rejected still means the list is not empty,
    // so the "no PARM line" diagnostic stays quiet — one per mistake.
    bool plistSawParm = false;
    // Named parameter lists collected so far, keyed by upper-cased name.
    // Outlives a single run (flushCSpecRun carries it over) because the
    // calculations of one program can be split into several runs by an
    // interleaved spec type, and a PLIST is a program-wide declaration.
    std::map<std::string, std::vector<CSpecParm>> plists;
    // A CALL that named a PLIST in its Result field. "A named PLIST can
    // be defined after the CALL that references it", so these cannot be
    // assembled in line order the way an inline PARM run can — the site
    // is recorded here and substituted once the run is flushed.
    struct PendingPlistCall {
        int bufIdx;
        int line;
        std::string program;
        std::string plist; // upper-cased, to match `plists`
        std::string cond;
    };
    std::vector<PendingPlistCall> plistCalls;
    // A CASxx group in progress. CASxx lines chain like SELECT/WHEN — the
    // first true comparison runs its subroutine — so the group transpiles
    // to an IF/ELSEIF/ELSE chain that ENDCS closes. casOpened is false
    // when the group led with an unconditional CAS, which needs no IF and
    // therefore no ENDIF.
    bool inCasGroup = false;
    bool casOpened = false;
    bool casElse = false; // an unconditional CAS has already taken the ELSE arm
    int casLine = 0;
    // Fixed-column embedded SQL in progress: C/EXEC SQL ... C+ ...
    // C/END-EXEC. The gathered statement is written into the C/EXEC SQL
    // line's own buffer entry when C/END-EXEC arrives.
    bool inSqlCapture = false;
    int sqlLineIdx = -1;
    int sqlLine = 0;
    std::string sqlText;
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
