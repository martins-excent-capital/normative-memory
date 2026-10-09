# Fixed usage-event profile of TOON. Run with LC_ALL=C.
function fail() { failed = 1; print "usage: invalid event or TOON profile" > "/dev/stderr"; exit 2 }
function utf8(s,    i,b,n,j,v,lo,hi) {
    for (i = 1; i <= length(s); i++) {
        b = byte[substr(s,i,1)]
        if (b < 128) continue
        if (b >= 194 && b <= 223) n = 1
        else if (b >= 224 && b <= 239) n = 2
        else if (b >= 240 && b <= 244) n = 3
        else return 0
        lo = (b == 224 ? 160 : (b == 240 ? 144 : 128))
        hi = (b == 237 ? 159 : (b == 244 ? 143 : 191))
        if (i + n > length(s)) return 0
        for (j = 1; j <= n; j++) {
            v = byte[substr(s,i+j,1)]
            if (v < (j == 1 ? lo : 128) || v > (j == 1 ? hi : 191)) return 0
        }
        i += n
    }
    return 1
}
function quote_needed(s) {
    return s == "" || s ~ /^[ \t]|[ \t]$/ || s ~ /^(true|false|null)$/ ||
        s ~ /^[+-]?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?$/ ||
        s ~ /[:"\\\[\]{},\001-\037]/ || s ~ /^[-#]/
}
function quoted(s,    i,c,b,out) {
    if (!utf8(s)) fail()
    if (!quote_needed(s)) return s
    out = "\""
    for (i = 1; i <= length(s); i++) {
        c = substr(s,i,1); b = byte[c]
        if (c == "\\" || c == "\"") out = out "\\" c
        else if (c == "\n") out = out "\\n"
        else if (c == "\r") out = out "\\r"
        else if (c == "\t") out = out "\\t"
        else if (b < 32) out = out sprintf("\\u%04x",b)
        else out = out c
    }
    return out "\""
}
function string_value(s,    i,c,e,out,h,v,k) {
    if (substr(s,1,1) != "\"") {
        if (quote_needed(s) || !utf8(s)) fail()
        return s
    }
    if (length(s) < 2 || substr(s,length(s),1) != "\"") fail()
    out = ""
    for (i = 2; i < length(s); i++) {
        c = substr(s,i,1)
        if (c == "\"" || byte[c] < 32) fail()
        if (c != "\\") { out = out c; continue }
        e = substr(s,++i,1)
        if (i >= length(s)) fail()
        if (e == "\\" || e == "\"") out = out e
        else if (e == "n") out = out "\n"
        else if (e == "r") out = out "\r"
        else if (e == "t") out = out "\t"
        else if (e == "u") {
            h = substr(s,i+1,4)
            if (length(h) != 4 || h ~ /[^0-9a-fA-F]/) fail()
            v = 0
            for (k = 1; k <= 4; k++) v = v*16 + index("0123456789abcdef",tolower(substr(h,k,1)))-1
            # The writer emits unicode escapes only for non-NUL controls.
            if (v < 1 || v > 31) fail()
            out = out sprintf("%c",v); i += 4
        } else fail()
    }
    if (!utf8(out)) fail()
    return out
}
function valid_fields(    k) {
    if (value[1] !~ /^(0|[1-9][0-9]*)$/ || length(value[1]) > 15) fail()
    if ((length(value[2]) != 40 && length(value[2]) != 64) || value[2] ~ /[^0-9a-f]/) fail()
    for (k = 2; k <= 6; k++) if (value[k] == "" || !utf8(value[k])) fail()
    if (index(value[4],"/") < 2 || index(value[4],"/") == length(value[4])) fail()
}
function read_field(path,    line,s,r,first) {
    s = ""; first = 1
    while ((r = (getline line < path)) > 0) {
        if (!first) s = s "\n"
        s = s line; first = 0
    }
    close(path)
    if (r < 0 || first) fail()
    return s
}
function parse_row(line,    i,c,inside,escape,n,token) {
    if (substr(line,1,2) != "  " || substr(line,3,1) == " ") fail()
    line = substr(line,3); n = 1; token = ""; inside = 0; escape = 0
    for (i = 1; i <= length(line); i++) {
        c = substr(line,i,1)
        if (!inside && c == ",") { cell[n++] = token; token = ""; continue }
        token = token c
        if (escape) escape = 0
        else if (inside && c == "\\") escape = 1
        else if (c == "\"") inside = !inside
    }
    cell[n] = token
    if (n != 6 || inside || escape) fail()
    value[1] = cell[1]
    for (i = 2; i <= 6; i++) value[i] = string_value(cell[i])
    valid_fields()
}
BEGIN {
    for (i = 0; i < 256; i++) byte[sprintf("%c",i)] = i
    split("ts base rule harness session effect", field, " ")
    if (mode == "encode") {
        total = ARGC-1
        for (a = 1; a < ARGC; a++) {
            for (k = 1; k <= 6; k++) value[k] = read_field(ARGV[a] "/" field[k])
            valid_fields()
            row[a] = "  " value[1]
            for (k = 2; k <= 6; k++) row[a] = row[a] "," quoted(value[k])
        }
        printf "events[%d]{ts,base,rule,harness,session,effect}:",total
        for (a = 1; a <= total; a++) printf "\n%s",row[a]
        exit
    }
    if (mode != "check") fail()
}
NR == 1 {
    if ($0 !~ /^events\[(0|[1-9][0-9]*)\]\{ts,base,rule,harness,session,effect\}:$/) fail()
    count = $0; sub(/^events\[/,"",count); sub(/\].*$/,"",count)
    next
}
{ parse_row($0); seen++ }
END {
    if (failed) exit 2
    if (mode == "check" && (NR == 0 || seen+0 != count+0)) fail()
}
