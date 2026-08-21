#ifndef RPG_FLATFILE_RUNTIME_H
#define RPG_FLATFILE_RUNTIME_H

// Program-described (I-spec/O-spec) flat file I/O — see TODO.md
// "Fixed-Format Source Support" item #4. Real IBM i program-described
// files are pure fixed-width bytes with no in-file delimiters, using the
// platform's native record-oriented file system; there's no equivalent on
// macOS/Linux/Windows, so this runtime uses a portable convention instead:
// each physical line is one record, exactly `recordLen` bytes followed by
// '\n' (right-padded with spaces, or truncated, to fit). Fixed per-record
// width makes byte-offset seeking for UPDATE trivial (record N starts at
// byte N*(recordLen+1)) without needing to track variable line lengths.
// This is an OpenRPG-specific interchange format, not literal IBM i
// on-disk semantics.

#include <cmath>
#include <cstdio>
#include <fstream>
#include <string>

// I-spec/O-spec numeric fields are stored as plain ASCII digit text in
// this runtime's flat-file format (not literal EBCDIC zoned/packed
// bytes — see the file-level comment above), with an implied decimal
// point `decimals` digits from the right and an optional leading '-'.
inline double rpg_flatfile_parse_numeric(const std::string& raw, int decimals) {
    double v = 0.0;
    try { v = std::stod(raw); } catch (...) { return 0.0; }
    for (int i = 0; i < decimals; i++) v /= 10.0;
    return v;
}

// Right-justified, zero-padded to `width` (leading '-' for negatives
// takes one digit position), `decimals` implied fractional digits.
inline std::string rpg_flatfile_format_numeric(double val, int width, int decimals) {
    bool neg = val < 0;
    double scaled = std::fabs(val);
    for (int i = 0; i < decimals; i++) scaled *= 10.0;
    long long digits = static_cast<long long>(scaled + 0.5);
    std::string s = std::to_string(digits);
    int digitWidth = neg ? width - 1 : width;
    if (static_cast<int>(s.size()) < digitWidth) {
        s = std::string(static_cast<size_t>(digitWidth) - s.size(), '0') + s;
    } else if (static_cast<int>(s.size()) > digitWidth) {
        s = s.substr(s.size() - static_cast<size_t>(digitWidth));
    }
    if (neg) s = "-" + s;
    return s;
}

class RpgFlatFile {
public:
    // Opens `path` for both sequential read and write — creating it fresh
    // if it doesn't already exist — so a single DCL-F can WRITE records
    // and later READ them back within the same program (or across
    // separate runs against the same on-disk file). Returns false only
    // on a real I/O failure (e.g. permission denied).
    bool open(const std::string& path, int recordLen) {
        recordLen_ = recordLen;
        file_.open(path, std::ios::in | std::ios::out | std::ios::binary);
        if (!file_.is_open()) {
            // Doesn't exist yet — create it, then reopen in read+write mode.
            file_.open(path, std::ios::out | std::ios::trunc | std::ios::binary);
            file_.close();
            file_.open(path, std::ios::in | std::ios::out | std::ios::binary);
        }
        return file_.is_open();
    }

    // Reads the next record into `buf` (exactly recordLen_ bytes, no
    // trailing newline). Returns false at EOF (buf is left unchanged).
    // Tracks its own read cursor (`readPos_`) independent of writeRecord()/
    // updateLast()'s put-pointer, so WRITE-then-READ-back within the same
    // program (or interleaved UPDATE calls) both work correctly without
    // relying on std::fstream's implementation-defined shared get/put
    // position behavior.
    bool readNext(std::string& buf) {
        if (!file_.is_open()) return false;
        file_.clear();
        file_.seekg(readPos_);
        lastRecordPos_ = readPos_;
        std::string line(static_cast<size_t>(recordLen_), ' ');
        file_.read(&line[0], recordLen_);
        std::streamsize got = file_.gcount();
        if (got <= 0) { file_.clear(); return false; }
        if (got < recordLen_) line.resize(static_cast<size_t>(got));
        // consume the trailing newline, if present
        int c = file_.peek();
        if (c == '\n') file_.get();
        readPos_ = file_.tellg();
        buf = line;
        // pad short trailing records the same way a full record would be
        if (static_cast<int>(buf.size()) < recordLen_) {
            buf.resize(static_cast<size_t>(recordLen_), ' ');
        }
        return true;
    }

    // Rewrites the most recently read record in place with `buf`,
    // padded/truncated to recordLen_. Does not disturb readPos_ (already
    // past this record from the readNext() call that preceded it).
    void updateLast(const std::string& buf) {
        if (!file_.is_open() || lastRecordPos_ < 0) return;
        file_.clear();
        file_.seekp(lastRecordPos_);
        writePadded(buf);
        file_.flush();
    }

    // Appends `buf`, padded/truncated to recordLen_, as a new record.
    // Always seeks to end-of-file first — independent of readPos_, so
    // this is safe to call at any point relative to readNext().
    void writeRecord(const std::string& buf) {
        if (!file_.is_open()) return;
        file_.clear();
        file_.seekp(0, std::ios::end);
        writePadded(buf);
        file_.flush();
    }

    void close() {
        if (file_.is_open()) file_.close();
    }

private:
    void writePadded(const std::string& buf) {
        std::string line = buf;
        if (static_cast<int>(line.size()) > recordLen_) {
            line.resize(static_cast<size_t>(recordLen_));
        } else if (static_cast<int>(line.size()) < recordLen_) {
            line.resize(static_cast<size_t>(recordLen_), ' ');
        }
        file_.write(line.data(), recordLen_);
        file_.write("\n", 1);
    }

    std::fstream file_;
    int recordLen_ = 0;
    std::streamoff readPos_ = 0;
    std::streamoff lastRecordPos_ = -1;
};

#endif // RPG_FLATFILE_RUNTIME_H
