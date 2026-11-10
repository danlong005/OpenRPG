// VS Code workspace files written by rpgc -g: .vscode/launch.json and
// .vscode/settings.json. Both are JSONC (comments and trailing commas
// allowed), and both are often the user's own, so they are edited in place
// as text -- what is already there, comments and layout included, is kept.
#pragma once
#include <string>

namespace rpgc {

enum class VscodeEdit {
    Created,    // the file did not exist and was written
    Updated,    // the file was changed
    Unchanged,  // it already said what was needed
    Unreadable  // not JSONC rpgc can follow: left alone
};

// A string as a JSON string literal's contents (quotes, backslashes and
// control characters escaped). Windows paths need it.
std::string jsonEscape(const std::string& s);

// Makes launch.json at `path` hold a configuration named `name` for
// `program`. One the user already has keeps everything they put in it; only
// its "program" is brought up to date. Otherwise a new configuration of
// type `type` is appended to "configurations", next to any others.
VscodeEdit upsertLaunchConfig(const std::string& path, const std::string& name,
                              const std::string& type, const std::string& program);

// Makes settings.json at `path` have `key` (a boolean setting): added as
// `value` when missing. A value the user set is theirs, and kept.
// `existing` is set to the value found when the key was already there.
VscodeEdit ensureBoolSetting(const std::string& path, const std::string& key, bool value,
                             bool* existing = nullptr);

} // namespace rpgc
