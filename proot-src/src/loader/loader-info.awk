# Note: This file is included only for targets which have pokedata workaround
function hextodec(h,    i, c, d, v) {
    v = 0
    for (i = 1; i <= length(h); i++) {
        c = tolower(substr(h, i, 1))
        d = index("0123456789abcdef", c) - 1
        if (d < 0) return 0
        v = v * 16 + d
    }
    return v
}
/\ypokedata_workaround\y/ { pokedata_workaround = hextodec($2) }
/\y_start\y/              { start = hextodec($2) }
END {
    print "#include <unistd.h>"
    print "const ssize_t offset_to_pokedata_workaround=" (pokedata_workaround - start) ";"
}
