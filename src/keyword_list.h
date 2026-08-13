#ifndef RPG_KEYWORD_LIST_H
#define RPG_KEYWORD_LIST_H

#include <map>
#include <string>

namespace rpg {

// Generic KEYWORD(value) / KEYWORD (flag-only) scanner — shared by
// CTL-OPT's keyword-list content (free-format, wrapped in "CTL-OPT(...)")
// and H-spec's keyword-list content (fixed-format, columns 7-80, no
// wrapper): both are the same "space-separated KEYWORD(value)..."
// vocabulary. Returns uppercased-key -> raw-arg-string (original case,
// trimmed of surrounding whitespace); flag-only keywords (no parens) map
// to an empty string. Values are NOT further parsed/validated here — the
// caller decides which keys it cares about (see ctlopt_* globals in
// lexer.l for the 4 currently meaningful ones: MAIN, NOMAIN, DATFMT,
// TIMFMT).
std::map<std::string, std::string> parseKeywordList(const std::string& text);

} // namespace rpg

#endif // RPG_KEYWORD_LIST_H
