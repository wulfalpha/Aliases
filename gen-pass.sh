#!/usr/bin/env bash
#
# gen-pass.sh - generate a random password from /dev/urandom
#
# Prints to stdout by default, so it pipes cleanly. Can also copy to the
# clipboard (xclip or wl-copy) and/or store the password in `pass`.
#
# Usage:
#   gen-pass.sh [-l LEN] [-8] [-t TYPE] [-k] [-s] [-n COUNT] [-c] [-p NAME] [-f] [-h]
#
#   -l LEN    password length (default 12)
#   -8        shorthand for -l 8
#   -t TYPE   restrict the character set; repeatable, or comma-separated.
#             alpha  a-z and A-Z      lower  a-z only
#             num    0-9              upper  A-Z only
#             sym    !@#$%^&* etc     alnum  alpha + num
#                                     all    alpha + num + sym (the default)
#   -k        key mode: 32 characters, alnum (same as -t alnum -l 32)
#   -s        drop symbols from whatever set is in play
#   -n COUNT  generate COUNT passwords (default 1)
#   -c        copy to the clipboard instead of printing
#   -p NAME   store in pass under NAME instead of printing
#   -f        force overwrite of an existing pass entry
#   -h        show this help
#
# Every selected class is guaranteed to appear at least once, so -l must be at
# least as large as the number of classes requested.
#
# With -c or -p the password is not echoed to a terminal, but it is still
# written to stdout when stdout is a pipe or a file, so this stays usable as
# `gen-pass.sh -c | tee -a somewhere`.

set -euo pipefail

readonly DEFAULT_LEN=12
readonly KEY_LEN=32
readonly MAX_TRIES=100

readonly LOWER='a-z'
readonly UPPER='A-Z'
readonly DIGIT='0-9'
# '-' is last so tr reads it as a literal rather than a range; this is always
# appended last when the charset is assembled, which keeps that true.
readonly SYMBOL='!@#$%^&*()_=+[]{};:,.<>?/~-'

length=$DEFAULT_LEN
count=1
to_clipboard=0
pass_name=''
force=0
len_given=0
type_given=0
key_mode=0
drop_symbols=0

# Selected character classes.
sel_lower=0 sel_upper=0 sel_digit=0 sel_sym=0

die() { printf '%s: %s\n' "${0##*/}" "$1" >&2; exit 1; }
note() { printf '%s\n' "$1" >&2; }

usage() {
    awk 'NR > 2 { if (!/^#/) exit; sub(/^# ?/, ""); print }' "$0"
}

select_all() { sel_lower=1 sel_upper=1 sel_digit=1 sel_sym=1; }
select_alnum() { sel_lower=1 sel_upper=1 sel_digit=1; }

# Accepts one -t value, which may itself be a comma-separated list. Values
# accumulate, so -t num -t sym is the same as -t num,sym.
add_types() {
    local spec=$1 name
    local -a parts
    [[ -n $spec ]] || die "-t needs a type (try -h)"
    IFS=',' read -ra parts <<< "$spec"
    for name in "${parts[@]}"; do
        name=${name#"${name%%[![:space:]]*}"}   # trim leading whitespace
        name=${name%"${name##*[![:space:]]}"}   # trim trailing whitespace
        case $name in
            alpha)        sel_lower=1 sel_upper=1 ;;
            lower)        sel_lower=1 ;;
            upper)        sel_upper=1 ;;
            num|digit)    sel_digit=1 ;;
            sym|punct)    sel_sym=1 ;;
            alnum)        select_alnum ;;
            all)          select_all ;;
            '')           die "-t got an empty type in '$spec'" ;;
            *)            die "unknown type '$name' (alpha, lower, upper, num, sym, alnum, all)" ;;
        esac
    done
    type_given=1
}

# Names of the classes in play, in charset order. Used for both building the
# charset and checking that each one landed in the password.
selected_classes() {
    (( sel_lower )) && printf 'lower\n'
    (( sel_upper )) && printf 'upper\n'
    (( sel_digit )) && printf 'digit\n'
    (( sel_sym ))   && printf 'sym\n'
    return 0
}

build_charset() {
    local out=''
    (( sel_lower )) && out+=$LOWER
    (( sel_upper )) && out+=$UPPER
    (( sel_digit )) && out+=$DIGIT
    # Appended last: $SYMBOL ends in '-', which tr only reads as a literal
    # when it is the final character of the set.
    (( sel_sym )) && out+=$SYMBOL
    printf '%s' "$out"
}

has_class() {
    local class=$1 pw=$2
    case $class in
        lower) [[ $pw == *[[:lower:]]* ]] ;;
        upper) [[ $pw == *[[:upper:]]* ]] ;;
        digit) [[ $pw == *[[:digit:]]* ]] ;;
        # Tested by removing the alphanumerics rather than globbing $SYMBOL,
        # which starts with '!' and contains ']' -- both special inside [...].
        sym)   [[ -n ${pw//[a-zA-Z0-9]/} ]] ;;
        *)     return 1 ;;
    esac
}

# Reject-and-resample: tr drops every byte outside the charset, so each kept
# byte is uniform over the charset. head closes the pipe once it has enough.
random_string() {
    local len=$1 charset=$2 out
    out=$(LC_ALL=C tr -dc "$charset" < /dev/urandom | head -c "$len" || true)
    [[ ${#out} -eq $len ]] || die "could not read $len bytes from /dev/urandom"
    printf '%s' "$out"
}

# Make sure the password actually spans every class it is allowed to use,
# instead of handing back 12 lowercase letters once in a while.
gen_password() {
    local try pw class ok
    for (( try = 0; try < MAX_TRIES; try++ )); do
        pw=$(random_string "$length" "$CHARSET")
        ok=1
        for class in "${CLASSES[@]}"; do
            if ! has_class "$class" "$pw"; then ok=0; break; fi
        done
        if (( ok )); then
            printf '%s' "$pw"
            return 0
        fi
    done

    die "gave up after $MAX_TRIES tries covering ${#CLASSES[@]} classes at length $length"
}

copy_to_clipboard() {
    local pw=$1
    if [[ -n ${WAYLAND_DISPLAY:-} ]] && command -v wl-copy &> /dev/null; then
        printf '%s' "$pw" | wl-copy
    elif command -v xclip &> /dev/null; then
        printf '%s' "$pw" | xclip -selection clipboard
    elif command -v wl-copy &> /dev/null; then
        printf '%s' "$pw" | wl-copy
    else
        die "no clipboard tool found (install xclip or wl-clipboard)"
    fi
}

store_in_pass() {
    local pw=$1 name=$2 args=(insert --multiline)
    if (( force )); then args+=(--force); fi
    printf '%s\n' "$pw" | pass "${args[@]}" "$name" > /dev/null
}

while getopts ':l:8t:ksn:cp:fh' opt; do
    case $opt in
        l) length=$OPTARG; len_given=1 ;;
        8) length=8; len_given=1 ;;
        t) add_types "$OPTARG" ;;
        k) key_mode=1 ;;
        s) drop_symbols=1 ;;
        n) count=$OPTARG ;;
        c) to_clipboard=1 ;;
        p) pass_name=$OPTARG ;;
        f) force=1 ;;
        h) usage; exit 0 ;;
        :) die "option -$OPTARG requires an argument" ;;
        ?) die "unknown option -$OPTARG (try -h)" ;;
    esac
done
shift $(( OPTIND - 1 ))

# -t wins outright; otherwise -k/-s mean alnum and a bare invocation means all.
if (( ! type_given )); then
    if (( key_mode || drop_symbols )); then select_alnum; else select_all; fi
fi
if (( key_mode && ! len_given )); then length=$KEY_LEN; fi
if (( drop_symbols )); then sel_sym=0; fi

mapfile -t CLASSES < <(selected_classes)
(( ${#CLASSES[@]} > 0 )) || die "no character classes left to choose from"
CHARSET=$(build_charset)
readonly CLASSES CHARSET

[[ $length =~ ^[0-9]+$ ]] || die "length must be a number, got '$length'"
[[ $count =~ ^[0-9]+$ ]] || die "count must be a number, got '$count'"
(( count >= 1 )) || die "count must be at least 1"
if (( length < ${#CLASSES[@]} )); then
    noun="character classes"; (( ${#CLASSES[@]} == 1 )) && noun="character class"
    die "length $length cannot cover ${#CLASSES[@]} $noun (${CLASSES[*]})"
fi

[[ -r /dev/urandom ]] || die "/dev/urandom is not readable"
if [[ -n $pass_name ]]; then
    command -v pass &> /dev/null || die "pass could not be found"
    (( count == 1 )) || die "-p stores a single password; drop -n"
fi
if (( to_clipboard )); then
    command -v xclip &> /dev/null || command -v wl-copy &> /dev/null \
        || die "xclip or wl-copy could not be found"
    (( count == 1 )) || die "-c copies a single password; drop -n"
fi

# A sink was chosen, so only print when stdout is redirected somewhere.
if (( to_clipboard )) || [[ -n $pass_name ]]; then
    print_password=0
    [[ -t 1 ]] || print_password=1
else
    print_password=1
fi

for (( i = 0; i < count; i++ )); do
    password=$(gen_password)

    if (( to_clipboard )); then
        copy_to_clipboard "$password"
    fi
    if [[ -n $pass_name ]]; then
        store_in_pass "$password" "$pass_name"
    fi
    if (( print_password )); then
        printf '%s\n' "$password"
    fi

    if (( to_clipboard )); then
        note "copied ${#password} characters to the clipboard"
    fi
    if [[ -n $pass_name ]]; then
        note "stored in pass as '$pass_name'"
    fi
done

exit 0
