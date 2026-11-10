#include "vscode_config.h"

#include <cstdio>
#include <fstream>
#include <sstream>
#include <utility>
#include <vector>

namespace rpgc {

std::string jsonEscape(const std::string& s) {
    std::string o;
    for (unsigned char c : s) {
        switch (c) {
            case '"':  o += "\\\""; break;
            case '\\': o += "\\\\"; break;
            case '\n': o += "\\n"; break;
            case '\r': o += "\\r"; break;
            case '\t': o += "\\t"; break;
            default:
                if (c < 0x20) { char b[8]; std::snprintf(b, sizeof b, "\\u%04x", c); o += b; }
                else o += static_cast<char>(c);
        }
    }
    return o;
}

namespace {

// A JSONC value and where it is in the text: [begin, end).
struct Node {
    char kind = 0;  // '{' object, '[' array, '"' string, 'v' anything else
    size_t begin = 0, end = 0;
    std::string str;                                   // a string's value
    std::vector<std::pair<std::string, Node>> members; // an object's
    std::vector<Node> elems;                           // an array's
    const Node* get(const std::string& k) const {
        for (auto& m : members) if (m.first == k) return &m.second;
        return nullptr;
    }
};

// Just enough of a JSONC reader to find things: it checks structure, not
// every detail of a number or an escape.
class Reader {
public:
    explicit Reader(const std::string& t) : s(t) {}
    bool document(Node& root) {
        ws();
        if (!value(root)) return false;
        ws();
        return p == s.size();
    }
private:
    const std::string& s;
    size_t p = 0;

    void ws() {
        while (p < s.size()) {
            char c = s[p];
            if (c == ' ' || c == '\t' || c == '\n' || c == '\r') { p++; continue; }
            if (c == '/' && p + 1 < s.size() && s[p + 1] == '/') {
                while (p < s.size() && s[p] != '\n') p++;
                continue;
            }
            if (c == '/' && p + 1 < s.size() && s[p + 1] == '*') {
                size_t e = s.find("*/", p + 2);
                p = e == std::string::npos ? s.size() : e + 2;
                continue;
            }
            break;
        }
    }
    bool string(std::string& out) {
        if (p >= s.size() || s[p] != '"') return false;
        p++;
        while (p < s.size() && s[p] != '"') {
            if (s[p] == '\\') {
                if (++p >= s.size()) return false;
                char e = s[p];
                out += e == 'n' ? '\n' : e == 't' ? '\t' : e == 'r' ? '\r' : e;
                if (e == 'u') { out.pop_back(); p += 4; }  // not needed here
            } else {
                out += s[p];
            }
            p++;
        }
        if (p >= s.size()) return false;
        p++;
        return true;
    }
    bool value(Node& n) {
        if (p >= s.size()) return false;
        n.begin = p;
        char c = s[p];
        if (c == '{') {
            n.kind = '{'; p++;
            while (true) {
                ws();
                if (p < s.size() && s[p] == '}') { p++; break; }
                std::string key;
                if (!string(key)) return false;
                ws();
                if (p >= s.size() || s[p] != ':') return false;
                p++; ws();
                Node v;
                if (!value(v)) return false;
                n.members.emplace_back(key, std::move(v));
                ws();
                if (p < s.size() && s[p] == ',') { p++; continue; }
                if (p < s.size() && s[p] == '}') { p++; break; }
                return false;
            }
        } else if (c == '[') {
            n.kind = '['; p++;
            while (true) {
                ws();
                if (p < s.size() && s[p] == ']') { p++; break; }
                Node v;
                if (!value(v)) return false;
                n.elems.push_back(std::move(v));
                ws();
                if (p < s.size() && s[p] == ',') { p++; continue; }
                if (p < s.size() && s[p] == ']') { p++; break; }
                return false;
            }
        } else if (c == '"') {
            n.kind = '"';
            if (!string(n.str)) return false;
        } else {
            n.kind = 'v';
            while (p < s.size() && s[p] != ',' && s[p] != '}' && s[p] != ']' &&
                   s[p] != ' ' && s[p] != '\t' && s[p] != '\n' && s[p] != '\r' && s[p] != '/') p++;
            if (p == n.begin) return false;
            n.str = s.substr(n.begin, p - n.begin);
        }
        n.end = p;
        return true;
    }
};

bool readFile(const std::string& path, std::string& text, bool& exists) {
    std::ifstream in(path, std::ios::binary);
    exists = static_cast<bool>(in);
    if (!exists) return true;
    std::ostringstream ss;
    ss << in.rdbuf();
    text = ss.str();
    return true;
}

bool writeFile(const std::string& path, const std::string& text) {
    std::ofstream out(path, std::ios::binary | std::ios::trunc);
    if (!out) return false;
    out << text;
    return static_cast<bool>(out);
}

// Inserts `member` ("\"key\": value") as an object's first member, just
// after its "{", keeping the comma rule whether or not it was empty.
std::string withFirstMember(const std::string& text, const Node& obj, const std::string& member) {
    std::string ins = "\n    " + member + (obj.members.empty() ? "\n" : ",");
    return text.substr(0, obj.begin + 1) + ins + text.substr(obj.begin + 1);
}

std::string configText(const std::string& name, const std::string& type, const std::string& program) {
    return "{\n"
           "            \"type\": \"" + jsonEscape(type) + "\",\n"
           "            \"request\": \"launch\",\n"
           "            \"name\": \"" + jsonEscape(name) + "\",\n"
           "            \"program\": \"" + jsonEscape(program) + "\",\n"
           "            \"args\": [],\n"
           "            \"cwd\": \"${workspaceFolder}\"\n"
           "        }";
}

} // namespace

VscodeEdit upsertLaunchConfig(const std::string& path, const std::string& name,
                              const std::string& type, const std::string& program) {
    std::string text;
    bool exists = false;
    readFile(path, text, exists);
    std::string config = configText(name, type, program);
    if (!exists || text.find_first_not_of(" \t\r\n") == std::string::npos) {
        std::string fresh = "{\n    \"version\": \"0.2.0\",\n    \"configurations\": [\n        " +
                            config + "\n    ]\n}\n";
        return writeFile(path, fresh) ? VscodeEdit::Created : VscodeEdit::Unreadable;
    }

    Node root;
    if (!Reader(text).document(root) || root.kind != '{') return VscodeEdit::Unreadable;
    const Node* configs = root.get("configurations");
    std::string updated;
    if (!configs) {
        updated = withFirstMember(text, root, "\"configurations\": [\n        " + config + "\n    ]");
    } else if (configs->kind != '[') {
        return VscodeEdit::Unreadable;
    } else {
        const Node* mine = nullptr;
        for (auto& e : configs->elems) {
            const Node* n = e.kind == '{' ? e.get("name") : nullptr;
            if (n && n->kind == '"' && n->str == name) { mine = &e; break; }
        }
        if (mine) {
            // The user's configuration: only where the program is changes.
            const Node* prog = mine->get("program");
            std::string lit = "\"" + jsonEscape(program) + "\"";
            if (prog && prog->kind == '"' && prog->str == program) return VscodeEdit::Unchanged;
            if (prog)
                updated = text.substr(0, prog->begin) + lit + text.substr(prog->end);
            else
                updated = withFirstMember(text, *mine, "        \"program\": " + lit);
        } else if (configs->elems.empty()) {
            // "[]", or "[" and "]" with only blanks (or a comment) between.
            std::string inner = text.substr(configs->begin + 1, configs->end - configs->begin - 2);
            bool blank = inner.find_first_not_of(" \t\r\n") == std::string::npos;
            updated = text.substr(0, configs->begin + 1) + "\n        " + config +
                      (blank ? "\n    " + text.substr(configs->end - 1)
                             : text.substr(configs->begin + 1));
        } else {
            size_t at = configs->elems.back().end;
            updated = text.substr(0, at) + ",\n        " + config + text.substr(at);
        }
    }
    return writeFile(path, updated) ? VscodeEdit::Updated : VscodeEdit::Unreadable;
}

VscodeEdit ensureBoolSetting(const std::string& path, const std::string& key, bool value,
                             bool* existing) {
    std::string text;
    bool exists = false;
    readFile(path, text, exists);
    std::string member = "\"" + jsonEscape(key) + "\": " + (value ? "true" : "false");
    if (!exists || text.find_first_not_of(" \t\r\n") == std::string::npos)
        return writeFile(path, "{\n    " + member + "\n}\n") ? VscodeEdit::Created : VscodeEdit::Unreadable;

    Node root;
    if (!Reader(text).document(root) || root.kind != '{') return VscodeEdit::Unreadable;
    if (const Node* v = root.get(key)) {
        if (existing) *existing = v->kind == 'v' && v->str == "true";
        return VscodeEdit::Unchanged;
    }
    return writeFile(path, withFirstMember(text, root, member)) ? VscodeEdit::Updated
                                                                : VscodeEdit::Unreadable;
}

} // namespace rpgc
