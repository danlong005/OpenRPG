#ifndef EXTDESC_H
#define EXTDESC_H

#include "conf.h"
#include <map>
#include <string>
#include <vector>

struct ExtField {
    std::string name;       // column name (uppercased)
    std::string cppType;    // C++ type (std::string, long, double)
    std::string bindKind;   // "str", "int", "dbl" — for ODBC binding dispatch
    int length = 0;
    int decimals = 0;
};

struct ExternalFileDesc {
    std::string tableName;          // actual DB table name
    std::vector<ExtField> fields;   // ordered list of columns
};

// .extdesc cache line: "FIELDNAME TYPE(len:dec)"
// e.g.  CUSTNO  VARCHAR(10)
//        CUSTBAL  PACKED(9:2)

// Query external descriptions for a caller-supplied list of DCL-F DISK
// files: {rpgName, extdescOverride} pairs (extdescOverride empty means
// "use the lowercased rpgName as the table name"). Callers extract this
// list by walking the already-parsed AST for DclF nodes with
// usage=="DISK" — not by re-scanning source text — so it works
// identically regardless of which frontend (free- or fixed-format)
// produced the AST.
// src_dir: directory of the .rpgle/.rpg source (for cache file lookup).
// conf: connection string from rpgc.conf (may be empty).
// If a .extdesc cache file exists and DB is unavailable, uses cache.
// Writes/updates .extdesc cache when DB is available.
std::map<std::string, ExternalFileDesc>
queryExternalDescs(const std::vector<std::pair<std::string, std::string>>& diskFiles,
                   const std::string& src_dir,
                   const RpgConf& conf);

#endif // EXTDESC_H
