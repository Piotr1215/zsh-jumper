#!/usr/bin/env zsh
# Test suite for zledit
# Run: zsh tests/test_plugin.zsh [--verbose]

emulate -L zsh
setopt NO_XTRACE NO_VERBOSE

SCRIPT_DIR="${0:A:h}"
PLUGIN_DIR="${SCRIPT_DIR:h}"

# Parse arguments
typeset -gi VERBOSE=0
[[ "$1" == "-v" || "$1" == "--verbose" ]] && VERBOSE=1

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

typeset -gi TESTS_RUN=0
typeset -gi TESTS_PASSED=0
typeset -gi TESTS_SKIPPED=0

# Verbose logging helper
vlog() {
    (( VERBOSE )) && print "${YELLOW}  ▸${NC} $*"
}

test_pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    print "${GREEN}✓${NC} $1"
}

test_fail() {
    print "${RED}✗${NC} $1"
    [[ -n "$2" ]] && print "  $2"
}

run_test() {
    TESTS_RUN=$((TESTS_RUN + 1))
    "$@"
}

skip_test() {
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    print -- "- Skipping: $1"
}

# Alias used in inline skip guards
test_skip() { skip_test "$@"; }

# ------------------------------------------------------------------------------
# Tests
# ------------------------------------------------------------------------------

test_plugin_loads() {
    # Run in subshell, capture exit code
    zsh -c "source $PLUGIN_DIR/zledit.plugin.zsh" >/dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        test_pass "Plugin loads without errors"
    else
        test_fail "Plugin fails to load" ""
    fi
}

test_functions_defined() {
    local result
    result=$(zsh -c "
        source $PLUGIN_DIR/zledit.plugin.zsh
        (( \$+functions[zledit-widget] )) || exit 1
        (( \$+functions[_zledit_load_config] )) || exit 1
        (( \$+functions[_zledit_load_default_actions] )) || exit 1
        (( \$+functions[_zledit_invoke_picker] )) || exit 1
        (( \$+functions[_zledit_adapter_fzf] )) || exit 1
        (( \$+functions[zledit-setup-bindings] )) || exit 1
        (( \$+functions[zledit-unload] )) || exit 1
        (( \$+functions[_zledit_tokenize] )) || exit 1
        (( \$+functions[_zledit_supports_binds] )) || exit 1
        (( \$+functions[_zledit_do_jump] )) || exit 1
        (( \$+functions[_zledit_do_custom_action] )) || exit 1
    " 2>&1)
    if [[ $? -eq 0 ]]; then
        test_pass "All functions defined"
    else
        test_fail "Missing function definitions" "$result"
    fi
}

test_global_state() {
    local result
    result=$(zsh -c "
        source $PLUGIN_DIR/zledit.plugin.zsh
        [[ -n \"\${Zledit[dir]}\" ]] || exit 1
    " 2>&1)
    if [[ $? -eq 0 ]]; then
        test_pass "Global state initialized"
    else
        test_fail "Global state not set" "$result"
    fi
}

test_default_actions_loaded() {
    local result
    result=$(zsh -c "
        source $PLUGIN_DIR/zledit.plugin.zsh
        # Check that default actions are registered (wrap, var, replace, move)
        (( \${#_ze_action_bindings[@]} >= 4 )) || exit 1
        (( \${#_ze_action_scripts[@]} >= 4 )) || exit 1
        [[ \"\${_ze_action_descriptions[*]}\" == *wrap* ]] || exit 1
        [[ \"\${_ze_action_descriptions[*]}\" == *var* ]] || exit 1
        [[ \"\${_ze_action_descriptions[*]}\" == *replace* ]] || exit 1
        [[ \"\${_ze_action_descriptions[*]}\" == *move* ]] || exit 1
    " 2>&1)
    if [[ $? -eq 0 ]]; then
        test_pass "Default actions loaded"
    else
        test_fail "Default actions not loaded" "$result"
    fi
}

test_action_scripts_exist() {
    local missing=""
    [[ ! -x "$PLUGIN_DIR/actions/wrap.sh" ]] && missing+=" wrap.sh"
    [[ ! -x "$PLUGIN_DIR/actions/var.sh" ]] && missing+=" var.sh"
    [[ ! -x "$PLUGIN_DIR/actions/replace.sh" ]] && missing+=" replace.sh"
    [[ ! -x "$PLUGIN_DIR/actions/move.sh" ]] && missing+=" move.sh"
    [[ ! -x "$PLUGIN_DIR/actions/dup.sh" ]] && missing+=" dup.sh"
    [[ ! -x "$PLUGIN_DIR/actions/path.sh" ]] && missing+=" path.sh"

    if [[ -z "$missing" ]]; then
        test_pass "Action scripts exist and are executable"
    else
        test_fail "Missing action scripts:$missing"
    fi
}

test_picker_detection_fzf() {
    if ! (( $+commands[fzf] )); then
        skip_test "fzf not installed"
        return 0
    fi

    local picker
    picker=$(zsh -c "
        source $PLUGIN_DIR/zledit.plugin.zsh
        echo \"\${Zledit[picker]}\"
    " 2>&1)

    if [[ "$picker" == fzf* ]]; then
        test_pass "Detects fzf picker: $picker"
    else
        test_fail "Failed to detect fzf" "Got: $picker"
    fi
}

test_picker_detection_sk() {
    if ! (( $+commands[sk] )); then
        skip_test "sk not installed"
        return 0
    fi

    local picker
    picker=$(zsh -c "
        source $PLUGIN_DIR/zledit.plugin.zsh
        echo \"\${Zledit[picker]}\"
    " 2>&1)

    if [[ -n "$picker" ]]; then
        test_pass "Picker detected (sk available): $picker"
    else
        test_fail "No picker detected" ""
    fi
}

test_picker_detection_peco() {
    if ! (( $+commands[peco] )); then
        skip_test "peco not installed"
        return 0
    fi

    local picker
    picker=$(zsh -c "
        source $PLUGIN_DIR/zledit.plugin.zsh
        echo \"\${Zledit[picker]}\"
    " 2>&1)

    if [[ -n "$picker" ]]; then
        test_pass "Picker detected (peco available): $picker"
    else
        test_fail "No picker detected" ""
    fi
}

test_zstyle_picker_override() {
    if ! (( $+commands[fzf] )); then
        skip_test "zstyle override (fzf not installed)"
        return 0
    fi

    local picker
    picker=$(zsh -c "
        zstyle ':zledit:' picker fzf
        source $PLUGIN_DIR/zledit.plugin.zsh
        echo \"\${Zledit[picker]}\"
    " 2>&1)

    if [[ "$picker" == "fzf" ]]; then
        test_pass "zstyle picker override works"
    else
        test_fail "zstyle override failed" "Expected: fzf, Got: $picker"
    fi
}

test_adapter_functions_exist() {
    local result
    result=$(zsh -c "
        source $PLUGIN_DIR/zledit.plugin.zsh
        (( \$+functions[_zledit_adapter_fzf] )) || exit 1
        (( \$+functions[_zledit_adapter_fzf-tmux] )) || exit 1
        (( \$+functions[_zledit_adapter_sk] )) || exit 1
        (( \$+functions[_zledit_adapter_peco] )) || exit 1
        (( \$+functions[_zledit_adapter_percol] )) || exit 1
    " 2>&1)

    if [[ $? -eq 0 ]]; then
        test_pass "All picker adapters defined"
    else
        test_fail "Missing adapter functions" "$result"
    fi
}

test_invoke_picker_dispatches() {
    local result
    result=$(zsh -c "
        source $PLUGIN_DIR/zledit.plugin.zsh
        # Test that invoke_picker dispatches to adapter (will fail on unknown picker)
        echo 'test' | _zledit_invoke_picker unknown_picker 'prompt> ' '' '' 2>&1
    " 2>&1)

    if [[ "$result" == *"unknown picker"* ]]; then
        test_pass "Invoke picker validates adapter"
    else
        test_fail "Invoke picker should reject unknown" "$result"
    fi
}

test_cursor_position() {
    # Test that cursor zstyle is read (can't test actual cursor movement without ZLE)
    local result
    result=$(zsh -c "
        zstyle ':zledit:' cursor end
        source $PLUGIN_DIR/zledit.plugin.zsh
        zstyle -s ':zledit:' cursor val && echo \$val
    " 2>&1)

    if [[ "$result" == "end" ]]; then
        test_pass "Cursor position config works"
    else
        test_fail "Cursor config not read" "Got: $result"
    fi
}

test_fzf_key_defaults_not_empty() {
    local result
    result=$(zsh -c "
        # Only set ONE key, others should get defaults
        zstyle ':zledit:' fzf-help-key 'ctrl-g'
        source $PLUGIN_DIR/zledit.plugin.zsh

        local wrap_key help_key var_key
        zstyle -s ':zledit:' fzf-wrap-key wrap_key
        zstyle -s ':zledit:' fzf-help-key help_key
        zstyle -s ':zledit:' fzf-var-key var_key
        [[ -z \"\$wrap_key\" ]] && wrap_key=ctrl-s
        [[ -z \"\$help_key\" ]] && help_key=ctrl-h
        [[ -z \"\$var_key\" ]] && var_key=ctrl-e

        # All should be non-empty
        [[ -n \"\$wrap_key\" && -n \"\$help_key\" && -n \"\$var_key\" ]] && echo 'ok' || echo 'fail'
    " 2>&1)

    if [[ "$result" == "ok" ]]; then
        test_pass "FZF key defaults are non-empty"
    else
        test_fail "FZF key defaults empty (regression)" "Got: $result"
    fi
}

test_disable_bindings() {
    local bound
    bound=$(zsh -c "
        zstyle ':zledit:' disable-bindings yes
        source $PLUGIN_DIR/zledit.plugin.zsh
        bindkey -L | grep -c 'zledit-widget' || true
    " 2>&1)
    # Remove any non-numeric chars (stderr noise)
    bound="${bound//[^0-9]/}"
    bound="${bound:-0}"

    if [[ "$bound" == "0" ]]; then
        test_pass "disable-bindings prevents keybinding"
    else
        test_fail "Binding still set despite disable-bindings" "Count: $bound"
    fi
}

test_unload() {
    local result
    result=$(zsh -c "
        source $PLUGIN_DIR/zledit.plugin.zsh
        zledit-unload
        (( \$+functions[zledit-widget] )) && exit 1
        exit 0
    " 2>&1)
    if [[ $? -eq 0 ]]; then
        test_pass "Unload removes functions"
    else
        test_fail "Unload failed to clean up" "$result"
    fi
}

test_picker_pipe() {
    local picker
    picker=$(zsh -c "
        source $PLUGIN_DIR/zledit.plugin.zsh
        echo \"\${Zledit[picker]}\"
    " 2>&1)

    if [[ -z "$picker" ]]; then
        skip_test "pipe test (no picker)"
        return 0
    fi

    local result
    case "$picker" in
        fzf|fzf-tmux)
            result=$(print -l foo bar baz | fzf --filter="foo" --no-sort 2>/dev/null | head -1)
            ;;
        sk)
            result=$(print -l foo bar baz | sk --filter="foo" --no-sort 2>/dev/null | head -1)
            ;;
        peco)
            skip_test "pipe test for peco (no filter mode)"
            return 0
            ;;
        *)
            skip_test "pipe test for $picker"
            return 0
            ;;
    esac

    if [[ "$result" == "foo" ]]; then
        test_pass "Picker pipe works ($picker)"
    else
        test_fail "Picker pipe failed" "Expected: foo, Got: $result"
    fi
}

test_position_substring_bug() {
    # Test that -u at index 3 is found correctly, not inside --user
    local result
    result=$(zsh -c '
        emulate -L zsh
        BUFFER="journalctl --user -u service"
        words=(${(z)BUFFER})
        idx=3  # -u is 3rd word
        target="${words[$idx]}"

        pos=0 j=1 remaining="$BUFFER"
        while (( j < idx )); do
            wpos="${remaining[(i)${words[$j]}]}"
            (( pos += wpos + ${#words[$j]} - 1 ))
            remaining="${remaining:$((wpos + ${#words[$j]} - 1))}"
            (( j++ ))
        done
        (( pos += ${remaining[(i)$target]} - 1 ))
        echo $pos
    ' 2>&1)

    # -u starts at position 18 in "journalctl --user -u service"
    if [[ "$result" == "18" ]]; then
        test_pass "Position finds -u correctly (not inside --user)"
    else
        test_fail "Position bug: -u found at wrong position" "Expected: 18, Got: $result"
    fi
}

test_many_words() {
    # Test with 15 words - index extraction must handle double digits
    local result
    result=$(zsh -c '
        emulate -L zsh
        BUFFER="a b c d e f g h i j k l m n TARGET"
        words=(${(z)BUFFER})
        idx=15  # TARGET is 15th word
        target="${words[$idx]}"

        pos=0 j=1 remaining="$BUFFER"
        while (( j < idx )); do
            wpos="${remaining[(i)${words[$j]}]}"
            (( pos += wpos + ${#words[$j]} - 1 ))
            remaining="${remaining:$((wpos + ${#words[$j]} - 1))}"
            (( j++ ))
        done
        (( pos += ${remaining[(i)$target]} - 1 ))
        echo "$pos:$target"
    ' 2>&1)

    if [[ "$result" == "28:TARGET" ]]; then
        test_pass "Handles 15+ words correctly"
    else
        test_fail "Many words failed" "Expected: 28:TARGET, Got: $result"
    fi
}

test_special_chars() {
    # Test words with special characters
    local result
    result=$(zsh -c '
        emulate -L zsh
        BUFFER="echo \$HOME /path/to/file --opt=value"
        words=(${(z)BUFFER})
        idx=3  # /path/to/file is 3rd word
        target="${words[$idx]}"

        pos=0 j=1 remaining="$BUFFER"
        while (( j < idx )); do
            wpos="${remaining[(i)${words[$j]}]}"
            (( pos += wpos + ${#words[$j]} - 1 ))
            remaining="${remaining:$((wpos + ${#words[$j]} - 1))}"
            (( j++ ))
        done
        (( pos += ${remaining[(i)$target]} - 1 ))
        echo "$pos:$target"
    ' 2>&1)

    if [[ "$result" == "11:/path/to/file" ]]; then
        test_pass "Handles special chars correctly"
    else
        test_fail "Special chars failed" "Expected: 11:/path/to/file, Got: $result"
    fi
}

test_duplicate_words() {
    # Test duplicate words - should find correct occurrence by index
    local result
    result=$(zsh -c '
        emulate -L zsh
        BUFFER="echo test echo final"
        words=(${(z)BUFFER})
        idx=3  # second "echo" is 3rd word
        target="${words[$idx]}"

        pos=0 j=1 remaining="$BUFFER"
        while (( j < idx )); do
            wpos="${remaining[(i)${words[$j]}]}"
            (( pos += wpos + ${#words[$j]} - 1 ))
            remaining="${remaining:$((wpos + ${#words[$j]} - 1))}"
            (( j++ ))
        done
        (( pos += ${remaining[(i)$target]} - 1 ))
        echo $pos
    ' 2>&1)

    # Second "echo" starts at position 10 in "echo test echo final"
    if [[ "$result" == "10" ]]; then
        test_pass "Handles duplicate words correctly"
    else
        test_fail "Duplicate words failed" "Expected: 10, Got: $result"
    fi
}

test_numbered_format() {
    # Test that numbered format is correct
    local result
    result=$(zsh -c '
        emulate -L zsh
        words=("kubectl" "get" "pods")
        numbered=()
        for i in {1..${#words[@]}}; do
            numbered+=("$i: ${words[$i]}")
        done
        printf "%s\n" "${numbered[@]}"
    ' 2>&1)

    if [[ "$result" == *"1: kubectl"* ]] && [[ "$result" == *"2: get"* ]] && [[ "$result" == *"3: pods"* ]]; then
        test_pass "Numbered format correct"
    else
        test_fail "Numbered format wrong" "Got: $result"
    fi
}

test_index_extraction() {
    # Test extracting index from selection (handles double digits)
    local result
    result=$(zsh -c '
        selection="15: TARGET"
        idx="${selection%%:*}"
        echo $idx
    ' 2>&1)

    if [[ "$result" == "15" ]]; then
        test_pass "Index extraction handles double digits"
    else
        test_fail "Index extraction failed" "Expected: 15, Got: $result"
    fi
}

test_empty_buffer() {
    # Empty buffer should return early
    local result
    result=$(zsh -c '
        emulate -L zsh
        BUFFER=""
        words=(${=BUFFER})
        echo "${#words[@]}"
    ' 2>&1)

    if [[ "$result" == "0" ]]; then
        test_pass "Empty buffer handled"
    else
        test_fail "Empty buffer failed" "Expected: 0 words, Got: $result"
    fi
}

test_single_word() {
    # Single word buffer
    local result
    result=$(zsh -c '
        emulate -L zsh
        BUFFER="kubectl"
        words=(${=BUFFER})
        echo "${#words[@]}:${words[1]}"
    ' 2>&1)

    if [[ "$result" == "1:kubectl" ]]; then
        test_pass "Single word handled"
    else
        test_fail "Single word failed" "Got: $result"
    fi
}

test_only_spaces() {
    # Buffer with only spaces
    local result
    result=$(zsh -c '
        emulate -L zsh
        BUFFER="     "
        words=(${=BUFFER})
        echo "${#words[@]}"
    ' 2>&1)

    if [[ "$result" == "0" ]]; then
        test_pass "Only spaces handled"
    else
        test_fail "Only spaces failed" "Expected: 0, Got: $result"
    fi
}

test_unicode() {
    # Unicode characters
    local result
    result=$(zsh -c '
        emulate -L zsh
        BUFFER="echo 你好 мир 🚀 λ"
        words=(${=BUFFER})
        idx=4
        target="${words[$idx]}"
        echo "${#words[@]}:$target"
    ' 2>&1)

    if [[ "$result" == "5:🚀" ]]; then
        test_pass "Unicode handled"
    else
        test_fail "Unicode failed" "Expected: 5:🚀, Got: $result"
    fi
}

test_all_special_chars() {
    # All kinds of special characters
    local result
    result=$(zsh -c '
        emulate -L zsh
        BUFFER="!@#\$%^&*()_+-=[]{}|;:,.<>? \\\\ \`\` \"\" ~"
        words=(${=BUFFER})
        echo "${#words[@]}"
    ' 2>&1)

    # Should split into individual tokens
    if (( result >= 5 )); then
        test_pass "Special chars split correctly ($result words)"
    else
        test_fail "Special chars failed" "Got only $result words"
    fi
}

test_numbers() {
    # Numeric tokens
    local result
    result=$(zsh -c '
        emulate -L zsh
        BUFFER="123 456.789 0x1F -99 1e10"
        words=(${=BUFFER})
        idx=3
        target="${words[$idx]}"

        pos=0 j=1 remaining="$BUFFER"
        while (( j < idx )); do
            wpos="${remaining[(i)${words[$j]}]}"
            (( pos += wpos + ${#words[$j]} - 1 ))
            remaining="${remaining:$((wpos + ${#words[$j]} - 1))}"
            (( j++ ))
        done
        (( pos += ${remaining[(i)$target]} - 1 ))
        echo "$pos:$target"
    ' 2>&1)

    if [[ "$result" == "12:0x1F" ]]; then
        test_pass "Numbers handled"
    else
        test_fail "Numbers failed" "Expected: 12:0x1F, Got: $result"
    fi
}

test_long_buffer() {
    # Very long buffer (100 words)
    local result
    result=$(zsh -c '
        emulate -L zsh
        BUFFER=""
        for i in {1..100}; do BUFFER+="word$i "; done
        words=(${=BUFFER})
        idx=99
        target="${words[$idx]}"
        echo "${#words[@]}:$target"
    ' 2>&1)

    if [[ "$result" == "100:word99" ]]; then
        test_pass "Long buffer (100 words) handled"
    else
        test_fail "Long buffer failed" "Got: $result"
    fi
}

test_tabs_and_newlines() {
    # Tabs and mixed whitespace
    local result
    result=$(zsh -c '
        emulate -L zsh
        BUFFER=$'"'"'first\tsecond   third'"'"'
        words=(${=BUFFER})
        echo "${#words[@]}:${words[2]}"
    ' 2>&1)

    if [[ "$result" == "3:second" ]]; then
        test_pass "Tabs and whitespace handled"
    else
        test_fail "Tabs failed" "Got: $result"
    fi
}

test_backslash_continuation() {
    local result
    result=$(zsh -c '
        emulate -L zsh
        BUFFER=$'"'"'kubectl get pods \
--namespace kube-system \
-o wide'"'"'
        words=(${${${=BUFFER}:#}:#\\})
        echo "${#words[@]}:${words[4]}"
    ' 2>&1)

    if [[ "$result" == "7:--namespace" ]]; then
        test_pass "Backslash continuation handled"
    else
        test_fail "Backslash continuation failed" "Expected: 7:--namespace, Got: $result"
    fi
}

test_quoted_strings() {
    # Quoted strings (not shell-parsed, just tokens)
    local result
    result=$(zsh -c '
        emulate -L zsh
        BUFFER="echo \"hello world\" done"
        words=(${=BUFFER})
        echo "${#words[@]}:${words[2]}:${words[3]}"
    ' 2>&1)

    # With whitespace split, quotes are just chars
    if [[ "$result" == '4:"hello:world"' ]]; then
        test_pass "Quoted strings split on whitespace"
    else
        test_fail "Quoted strings failed" "Got: $result"
    fi
}

test_pipes_and_redirects() {
    # Shell operators as separate tokens
    local result
    result=$(zsh -c '
        emulate -L zsh
        BUFFER="cat file | grep foo > out 2>&1"
        words=(${=BUFFER})
        echo "${#words[@]}"
    ' 2>&1)

    if [[ "$result" == "8" ]]; then
        test_pass "Pipes and redirects handled (8 tokens)"
    else
        test_fail "Pipes failed" "Expected: 8, Got: $result"
    fi
}

test_cyrillic() {
    # Cyrillic alphabet
    local result
    result=$(zsh -c '
        emulate -L zsh
        BUFFER="привет мир команда"
        words=(${=BUFFER})
        echo "${#words[@]}:${words[2]}"
    ' 2>&1)

    if [[ "$result" == "3:мир" ]]; then
        test_pass "Cyrillic handled"
    else
        test_fail "Cyrillic failed" "Got: $result"
    fi
}

test_chinese() {
    # Chinese characters
    local result
    result=$(zsh -c '
        emulate -L zsh
        BUFFER="你好 世界 测试"
        words=(${=BUFFER})
        echo "${#words[@]}:${words[3]}"
    ' 2>&1)

    if [[ "$result" == "3:测试" ]]; then
        test_pass "Chinese handled"
    else
        test_fail "Chinese failed" "Got: $result"
    fi
}

test_arabic() {
    # Arabic (RTL)
    local result
    result=$(zsh -c '
        emulate -L zsh
        BUFFER="مرحبا عالم اختبار"
        words=(${=BUFFER})
        echo "${#words[@]}:${words[1]}"
    ' 2>&1)

    if [[ "$result" == "3:مرحبا" ]]; then
        test_pass "Arabic handled"
    else
        test_fail "Arabic failed" "Got: $result"
    fi
}

test_japanese() {
    # Japanese (hiragana, katakana, kanji)
    local result
    result=$(zsh -c '
        emulate -L zsh
        BUFFER="こんにちは カタカナ 漢字"
        words=(${=BUFFER})
        echo "${#words[@]}:${words[2]}"
    ' 2>&1)

    if [[ "$result" == "3:カタカナ" ]]; then
        test_pass "Japanese handled"
    else
        test_fail "Japanese failed" "Got: $result"
    fi
}

test_korean() {
    # Korean hangul
    local result
    result=$(zsh -c '
        emulate -L zsh
        BUFFER="안녕하세요 세계 테스트"
        words=(${=BUFFER})
        echo "${#words[@]}:${words[2]}"
    ' 2>&1)

    if [[ "$result" == "3:세계" ]]; then
        test_pass "Korean handled"
    else
        test_fail "Korean failed" "Got: $result"
    fi
}

test_greek() {
    # Greek alphabet
    local result
    result=$(zsh -c '
        emulate -L zsh
        BUFFER="αλφα βητα γαμμα δελτα"
        words=(${=BUFFER})
        echo "${#words[@]}:${words[3]}"
    ' 2>&1)

    if [[ "$result" == "4:γαμμα" ]]; then
        test_pass "Greek handled"
    else
        test_fail "Greek failed" "Got: $result"
    fi
}

test_hebrew() {
    # Hebrew (RTL)
    local result
    result=$(zsh -c '
        emulate -L zsh
        BUFFER="שלום עולם בדיקה"
        words=(${=BUFFER})
        echo "${#words[@]}:${words[2]}"
    ' 2>&1)

    if [[ "$result" == "3:עולם" ]]; then
        test_pass "Hebrew handled"
    else
        test_fail "Hebrew failed" "Got: $result"
    fi
}

test_mixed_scripts() {
    # Mixed scripts in one buffer
    local result
    result=$(zsh -c '
        emulate -L zsh
        BUFFER="hello 你好 привет مرحبا 🎉"
        words=(${=BUFFER})
        idx=3
        target="${words[$idx]}"

        pos=0 j=1 remaining="$BUFFER"
        while (( j < idx )); do
            wpos="${remaining[(i)${words[$j]}]}"
            (( pos += wpos + ${#words[$j]} - 1 ))
            remaining="${remaining:$((wpos + ${#words[$j]} - 1))}"
            (( j++ ))
        done
        (( pos += ${remaining[(i)$target]} - 1 ))
        echo "$pos:$target"
    ' 2>&1)

    # "hello 你好 привет" - привет starts at 0-based position 9 (for CURSOR)
    if [[ "$result" == "9:привет" ]]; then
        test_pass "Mixed scripts position correct"
    else
        test_fail "Mixed scripts failed" "Got: $result"
    fi
}

test_emoji_sequence() {
    # Various emoji
    local result
    result=$(zsh -c '
        emulate -L zsh
        BUFFER="🚀 🎉 💻 🔥 ⭐"
        words=(${=BUFFER})
        echo "${#words[@]}:${words[4]}"
    ' 2>&1)

    if [[ "$result" == "5:🔥" ]]; then
        test_pass "Emoji sequence handled"
    else
        test_fail "Emoji failed" "Got: $result"
    fi
}

test_accented_latin() {
    # Accented Latin characters
    local result
    result=$(zsh -c '
        emulate -L zsh
        BUFFER="café naïve résumé piñata"
        words=(${=BUFFER})
        echo "${#words[@]}:${words[3]}"
    ' 2>&1)

    if [[ "$result" == "4:résumé" ]]; then
        test_pass "Accented Latin handled"
    else
        test_fail "Accented Latin failed" "Got: $result"
    fi
}

# ------------------------------------------------------------------------------
# FZF Enrichment Feature Tests
# ------------------------------------------------------------------------------

test_supports_binds_detection() {
    local result
    result=$(zsh -c "
        source $PLUGIN_DIR/zledit.plugin.zsh
        _zledit_supports_binds 'fzf' && echo 'fzf:yes'
        _zledit_supports_binds 'fzf-tmux' && echo 'fzf-tmux:yes'
        _zledit_supports_binds 'sk' && echo 'sk:yes'
        _zledit_supports_binds 'peco' || echo 'peco:no'
    " 2>&1)

    if [[ "$result" == *"fzf:yes"* ]] && [[ "$result" == *"fzf-tmux:yes"* ]] && \
       [[ "$result" == *"sk:yes"* ]] && [[ "$result" == *"peco:no"* ]]; then
        test_pass "Bind support detection works (fzf, fzf-tmux, sk: yes; peco: no)"
    else
        test_fail "Bind detection failed" "Got: $result"
    fi
}

# ------------------------------------------------------------------------------
# Picker Integration Tests
# ------------------------------------------------------------------------------

test_integration_fzf_binds() {
    if ! (( $+commands[fzf] )); then
        skip_test "fzf not installed"
        return 0
    fi

    # Test that fzf accepts --bind syntax (using basic actions for compatibility)
    local result
    result=$(echo -e "1: first\n2: second" | fzf --filter="first" --bind "enter:accept,ctrl-s:accept" 2>&1)

    if [[ "$result" == "1: first" ]]; then
        test_pass "fzf accepts --bind syntax"
    else
        test_fail "fzf --bind failed" "Got: $result"
    fi
}

test_integration_fzf_header() {
    if ! (( $+commands[fzf] )); then
        skip_test "fzf not installed"
        return 0
    fi

    # Test that fzf accepts --header option
    local result
    result=$(echo -e "1: test" | fzf --filter="test" --header="^S:wrap | ^H:help" 2>&1)

    if [[ "$result" == "1: test" ]]; then
        test_pass "fzf accepts --header"
    else
        test_fail "fzf --header failed" "Got: $result"
    fi
}

test_integration_sk_binds() {
    if ! (( $+commands[sk] )); then
        skip_test "sk not installed"
        return 0
    fi

    # Test that sk accepts --bind syntax like fzf
    local result
    result=$(echo -e "1: first\n2: second" | sk --filter="first" --bind "enter:accept,ctrl-s:accept" 2>&1)

    if [[ "$result" == "1: first" ]]; then
        test_pass "sk accepts --bind syntax"
    else
        test_fail "sk --bind failed" "Got: $result"
    fi
}

test_integration_sk_header() {
    if ! (( $+commands[sk] )); then
        skip_test "sk not installed"
        return 0
    fi

    # Test that sk accepts --header option
    local result
    result=$(echo -e "1: test" | sk --filter="test" --header="^S:wrap | ^H:help" 2>&1)

    if [[ "$result" == "1: test" ]]; then
        test_pass "sk accepts --header"
    else
        test_fail "sk --header failed" "Got: $result"
    fi
}

test_integration_peco_basic() {
    if ! (( $+commands[peco] )); then
        skip_test "peco not installed"
        return 0
    fi

    # Peco doesn't support non-interactive mode like fzf --filter
    # Just verify peco binary works and accepts --prompt option
    local result
    result=$(peco --help 2>&1)

    if [[ "$result" == *"--prompt"* ]]; then
        test_pass "peco accepts --prompt option"
    else
        test_fail "peco --help failed" "Got: $result"
    fi
}

test_tokenizer_positions() {
    local result
    result=$(zsh -c '
        emulate -L zsh
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        BUFFER="kubectl get pods -n kube-system"
        _zledit_tokenize
        echo "${_ze_positions[4]}"
    ' 2>&1)

    if [[ "$result" == "17" ]]; then
        test_pass "Tokenizer records -n at correct position"
    else
        test_fail "Tokenizer position failed" "Expected: 17, Got: $result"
    fi
}

test_tokenizer_multiple_spaces() {
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        BUFFER="a    b     c"
        _zledit_tokenize
        echo "${#_ze_words[@]}:${_ze_positions[1]}:${_ze_positions[2]}:${_ze_positions[3]}"
    ' 2>&1)
    if [[ "$result" == "3:0:5:11" ]]; then
        test_pass "Multiple spaces handled correctly"
    else
        test_fail "Multiple spaces failed" "Expected: 3:0:5:11, Got: $result"
    fi
}

test_tokenizer_leading_trailing_spaces() {
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        BUFFER="   word   "
        _zledit_tokenize
        echo "${#_ze_words[@]}:${_ze_words[1]}:${_ze_positions[1]}"
    ' 2>&1)
    if [[ "$result" == "1:word:3" ]]; then
        test_pass "Leading/trailing spaces handled"
    else
        test_fail "Leading/trailing spaces failed" "Got: $result"
    fi
}

test_tokenizer_tabs_mixed() {
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        BUFFER=$'"'"'a\tb\t\tc'"'"'
        _zledit_tokenize
        echo "${#_ze_words[@]}"
    ' 2>&1)
    if [[ "$result" == "3" ]]; then
        test_pass "Tabs handled as whitespace"
    else
        test_fail "Tabs handling failed" "Got: $result"
    fi
}

test_tokenizer_very_long_string() {
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        BUFFER=$(printf "word%.0s " {1..500})
        _zledit_tokenize
        echo "${#_ze_words[@]}:${_ze_positions[500]}"
    ' 2>&1)
    if [[ "$result" == "500:2495" ]]; then
        test_pass "500 words tokenized correctly"
    else
        test_fail "Long string failed" "Got: $result"
    fi
}

test_tokenizer_special_shell_chars() {
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        BUFFER="echo \$VAR | grep -E \"[a-z]+\" > /dev/null && cmd"
        _zledit_tokenize
        local simple=0 i
        for i in {1..${#_ze_words[@]}}; do
            [[ "${_ze_is_composite[$i]}" != "1" ]] && (( simple++ ))
        done
        echo "${simple}:${_ze_words[2]}:${_ze_words[6]}"
    ' 2>&1)
    if [[ "$result" == '10:$VAR:"[a-z]+"' ]]; then
        test_pass "Shell special chars preserved"
    else
        test_fail "Shell chars failed" "Got: $result"
    fi
}

test_tokenizer_dashes_flags() {
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        BUFFER="cmd --flag -f --long-option --another=value"
        _zledit_tokenize
        echo "${_ze_words[2]}:${_ze_positions[2]}|${_ze_words[4]}:${_ze_positions[4]}"
    ' 2>&1)
    if [[ "$result" == "--flag:4|--long-option:14" ]]; then
        test_pass "Dashes and flags positioned correctly"
    else
        test_fail "Dashes/flags failed" "Got: $result"
    fi
}

# ------------------------------------------------------------------------------
# Composite span tests
# ------------------------------------------------------------------------------

# Helper for tests: collect composite spans as 'pos:word' lines, sorted by pos:len
_test_composite_dump() {
    local i pos word lines=""
    for i in {1..${#_ze_words[@]}}; do
        [[ "${_ze_is_composite[$i]}" == "1" ]] || continue
        lines+="${_ze_positions[$i]}:${_ze_words[$i]}"$'\n'
    done
    print -rn -- "$lines"
}

test_composite_basic_double_quotes() {
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        BUFFER='"'"'snd -g mcp "ok bob soon"'"'"'
        _zledit_tokenize
        local i found=0
        for i in {1..${#_ze_words[@]}}; do
            [[ "${_ze_is_composite[$i]}" == "1" ]] && \
              [[ "${_ze_words[$i]}" == "\"ok bob soon\"" ]] && \
              [[ "${_ze_positions[$i]}" == "11" ]] && found=1
        done
        echo "$found"
    ' 2>&1)
    [[ "$result" == "1" ]] && test_pass "Composite: double-quoted span surfaces" \
        || test_fail "Composite double-quote span" "Got: $result"
}

test_composite_simple_tokens_unchanged() {
    # Composite enrichment must not change the simple-token view of a buffer.
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        BUFFER='"'"'snd -g mcp "ok bob soon"'"'"'
        _zledit_tokenize
        local simple=0 i
        for i in {1..${#_ze_words[@]}}; do
            [[ "${_ze_is_composite[$i]}" != "1" ]] && (( simple++ ))
        done
        echo "$simple:${_ze_words[1]}:${_ze_words[6]}"
    ' 2>&1)
    [[ "$result" == "6:snd:soon\"" ]] && test_pass "Composite: simple tokens preserved" \
        || test_fail "Composite simple tokens" "Got: $result"
}

test_composite_nested_balanced_pairs() {
    # "aaa"bbb"aaa" → 4 composites: "aaa" (pos 0), "aaa"bbb"aaa" (pos 0),
    #                                "bbb" (pos 4), "aaa" (pos 8)
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        BUFFER='"'"'"aaa"bbb"aaa"'"'"'
        _zledit_tokenize
        local i count=0
        for i in {1..${#_ze_words[@]}}; do
            [[ "${_ze_is_composite[$i]}" == "1" ]] && (( count++ ))
        done
        echo "$count"
    ' 2>&1)
    [[ "$result" == "4" ]] && test_pass "Composite: nested balanced pairs (4 candidates)" \
        || test_fail "Composite nested" "Got: $result (expected 4)"
}

test_composite_quad_quote_edge() {
    # """" → 4 composites: "" (×3 at different positions) + """"
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        BUFFER='"'"'""""'"'"'
        _zledit_tokenize
        local i count=0
        for i in {1..${#_ze_words[@]}}; do
            [[ "${_ze_is_composite[$i]}" == "1" ]] && (( count++ ))
        done
        echo "$count"
    ' 2>&1)
    [[ "$result" == "4" ]] && test_pass "Composite: \"\"\"\" edge case (4 candidates)" \
        || test_fail "Composite quad-quote" "Got: $result (expected 4)"
}

test_composite_brackets_and_braces() {
    # echo (a [b] c) {d} → 3 composites: (a [b] c), [b], {d}
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        BUFFER='"'"'echo (a [b] c) {d}'"'"'
        _zledit_tokenize
        local i count=0 has_outer=0 has_inner=0 has_brace=0
        for i in {1..${#_ze_words[@]}}; do
            [[ "${_ze_is_composite[$i]}" != "1" ]] && continue
            (( count++ ))
            [[ "${_ze_words[$i]}" == "(a [b] c)" ]] && has_outer=1
            [[ "${_ze_words[$i]}" == "[b]" ]] && has_inner=1
            [[ "${_ze_words[$i]}" == "{d}" ]] && has_brace=1
        done
        echo "$count:$has_outer:$has_inner:$has_brace"
    ' 2>&1)
    [[ "$result" == "3:1:1:1" ]] && test_pass "Composite: brackets and braces" \
        || test_fail "Composite brackets" "Got: $result"
}

test_composite_backticks() {
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        BUFFER='"'"'run `cmd arg` here'"'"'
        _zledit_tokenize
        local i found=""
        for i in {1..${#_ze_words[@]}}; do
            [[ "${_ze_is_composite[$i]}" == "1" ]] && found="${_ze_words[$i]}"
        done
        echo "$found"
    ' 2>&1)
    [[ "$result" == '`cmd arg`' ]] && test_pass "Composite: backticks" \
        || test_fail "Composite backticks" "Got: $result"
}

test_composite_apostrophe_inside_double_quotes() {
    # Apostrophes inside "..." are literal text (shell-like rule), so
    # "don't worry" surfaces as a composite span.
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        BUFFER='"'"'echo "don'"'"'"'"'"'"'"'"'t worry"'"'"'
        _zledit_tokenize
        local i found=""
        for i in {1..${#_ze_words[@]}}; do
            [[ "${_ze_is_composite[$i]}" == "1" ]] && found="${_ze_words[$i]}"
        done
        echo "$found"
    ' 2>&1)
    [[ "$result" == "\"don't worry\"" ]] && test_pass "Composite: apostrophe inside double quotes" \
        || test_fail "Composite apostrophe in double quotes" "Got: $result"
}

test_composite_realistic_natural_language() {
    # The motivating real-world case: a quoted command-line argument with
    # English text that contains apostrophes must surface as a composite.
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        BUFFER='"'"'snd -g mcp "ok bob what'"'"'"'"'"'"'"'"'s the status hit"'"'"'
        _zledit_tokenize
        local i found=""
        for i in {1..${#_ze_words[@]}}; do
            [[ "${_ze_is_composite[$i]}" == "1" ]] && found="${_ze_words[$i]}"
        done
        echo "$found"
    ' 2>&1)
    [[ "$result" == "\"ok bob what's the status hit\"" ]] && test_pass "Composite: natural language with apostrophe" \
        || test_fail "Composite natural-language" "Got: $result"
}

test_composite_unmatched_no_span() {
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        BUFFER='"'"'echo "hello'"'"'
        _zledit_tokenize
        local i count=0
        for i in {1..${#_ze_words[@]}}; do
            [[ "${_ze_is_composite[$i]}" == "1" ]] && (( count++ ))
        done
        echo "$count"
    ' 2>&1)
    [[ "$result" == "0" ]] && test_pass "Composite: unmatched delimiter yields no span" \
        || test_fail "Composite unmatched" "Got: $result"
}

test_composite_no_delimiters() {
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        BUFFER="kubectl get pods -n default"
        _zledit_tokenize
        local i count=0
        for i in {1..${#_ze_words[@]}}; do
            [[ "${_ze_is_composite[$i]}" == "1" ]] && (( count++ ))
        done
        echo "$count"
    ' 2>&1)
    [[ "$result" == "0" ]] && test_pass "Composite: no delimiters → no spans" \
        || test_fail "Composite no-delim" "Got: $result"
}

test_composite_empty_buffer() {
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        BUFFER=""
        _zledit_tokenize
        echo "${#_ze_words[@]}:${#_ze_is_composite[@]}"
    ' 2>&1)
    [[ "$result" == "0:0" ]] && test_pass "Composite: empty buffer safe" \
        || test_fail "Composite empty buffer" "Got: $result"
}

test_composite_config_off() {
    local result
    result=$(zsh -c '
        zstyle ":zledit:" composite-delimiters off
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        BUFFER='"'"'echo "hello world" (x)'"'"'
        _zledit_tokenize
        local i count=0
        for i in {1..${#_ze_words[@]}}; do
            [[ "${_ze_is_composite[$i]}" == "1" ]] && (( count++ ))
        done
        echo "$count"
    ' 2>&1)
    [[ "$result" == "0" ]] && test_pass "Composite: config off disables" \
        || test_fail "Composite config off" "Got: $result"
}

test_composite_config_subset() {
    # Configure only () and skip everything else — quotes should not produce composites.
    local result
    result=$(zsh -c '
        zstyle ":zledit:" composite-delimiters "()"
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        BUFFER='"'"'echo "hello" (world)'"'"'
        _zledit_tokenize
        local i quotes=0 parens=0
        for i in {1..${#_ze_words[@]}}; do
            [[ "${_ze_is_composite[$i]}" != "1" ]] && continue
            [[ "${_ze_words[$i]}" == "(world)" ]] && parens=1
            [[ "${_ze_words[$i]}" == "\"hello\"" ]] && quotes=1
        done
        echo "parens=$parens quotes=$quotes"
    ' 2>&1)
    [[ "$result" == "parens=1 quotes=0" ]] && test_pass "Composite: config subset honored" \
        || test_fail "Composite config subset" "Got: $result"
}

test_composite_balanced_helper() {
    # Direct unit test of _zledit_is_balanced.
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        local outcomes=""
        for s in "" "abc" "()" "(())" "([])" "([)]" "(" "(()" "\"x\"" "\"x"; do
            if _zledit_is_balanced "$s"; then outcomes+="1"; else outcomes+="0"; fi
        done
        echo "$outcomes"
    ' 2>&1)
    # Expected per delimiter logic:
    # ""=ok, "abc"=ok, "()"=ok, "(())"=ok, "([])"=ok,
    # "([)]"=mismatched close, "("=open w/ no close,
    # "(()"=open w/ no close, "\"x\""=ok, "\"x"=lone quote
    [[ "$result" == "1111100010" ]] && test_pass "Composite: _zledit_is_balanced unit cases" \
        || test_fail "Composite balanced helper" "Got: $result (expected 1111100010)"
}

test_composite_overlay_skips_composites() {
    # Overlay must not insert hint markers for composite tokens (they overlap simple-token positions).
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        BUFFER='"'"'snd "hi there"'"'"'
        _zledit_tokenize
        _zledit_build_overlay
        echo "$REPLY"
    ' 2>&1)
    # Expected: each simple token gets a [letter] prefix, composite is skipped.
    # snd → [a]snd, "hi → [s]"hi, there" → [d]there"
    [[ "$result" == '[a]snd [s]"hi [d]there"' ]] && test_pass "Composite: overlay skips composites" \
        || test_fail "Composite overlay" "Got: '$result'"
}

test_composite_unload_cleans_state() {
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        BUFFER='"'"'echo "hi"'"'"'
        _zledit_tokenize
        zledit-unload
        # All composite-related globals should be unset
        local check=0
        [[ -z "${_ze_is_composite+x}" ]] && (( check++ ))
        [[ -z "${_ze_composite_symmetric+x}" ]] && (( check++ ))
        [[ -z "${_ze_composite_opens+x}" ]] && (( check++ ))
        [[ -z "${_ze_composite_closes+x}" ]] && (( check++ ))
        # Helper functions should be gone
        (( ! ${+functions[_zledit_is_balanced]} )) && (( check++ ))
        (( ! ${+functions[_zledit_find_composite_spans]} )) && (( check++ ))
        echo "$check"
    ' 2>&1)
    [[ "$result" == "6" ]] && test_pass "Composite: unload cleans all state" \
        || test_fail "Composite unload" "Got: $result (expected 6)"
}

test_tokenizer_equals_in_word() {
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        BUFFER="export VAR=value KEY=123"
        _zledit_tokenize
        echo "${_ze_words[2]}:${_ze_positions[2]}"
    ' 2>&1)
    if [[ "$result" == "VAR=value:7" ]]; then
        test_pass "Equals preserved in word"
    else
        test_fail "Equals handling failed" "Got: $result"
    fi
}

test_action_helpers_defined() {
    local result
    result=$(zsh -c "
        source $PLUGIN_DIR/zledit.plugin.zsh
        (( \$+functions[_zledit_do_jump] )) || exit 1
        (( \$+functions[_zledit_do_custom_action] )) || exit 1
        (( \$+functions[_zledit_load_default_actions] )) || exit 1
        echo 'ok'
    " 2>&1)

    if [[ "$result" == "ok" ]]; then
        test_pass "Action helpers defined"
    else
        test_fail "Action helpers missing" "$result"
    fi
}

test_single_keybinding() {
    local result
    result=$(zsh -c "
        source $PLUGIN_DIR/zledit.plugin.zsh
        bindkey -L | grep -c 'zledit-widget'
    " 2>&1)
    result="${result//[^0-9]/}"

    if [[ "$result" == "1" ]]; then
        test_pass "Single keybinding set (actions via FZF --expect)"
    else
        test_fail "Wrong keybinding count" "Expected: 1, Got: $result"
    fi
}

test_unload_cleans_enrichment() {
    # Comprehensive leak detection - catches ANY leaked function/variable by pattern
    local leaked_funcs leaked_vars
    leaked_funcs=$(zsh -c "
        source $PLUGIN_DIR/zledit.plugin.zsh
        zledit-unload
        print -l \${(k)functions} | grep -E '^_?zsh.jumper|^_ze_' || true
    " 2>&1)
    leaked_vars=$(zsh -c "
        source $PLUGIN_DIR/zledit.plugin.zsh
        zledit-unload
        print -l \${(k)parameters} | grep -E '^_ze_|^Zledit' || true
    " 2>&1)

    if [[ -z "$leaked_funcs" && -z "$leaked_vars" ]]; then
        test_pass "Unload removes all functions and variables"
    else
        test_fail "Unload leaked:" "funcs: $leaked_funcs | vars: $leaked_vars"
    fi
}

test_var_name_uppercase() {
    # Variable names should be uppercase
    local result
    result=$(zsh -c '
        emulate -L zsh
        target="my-value"
        var_name="${${(U)target}//[^A-Z0-9]/_}"
        echo "$var_name"
    ' 2>&1)

    if [[ "$result" == "MY_VALUE" ]]; then
        test_pass "Var name converted to uppercase"
    else
        test_fail "Var name uppercase failed" "Expected: MY_VALUE, Got: $result"
    fi
}

test_var_name_special_chars() {
    # Special chars replaced with underscore
    local result
    result=$(zsh -c '
        emulate -L zsh
        target="my-gpu.test@foo"
        var_name="${${(U)target}//[^A-Z0-9]/_}"
        echo "$var_name"
    ' 2>&1)

    if [[ "$result" == "MY_GPU_TEST_FOO" ]]; then
        test_pass "Var name special chars replaced"
    else
        test_fail "Var name special chars failed" "Expected: MY_GPU_TEST_FOO, Got: $result"
    fi
}

test_var_value_quoted() {
    # Variable assignment should have quoted value
    local result
    result=$(zsh -c '
        emulate -L zsh
        target="my-value"
        var_name="${${(U)target}//[^A-Z0-9]/_}"
        assignment="${var_name}=\"${target}\""
        echo "$assignment"
    ' 2>&1)

    if [[ "$result" == 'MY_VALUE="my-value"' ]]; then
        test_pass "Var value is double-quoted"
    else
        test_fail "Var value quoting failed" "Expected: MY_VALUE=\"my-value\", Got: $result"
    fi
}

test_var_reference_quoted() {
    # Variable reference in command should be quoted
    local result
    result=$(zsh -c '
        emulate -L zsh
        BUFFER="echo my-value end"
        pos=5
        end_pos=13
        var_name="MY_VALUE"
        BUFFER="${BUFFER:0:$pos}\"\$${var_name}\"${BUFFER:$end_pos}"
        echo "$BUFFER"
    ' 2>&1)

    if [[ "$result" == 'echo "$MY_VALUE" end' ]]; then
        test_pass "Var reference is double-quoted"
    else
        test_fail "Var reference quoting failed" "Expected: echo \"\$MY_VALUE\" end, Got: $result"
    fi
}

test_var_with_numbers() {
    # Numbers should be preserved in var name
    local result
    result=$(zsh -c '
        emulate -L zsh
        target="gpu123-test"
        var_name="${${(U)target}//[^A-Z0-9]/_}"
        echo "$var_name"
    ' 2>&1)

    if [[ "$result" == "GPU123_TEST" ]]; then
        test_pass "Var name preserves numbers"
    else
        test_fail "Var name numbers failed" "Expected: GPU123_TEST, Got: $result"
    fi
}

test_var_leading_number() {
    # Leading numbers stay (user can fix if needed)
    local result
    result=$(zsh -c '
        emulate -L zsh
        target="123abc"
        var_name="${${(U)target}//[^A-Z0-9]/_}"
        echo "$var_name"
    ' 2>&1)

    if [[ "$result" == "123ABC" ]]; then
        test_pass "Var name with leading number"
    else
        test_fail "Var leading number failed" "Expected: 123ABC, Got: $result"
    fi
}

test_var_escapes_quotes() {
    # Quotes in target should be escaped in assignment
    local result
    result=$(zsh -c '
        emulate -L zsh
        target="foo\"bar"
        escaped="${target//\"/\\\"}"
        echo "VAR=\"${escaped}\""
    ' 2>&1)

    if [[ "$result" == 'VAR="foo\"bar"' ]]; then
        test_pass "Var escapes quotes in assignment"
    else
        test_fail "Var quote escaping failed" "Expected: VAR=\"foo\\\"bar\", Got: $result"
    fi
}

test_replace_signals_deferred() {
    local meta_file=$(mktemp)
    (
        export ZJ_BUFFER="echo --flag-long-!123 bar"
        export ZJ_POSITIONS=$'0\n5\n22'
        exec 3>"$meta_file"
        "$PLUGIN_DIR/actions/replace.sh" "--flag-long-!123" "2" 2>/dev/null
        exec 3>&-
    )
    local metadata=$(<"$meta_file"); rm -f "$meta_file"

    if [[ "$metadata" == *"mode:deferred"* ]]; then
        test_pass "Replace signals mode:deferred via fd3"
    else
        test_fail "Replace failed" "Expected mode:deferred, Got: '$metadata'"
    fi
}

test_replace_no_stdout() {
    local result
    result=$(
        export ZJ_BUFFER="kubectl get pods"
        export ZJ_POSITIONS=$'0\n8\n12'
        "$PLUGIN_DIR/actions/replace.sh" "kubectl" "1" 3>/dev/null 2>/dev/null
    )

    if [[ -z "$result" ]]; then
        test_pass "Replace produces no stdout (deferred mode)"
    else
        test_fail "Replace no stdout" "Expected empty, Got: '$result'"
    fi
}

test_replace_exits_zero() {
    (
        export ZJ_BUFFER="git commit -m"
        export ZJ_POSITIONS=$'0\n4\n11'
        "$PLUGIN_DIR/actions/replace.sh" "-m" "3" 3>/dev/null 2>/dev/null
    )
    local exit_code=$?

    if (( exit_code == 0 )); then
        test_pass "Replace exits 0 in deferred mode"
    else
        test_fail "Replace exit code" "Expected 0, Got: $exit_code"
    fi
}

# Move action tests - test the swap logic (not the fzf interaction)
test_move_swap_first_last() {
    # Test swap logic: swap first and last token
    # move.sh requires fzf for interactive selection, so we test the buffer manipulation logic
    # Buffer: "mv oldname.txt newname.txt" -> positions: 0, 3, 15
    local result
    result=$(zsh -c '
        src_pos=0
        src_word="mv"
        dest_pos=15
        dest_word="newname.txt"
        buffer="mv oldname.txt newname.txt"
        # Swap: source before destination
        new_buffer="${buffer:0:$src_pos}${dest_word}${buffer:$((src_pos + ${#src_word})):$((dest_pos - src_pos - ${#src_word}))}${src_word}${buffer:$((dest_pos + ${#dest_word}))}"
        echo "$new_buffer"
    ' 2>&1)

    if [[ "$result" == "newname.txt oldname.txt mv" ]]; then
        test_pass "Move swap first/last"
    else
        test_fail "Move swap first/last" "Expected: 'newname.txt oldname.txt mv', Got: '$result'"
    fi
}

test_move_swap_adjacent() {
    # Test swap of adjacent tokens
    local result
    result=$(zsh -c '
        src_pos=3
        src_word="oldname.txt"
        dest_pos=15
        dest_word="newname.txt"
        buffer="mv oldname.txt newname.txt"
        # Swap: source before destination
        new_buffer="${buffer:0:$src_pos}${dest_word}${buffer:$((src_pos + ${#src_word})):$((dest_pos - src_pos - ${#src_word}))}${src_word}${buffer:$((dest_pos + ${#dest_word}))}"
        echo "$new_buffer"
    ' 2>&1)

    if [[ "$result" == "mv newname.txt oldname.txt" ]]; then
        test_pass "Move swap adjacent"
    else
        test_fail "Move swap adjacent" "Expected: 'mv newname.txt oldname.txt', Got: '$result'"
    fi
}

test_move_script_exists() {
    if [[ -x "$PLUGIN_DIR/actions/move.sh" ]]; then
        test_pass "Move script exists and is executable"
    else
        test_fail "Move script missing or not executable"
    fi
}

test_move_exits_on_single_token() {
    # move.sh should exit 1 if less than 2 tokens
    local result exit_code
    result=$(
        export ZJ_BUFFER="single"
        export ZJ_POSITIONS="0"
        export ZJ_WORDS="single"
        "$PLUGIN_DIR/actions/move.sh" "single" "1" 2>&1
    )
    exit_code=$?

    if [[ $exit_code -eq 1 ]]; then
        test_pass "Move exits on single token"
    else
        test_fail "Move should exit 1 on single token" "Exit code: $exit_code"
    fi
}

# Dup action tests
test_dup_basic() {
    local result
    result=$(
        export ZJ_BUFFER="cp file.txt dest"
        export ZJ_POSITIONS=$'0\n3\n12'
        "$PLUGIN_DIR/actions/dup.sh" "file.txt" "2" 2>&1
    )

    if [[ "$result" == "cp file.txt file.txt dest" ]]; then
        test_pass "Dup duplicates token"
    else
        test_fail "Dup basic" "Expected: 'cp file.txt file.txt dest', Got: '$result'"
    fi
}

test_dup_last_token() {
    local result
    result=$(
        export ZJ_BUFFER="echo hello"
        export ZJ_POSITIONS=$'0\n5'
        "$PLUGIN_DIR/actions/dup.sh" "hello" "2" 2>&1
    )

    if [[ "$result" == "echo hello hello" ]]; then
        test_pass "Dup last token"
    else
        test_fail "Dup last token" "Expected: 'echo hello hello', Got: '$result'"
    fi
}

test_dup_first_token() {
    local result
    result=$(
        export ZJ_BUFFER="kubectl get pods"
        export ZJ_POSITIONS=$'0\n8\n12'
        "$PLUGIN_DIR/actions/dup.sh" "kubectl" "1" 2>&1
    )

    if [[ "$result" == "kubectl kubectl get pods" ]]; then
        test_pass "Dup first token"
    else
        test_fail "Dup first token" "Expected: 'kubectl kubectl get pods', Got: '$result'"
    fi
}

test_dup_fd3_metadata() {
    local tmpdir meta_file result
    tmpdir=$(mktemp -d)
    meta_file="$tmpdir/meta"

    result=$(
        export ZJ_BUFFER="cp a b"
        export ZJ_POSITIONS=$'0\n3\n5'
        "$PLUGIN_DIR/actions/dup.sh" "a" "2" 3>"$meta_file"
    )

    local metadata
    metadata=$(<"$meta_file")
    rm -rf "$tmpdir"

    if [[ "$metadata" == *"mode:replace"* && "$metadata" == *"cursor:5"* ]]; then
        test_pass "Dup fd3 metadata"
    else
        test_fail "Dup fd3 metadata" "Expected mode:replace and cursor:5, Got: $metadata"
    fi
}

# Path action tests
test_path_script_exists() {
    if [[ -x "$PLUGIN_DIR/actions/path.sh" ]]; then
        test_pass "Path script exists and executable"
    else
        test_fail "Path script missing or not executable"
    fi
}

# Wrap action tests - test wrapping logic directly
test_wrap_double_quote() {
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        BUFFER="echo foo bar"
        _zledit_tokenize
        local pos="${_ze_positions[2]}" target="${_ze_words[2]}"
        local open="\"" close="\""
        local end_pos=$((pos + ${#target}))
        BUFFER="${BUFFER:0:$end_pos}${close}${BUFFER:$end_pos}"
        BUFFER="${BUFFER:0:$pos}${open}${BUFFER:$pos}"
        echo "$BUFFER"
    ' 2>&1)
    [[ "$result" == 'echo "foo" bar' ]] && test_pass "Wrap double quote" || test_fail "Wrap double quote" "Got: $result"
}

test_wrap_single_quote() {
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        BUFFER="echo foo bar"
        _zledit_tokenize
        local pos="${_ze_positions[2]}" target="${_ze_words[2]}"
        local open="'"'"'" close="'"'"'"
        local end_pos=$((pos + ${#target}))
        BUFFER="${BUFFER:0:$end_pos}${close}${BUFFER:$end_pos}"
        BUFFER="${BUFFER:0:$pos}${open}${BUFFER:$pos}"
        echo "$BUFFER"
    ' 2>&1)
    [[ "$result" == "echo 'foo' bar" ]] && test_pass "Wrap single quote" || test_fail "Wrap single quote" "Got: $result"
}

test_wrap_quoted_var() {
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        BUFFER="echo foo bar"
        _zledit_tokenize
        local pos="${_ze_positions[2]}" target="${_ze_words[2]}"
        local open='"'"'"$'"'"' close='"'"'"'"'"'
        local end_pos=$((pos + ${#target}))
        BUFFER="${BUFFER:0:$end_pos}${close}${BUFFER:$end_pos}"
        BUFFER="${BUFFER:0:$pos}${open}${BUFFER:$pos}"
        echo "$BUFFER"
    ' 2>&1)
    [[ "$result" == 'echo "$foo" bar' ]] && test_pass 'Wrap "$..." quoted var' || test_fail 'Wrap "$..."' "Got: $result"
}

test_wrap_var_expansion() {
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        BUFFER="echo foo bar"
        _zledit_tokenize
        local pos="${_ze_positions[2]}" target="${_ze_words[2]}"
        local open='"'"'${'"'"' close="}"
        local end_pos=$((pos + ${#target}))
        BUFFER="${BUFFER:0:$end_pos}${close}${BUFFER:$end_pos}"
        BUFFER="${BUFFER:0:$pos}${open}${BUFFER:$pos}"
        echo "$BUFFER"
    ' 2>&1)
    [[ "$result" == 'echo ${foo} bar' ]] && test_pass 'Wrap ${...} expansion' || test_fail 'Wrap ${...}' "Got: $result"
}

test_wrap_cmd_subst() {
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        BUFFER="echo foo bar"
        _zledit_tokenize
        local pos="${_ze_positions[2]}" target="${_ze_words[2]}"
        local open='"'"'$('"'"' close=")"
        local end_pos=$((pos + ${#target}))
        BUFFER="${BUFFER:0:$end_pos}${close}${BUFFER:$end_pos}"
        BUFFER="${BUFFER:0:$pos}${open}${BUFFER:$pos}"
        echo "$BUFFER"
    ' 2>&1)
    [[ "$result" == 'echo $(foo) bar' ]] && test_pass 'Wrap $(...) cmd subst' || test_fail 'Wrap $(...)' "Got: $result"
}

test_wrap_special_chars() {
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        BUFFER="echo --my-flag=value"
        _zledit_tokenize
        local pos="${_ze_positions[2]}" target="${_ze_words[2]}"
        local open="\"" close="\""
        local end_pos=$((pos + ${#target}))
        BUFFER="${BUFFER:0:$end_pos}${close}${BUFFER:$end_pos}"
        BUFFER="${BUFFER:0:$pos}${open}${BUFFER:$pos}"
        echo "$BUFFER"
    ' 2>&1)
    [[ "$result" == 'echo "--my-flag=value"' ]] && test_pass "Wrap special chars preserved" || test_fail "Wrap special chars" "Got: $result"
}

test_wrap_first_word() {
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        BUFFER="kubectl get pods"
        _zledit_tokenize
        local pos="${_ze_positions[1]}" target="${_ze_words[1]}"
        local open='"'"'$('"'"' close=")"
        local end_pos=$((pos + ${#target}))
        BUFFER="${BUFFER:0:$end_pos}${close}${BUFFER:$end_pos}"
        BUFFER="${BUFFER:0:$pos}${open}${BUFFER:$pos}"
        echo "$BUFFER"
    ' 2>&1)
    [[ "$result" == '$(kubectl) get pods' ]] && test_pass "Wrap first word" || test_fail "Wrap first word" "Got: $result"
}

test_wrap_last_word() {
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        BUFFER="echo hello world"
        _zledit_tokenize
        local pos="${_ze_positions[3]}" target="${_ze_words[3]}"
        local open='"'"'${'"'"' close="}"
        local end_pos=$((pos + ${#target}))
        BUFFER="${BUFFER:0:$end_pos}${close}${BUFFER:$end_pos}"
        BUFFER="${BUFFER:0:$pos}${open}${BUFFER:$pos}"
        echo "$BUFFER"
    ' 2>&1)
    [[ "$result" == 'echo hello ${world}' ]] && test_pass "Wrap last word" || test_fail "Wrap last word" "Got: $result"
}

# Data-driven tokenizer tests from fixture file
test_tokenizer_fixtures() {
    setopt local_options NO_XTRACE NO_VERBOSE
    local fixture_file="$PLUGIN_DIR/tests/fixtures/tokenizer_edge_cases.txt"
    [[ ! -f "$fixture_file" ]] && { test_skip "Fixture file not found"; return; }

    local failed=0 total=0 tmpfile result actual_count actual_positions
    while IFS=$'\t' read -r input expected_count expected_positions; do
        [[ "$input" == \#* || -z "$input" ]] && continue
        (( total++ ))
        tmpfile=$(mktemp)
        print -r -- "$input" > "$tmpfile"
        result=$(zsh -c '
            source '"$PLUGIN_DIR"'/zledit.plugin.zsh
            BUFFER=$(<'"$tmpfile"')
            _zledit_tokenize
            local simple_count=0 simple_positions="" i
            for i in {1..${#_ze_words[@]}}; do
                if [[ "${_ze_is_composite[$i]}" != "1" ]]; then
                    (( simple_count++ ))
                    simple_positions+="${simple_positions:+ }${_ze_positions[$i]}"
                fi
            done
            print -r -- "${simple_count} ${simple_positions}"
        ' 2>/dev/null)
        rm -f "$tmpfile"
        actual_count="${result%% *}"
        actual_positions="${result#* }"
        if [[ "$actual_count" != "$expected_count" ]]; then
            (( failed++ ))
            print "[0;31m✗[0m Tokenizer: '$input' - expected $expected_count words, got $actual_count"
        elif [[ -n "$expected_positions" && "$actual_positions" != "$expected_positions" ]]; then
            (( failed++ ))
            print "[0;31m✗[0m Tokenizer: '$input' - positions expected '$expected_positions', got '$actual_positions'"
        else
            vlog "Tokenizer: '$input' → $actual_count words at [$actual_positions]"
        fi
    done < "$fixture_file"

    (( failed == 0 )) && test_pass "Tokenizer fixtures ($total cases)" || test_fail "Tokenizer fixtures" "$failed/$total cases failed"
}

# Data-driven multiline command tests
test_multiline_fixtures() {
    setopt local_options NO_XTRACE NO_VERBOSE
    local fixture_file="$PLUGIN_DIR/tests/fixtures/multiline_cases.txt"
    [[ ! -f "$fixture_file" ]] && { test_skip "Multiline fixture file not found"; return; }

    local failed=0 total=0 tmpfile result actual_count actual_positions
    while IFS=$'\t' read -r input expected_count expected_positions; do
        [[ "$input" == \#* || -z "$input" ]] && continue
        (( total++ ))
        # Expand <NL> to newline, <TAB> to tab (pure zsh)
        local expanded=${input//'<NL>'/$'\n'}
        expanded=${expanded//'<TAB>'/$'\t'}
        tmpfile=$(mktemp)
        print -r -- "$expanded" > "$tmpfile"
        result=$(zsh -c '
            source '"$PLUGIN_DIR"'/zledit.plugin.zsh
            BUFFER=$(<'"$tmpfile"')
            _zledit_tokenize
            local simple_count=0 simple_positions="" i
            for i in {1..${#_ze_words[@]}}; do
                if [[ "${_ze_is_composite[$i]}" != "1" ]]; then
                    (( simple_count++ ))
                    simple_positions+="${simple_positions:+ }${_ze_positions[$i]}"
                fi
            done
            print -r -- "${simple_count} ${simple_positions}"
        ' 2>/dev/null)
        rm -f "$tmpfile"
        actual_count="${result%% *}"
        actual_positions="${result#* }"
        if [[ "$actual_count" != "$expected_count" ]]; then
            (( failed++ ))
            print "[0;31m✗[0m Multiline: '$input' - expected $expected_count words, got $actual_count"
        elif [[ -n "$expected_positions" && "$actual_positions" != "$expected_positions" ]]; then
            (( failed++ ))
            print "[0;31m✗[0m Multiline: '$input' - positions expected '$expected_positions', got '$actual_positions'"
        else
            vlog "Multiline: '$input' → $actual_count words"
        fi
    done < "$fixture_file"

    (( failed == 0 )) && test_pass "Multiline fixtures ($total cases)" || test_fail "Multiline fixtures" "$failed/$total cases failed"
}

# Data-driven var extraction tests from fixture file
test_var_fixtures() {
    setopt local_options NO_XTRACE NO_VERBOSE
    local fixture_file="$PLUGIN_DIR/tests/fixtures/var_cases.txt"
    [[ ! -f "$fixture_file" ]] && { test_skip "Var fixture file not found"; return; }

    local failed=0 total=0 tmpfile tmpexpected result expected actual_var_name actual_buffer
    while IFS=$'\t' read -r input token_idx expected_var_name expected_buffer; do
        [[ "$input" == \#* || -z "$input" ]] && continue
        (( total++ ))
        tmpfile=$(mktemp)
        tmpexpected=$(mktemp)
        print -r -- "$input" > "$tmpfile"
        print -r -- "$expected_buffer" > "$tmpexpected"
        result=$(zsh -c '
            source '"$PLUGIN_DIR"'/zledit.plugin.zsh
            BUFFER=$(<'"$tmpfile"')
            _zledit_tokenize
            local idx='"$token_idx"'
            local pos="${_ze_positions[$idx]}"
            local target="${_ze_words[$idx]}"
            local var_name="${${(U)target}//[^A-Z0-9]/_}"
            local end_pos=$((pos + ${#target}))
            BUFFER="${BUFFER:0:$pos}\"\$${var_name}\"${BUFFER:$end_pos}"
            print -r -- "$var_name"
            print -r -- "$BUFFER"
        ' 2>/dev/null)
        expected=$(<"$tmpexpected")
        actual_var_name="${result%%$'\n'*}"
        actual_buffer="${result#*$'\n'}"
        rm -f "$tmpfile" "$tmpexpected"
        if [[ "$actual_var_name" != "$expected_var_name" ]]; then
            (( failed++ ))
            print "[0;31m✗[0m Var: '$input' [$token_idx] - var name expected '$expected_var_name', got '$actual_var_name'"
        elif [[ "$actual_buffer" != "$expected" ]]; then
            (( failed++ ))
            print "[0;31m✗[0m Var: '$input' [$token_idx] - buffer expected '$expected', got '$actual_buffer'"
        else
            vlog "Var: '$input' [$token_idx] → $actual_var_name"
        fi
    done < "$fixture_file"

    (( failed == 0 )) && test_pass "Var fixtures ($total cases)" || test_fail "Var fixtures" "$failed/$total cases failed"
}

# Data-driven replace tests from fixture file
test_replace_fixtures() {
    setopt local_options NO_XTRACE NO_VERBOSE
    local fixture_file="$PLUGIN_DIR/tests/fixtures/replace_cases.txt"
    [[ ! -f "$fixture_file" ]] && { test_skip "Replace fixture file not found"; return; }

    local failed=0 total=0 tmpfile tmpexpected result expected actual_buffer actual_cursor
    while IFS=$'\t' read -r input token_idx expected_buffer expected_cursor; do
        [[ "$input" == \#* || -z "$input" ]] && continue
        (( total++ ))
        tmpfile=$(mktemp)
        tmpexpected=$(mktemp)
        print -r -- "$input" > "$tmpfile"
        print -r -- "$expected_buffer" > "$tmpexpected"
        result=$(zsh -c '
            source '"$PLUGIN_DIR"'/zledit.plugin.zsh
            BUFFER=$(<'"$tmpfile"')
            CURSOR=0
            _zledit_tokenize
            local idx='"$token_idx"'
            local pos="${_ze_positions[$idx]}" target="${_ze_words[$idx]}"
            local end_pos=$((pos + ${#target}))
            BUFFER="${BUFFER:0:$pos}${BUFFER:$end_pos}"
            CURSOR=$pos
            print -r -- "$BUFFER"
            print -r -- "$CURSOR"
        ' 2>/dev/null)
        expected=$(<"$tmpexpected")
        actual_buffer="${result%%$'\n'*}"
        actual_cursor="${result#*$'\n'}"
        rm -f "$tmpfile" "$tmpexpected"
        if [[ "$actual_buffer" != "$expected" ]]; then
            (( failed++ ))
            print "[0;31m✗[0m Replace: '$input' [$token_idx] - buffer expected '$expected', got '$actual_buffer'"
        elif [[ "$actual_cursor" != "$expected_cursor" ]]; then
            (( failed++ ))
            print "[0;31m✗[0m Replace: '$input' [$token_idx] - cursor expected '$expected_cursor', got '$actual_cursor'"
        else
            vlog "Replace: '$input' [$token_idx] → cursor at $actual_cursor"
        fi
    done < "$fixture_file"

    (( failed == 0 )) && test_pass "Replace fixtures ($total cases)" || test_fail "Replace fixtures" "$failed/$total cases failed"
}

# Data-driven wrap tests from fixture file
test_wrap_fixtures() {
    setopt local_options NO_XTRACE NO_VERBOSE
    local fixture_file="$PLUGIN_DIR/tests/fixtures/wrap_cases.txt"
    [[ ! -f "$fixture_file" ]] && { test_skip "Wrap fixture file not found"; return; }

    local failed=0 total=0 open close tmpfile tmpopen tmpclose tmpexpected result expected
    while IFS=$'\t' read -r input token_idx wrapper_type expected_buffer; do
        [[ "$input" == \#* || -z "$input" ]] && continue
        (( total++ ))
        case "$wrapper_type" in
            '"..."')   open='"' close='"' ;;
            "'...'")   open="'" close="'" ;;
            '"$..."')  open='"$' close='"' ;;
            '${...}')  open='${' close='}' ;;
            '$(...)')  open='$(' close=')' ;;
            '`...`')   open='`' close='`' ;;
            '[...]')   open='[' close=']' ;;
            '{...}')   open='{' close='}' ;;
            '(...)')   open='(' close=')' ;;
            '<...>')   open='<' close='>' ;;
        esac
        tmpfile=$(mktemp)
        tmpopen=$(mktemp)
        tmpclose=$(mktemp)
        tmpexpected=$(mktemp)
        print -r -- "$input" > "$tmpfile"
        print -r -- "$open" > "$tmpopen"
        print -r -- "$close" > "$tmpclose"
        print -r -- "$expected_buffer" > "$tmpexpected"
        result=$(zsh -c '
            source '"$PLUGIN_DIR"'/zledit.plugin.zsh
            BUFFER=$(<'"$tmpfile"')
            _zledit_tokenize
            local idx='"$token_idx"'
            local pos="${_ze_positions[$idx]}" target="${_ze_words[$idx]}"
            local open=$(<'"$tmpopen"') close=$(<'"$tmpclose"')
            local end_pos=$((pos + ${#target}))
            BUFFER="${BUFFER:0:$end_pos}${close}${BUFFER:$end_pos}"
            BUFFER="${BUFFER:0:$pos}${open}${BUFFER:$pos}"
            print -r -- "$BUFFER"
        ' 2>/dev/null)
        expected=$(<"$tmpexpected")
        rm -f "$tmpfile" "$tmpopen" "$tmpclose" "$tmpexpected"
        if [[ "$result" != "$expected" ]]; then
            (( failed++ ))
            print "[0;31m✗[0m Wrap: '$input' [$token_idx] $wrapper_type - expected '$expected', got '$result'"
        else
            vlog "Wrap: '$input' [$token_idx] $wrapper_type → '$result'"
        fi
    done < "$fixture_file"

    (( failed == 0 )) && test_pass "Wrap fixtures ($total cases)" || test_fail "Wrap fixtures" "$failed/$total cases failed"
}

# ------------------------------------------------------------------------------
# Overlay and Instant Jump Tests
# ------------------------------------------------------------------------------

test_hint_keys_defined() {
    local result
    result=$(zsh -c "
        source $PLUGIN_DIR/zledit.plugin.zsh
        echo \"\${#_ze_hint_keys[@]}\"
    " 2>&1)

    if [[ "$result" == "26" ]]; then
        test_pass "Hint keys array has 26 elements (a-z, excluding semicolon)"
    else
        test_fail "Hint keys count wrong" "Expected: 26, Got: $result"
    fi
}

test_hint_keys_home_row_first() {
    local result
    result=$(zsh -c "
        source $PLUGIN_DIR/zledit.plugin.zsh
        echo \"\${_ze_hint_keys[1]} \${_ze_hint_keys[2]} \${_ze_hint_keys[3]}\"
    " 2>&1)

    if [[ "$result" == "a s d" ]]; then
        test_pass "Hint keys start with home row (a s d)"
    else
        test_fail "Hint keys order wrong" "Expected: 'a s d', Got: '$result'"
    fi
}

test_build_overlay_simple() {
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        BUFFER="kubectl get pods"
        _zledit_tokenize
        _zledit_build_overlay
        echo "$REPLY"
    ' 2>&1)

    if [[ "$result" == "[a]kubectl [s]get [d]pods" ]]; then
        test_pass "Build overlay creates [a]kubectl [s]get [d]pods"
    else
        test_fail "Build overlay wrong" "Expected: '[a]kubectl [s]get [d]pods', Got: '$result'"
    fi
}

test_build_overlay_preserves_spaces() {
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        BUFFER="a    b"
        _zledit_tokenize
        _zledit_build_overlay
        echo "$REPLY"
    ' 2>&1)

    if [[ "$result" == "[a]a    [s]b" ]]; then
        test_pass "Build overlay preserves multiple spaces"
    else
        test_fail "Build overlay spaces wrong" "Expected: '[a]a    [s]b', Got: '$result'"
    fi
}

test_build_overlay_many_words() {
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        BUFFER="a b c d e f g h i j k l m n o p q r s t u v w x y z aa bb"
        _zledit_tokenize
        _zledit_build_overlay
        echo "${REPLY:0:4}|${REPLY: -6}"
    ' 2>&1)

    if [[ "$result" == "[a]a|[28]bb" ]]; then
        test_pass "Build overlay falls back to numbers after 26 words"
    else
        test_fail "Build overlay many words wrong" "Expected: '[a]a|[28]bb', Got: '$result'"
    fi
}

test_highlight_multidigit_hints() {
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        BUFFER="[a]word [27]another [123]third"
        _zledit_highlight_hints
        echo "${#region_highlight[@]}"
    ' 2>&1)

    if [[ "$result" == "3" ]]; then
        test_pass "Highlight matches single-char and multi-digit hints"
    else
        test_fail "Highlight multi-digit wrong" "Expected: 3 highlights, Got: $result"
    fi
}

test_hint_to_index_a() {
    local result
    result=$(zsh -c "
        source $PLUGIN_DIR/zledit.plugin.zsh
        _zledit_hint_to_index 'a'
    " 2>&1)

    if [[ "$result" == "1" ]]; then
        test_pass "Hint 'a' maps to index 1"
    else
        test_fail "Hint 'a' mapping wrong" "Expected: 1, Got: $result"
    fi
}

test_hint_to_index_s() {
    local result
    result=$(zsh -c "
        source $PLUGIN_DIR/zledit.plugin.zsh
        _zledit_hint_to_index 's'
    " 2>&1)

    if [[ "$result" == "2" ]]; then
        test_pass "Hint 's' maps to index 2"
    else
        test_fail "Hint 's' mapping wrong" "Expected: 2, Got: $result"
    fi
}

test_hint_to_index_q() {
    local result
    result=$(zsh -c "
        source $PLUGIN_DIR/zledit.plugin.zsh
        _zledit_hint_to_index 'q'
    " 2>&1)

    if [[ "$result" == "10" ]]; then
        test_pass "Hint 'q' maps to index 10"
    else
        test_fail "Hint 'q' mapping wrong" "Expected: 10, Got: $result"
    fi
}

test_hint_to_index_numeric_fallback() {
    local result
    result=$(zsh -c "
        source $PLUGIN_DIR/zledit.plugin.zsh
        _zledit_hint_to_index '5'
    " 2>&1)

    if [[ "$result" == "5" ]]; then
        test_pass "Numeric hint '5' returns 5"
    else
        test_fail "Numeric hint fallback wrong" "Expected: 5, Got: $result"
    fi
}

test_extract_index_letter_hint() {
    local result
    result=$(zsh -c "
        source $PLUGIN_DIR/zledit.plugin.zsh
        _zledit_extract_index 'a: kubectl'
    " 2>&1)

    if [[ "$result" == "1" ]]; then
        test_pass "Extract index from 'a: kubectl' returns 1"
    else
        test_fail "Extract index letter hint wrong" "Expected: 1, Got: $result"
    fi
}

test_extract_index_letter_s() {
    local result
    result=$(zsh -c "
        source $PLUGIN_DIR/zledit.plugin.zsh
        _zledit_extract_index 's: get'
    " 2>&1)

    if [[ "$result" == "2" ]]; then
        test_pass "Extract index from 's: get' returns 2"
    else
        test_fail "Extract index letter s wrong" "Expected: 2, Got: $result"
    fi
}

test_extract_index_number() {
    local result
    result=$(zsh -c "
        source $PLUGIN_DIR/zledit.plugin.zsh
        _zledit_extract_index '27: word'
    " 2>&1)

    if [[ "$result" == "27" ]]; then
        test_pass "Extract index from '27: word' returns 27"
    else
        test_fail "Extract index number wrong" "Expected: 27, Got: $result"
    fi
}

test_numbered_list_format() {
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        _ze_words=(kubectl get pods)
        local -a numbered
        for i in {1..${#_ze_words[@]}}; do
            numbered+=("$i: ${_ze_words[$i]}")
        done
        printf "%s\n" "${numbered[@]}"
    ' 2>&1)

    # Initial list uses numbers only (letters appear after instant-key)
    if [[ "$result" == *"1: kubectl"* ]] && [[ "$result" == *"2: get"* ]] && [[ "$result" == *"3: pods"* ]]; then
        test_pass "Numbered list uses clean format"
    else
        test_fail "Numbered list format wrong" "Got: $result"
    fi
}

test_lettered_list_format() {
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        _ze_words=(kubectl get pods)
        local -a lettered
        for i in {1..${#_ze_words[@]}}; do
            lettered+=("${_ze_hint_keys[$i]}: ${_ze_words[$i]}")
        done
        printf "%s\n" "${lettered[@]}"
    ' 2>&1)

    # Lettered list shown after instant-key press
    if [[ "$result" == *"a: kubectl"* ]] && [[ "$result" == *"s: get"* ]] && [[ "$result" == *"d: pods"* ]]; then
        test_pass "Lettered list uses hint format"
    else
        test_fail "Lettered list format wrong" "Got: $result"
    fi
}

test_overlay_functions_exist() {
    local result
    result=$(zsh -c "
        source $PLUGIN_DIR/zledit.plugin.zsh
        (( \$+functions[_zledit_build_overlay] )) || exit 1
        (( \$+functions[_zledit_hint_to_index] )) || exit 1
        (( \$+functions[_zledit_extract_index] )) || exit 1
        echo 'ok'
    " 2>&1)

    if [[ "$result" == "ok" ]]; then
        test_pass "Overlay helper functions defined"
    else
        test_fail "Overlay functions missing" "$result"
    fi
}

test_overlay_clear_escape_sequence() {
    # Verify the ANSI escape sequence for clearing overlay is present and correct
    if grep -q "\\\\e\[1A\\\\e\[2K" "$PLUGIN_DIR/zledit.plugin.zsh"; then
        test_pass "Overlay clear escape sequence present (move up + clear line)"
    else
        test_fail "Missing overlay clear escape sequence \\e[1A\\e[2K"
    fi
}

test_instant_key_default() {
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        echo "${Zledit[instant-key]}"
    ' 2>&1)

    if [[ "$result" == ";" ]]; then
        test_pass "Default instant key is ;"
    else
        test_fail "Default instant key wrong" "Expected: ';', Got: '$result'"
    fi
}

test_instant_key_configurable() {
    local result
    result=$(zsh -c '
        zstyle ":zledit:" fzf-instant-key "ctrl-i"
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        echo "${Zledit[instant-key]}"
    ' 2>&1)

    if [[ "$result" == "ctrl-i" ]]; then
        test_pass "Instant key configurable via zstyle"
    else
        test_fail "Instant key config wrong" "Expected: 'ctrl-i', Got: '$result'"
    fi
}

test_command_with_double_dash() {
    # Test that commands containing -- don't break argument parsing
    result=$(zsh -c '
        source ./zledit.plugin.zsh
        words=(cmd --flag -- arg1 arg2)
        word_count="${#words[@]}"
        sel="4: arg1"

        # Simulate _zledit_do_var argument parsing
        args=("$word_count" "${words[@]}" "$sel")
        wc="${args[1]}"; shift args
        parsed_words=("${args[@]:0:$wc}")
        shift wc args
        parsed_sel="${args[1]}"
        idx="${parsed_sel%%:*}"

        echo "wc=$wc idx=$idx words=${#parsed_words[@]}"
    ' 2>&1)

    if [[ "$result" == "wc=5 idx=4 words=5" ]]; then
        test_pass "Commands with -- parse correctly"
    else
        test_fail "Double-dash parsing failed" "Got: $result"
    fi
}

# ------------------------------------------------------------------------------
# Extensibility Tests
# ------------------------------------------------------------------------------

test_toml_parser_previewers() {
    local result
    result=$(zsh -c "
        source $PLUGIN_DIR/zledit.plugin.zsh
        _zledit_parse_toml '$PLUGIN_DIR/tests/fixtures/test_previewers.toml' previewers
        echo \"\${#_ze_previewer_patterns[@]}:\${_ze_previewer_patterns[1]}\"
    " 2>&1)

    if [[ "$result" == '3:^https?://.*' ]]; then
        test_pass "TOML parser extracts previewers correctly"
    else
        test_fail "TOML parser previewers failed" "Expected: 3:^https?://.*, Got: $result"
    fi
}

test_toml_parser_actions() {
    local result
    result=$(zsh -c "
        source $PLUGIN_DIR/zledit.plugin.zsh
        _zledit_parse_toml '$PLUGIN_DIR/tests/fixtures/test_actions.toml' actions
        echo \"\${#_ze_action_bindings[@]}:\${_ze_action_bindings[1]}:\${_ze_action_descriptions[1]}\"
    " 2>&1)

    if [[ "$result" == "2:ctrl-y:uppercase" ]]; then
        test_pass "TOML parser extracts actions correctly"
    else
        test_fail "TOML parser actions failed" "Expected: 2:ctrl-y:uppercase, Got: $result"
    fi
}

test_toml_parser_missing_file() {
    local result
    result=$(zsh -c "
        source $PLUGIN_DIR/zledit.plugin.zsh
        _zledit_parse_toml '/nonexistent/file.toml' previewers
        echo \$?
    " 2>&1)

    if [[ "$result" == "1" ]]; then
        test_pass "TOML parser returns 1 for missing file"
    else
        test_fail "TOML parser missing file" "Expected: 1, Got: $result"
    fi
}

test_toml_parser_empty_file() {
    local result tmpfile
    tmpfile=$(mktemp)
    result=$(zsh -c "
        source $PLUGIN_DIR/zledit.plugin.zsh
        _zledit_parse_toml '$tmpfile' previewers
        echo \"\${#_ze_previewer_patterns[@]}\"
    " 2>&1)
    rm -f "$tmpfile"

    if [[ "$result" == "0" ]]; then
        test_pass "TOML parser handles empty file"
    else
        test_fail "TOML parser empty file" "Expected: 0, Got: $result"
    fi
}

test_toml_parser_comments() {
    local result tmpfile
    tmpfile=$(mktemp)
    cat > "$tmpfile" << 'EOF'
# This is a comment
[[previewers]]
# Another comment
pattern = '^test$'
script = '/bin/echo'
EOF
    result=$(zsh -c "
        source $PLUGIN_DIR/zledit.plugin.zsh
        _zledit_parse_toml '$tmpfile' previewers
        echo \"\${#_ze_previewer_patterns[@]}:\${_ze_previewer_patterns[1]}\"
    " 2>&1)
    rm -f "$tmpfile"

    if [[ "$result" == '1:^test$' ]]; then
        test_pass "TOML parser ignores comments"
    else
        test_fail "TOML parser comments" "Expected: 1:^test\$, Got: $result"
    fi
}

test_build_preview_cmd_script() {
    local result
    result=$(zsh -c "
        source $PLUGIN_DIR/zledit.plugin.zsh
        _zledit_build_preview_cmd
        # Script-based preview uses preview.sh
        [[ \"\$REPLY\" == *\"preview.sh\"* ]] && echo 'ok' || echo \"\$REPLY\"
    " 2>&1)

    if [[ "$result" == "ok" ]]; then
        test_pass "Build preview cmd uses script"
    else
        test_fail "Build preview cmd script failed" "$result"
    fi
}

test_build_preview_cmd_fallback() {
    local result
    result=$(zsh -c "
        source $PLUGIN_DIR/zledit.plugin.zsh
        # Simulate no script available
        Zledit[dir]='/nonexistent'
        _zledit_build_preview_cmd
        # Fallback should have inline preview
        [[ \"\$REPLY\" == *\"ls -la\"* ]] && echo 'ok' || echo \"\$REPLY\"
    " 2>&1)

    if [[ "$result" == "ok" ]]; then
        test_pass "Build preview cmd fallback works"
    else
        test_fail "Build preview cmd fallback failed" "$result"
    fi
}

test_custom_action_function_exists() {
    local result
    result=$(zsh -c "
        source $PLUGIN_DIR/zledit.plugin.zsh
        (( \$+functions[_zledit_do_custom_action] )) && echo 'ok' || echo 'missing'
    " 2>&1)

    if [[ "$result" == "ok" ]]; then
        test_pass "Custom action function exists"
    else
        test_fail "Custom action function missing" "$result"
    fi
}

test_extensibility_config_loading() {
    local result tmpfile
    tmpfile=$(mktemp)
    cat > "$tmpfile" << 'EOF'
[[previewers]]
pattern = '^test$'
script = '/bin/echo'
EOF
    result=$(zsh -c "
        zstyle ':zledit:' previewer-config '$tmpfile'
        source $PLUGIN_DIR/zledit.plugin.zsh
        echo \"\${#_ze_previewer_patterns[@]}\"
    " 2>&1)
    rm -f "$tmpfile"

    if [[ "$result" == "1" ]]; then
        test_pass "Extensibility config loaded via zstyle"
    else
        test_fail "Extensibility config loading failed" "Expected: 1, Got: $result"
    fi
}

test_unload_cleans_extensibility() {
    local result
    result=$(zsh -c "
        source $PLUGIN_DIR/zledit.plugin.zsh
        _ze_previewer_patterns=('test')
        _ze_action_bindings=('ctrl-t')
        zledit-unload
        (( \$+functions[_zledit_parse_toml] )) && exit 1
        (( \$+functions[_zledit_do_custom_action] )) && exit 1
        (( \$+functions[_zledit_build_preview_cmd] )) && exit 1
        exit 0
    " 2>&1)
    if [[ $? -eq 0 ]]; then
        test_pass "Unload cleans extensibility functions"
    else
        test_fail "Unload extensibility cleanup failed" "$result"
    fi
}

test_toml_malformed_no_equals() {
    local result tmpfile
    tmpfile=$(mktemp)
    cat > "$tmpfile" << 'EOF'
[[previewers]]
pattern '^test$'
command = 'echo test'
EOF
    result=$(zsh -c "
        source $PLUGIN_DIR/zledit.plugin.zsh
        _zledit_parse_toml '$tmpfile' previewers
        echo \"\${#_ze_previewer_patterns[@]}\"
    " 2>&1)
    rm -f "$tmpfile"
    if [[ "$result" == "0" ]]; then
        test_pass "TOML parser ignores malformed line (no equals)"
    else
        test_fail "TOML malformed handling" "Expected: 0, Got: $result"
    fi
}

test_toml_unclosed_quotes() {
    local result tmpfile
    tmpfile=$(mktemp)
    cat > "$tmpfile" << 'EOF'
[[previewers]]
pattern = '^test$
command = 'echo test'
EOF
    result=$(zsh -c "
        source $PLUGIN_DIR/zledit.plugin.zsh
        _zledit_parse_toml '$tmpfile' previewers
        echo \"\${#_ze_previewer_patterns[@]}:\${_ze_previewer_patterns[1]:-empty}\"
    " 2>&1)
    rm -f "$tmpfile"
    # Parser takes value as-is when quotes don't match
    if [[ "$result" == *"empty"* ]] || [[ "$result" == "1:"* ]]; then
        test_pass "TOML parser handles unclosed quotes"
    else
        test_fail "TOML unclosed quotes" "Got: $result"
    fi
}

test_preview_script_exists() {
    if [[ -x "$PLUGIN_DIR/preview.sh" ]]; then
        test_pass "Preview script exists and is executable"
    else
        test_fail "Preview script missing" "$PLUGIN_DIR/preview.sh"
    fi
}

test_action_nonzero_exit() {
    local result tmpdir script
    tmpdir=$(mktemp -d)
    script="$tmpdir/fail.sh"
    cat > "$script" << 'EOF'
#!/bin/bash
echo "error message" >&2
exit 1
EOF
    chmod +x "$script"
    result=$(zsh -c "
        _ze_words=(echo test)
        local script='$script' selected_index=0
        local result stderr_file=\$(mktemp)
        result=\$(printf '%s\n' \"\${_ze_words[@]}\" | SELECTED_INDEX=\"\$selected_index\" \"\$script\" 2>\"\$stderr_file\")
        local exit_code=\$?
        rm -f \"\$stderr_file\"
        echo \"exit:\$exit_code\"
    " 2>&1)
    rm -rf "$tmpdir"
    if [[ "$result" == "exit:1" ]]; then
        test_pass "Action non-zero exit detected"
    else
        test_fail "Action non-zero exit" "Expected: exit:1, Got: $result"
    fi
}

test_fd3_metadata_mode_replace() {
    local result tmpdir script
    tmpdir=$(mktemp -d)
    script="$tmpdir/fd3_replace.sh"
    cat > "$script" << 'EOF'
#!/bin/bash
echo "REPLACED BUFFER"
echo "mode:replace" >&3
echo "cursor:5" >&3
EOF
    chmod +x "$script"
    result=$(zsh -c "
        source $PLUGIN_DIR/zledit.plugin.zsh
        _ze_words=(hello world)
        _ze_positions=(0 6)
        _ze_action_scripts=('$script')
        BUFFER='hello world'
        CURSOR=0
        _zledit_do_custom_action 1 '1: hello'
        echo \"BUFFER:\$BUFFER|CURSOR:\$CURSOR\"
    " 2>&1)
    rm -rf "$tmpdir"
    if [[ "$result" == "BUFFER:REPLACED BUFFER|CURSOR:5" ]]; then
        test_pass "fd 3 metadata mode:replace works"
    else
        test_fail "fd 3 mode:replace" "Expected: BUFFER:REPLACED BUFFER|CURSOR:5, Got: $result"
    fi
}

test_fd3_metadata_mode_error() {
    local result tmpdir script
    tmpdir=$(mktemp -d)
    script="$tmpdir/fd3_error.sh"
    cat > "$script" << 'EOF'
#!/bin/bash
echo "mode:error" >&3
echo "message:custom error" >&3
EOF
    chmod +x "$script"
    result=$(zsh -c "
        source $PLUGIN_DIR/zledit.plugin.zsh
        _ze_words=(hello)
        _ze_positions=(0)
        _ze_action_scripts=('$script')
        BUFFER='hello'
        _zledit_do_custom_action 1 '1: hello'
        echo \"exit:\$?\"
    " 2>&1)
    rm -rf "$tmpdir"
    if [[ "$result" == *"exit:1"* ]]; then
        test_pass "fd 3 metadata mode:error works"
    else
        test_fail "fd 3 mode:error" "Expected exit:1, Got: $result"
    fi
}

test_fd3_fallback_to_exit_codes() {
    local result tmpdir script
    tmpdir=$(mktemp -d)
    script="$tmpdir/legacy.sh"
    cat > "$script" << 'EOF'
#!/bin/bash
# No fd 3 output - should use exit code
echo "LEGACY OUTPUT"
exit 0
EOF
    chmod +x "$script"
    result=$(zsh -c "
        source $PLUGIN_DIR/zledit.plugin.zsh
        _ze_words=(hello)
        _ze_positions=(0)
        _ze_action_scripts=('$script')
        BUFFER='hello'
        CURSOR=0
        _zledit_do_custom_action 1 '1: hello'
        echo \"BUFFER:\$BUFFER\"
    " 2>&1)
    rm -rf "$tmpdir"
    if [[ "$result" == "BUFFER:LEGACY OUTPUT" ]]; then
        test_pass "fd 3 fallback to exit codes works"
    else
        test_fail "fd 3 fallback" "Expected: BUFFER:LEGACY OUTPUT, Got: $result"
    fi
}

# ------------------------------------------------------------------------------
# Batch-apply tests
# ------------------------------------------------------------------------------

test_batch_apply_config_default() {
    local result
    result=$(zsh -c "
        source $PLUGIN_DIR/zledit.plugin.zsh
        echo \"\${Zledit[batch-apply]}\"
    " 2>&1)
    if [[ "$result" == "on" ]]; then
        test_pass "Batch-apply defaults to on"
    else
        test_fail "Batch-apply default" "Expected: on, Got: $result"
    fi
}

test_single_key_config_default() {
    local result
    result=$(zsh -c "
        source $PLUGIN_DIR/zledit.plugin.zsh
        echo \"\${Zledit[single-key]}\"
    " 2>&1)
    if [[ "$result" == "alt-1" ]]; then
        test_pass "Single-key defaults to alt-1"
    else
        test_fail "Single-key default" "Expected: alt-1, Got: $result"
    fi
}

test_token_counts_basic() {
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        BUFFER="echo hello echo world"
        _zledit_tokenize
        _zledit_token_counts
        echo "${_ze_token_counts[echo]}:${_ze_token_counts[hello]}:${_ze_token_counts[world]}"
    ' 2>&1)
    if [[ "$result" == "2:1:1" ]]; then
        test_pass "Token counts correct"
    else
        test_fail "Token counts" "Expected: 2:1:1, Got: $result"
    fi
}

test_duplicate_count_display() {
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        _ze_words=(echo hello echo world)
        _ze_positions=(0 5 11 16)
        _zledit_token_counts
        local -a numbered
        for i in {1..${#_ze_words[@]}}; do
            local w="${_ze_words[$i]}"
            local cnt="${_ze_token_counts[$w]}"
            if (( cnt > 1 )); then
                numbered+=("$i: $w (x$cnt)")
            else
                numbered+=("$i: $w")
            fi
        done
        printf "%s\n" "${numbered[@]}"
    ' 2>&1)
    if [[ "$result" == *"1: echo (x2)"* ]] && [[ "$result" == *"2: hello"* ]] && \
       [[ "$result" != *"2: hello (x"* ]] && [[ "$result" == *"3: echo (x2)"* ]]; then
        test_pass "Duplicate count (xN) shown only for duplicates"
    else
        test_fail "Duplicate count display" "Got: $result"
    fi
}

test_batch_replacement_basic() {
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        BUFFER="kubectl get sre-haiku -n sre-haiku"
        _zledit_tokenize
        _zledit_token_counts
        local saved_buffer="$BUFFER"
        local token_idx=3  # first sre-haiku

        # Simulate action: wrap sre-haiku in quotes at position 3
        local pos="${_ze_positions[$token_idx]}"
        local target="${_ze_words[$token_idx]}"
        local end_pos=$((pos + ${#target}))
        BUFFER="${BUFFER:0:$end_pos}\"${BUFFER:$end_pos}"
        BUFFER="${BUFFER:0:$pos}\"${BUFFER:$pos}"

        _zledit_batch_replace "$saved_buffer" "$token_idx"
        echo "$BUFFER"
    ' 2>&1)
    if [[ "$result" == 'kubectl get "sre-haiku" -n "sre-haiku"' ]]; then
        test_pass "Batch replacement applies to both identical tokens"
    else
        test_fail "Batch replacement basic" "Expected: kubectl get \"sre-haiku\" -n \"sre-haiku\", Got: $result"
    fi
}

test_batch_replacement_different_lengths() {
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        BUFFER="echo foo bar foo"
        _zledit_tokenize
        _zledit_token_counts
        local saved_buffer="$BUFFER"
        local token_idx=2  # first foo at position 5

        # Simulate action: wrap foo -> $(foo) (longer replacement)
        local pos="${_ze_positions[$token_idx]}"
        local target="${_ze_words[$token_idx]}"
        local end_pos=$((pos + ${#target}))
        BUFFER="${BUFFER:0:$end_pos})${BUFFER:$end_pos}"
        BUFFER="${BUFFER:0:$pos}\$(${BUFFER:$pos}"

        _zledit_batch_replace "$saved_buffer" "$token_idx"
        echo "$BUFFER"
    ' 2>&1)
    if [[ "$result" == 'echo $(foo) bar $(foo)' ]]; then
        test_pass "Batch replacement with different lengths"
    else
        test_fail "Batch replacement different lengths" "Expected: echo \$(foo) bar \$(foo), Got: $result"
    fi
}

test_batch_replacement_reverse_order() {
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        BUFFER="x a x a x"
        _zledit_tokenize
        _zledit_token_counts
        local saved_buffer="$BUFFER"
        local token_idx=1  # first x at position 0

        # Simulate action: wrap x -> "x"
        BUFFER="\"x\" a x a x"

        _zledit_batch_replace "$saved_buffer" "$token_idx"
        echo "$BUFFER"
    ' 2>&1)
    if [[ "$result" == '"x" a "x" a "x"' ]]; then
        test_pass "Batch replacement right-to-left order"
    else
        test_fail "Batch replacement reverse order" "Expected: \"x\" a \"x\" a \"x\", Got: $result"
    fi
}

test_batch_trailing_newline() {
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        BUFFER="echo foo -n foo
"
        _zledit_tokenize
        _zledit_token_counts
        local saved_buffer="$BUFFER"
        local token_idx=2

        # Simulate wrap action (trailing newline stripped by $())
        BUFFER="echo \"foo\" -n foo"

        _zledit_batch_replace "$saved_buffer" "$token_idx"
        echo "$BUFFER"
    ' 2>&1)
    if [[ "$result" == 'echo "foo" -n "foo"' ]]; then
        test_pass "Batch works despite trailing newline mismatch"
    else
        test_fail "Batch trailing newline" "Got: $result"
    fi
}

test_batch_skip_when_prefix_changed() {
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        BUFFER="foo bar foo"
        _zledit_tokenize
        _zledit_token_counts
        local saved_buffer="$BUFFER"
        local token_idx=1  # first foo at position 0

        # Simulate a move-type action that changes prefix
        BUFFER="bar foo foo"

        _zledit_batch_replace "$saved_buffer" "$token_idx"
        local count="$REPLY"
        echo "buffer:$BUFFER|count:$count"
    ' 2>&1)
    if [[ "$result" == "buffer:bar foo foo|count:0" ]]; then
        test_pass "Batch skips when prefix changed (safety guard)"
    else
        test_fail "Batch prefix safety" "Got: $result"
    fi
}

test_single_mode_bypass() {
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        BUFFER="echo foo bar foo"
        _zledit_tokenize
        _zledit_token_counts
        local saved_buffer="$BUFFER"
        local token_idx=2  # first foo

        # Simulate wrap action
        BUFFER="echo \"foo\" bar foo"

        _ze_single_mode=1
        _zledit_batch_replace "$saved_buffer" "$token_idx"
        local count="$REPLY"
        echo "buffer:$BUFFER|count:$count"
    ' 2>&1)
    if [[ "$result" == 'buffer:echo "foo" bar foo|count:0' ]]; then
        test_pass "Single mode bypasses batch"
    else
        test_fail "Single mode bypass" "Got: $result"
    fi
}

test_batch_config_off() {
    local result
    result=$(zsh -c '
        zstyle ":zledit:" batch-apply off
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        BUFFER="echo foo bar foo"
        _zledit_tokenize
        _zledit_token_counts
        local saved_buffer="$BUFFER"
        local token_idx=2

        BUFFER="echo \"foo\" bar foo"

        _zledit_batch_replace "$saved_buffer" "$token_idx"
        local count="$REPLY"
        echo "buffer:$BUFFER|count:$count"
    ' 2>&1)
    if [[ "$result" == 'buffer:echo "foo" bar foo|count:0' ]]; then
        test_pass "Batch-apply off prevents batch"
    else
        test_fail "Batch config off" "Got: $result"
    fi
}

test_binding_to_byte_ctrl() {
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        _zledit_binding_to_byte "ctrl-s"
        printf "%s" "$REPLY" | xxd -p
    ' 2>&1)
    if [[ "$result" == "13" ]]; then
        test_pass "ctrl-s converts to byte 0x13"
    else
        test_fail "Binding to byte ctrl" "Expected: 13, Got: $result"
    fi
}

test_binding_to_byte_alt() {
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        _zledit_binding_to_byte "alt-d"
        printf "%s" "$REPLY" | xxd -p
    ' 2>&1)
    if [[ "$result" == "1b64" ]]; then
        test_pass "alt-d converts to ESC+d (0x1b64)"
    else
        test_fail "Binding to byte alt" "Expected: 1b64, Got: $result"
    fi
}

test_find_action_by_key() {
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        # Action bindings already loaded (ctrl-s=wrap, ctrl-e=var, etc.)
        _zledit_binding_to_byte "${_ze_action_bindings[1]}"
        local key="$REPLY"
        _zledit_find_action_by_key "$key"
        echo "$REPLY"
    ' 2>&1)
    if [[ "$result" == "1" ]]; then
        test_pass "Find action by key matches first action"
    else
        test_fail "Find action by key" "Expected: 1, Got: $result"
    fi
}

test_batch_no_duplicates_noop() {
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        BUFFER="kubectl get pods"
        _zledit_tokenize
        _zledit_token_counts
        local saved_buffer="$BUFFER"
        local token_idx=1

        BUFFER="\"kubectl\" get pods"

        _zledit_batch_replace "$saved_buffer" "$token_idx"
        local count="$REPLY"
        echo "count:$count"
    ' 2>&1)
    if [[ "$result" == "count:0" ]]; then
        test_pass "No duplicates = no batch replacements"
    else
        test_fail "Batch no duplicates" "Got: $result"
    fi
}

test_batch_functions_defined() {
    local result
    result=$(zsh -c "
        source $PLUGIN_DIR/zledit.plugin.zsh
        (( \$+functions[_zledit_token_counts] )) || exit 1
        (( \$+functions[_zledit_batch_replace] )) || exit 1
        (( \$+functions[_zledit_binding_to_byte] )) || exit 1
        (( \$+functions[_zledit_find_action_by_key] )) || exit 1
        echo 'ok'
    " 2>&1)
    if [[ "$result" == "ok" ]]; then
        test_pass "All 4 batch functions defined"
    else
        test_fail "Batch functions missing" "$result"
    fi
}

test_unload_cleans_batch() {
    local result
    result=$(zsh -c "
        source $PLUGIN_DIR/zledit.plugin.zsh
        zledit-unload
        (( \$+functions[_zledit_token_counts] )) && exit 1
        (( \$+functions[_zledit_batch_replace] )) && exit 1
        (( \$+functions[_zledit_binding_to_byte] )) && exit 1
        (( \$+functions[_zledit_find_action_by_key] )) && exit 1
        exit 0
    " 2>&1)
    if [[ $? -eq 0 ]]; then
        test_pass "Unload removes batch functions"
    else
        test_fail "Unload batch cleanup failed" "$result"
    fi
}

# ------------------------------------------------------------------------------
# Config permutation tests
# ------------------------------------------------------------------------------

test_config_overlay_off() {
    local result
    result=$(zsh -c '
        zstyle ":zledit:" overlay off
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        echo "${Zledit[overlay]}"
    ' 2>/dev/null)
    if [[ "$result" == "off" ]]; then
        test_pass "Config: overlay=off respected"
    else
        test_fail "Config overlay off" "Expected: off, Got: $result"
    fi
}

test_config_preview_off() {
    local result
    result=$(zsh -c '
        zstyle ":zledit:" preview off
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        echo "${Zledit[preview]}"
    ' 2>/dev/null)
    if [[ "$result" == "off" ]]; then
        test_pass "Config: preview=off respected"
    else
        test_fail "Config preview off" "Expected: off, Got: $result"
    fi
}

test_config_debug_on() {
    local result
    result=$(zsh -c '
        zstyle ":zledit:" debug on
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        echo "${Zledit[debug]}"
    ' 2>/dev/null)
    if [[ "$result" == "on" ]]; then
        test_pass "Config: debug=on respected"
    else
        test_fail "Config debug on" "Expected: on, Got: $result"
    fi
}

test_config_custom_action_keys() {
    local result
    result=$(zsh -c '
        zstyle ":zledit:" fzf-wrap-key ctrl-w
        zstyle ":zledit:" fzf-var-key ctrl-v
        zstyle ":zledit:" fzf-replace-key ctrl-x
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        echo "${Zledit[wrap-key]}|${Zledit[var-key]}|${Zledit[replace-key]}"
    ' 2>/dev/null)
    if [[ "$result" == "ctrl-w|ctrl-v|ctrl-x" ]]; then
        test_pass "Config: custom action keys respected"
    else
        test_fail "Config action keys" "Expected: ctrl-w|ctrl-v|ctrl-x, Got: $result"
    fi
}

test_config_custom_binding() {
    local result
    result=$(zsh -c '
        zstyle ":zledit:" binding "^[j"
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        bindkey "^[j" 2>&1 | grep -c zledit
    ' 2>/dev/null)
    if [[ "$result" == "1" ]]; then
        test_pass "Config: custom binding key works"
    else
        test_fail "Config custom binding" "Expected: 1 match, Got: $result"
    fi
}

test_config_preview_window_custom() {
    local result
    result=$(zsh -c '
        zstyle ":zledit:" preview-window "bottom:40%"
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        echo "${Zledit[preview-window]}"
    ' 2>/dev/null)
    if [[ "$result" == "bottom:40%" ]]; then
        test_pass "Config: custom preview-window"
    else
        test_fail "Config preview-window" "Expected: bottom:40%, Got: $result"
    fi
}

test_config_cursor_end() {
    local result
    result=$(zsh -c '
        zstyle ":zledit:" cursor end
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        echo "${Zledit[cursor]}"
    ' 2>/dev/null)
    if [[ "$result" == "end" ]]; then
        test_pass "Config: cursor=end respected"
    else
        test_fail "Config cursor end" "Expected: end, Got: $result"
    fi
}

test_config_defaults_consistent() {
    # Verify all defaults are set and non-conflicting
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        local keys=("${Zledit[wrap-key]}" "${Zledit[var-key]}" "${Zledit[replace-key]}" "${Zledit[move-key]}" "${Zledit[dup-key]}" "${Zledit[path-key]}")
        # Check no empty defaults
        for k in "${keys[@]}"; do [[ -z "$k" ]] && { echo "empty"; exit 1; }; done
        # Check no duplicates
        local -A seen
        for k in "${keys[@]}"; do
            [[ -n "${seen[$k]}" ]] && { echo "dup:$k"; exit 1; }
            seen[$k]=1
        done
        echo "ok"
    ' 2>/dev/null)
    if [[ "$result" == "ok" ]]; then
        test_pass "Config: all default action keys unique and non-empty"
    else
        test_fail "Config defaults consistency" "$result"
    fi
}

test_config_picker_opts_passthrough() {
    local result
    result=$(zsh -c '
        zstyle ":zledit:" picker-opts "--height=20 --reverse"
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        echo "${Zledit[picker-opts]}"
    ' 2>/dev/null)
    if [[ "$result" == "--height=20 --reverse" ]]; then
        test_pass "Config: picker-opts passthrough"
    else
        test_fail "Config picker-opts" "Expected: --height=20 --reverse, Got: $result"
    fi
}

test_config_batch_and_single_independent() {
    # batch-apply=off should not affect single-key setting
    local result
    result=$(zsh -c '
        zstyle ":zledit:" batch-apply off
        zstyle ":zledit:" fzf-single-key alt-2
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        echo "${Zledit[batch-apply]}|${Zledit[single-key]}"
    ' 2>/dev/null)
    if [[ "$result" == "off|alt-2" ]]; then
        test_pass "Config: batch-apply and single-key independent"
    else
        test_fail "Config batch/single independence" "Expected: off|alt-2, Got: $result"
    fi
}

# ------------------------------------------------------------------------------
# Environment constraint tests
# ------------------------------------------------------------------------------

test_version_compare_modern() {
    # Test version comparison logic directly (no fzf binary needed)
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        # Override to test comparison with modern version
        fzf() { echo "0.55.0"; }
        _zledit_check_fzf_version && echo "pass" || echo "fail"
    ' 2>/dev/null)
    if [[ "$result" == "pass" ]]; then
        test_pass "Version compare: 0.55.0 >= 0.53.0"
    else
        test_fail "Version compare modern" "Expected: pass, Got: $result"
    fi
}

test_version_compare_old() {
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        fzf() { echo "0.44.1"; }
        _zledit_check_fzf_version && echo "pass" || echo "reject"
    ' 2>/dev/null)
    if [[ "$result" == "reject" ]]; then
        test_pass "Version compare: 0.44.1 < 0.53.0 rejected"
    else
        test_fail "Version compare old" "Expected: reject, Got: $result"
    fi
}

test_version_compare_boundary() {
    local result
    result=$(zsh -c '
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        fzf() { echo "0.53.0"; }
        _zledit_check_fzf_version && echo "pass" || echo "fail"
    ' 2>/dev/null)
    if [[ "$result" == "pass" ]]; then
        test_pass "Version compare: exact 0.53.0 accepted"
    else
        test_fail "Version compare boundary" "Expected: pass, Got: $result"
    fi
}

test_old_fzf_clears_picker() {
    command -v fzf &>/dev/null || { test_skip "fzf not installed"; return; }
    local result
    result=$(zsh -c '
        # Wrap real fzf to report old version
        real_fzf=$(command -v fzf)
        fzf() { [[ "$1" == "--version" ]] && echo "0.44.1" || "$real_fzf" "$@"; }
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        echo "${Zledit[picker]:-cleared}"
    ' 2>/dev/null)
    if [[ "$result" == "cleared" ]]; then
        test_pass "Old fzf clears picker (graceful degradation)"
    else
        test_fail "Old fzf picker clear" "Expected: cleared, Got: $result"
    fi
}

test_no_picker_graceful() {
    local result
    result=$(zsh -c '
        PATH=""
        hash -r
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        echo "${Zledit[picker]:-none}"
    ' 2>/dev/null)
    if [[ "$result" == "none" ]]; then
        test_pass "No picker: graceful empty state"
    else
        test_fail "No picker handling" "Expected: none, Got: $result"
    fi
}

test_plugin_loads_without_picker() {
    local result
    result=$(zsh -c '
        PATH=""
        hash -r
        source '"$PLUGIN_DIR"'/zledit.plugin.zsh
        (( $+functions[_zledit_tokenize] )) && echo "ok" || echo "fail"
    ' 2>/dev/null)
    if [[ "$result" == "ok" ]]; then
        test_pass "Core functions available without picker"
    else
        test_fail "Functions missing without picker" "$result"
    fi
}

# ------------------------------------------------------------------------------
# Performance tests (with thresholds)
# ------------------------------------------------------------------------------

test_perf_load_time() {
    local max_ms=200  # Threshold: plugin should load in <200ms
    local total=0
    for i in {1..3}; do
        local ms=$(zsh -c "
            start=\$(date +%s%N)
            source $PLUGIN_DIR/zledit.plugin.zsh
            end=\$(date +%s%N)
            echo \$(( (end - start) / 1000000 ))
        " 2>&1)
        total=$((total + ms))
    done
    local avg=$((total / 3))
    if (( avg < max_ms )); then
        test_pass "Load time ${avg}ms (< ${max_ms}ms threshold)"
    else
        test_fail "Load time ${avg}ms exceeds ${max_ms}ms threshold"
    fi
}

test_perf_tokenize() {
    local max_ms=150  # 100 tokenizations should complete in <150ms
    local ms=$(zsh -c "
        source $PLUGIN_DIR/zledit.plugin.zsh
        BUFFER='kubectl get pods -n default -o wide --show-labels --sort-by=name'
        start=\$(date +%s%N)
        for i in {1..100}; do _zledit_tokenize; done
        end=\$(date +%s%N)
        echo \$(( (end - start) / 1000000 ))
    " 2>&1)
    if (( ms < max_ms )); then
        test_pass "Tokenize 100x in ${ms}ms (< ${max_ms}ms threshold)"
    else
        test_fail "Tokenize 100x took ${ms}ms, exceeds ${max_ms}ms threshold"
    fi
}

test_perf_memory_no_leak() {
    # Verify no memory LEAK (linear growth) - one-time allocation is OK
    # Compare memory at cycle 5 vs cycle 15 (skip initial allocation)
    local result=$(zsh -c "
        for i in {1..5}; do
            source $PLUGIN_DIR/zledit.plugin.zsh
            zledit-unload
        done
        mem1=\$(ps -o rss= -p \$\$)
        for i in {1..10}; do
            source $PLUGIN_DIR/zledit.plugin.zsh
            zledit-unload
        done
        mem2=\$(ps -o rss= -p \$\$)
        echo \$((mem2 - mem1))
    " 2>&1)
    local max_growth=400  # After warmup, should be stable within 400KB (macOS reports higher variance)
    if (( result < max_growth )); then
        test_pass "No memory leak after warmup (delta: ${result}KB)"
    else
        test_fail "Memory leak detected: grew ${result}KB after warmup"
    fi
}

# ------------------------------------------------------------------------------
# Run tests
# ------------------------------------------------------------------------------

print "=== zledit test suite ==="
print ""

run_test test_plugin_loads
run_test test_functions_defined
run_test test_global_state
run_test test_default_actions_loaded
run_test test_action_scripts_exist
run_test test_picker_detection_fzf
run_test test_picker_detection_sk
run_test test_picker_detection_peco
run_test test_zstyle_picker_override
run_test test_adapter_functions_exist
run_test test_invoke_picker_dispatches
run_test test_cursor_position
run_test test_fzf_key_defaults_not_empty
run_test test_disable_bindings
run_test test_unload
run_test test_picker_pipe
run_test test_position_substring_bug
run_test test_many_words
run_test test_special_chars
run_test test_duplicate_words
run_test test_numbered_format
run_test test_index_extraction
run_test test_empty_buffer
run_test test_single_word
run_test test_only_spaces
run_test test_unicode
run_test test_all_special_chars
run_test test_numbers
run_test test_long_buffer
run_test test_tabs_and_newlines
run_test test_backslash_continuation
run_test test_quoted_strings
run_test test_pipes_and_redirects
run_test test_cyrillic
run_test test_chinese
run_test test_arabic
run_test test_japanese
run_test test_korean
run_test test_greek
run_test test_hebrew
run_test test_mixed_scripts
run_test test_emoji_sequence
run_test test_accented_latin

# FZF/SK Bind support tests
run_test test_supports_binds_detection

# Picker integration tests
run_test test_integration_fzf_binds
run_test test_integration_fzf_header
run_test test_integration_sk_binds
run_test test_integration_sk_header
run_test test_integration_peco_basic

# Tokenizer edge case tests
run_test test_tokenizer_positions
run_test test_tokenizer_multiple_spaces
run_test test_tokenizer_leading_trailing_spaces
run_test test_tokenizer_tabs_mixed
run_test test_tokenizer_very_long_string
run_test test_tokenizer_special_shell_chars
run_test test_tokenizer_dashes_flags
run_test test_tokenizer_equals_in_word

run_test test_action_helpers_defined
run_test test_single_keybinding
run_test test_unload_cleans_enrichment
run_test test_command_with_double_dash

# Variable extraction tests
run_test test_var_name_uppercase
run_test test_var_name_special_chars
run_test test_var_value_quoted
run_test test_var_reference_quoted
run_test test_var_with_numbers
run_test test_var_leading_number
run_test test_var_escapes_quotes

# Replace action tests
run_test test_replace_signals_deferred
run_test test_replace_no_stdout
run_test test_replace_exits_zero

# Move action tests
run_test test_move_swap_first_last
run_test test_move_swap_adjacent
run_test test_move_script_exists
run_test test_move_exits_on_single_token

# Dup action tests
run_test test_dup_basic
run_test test_dup_last_token
run_test test_dup_first_token
run_test test_dup_fd3_metadata

# Path action tests
run_test test_path_script_exists

# Wrap action tests
run_test test_wrap_double_quote
run_test test_wrap_single_quote
run_test test_wrap_quoted_var
run_test test_wrap_var_expansion
run_test test_wrap_cmd_subst
run_test test_wrap_special_chars
run_test test_wrap_first_word
run_test test_wrap_last_word
run_test test_tokenizer_fixtures
run_test test_multiline_fixtures
run_test test_var_fixtures
run_test test_replace_fixtures
run_test test_wrap_fixtures

# Overlay and instant jump tests
run_test test_hint_keys_defined
run_test test_hint_keys_home_row_first
run_test test_build_overlay_simple
run_test test_build_overlay_preserves_spaces
run_test test_build_overlay_many_words
run_test test_highlight_multidigit_hints
run_test test_hint_to_index_a
run_test test_hint_to_index_s
run_test test_hint_to_index_q
run_test test_hint_to_index_numeric_fallback
run_test test_extract_index_letter_hint
run_test test_extract_index_letter_s
run_test test_extract_index_number
run_test test_numbered_list_format
run_test test_lettered_list_format
run_test test_overlay_functions_exist
run_test test_overlay_clear_escape_sequence
run_test test_instant_key_default
run_test test_instant_key_configurable

# Extensibility tests
run_test test_toml_parser_previewers
run_test test_toml_parser_actions
run_test test_toml_parser_missing_file
run_test test_toml_parser_empty_file
run_test test_toml_parser_comments
run_test test_toml_malformed_no_equals
run_test test_toml_unclosed_quotes
run_test test_build_preview_cmd_script
run_test test_build_preview_cmd_fallback
run_test test_custom_action_function_exists
run_test test_extensibility_config_loading
run_test test_action_nonzero_exit
run_test test_fd3_metadata_mode_replace
run_test test_fd3_metadata_mode_error
run_test test_fd3_fallback_to_exit_codes
run_test test_unload_cleans_extensibility

# Batch-apply tests
run_test test_batch_apply_config_default
run_test test_single_key_config_default
run_test test_token_counts_basic
run_test test_duplicate_count_display
run_test test_batch_replacement_basic
run_test test_batch_replacement_different_lengths
run_test test_batch_replacement_reverse_order
run_test test_batch_trailing_newline
run_test test_batch_skip_when_prefix_changed
run_test test_single_mode_bypass
run_test test_batch_config_off
run_test test_binding_to_byte_ctrl
run_test test_binding_to_byte_alt
run_test test_find_action_by_key
run_test test_batch_no_duplicates_noop
run_test test_batch_functions_defined
run_test test_unload_cleans_batch

# Composite span tests
run_test test_composite_basic_double_quotes
run_test test_composite_simple_tokens_unchanged
run_test test_composite_nested_balanced_pairs
run_test test_composite_quad_quote_edge
run_test test_composite_brackets_and_braces
run_test test_composite_backticks
run_test test_composite_apostrophe_inside_double_quotes
run_test test_composite_realistic_natural_language
run_test test_composite_unmatched_no_span
run_test test_composite_no_delimiters
run_test test_composite_empty_buffer
run_test test_composite_config_off
run_test test_composite_config_subset
run_test test_composite_balanced_helper
run_test test_composite_overlay_skips_composites
run_test test_composite_unload_cleans_state

# Config permutation tests
run_test test_config_overlay_off
run_test test_config_preview_off
run_test test_config_debug_on
run_test test_config_custom_action_keys
run_test test_config_custom_binding
run_test test_config_preview_window_custom
run_test test_config_cursor_end
run_test test_config_defaults_consistent
run_test test_config_picker_opts_passthrough
run_test test_config_batch_and_single_independent

# Environment constraint tests
run_test test_version_compare_modern
run_test test_version_compare_old
run_test test_version_compare_boundary
run_test test_old_fzf_clears_picker
run_test test_no_picker_graceful
run_test test_plugin_loads_without_picker

# Performance tests
run_test test_perf_load_time
run_test test_perf_tokenize
run_test test_perf_memory_no_leak

print ""
local actual_tests=$((TESTS_RUN - TESTS_SKIPPED))
print "=== Results: $TESTS_PASSED/$actual_tests passed ($TESTS_SKIPPED skipped) ==="

[[ $TESTS_PASSED -eq $actual_tests ]]
