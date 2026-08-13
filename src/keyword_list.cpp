#include "keyword_list.h"
#include <cctype>

namespace rpg {

static std::string trim(const std::string& s) {
    size_t a = s.find_first_not_of(" \t");
    if (a == std::string::npos) return "";
    size_t b = s.find_last_not_of(" \t");
    return s.substr(a, b - a + 1);
}

std::map<std::string, std::string> parseKeywordList(const std::string& text) {
    std::map<std::string, std::string> result;
    size_t i = 0;
    size_t n = text.size();
    while (i < n) {
        // Skip whitespace and stray separators between keywords.
        while (i < n && (isspace((unsigned char)text[i]) || text[i] == ':')) i++;
        if (i >= n) break;

        // Read a keyword name: letters/digits/underscore. A tokenizer
        // reading the whole name (rather than the old code's
        // substring-search-for-"MAIN(") naturally distinguishes MAIN
        // from NOMAIN as different tokens with no special-casing needed.
        size_t start = i;
        while (i < n && (isalnum((unsigned char)text[i]) || text[i] == '_')) i++;
        if (i == start) { i++; continue; } // stray character, skip it

        std::string key = text.substr(start, i - start);
        for (auto& c : key) c = (char)toupper((unsigned char)c);

        // Optional (value) — no space required before the paren.
        std::string value;
        if (i < n && text[i] == '(') {
            size_t depth = 0;
            size_t j = i;
            while (j < n) {
                if (text[j] == '(') depth++;
                else if (text[j] == ')') { if (--depth == 0) { j++; break; } }
                j++;
            }
            // text[i+1 .. j-2] is the inner content (excluding the parens).
            if (j > i + 1) value = trim(text.substr(i + 1, (j - 1) - (i + 1)));
            i = j;
        }

        result[key] = value;
    }
    return result;
}

} // namespace rpg
