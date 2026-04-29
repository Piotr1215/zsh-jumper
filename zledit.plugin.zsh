#!/usr/bin/env zsh
# zledit - Jump to any word on the current line via fuzzy picker
# https://github.com/decoder/zledit

# Standardized $0 handling (Zsh Plugin Standard)
0="${ZERO:-${${0:#$ZSH_ARGZERO}:-${(%):-%N}}}"
0="${${(M)0:#/*}:-$PWD/$0}"

typeset -gA Zledit
Zledit[dir]="${0:h}"

# ------------------------------------------------------------------------------
# Configuration (read once at load time)
# ------------------------------------------------------------------------------
# Configure via zstyle BEFORE loading the plugin:
#   zstyle ':zledit:' picker fzf
#   zstyle ':zledit:' picker-opts '--height=10 --reverse'
#   zstyle ':zledit:' disable-bindings yes
#   zstyle ':zledit:' preview off
#   zstyle ':zledit:' preview-window 'right:50%:wrap'
# ------------------------------------------------------------------------------

typeset -ga _ze_previewer_patterns _ze_previewer_descriptions _ze_previewer_scripts
typeset -ga _ze_action_bindings _ze_action_descriptions _ze_action_scripts

_zledit_parse_toml() {
    emulate -L zsh
    local file="$1" target_array="$2"
    [[ ! -f "$file" ]] && return 1

    local line in_target=0 current_idx=0
    local -A current_item
    typeset -a match mbegin mend

    # Clear output arrays based on target
    case "$target_array" in
        previewers)
            _ze_previewer_patterns=()
            _ze_previewer_descriptions=()
            _ze_previewer_scripts=()
            ;;
        actions)
            _ze_action_bindings=()
            _ze_action_descriptions=()
            _ze_action_scripts=()
            ;;
    esac

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "${line// /}" || "$line" == \#* ]] && continue
        if [[ "$line" =~ '^\[\[([a-zA-Z_]+)\]\]' ]]; then
            (( in_target )) && _zledit_save_toml_item "$target_array"
            if [[ "${match[1]}" == "$target_array" ]]; then
                in_target=1; current_item=()
            else
                in_target=0
            fi
            continue
        fi
        if (( in_target )) && [[ "$line" =~ '^[[:space:]]*([a-zA-Z_]+)[[:space:]]*=[[:space:]]*(.+)' ]]; then
            local key="${match[1]}" value="${match[2]}"
            if [[ "$value" == \"*\" ]]; then
                value="${value#\"}"; value="${value%\"}"
            elif [[ "$value" == \'*\' ]]; then
                value="${value#\'}"; value="${value%\'}"
            fi
            current_item[$key]="$value"
        fi
    done < "$file"
    (( in_target )) && _zledit_save_toml_item "$target_array"
    return 0
}

_zledit_save_toml_item() {
    local target="$1"
    case "$target" in
        previewers)
            [[ -n "${current_item[pattern]}" && -n "${current_item[script]}" ]] && {
                _ze_previewer_patterns+=("${current_item[pattern]}")
                _ze_previewer_descriptions+=("${current_item[description]:-custom}")
                local script="${current_item[script]}"
                [[ "$script" == "~"* ]] && script="$HOME${script#"~"}"
                _ze_previewer_scripts+=("$script")
            }
            ;;
        actions)
            [[ -n "${current_item[binding]}" && -n "${current_item[script]}" ]] && {
                _ze_action_bindings+=("${current_item[binding]}")
                _ze_action_descriptions+=("${current_item[description]:-custom}")
                local script="${current_item[script]}"
                [[ "$script" == "~"* ]] && script="$HOME${script#"~"}"
                _ze_action_scripts+=("$script")
            }
            ;;
    esac
    current_item=()
}

# Load default built-in actions from plugin's actions/ directory
_zledit_load_default_actions() {
    emulate -L zsh
    local dir="${Zledit[dir]}/actions"

    # Default actions with their configured keybindings
    # Format: binding:description:script
    local -a defaults=(
        "${Zledit[wrap-key]}:wrap:${dir}/wrap.sh"
        "${Zledit[var-key]}:var:${dir}/var.sh"
        "${Zledit[replace-key]}:replace:${dir}/replace.sh"
        "${Zledit[move-key]}:move:${dir}/move.sh"
        "${Zledit[dup-key]}:dup:${dir}/dup.sh"
        "${Zledit[path-key]}:path:${dir}/path.sh"
    )

    local entry binding desc script
    for entry in "${defaults[@]}"; do
        binding="${entry%%:*}"
        entry="${entry#*:}"
        desc="${entry%%:*}"
        script="${entry#*:}"

        # Only add if script exists and binding not already registered (user override)
        [[ ! -x "$script" ]] && continue

        # Check if binding already registered by user config (skip if already in array)
        (( ${_ze_action_bindings[(Ie)$binding]} )) && continue

        _ze_action_bindings+=("$binding")
        _ze_action_descriptions+=("$desc")
        _ze_action_scripts+=("$script")
    done
}

_zledit_check_fzf_version() {
    emulate -L zsh
    local version_str min_version="0.53.0"
    version_str="$(fzf --version 2>/dev/null | awk '{print $1}')"
    [[ -z "$version_str" ]] && return 1

    # Compare versions (major.minor.patch)
    local -a cur=(${(s:.:)version_str}) min=(${(s:.:)min_version})
    local i
    for i in 1 2 3; do
        (( ${cur[$i]:-0} > ${min[$i]:-0} )) && return 0
        (( ${cur[$i]:-0} < ${min[$i]:-0} )) && return 1
    done
    return 0
}

_zledit_load_config() {
    emulate -L zsh
    local val

    # Read all zstyle config once and store in Zledit array
    zstyle -s ':zledit:' overlay val; Zledit[overlay]="${val:-on}"
    zstyle -s ':zledit:' preview val; Zledit[preview]="${val:-on}"
    zstyle -s ':zledit:' preview-window val; Zledit[preview-window]="${val:-right:50%:wrap}"
    zstyle -s ':zledit:' cursor val; Zledit[cursor]="${val:-start}"
    zstyle -s ':zledit:' picker-opts val; Zledit[picker-opts]="$val"

    # FZF action keys
    zstyle -s ':zledit:' fzf-wrap-key val; Zledit[wrap-key]="${val:-ctrl-s}"
    zstyle -s ':zledit:' fzf-var-key val; Zledit[var-key]="${val:-ctrl-e}"
    zstyle -s ':zledit:' fzf-replace-key val; Zledit[replace-key]="${val:-ctrl-r}"
    zstyle -s ':zledit:' fzf-move-key val; Zledit[move-key]="${val:-ctrl-t}"
    zstyle -s ':zledit:' fzf-dup-key val; Zledit[dup-key]="${val:-alt-d}"
    zstyle -s ':zledit:' fzf-path-key val; Zledit[path-key]="${val:-ctrl-p}"
    zstyle -s ':zledit:' fzf-instant-key val; Zledit[instant-key]="${val:-;}"
    zstyle -s ':zledit:' debug val; Zledit[debug]="${val:-off}"
    zstyle -s ':zledit:' batch-apply val; Zledit[batch-apply]="${val:-on}"
    zstyle -s ':zledit:' fzf-single-key val; Zledit[single-key]="${val:-alt-1}"

    # Composite delimiters: balanced pairs surface as extra tokens in the picker.
    # Each value is 1 char (symmetric: " ' `) or 2 chars (open/close: () [] {}).
    # Set to 'off' or empty to disable composite spans.
    local -a _ze_delim_cfg=()
    if zstyle -a ':zledit:' composite-delimiters _ze_delim_cfg; then
        [[ "${_ze_delim_cfg[1]:-}" == "off" ]] && _ze_delim_cfg=()
    else
        _ze_delim_cfg=('"' "'" '`' '()' '[]' '{}')
    fi
    typeset -g _ze_composite_symmetric="" _ze_composite_opens="" _ze_composite_closes=""
    local _d
    for _d in "${_ze_delim_cfg[@]}"; do
        if (( ${#_d} == 1 )); then
            _ze_composite_symmetric+="$_d"
        elif (( ${#_d} == 2 )); then
            _ze_composite_opens+="${_d[1]}"
            _ze_composite_closes+="${_d[2]}"
        fi
    done

    # Extensibility config - unified or separate files
    zstyle -s ':zledit:' config val
    if [[ -n "$val" ]]; then
        [[ "$val" == "~"* ]] && val="$HOME${val#"~"}"
        _zledit_parse_toml "$val" previewers
        _zledit_parse_toml "$val" actions
    else
        zstyle -s ':zledit:' previewer-config val
        [[ -n "$val" ]] && {
            [[ "$val" == "~"* ]] && val="$HOME${val#"~"}"
            _zledit_parse_toml "$val" previewers
        }
        zstyle -s ':zledit:' action-config val
        [[ -n "$val" ]] && {
            [[ "$val" == "~"* ]] && val="$HOME${val#"~"}"
            _zledit_parse_toml "$val" actions
        }
    fi

    # Detect picker (prefer explicit config, then auto-detect)
    zstyle -s ':zledit:' picker val
    if [[ -n "$val" ]]; then
        (( $+commands[$val] )) && Zledit[picker]="$val"
    elif [[ -n "$TMUX" ]] && (( $+commands[fzf-tmux] )); then
        Zledit[picker]="fzf-tmux"
    elif (( $+commands[fzf] )); then
        Zledit[picker]="fzf"
    elif (( $+commands[sk] )); then
        Zledit[picker]="sk"
    elif (( $+commands[peco] )); then
        Zledit[picker]="peco"
    elif (( $+commands[percol] )); then
        Zledit[picker]="percol"
    fi

    # Version check for fzf (requires 0.53.0+ for print() action)
    if [[ "${Zledit[picker]}" == fzf* ]] && ! _zledit_check_fzf_version; then
        print -u2 "zledit: fzf 0.53.0+ required (found: $(fzf --version 2>/dev/null | awk '{print $1}'))"
        print -u2 "zledit: install from https://github.com/junegunn/fzf/releases"
        Zledit[picker]=""
    fi

    # Load default actions (after user config, so user can override)
    _zledit_load_default_actions
}

_zledit_load_config

# Result variables (set by adapters)
typeset -g _ze_result_key _ze_result_selection

# ------------------------------------------------------------------------------
# Picker Adapters (Ports & Adapters pattern)
# ------------------------------------------------------------------------------
# Each adapter implements the same interface:
#   Input:  items via stdin, config via _ze_invoke_* variables
#   Output: _ze_result_key (action), _ze_result_selection (chosen item)
#   Return: 0 = success, 1 = cancelled/error
# ------------------------------------------------------------------------------

# Shared helper for fzf-like pickers (fzf, fzf-tmux, sk)
# Args: $1=command, $2=height (empty for fzf-tmux which uses tmux pane)
_zledit_adapter_fzflike() {
    local cmd="$1"
    local -a base_opts=(${2:+--height=$2} --reverse)
    [[ -n "${Zledit[picker-opts]}" ]] && base_opts+=(${(z)Zledit[picker-opts]})

    [[ "${Zledit[debug]}" == "on" ]] && {
        echo "FZF: $cmd ${base_opts[*]} prompt=${_ze_invoke_prompt}" >> /tmp/zledit-debug.log
    }

    local result
    if [[ -n "$_ze_invoke_binds" ]]; then
        result=$($cmd "${base_opts[@]}" \
            --prompt="$_ze_invoke_prompt" \
            --header="$_ze_invoke_header" \
            --bind "$_ze_invoke_binds" \
            "${_ze_invoke_preview_args[@]}")
        _ze_result_key="${result%%$'\n'*}"
        _ze_result_selection="${result#*$'\n'}"
    else
        result=$($cmd "${base_opts[@]}" --prompt="$_ze_invoke_prompt")
        _ze_result_key=""
        _ze_result_selection="$result"
    fi
    [[ -n "$_ze_result_selection" ]]
}

_zledit_adapter_fzf() { _zledit_adapter_fzflike fzf 40%; }
_zledit_adapter_fzf-tmux() { _zledit_adapter_fzflike fzf-tmux; }
_zledit_adapter_sk() { _zledit_adapter_fzflike sk 40%; }

# Shared helper for simple pickers (no bind support)
_zledit_adapter_simple() {
    local cmd="$1"
    local -a base_opts=()
    [[ -n "${Zledit[picker-opts]}" ]] && base_opts=(${(z)Zledit[picker-opts]})

    _ze_result_key=""
    _ze_result_selection=$($cmd "${base_opts[@]}" --prompt="$_ze_invoke_prompt")
    [[ -n "$_ze_result_selection" ]]
}

_zledit_adapter_peco() { _zledit_adapter_simple peco; }
_zledit_adapter_percol() { _zledit_adapter_simple percol; }

# ------------------------------------------------------------------------------
# Port: Unified Picker Interface
# ------------------------------------------------------------------------------
# Usage:
#   printf '%s\n' "${items[@]}" | _zledit_invoke_picker <picker> <prompt> [header] [binds] [preview_args...]
# Returns:
#   _ze_result_key - action key (empty for basic selection)
#   _ze_result_selection - selected item(s)
# ------------------------------------------------------------------------------

_zledit_invoke_picker() {
    local picker="$1" prompt="$2" header="$3" binds="$4"
    shift 4
    local -a preview_args=("$@")

    # Set invocation context for adapter
    _ze_invoke_prompt="$prompt"
    _ze_invoke_header="$header"
    _ze_invoke_binds="$binds"
    _ze_invoke_preview_args=("${preview_args[@]}")

    # Clear results
    _ze_result_key=""
    _ze_result_selection=""

    # Dispatch to adapter
    local adapter_fn="_zledit_adapter_${picker}"
    if (( $+functions[$adapter_fn] )); then
        $adapter_fn
    else
        echo "zledit: unknown picker '$picker'" >&2
        return 1
    fi
}

_zledit_supports_binds() {
    [[ "$1" == fzf* || "$1" == sk ]]
}

# ------------------------------------------------------------------------------
# Overlay (visual hints on command line)
# ------------------------------------------------------------------------------

# Hint keys: home row first, then top row, then bottom
typeset -ga _ze_hint_keys=(a s d f g h j k l q w e r t y u i o p z x c v b n m)

_zledit_build_overlay() {
    local -a hints=(a s d f g h j k l q w e r t y u i o p z x c v b n m)
    local i=1 pos word last_end=0 result=""
    while (( i <= ${#_ze_words[@]} )); do
        # Composite spans cover positions of simple tokens; skip them in overlay
        if [[ "${_ze_is_composite[$i]:-0}" == "1" ]]; then
            (( i++ ))
            continue
        fi
        pos=${_ze_positions[$i]}
        word=${_ze_words[$i]}
        result+="${BUFFER:$last_end:$((pos - last_end))}"
        (( i <= ${#hints[@]} )) && result+="[${hints[$i]}]${word}" || result+="[${i}]${word}"
        last_end=$((pos + ${#word}))
        (( i++ ))
    done
    result+="${BUFFER:$last_end}"
    REPLY="$result"
}

# Highlight hint keys [a] [s] [27] etc with color via region_highlight
_zledit_highlight_hints() {
    region_highlight=()
    local i=0 len=${#BUFFER} j content
    while (( i < len )); do
        if [[ "${BUFFER:$i:1}" == "[" ]]; then
            # Find closing ]
            j=$((i + 1))
            while (( j < len )) && [[ "${BUFFER:$j:1}" != "]" ]]; do
                (( j++ ))
            done
            if (( j < len )); then
                content="${BUFFER:$((i+1)):$((j-i-1))}"
                # Highlight if content is a single letter (a-z) or a number
                if [[ "$content" == [a-z] ]] || [[ "$content" =~ ^[0-9]+$ ]]; then
                    region_highlight+=("$i $((j+1)) fg=yellow,bold")
                fi
                (( i = j + 1 ))
            else
                (( i++ ))
            fi
        else
            (( i++ ))
        fi
    done
}

# Map hint key back to word index
_zledit_hint_to_index() {
    local hint="$1" i
    for i in {1..${#_ze_hint_keys[@]}}; do
        [[ "${_ze_hint_keys[$i]}" == "$hint" ]] && { echo "$i"; return 0; }
    done
    # Fallback: if it's a number, use directly
    [[ "$hint" =~ ^[0-9]+$ ]] && echo "$hint"
}

# ------------------------------------------------------------------------------
# Tokenizer
# ------------------------------------------------------------------------------

_zledit_tokenize() {
    emulate -L zsh
    _ze_words=()
    _ze_positions=()
    _ze_is_composite=()

    local i=0 word_start=-1 in_word=0
    local len=${#BUFFER}

    while (( i < len )); do
        if [[ "${BUFFER:$i:1}" == [[:space:]] ]]; then
            if (( in_word )); then
                local word="${BUFFER:$word_start:$((i - word_start))}"
                [[ "$word" != "\\" ]] && {
                    _ze_words+=("$word")
                    _ze_positions+=($word_start)
                }
                in_word=0
            fi
        elif (( ! in_word )); then
            word_start=$i
            in_word=1
        fi
        (( i++ ))
    done

    if (( in_word )); then
        local word="${BUFFER:$word_start}"
        [[ "$word" != "\\" ]] && {
            _ze_words+=("$word")
            _ze_positions+=($word_start)
        }
    fi

    # Mark all simple tokens as non-composite
    local n=${#_ze_words[@]} k
    for (( k=1; k<=n; k++ )); do _ze_is_composite+=(0); done

    # Append composite spans (balanced delimiter pairs) as extra tokens
    _zledit_find_composite_spans
}

# ------------------------------------------------------------------------------
# Composite spans (balanced delimiter pairs as tokens)
# ------------------------------------------------------------------------------

# Balance check for the contents of a delimiter span. The optional second arg
# is the enclosing delimiter char, which selects the rule:
#   - symmetric quote (" ' `): require an even count of that same char inside;
#     other delimiter chars are treated as literal. This mirrors shell quoting
#     where e.g. apostrophes inside "..." are literal.
#   - bracket (() [] {}) or unspecified: full greedy stack matching.
_zledit_is_balanced() {
    emulate -L zsh
    local s="$1"
    local enclosing="${2:-}"
    local sym="$_ze_composite_symmetric"
    local opens="$_ze_composite_opens"
    local closes="$_ze_composite_closes"
    local i=1 len=${#s}

    if [[ -n "$enclosing" && -n "$sym" && "$sym" == *"$enclosing"* ]]; then
        local count=0
        while (( i <= len )); do
            [[ "${s[$i]}" == "$enclosing" ]] && (( count++ ))
            (( i++ ))
        done
        (( count % 2 == 0 ))
        return $?
    fi

    local stack="" c top expected idx_str
    while (( i <= len )); do
        c="${s[$i]}"
        if [[ -n "$opens" && "$opens" == *"$c"* ]]; then
            stack+="$c"
        elif [[ -n "$closes" && "$closes" == *"$c"* ]]; then
            [[ -z "$stack" ]] && return 1
            top="${stack[-1]}"
            idx_str="${opens%%${top}*}"
            expected="${closes[$(( ${#idx_str} + 1 ))]}"
            [[ "$c" == "$expected" ]] || return 1
            stack="${stack[1,-2]}"
        elif [[ -n "$sym" && "$sym" == *"$c"* ]]; then
            if [[ -n "$stack" && "${stack[-1]}" == "$c" ]]; then
                stack="${stack[1,-2]}"
            else
                stack+="$c"
            fi
        fi
        (( i++ ))
    done
    [[ -z "$stack" ]]
}

# Find all balanced delimiter pairs in BUFFER. Each match is appended as a
# composite token to _ze_words / _ze_positions / _ze_is_composite.
_zledit_find_composite_spans() {
    emulate -L zsh
    local sym="$_ze_composite_symmetric"
    local opens="$_ze_composite_opens"
    local closes="$_ze_composite_closes"

    [[ -z "$sym$opens$closes" ]] && return 0

    local buf="$BUFFER"
    local len=${#buf}

    # Pass 1: collect delimiter positions (0-based) and chars
    local -a delim_pos delim_char
    local i=1 c
    while (( i <= len )); do
        c="${buf[$i]}"
        if [[ "$sym$opens$closes" == *"$c"* ]]; then
            delim_pos+=($(( i - 1 )))
            delim_char+=("$c")
        fi
        (( i++ ))
    done

    local n=${#delim_pos[@]}
    (( n < 2 )) && return 0

    # Pass 2: enumerate (a,b) delimiter-index pairs, keep balanced ones
    local a b ca cb pa pb inside idx_str matches
    for (( a=1; a<=n; a++ )); do
        for (( b=a+1; b<=n; b++ )); do
            ca="${delim_char[$a]}"
            cb="${delim_char[$b]}"
            matches=0

            if [[ -n "$sym" && "$sym" == *"$ca"* && "$ca" == "$cb" ]]; then
                matches=1
            elif [[ -n "$opens" && "$opens" == *"$ca"* && "$closes" == *"$cb"* ]]; then
                idx_str="${opens%%${ca}*}"
                [[ "${closes[$(( ${#idx_str} + 1 ))]}" == "$cb" ]] && matches=1
            fi

            (( ! matches )) && continue

            pa=${delim_pos[$a]}
            pb=${delim_pos[$b]}
            inside="${buf:$(( pa + 1 )):$(( pb - pa - 1 ))}"

            if _zledit_is_balanced "$inside" "$ca"; then
                _ze_words+=("${buf:$pa:$(( pb - pa + 1 ))}")
                _ze_positions+=($pa)
                _ze_is_composite+=(1)
            fi
        done
    done
}

# ------------------------------------------------------------------------------
# Batch-apply helpers
# ------------------------------------------------------------------------------

_zledit_token_counts() {
    emulate -L zsh
    typeset -gA _ze_token_counts
    _ze_token_counts=()
    local w
    for w in "${_ze_words[@]}"; do
        (( _ze_token_counts[$w] = ${_ze_token_counts[$w]:-0} + 1 ))
    done
}

_zledit_batch_replace() {
    emulate -L zsh
    local saved_buffer="$1" token_idx="$2"
    REPLY=0

    local _dbg="${Zledit[debug]}"
    if [[ "$_dbg" == "on" ]]; then
        print "batch: idx=$token_idx batch=${Zledit[batch-apply]} single=$_ze_single_mode" >> /tmp/zledit-debug.log
    fi

    if [[ "${Zledit[batch-apply]}" != "on" ]]; then
        [[ "$_dbg" == "on" ]] && print "batch: SKIP batch-apply off" >> /tmp/zledit-debug.log
        return 0
    fi
    if (( _ze_single_mode )); then
        [[ "$_dbg" == "on" ]] && print "batch: SKIP single mode" >> /tmp/zledit-debug.log
        return 0
    fi

    # Normalize: $() in _zledit_do_custom_action strips trailing newlines
    while [[ "$saved_buffer" == *$'\n' ]]; do saved_buffer="${saved_buffer%$'\n'}"; done

    local token="${_ze_words[$token_idx]}"
    local count="${_ze_token_counts[$token]}"
    if [[ "$_dbg" == "on" ]]; then
        print "batch: token='$token' count=$count words=${#_ze_words[@]}" >> /tmp/zledit-debug.log
    fi
    if (( count <= 1 )); then
        [[ "$_dbg" == "on" ]] && print "batch: SKIP count<=1" >> /tmp/zledit-debug.log
        return 0
    fi

    local orig_pos="${_ze_positions[$token_idx]}"
    if (( orig_pos > 0 )); then
        if [[ "${saved_buffer:0:$orig_pos}" != "${BUFFER:0:$orig_pos}" ]]; then
            if [[ "$_dbg" == "on" ]]; then
                print "batch: prefix old='${saved_buffer:0:$orig_pos}' new='${BUFFER:0:$orig_pos}'" >> /tmp/zledit-debug.log
                print "batch: SKIP prefix mismatch" >> /tmp/zledit-debug.log
            fi
            return 0
        fi
    fi
    [[ "$_dbg" == "on" ]] && print "batch: prefix old='${saved_buffer:0:$orig_pos}' new='${BUFFER:0:$orig_pos}'" >> /tmp/zledit-debug.log

    local orig_len=${#token}
    local old_end=$((orig_pos + orig_len))
    local saved_tail="${saved_buffer:$old_end}"
    local buf_len=${#BUFFER}
    local tail_len=${#saved_tail}
    local new_tail_start=$((buf_len - tail_len))

    if [[ "${BUFFER:$new_tail_start}" != "$saved_tail" ]]; then
        if [[ "$_dbg" == "on" ]]; then
            print "batch: tail saved='$saved_tail' actual='${BUFFER:$new_tail_start}'" >> /tmp/zledit-debug.log
            print "batch: SKIP tail mismatch" >> /tmp/zledit-debug.log
        fi
        return 0
    fi
    [[ "$_dbg" == "on" ]] && print "batch: tail saved='$saved_tail' actual='${BUFFER:$new_tail_start}'" >> /tmp/zledit-debug.log

    local replacement="${BUFFER:$orig_pos:$((new_tail_start - orig_pos))}"
    [[ "$replacement" == "$token" ]] && return 0

    [[ "$_dbg" == "on" ]] && print "batch: replacement='$replacement'" >> /tmp/zledit-debug.log

    local -a other_positions=()
    local i
    for i in {1..${#_ze_words[@]}}; do
        (( i == token_idx )) && continue
        [[ "${_ze_words[$i]}" == "$token" ]] || continue
        other_positions+=("${_ze_positions[$i]}")
    done
    (( ${#other_positions[@]} == 0 )) && return 0

    [[ "$_dbg" == "on" ]] && print "batch: other_positions=(${other_positions[*]})" >> /tmp/zledit-debug.log

    local -a sorted=(${(On)other_positions})
    local delta=$(( ${#replacement} - orig_len ))
    local pos adj_pos replaced=0
    for pos in "${sorted[@]}"; do
        if (( pos > orig_pos )); then
            adj_pos=$((pos + delta))
        else
            adj_pos=$pos
        fi
        BUFFER="${BUFFER:0:$adj_pos}${replacement}${BUFFER:$((adj_pos + orig_len))}"
        (( replaced++ ))
    done

    [[ "$_dbg" == "on" ]] && print "batch: replaced=$replaced BUFFER='$BUFFER'" >> /tmp/zledit-debug.log

    REPLY=$replaced
}

_zledit_binding_to_byte() {
    emulate -L zsh
    local binding="$1"
    REPLY=""

    if [[ "$binding" == ctrl-* ]]; then
        local ch="${binding#ctrl-}"
        local ord=$(( #ch ))
        local ctrl_ord=$(( ord - 96 ))
        REPLY=$(printf '\x'"$(printf '%02x' $ctrl_ord)")
    elif [[ "$binding" == alt-* ]]; then
        local ch="${binding#alt-}"
        REPLY=$'\e'"$ch"
    else
        REPLY="$binding"
    fi
}

_zledit_find_action_by_key() {
    emulate -L zsh
    local key="$1"
    REPLY=0

    local i binding_bytes
    for i in {1..${#_ze_action_bindings[@]}}; do
        _zledit_binding_to_byte "${_ze_action_bindings[$i]}"
        binding_bytes="$REPLY"
        if [[ "$key" == "$binding_bytes" ]]; then
            REPLY=$i
            return 0
        fi
    done
    REPLY=0
}

# Build preview command
# Returns preview command string via REPLY
_zledit_build_preview_cmd() {
    emulate -L zsh
    # Simple approach: use external script to avoid quoting hell
    local script="${Zledit[dir]}/preview.sh"
    if [[ -x "$script" ]]; then
        # Inline env vars for fzf-tmux compatibility (tmux panes don't inherit exports)
        local env_prefix=""
        if (( ${#_ze_previewer_patterns[@]} > 0 )); then
            local patterns="${(pj:\n:)_ze_previewer_patterns}"
            local scripts="${(pj:\n:)_ze_previewer_scripts}"
            env_prefix="ZJ_PREVIEWER_PATTERNS=${(qq)patterns} ZJ_PREVIEWER_SCRIPTS=${(qq)scripts} "
        fi
        REPLY="${env_prefix}$script {}"
    else
        # Fallback inline preview (no custom previewers)
        REPLY='t="{}"; t="${t#*: }"; t="${t//\"/}"; [ -d "$t" ] && ls -la "$t" 2>/dev/null || [ -f "$t" ] && head -30 "$t" 2>/dev/null'
    fi
}

# ------------------------------------------------------------------------------
# Main Widget
# ------------------------------------------------------------------------------

zledit-widget() {
    emulate -L zsh
    setopt local_options no_xtrace no_verbose

    local picker="${Zledit[picker]}"
    if [[ -z "$picker" ]]; then
        zle -M "zledit: no picker found (install fzf, sk, peco, or percol)"
        return 1
    fi

    _zledit_tokenize
    [[ ${#_ze_words[@]} -eq 0 ]] && return 0
    _zledit_token_counts

    # Build numbered list for fzf (letters shown via overlay after instant-key)
    local -a numbered
    local i
    for i in {1..${#_ze_words[@]}}; do
        local _w="${_ze_words[$i]}" _cnt="${_ze_token_counts[${_ze_words[$i]}]}"
        if (( _cnt > 1 )); then
            numbered+=("$i: ${_w} (x${_cnt})")
        else
            numbered+=("$i: ${_w}")
        fi
    done

    # Use pre-loaded config from Zledit array (no zstyle reads during widget)
    local header="" binds=""
    local -a preview_args=()

    if _zledit_supports_binds "$picker"; then
        local ik=${Zledit[instant-key]}

        # Build header and bindings dynamically from action arrays
        local ai binding desc key_display
        local -a header_parts=()
        for ai in {1..${#_ze_action_bindings[@]}}; do
            binding="${_ze_action_bindings[$ai]}"
            [[ -z "$binding" ]] && continue
            desc="${_ze_action_descriptions[$ai]}"
            key_display="${binding#ctrl-}"
            [[ "$binding" == ctrl-* ]] && key_display="^${(U)key_display}"
            header_parts+=("${key_display}:${desc}")
        done
        header_parts+=("${ik}+a-z:jump")
        [[ "${Zledit[batch-apply]}" == "on" ]] && header_parts+=("M-1:single")
        header="${(j: | :)header_parts}"

        # Build hint key bindings and unbind/rebind lists
        # Letter keys start unbound (for fuzzy search), instant-key rebinds them
        local hint_binds="" unbinds="" rebinds="" k
        for k in a s d f g h j k l q w e r t y u i o p z x c v b n m; do
            hint_binds+=",$k:print(hint-$k)+accept"
            unbinds+="${unbinds:+,}$k"
            rebinds+="${rebinds:+,}$k"
        done

        binds="enter:print()+accept"

        # Add all action bindings (both built-in and custom use same mechanism)
        for ai in {1..${#_ze_action_bindings[@]}}; do
            [[ -z "${_ze_action_bindings[$ai]}" ]] && continue
            binds+=",${_ze_action_bindings[$ai]}:print(action-${ai})+accept"
        done

        binds+="$hint_binds"
        # Letter keys unbound initially; instant-key rebinds them for direct jump
        binds+=",start:unbind($unbinds)"
        binds+=",${ik}:rebind($rebinds)"
        # Preview scroll
        binds+=",ctrl-d:preview-page-down,ctrl-u:preview-page-up"
        # Single-mode escape hatch for batch-apply
        [[ "${Zledit[batch-apply]}" == "on" ]] && \
            binds+=",${Zledit[single-key]}:print(single)+accept"

        if [[ "${Zledit[preview]}" != "off" ]]; then
            _zledit_build_preview_cmd
            local preview_cmd="$REPLY"
            preview_args=(--preview "$preview_cmd" --preview-window "${Zledit[preview-window]}")
        fi
    fi

    # Always save original buffer (for safe restoration)
    local saved_buffer="$BUFFER"

    # Show overlay on command line with highlighted hints
    if [[ "${Zledit[overlay]}" != "off" ]]; then
        _zledit_build_overlay
        BUFFER="$REPLY"
        _zledit_highlight_hints
        zle -R
    fi

    # Invoke picker
    zle -I
    printf '%s\n' "${numbered[@]}" | _zledit_invoke_picker "$picker" "jump> " "$header" "$binds" "${preview_args[@]}"

    # Clear overlay line from terminal scrollback (move up, clear line)
    [[ "${Zledit[overlay]}" != "off" ]] && print -n '\e[1A\e[2K'

    # Restore original buffer and clear highlights
    region_highlight=()
    BUFFER="$saved_buffer"

    # Handle instant hint keys (hint-a, hint-s, etc)
    if [[ "$_ze_result_key" == hint-* ]]; then
        local hint_char="${_ze_result_key#hint-}"
        local hint_idx="$(_zledit_hint_to_index "$hint_char")"
        if [[ -n "$hint_idx" ]] && (( hint_idx >= 1 && hint_idx <= ${#_ze_words[@]} )); then
            _zledit_do_jump "${hint_idx}: ${_ze_words[$hint_idx]}"
        fi
        zle reset-prompt
        return 0
    fi

    [[ -z "$_ze_result_selection" ]] && { zle reset-prompt; return 0; }

    # Handle result based on action key
    local -a selections=("${(@f)_ze_result_selection}")

    local _raw_sel="${selections[1]}"
    _raw_sel="${_raw_sel% (x[0-9]*)}"

    typeset -g _ze_single_mode=0
    typeset -g _ze_deferred=0
    typeset -g _ze_deferred_prefix=""

    case "$_ze_result_key" in
        single)
            _ze_single_mode=1
            local -a _act_list=()
            local _ai
            for _ai in {1..${#_ze_action_bindings[@]}}; do
                _act_list+=("${_ai}: ${_ze_action_descriptions[$_ai]}")
            done
            zle -I
            local _act_sel
            if [[ "$picker" == "fzf-tmux" ]]; then
                _act_sel=$(printf '%s\n' "${_act_list[@]}" | fzf-tmux --reverse --prompt="action> ") || true
            else
                _act_sel=$(printf '%s\n' "${_act_list[@]}" | fzf --height=10 --reverse --prompt="action> ") || true
            fi
            if [[ -n "$_act_sel" ]]; then
                local _act_idx="${_act_sel%%:*}"
                _zledit_do_custom_action "$_act_idx" "$_raw_sel"
            fi
            ;;
        action-*)
            # All actions (built-in and custom) use external scripts
            local action_idx="${_ze_result_key#action-}"
            local _batch_saved="$BUFFER"
            local _batch_tidx="$(_zledit_extract_index "$_raw_sel")"
            _zledit_do_custom_action "$action_idx" "$_raw_sel"
            if (( _ze_deferred )); then
                # Deferred replacement: in-context recursive-edit with tab completion
                local _target="${_ze_words[$_batch_tidx]}"
                local _tpos="${_ze_positions[$_batch_tidx]}"
                local _prefix="$_ze_deferred_prefix"
                local _count=0 _i
                for _i in {1..${#_ze_words[@]}}; do
                    [[ "${_ze_words[$_i]}" == "$_target" ]] && (( _count++ ))
                done
                # Delete target (or just value part if prefix set) from BUFFER at selected position
                local _del_start _del_len
                if [[ -n "$_prefix" ]]; then
                    _del_start=$(( _tpos + ${#_prefix} ))
                    _del_len=$(( ${#_target} - ${#_prefix} ))
                else
                    _del_start=$_tpos
                    _del_len=${#_target}
                fi
                local _buf_after_delete="${BUFFER:0:$_del_start}${BUFFER:$((_del_start + _del_len))}"
                BUFFER="$_buf_after_delete"
                CURSOR=$_del_start
                zle reset-prompt
                if (( _count > 1 )); then
                    zle -M "replace '$_target' (x${_count}) → Enter to apply, Ctrl-G cancel"
                else
                    zle -M "replace '$_target' → Enter to apply, Ctrl-G cancel"
                fi
                zle recursive-edit
                local _ret=$?
                if (( _ret == 0 )); then
                    if (( _count > 1 )); then
                        # Extract what user typed at the deletion point
                        local _typed_len=$(( ${#BUFFER} - ${#_buf_after_delete} ))
                        local _typed_text="${BUFFER:$_del_start:$((_typed_len > 0 ? _typed_len : 0))}"
                        # Build full replacement (prefix + typed text)
                        local _replacement
                        if [[ -n "$_prefix" ]]; then
                            _replacement="${_prefix}${_typed_text}"
                        else
                            _replacement="$_typed_text"
                        fi
                        # Restore and replace ALL occurrences right-to-left
                        BUFFER="$_batch_saved"
                        local -a _all_pos=()
                        for _i in {1..${#_ze_words[@]}}; do
                            [[ "${_ze_words[$_i]}" == "$_target" ]] || continue
                            _all_pos+=("${_ze_positions[$_i]}")
                        done
                        local -a _sorted=(${(On)_all_pos})
                        local _p
                        for _p in "${_sorted[@]}"; do
                            BUFFER="${BUFFER:0:$_p}${_replacement}${BUFFER:$((_p + ${#_target}))}"
                        done
                        # Cursor on last (rightmost) replaced element
                        local _delta=$(( ${#_replacement} - ${#_target} ))
                        CURSOR=$(( _sorted[1] + (${#_all_pos[@]} - 1) * _delta ))
                        zle -M "zledit: replaced '$_target' (x${_count})"
                    fi
                    # Single occurrence: BUFFER already has the final result
                else
                    BUFFER="$_batch_saved"
                fi
            else
                # Batch-apply to identical tokens
                _zledit_batch_replace "$_batch_saved" "$_batch_tidx"
                if (( REPLY > 0 )); then
                    local _bw="${_ze_words[$_batch_tidx]}"
                    zle -M "zledit: ${_ze_action_descriptions[$action_idx]} ${_bw} (x$((REPLY + 1)))"
                fi
            fi
            ;;
        *)
            # Default: jump to selection
            _zledit_do_jump "$_raw_sel"
            ;;
    esac

    zle reset-prompt
}

# ------------------------------------------------------------------------------
# Actions
# ------------------------------------------------------------------------------

# Extract index from selection format: "a: word" or "123: word"
# Returns numeric index (1-based)
_zledit_extract_index() {
    local sel="$1" key
    # Extract key before colon
    key="${sel%%:*}"
    # If it's a single letter, convert to index
    if [[ "$key" =~ ^[a-z]$ ]]; then
        _zledit_hint_to_index "$key"
    else
        echo "$key"
    fi
}

_zledit_do_jump() {
    local sel="$1"
    [[ -z "$sel" ]] && return 1

    local idx="$(_zledit_extract_index "$sel")"
    [[ "$idx" =~ ^[0-9]+$ ]] || return 1
    (( idx < 1 || idx > ${#_ze_words[@]} )) && return 1

    local pos="${_ze_positions[$idx]}"
    local target="${_ze_words[$idx]}"

    case "${Zledit[cursor]}" in
        end)    CURSOR=$((pos + ${#target})) ;;
        middle) CURSOR=$((pos + ${#target} / 2)) ;;
        *)      CURSOR=$pos ;;
    esac
}

# Execute custom action script
# Args: $1 = action index, $2 = selection string
# Script interface:
#   args: $1 = selected token, $2 = token index (1-based)
#   env:  ZJ_BUFFER = current command line
#         ZJ_WORDS = newline-separated tokens
#         ZJ_POSITIONS = newline-separated positions (0-based byte offsets)
#         ZJ_CURSOR = current cursor position
#   stdout: new command line content
#
#   fd 3 metadata (preferred):
#     mode:replace|display|pushline|pushline-exec|error
#     cursor:N
#     pushline:command to execute
#     message:error or info message
#
#   exit codes (legacy fallback, used when fd 3 is empty):
#     0 = apply stdout as new BUFFER
#     1 = error (show stderr)
#     2 = display mode (show stdout in terminal, no buffer change)
#     3 = push-line mode (format: "new_buffer\n---ZJ_PUSHLINE---\npushed_line")
#     4 = push-line + auto-execute (same format, but executes pushed_line immediately)
_zledit_do_custom_action() {
    emulate -L zsh
    local action_idx="$1" sel="$2"
    [[ -z "$sel" ]] && return 1

    # Validate action index
    (( action_idx < 1 || action_idx > ${#_ze_action_scripts[@]} )) && return 1

    local script="${_ze_action_scripts[$action_idx]}"
    [[ ! -x "$script" ]] && {
        zle -M "zledit: action script not executable: $script"
        return 1
    }

    # Get selected token
    local token_idx="$(_zledit_extract_index "$sel")"
    [[ "$token_idx" =~ ^[0-9]+$ ]] || return 1
    (( token_idx < 1 || token_idx > ${#_ze_words[@]} )) && return 1
    local token="${_ze_words[$token_idx]}"

    # Export environment for script, capture stdout, stderr, and fd 3 (metadata)
    local result stderr_file=$(mktemp) meta_file=$(mktemp)
    {
        exec 3>"$meta_file"
        result=$(
            export ZJ_BUFFER="$BUFFER"
            export ZJ_WORDS="${(pj:\n:)_ze_words}"
            export ZJ_POSITIONS="${(pj:\n:)_ze_positions}"
            export ZJ_CURSOR="$CURSOR"
            export ZJ_PICKER="${Zledit[picker]}"
            "$script" "$token" "$token_idx" 2>"$stderr_file" 3>&3
        )
        exec 3>&-
    }
    local exit_code=$?
    local stderr_out=$(<"$stderr_file"); rm -f "$stderr_file"
    local meta_out=$(<"$meta_file"); rm -f "$meta_file"

    # Parse fd 3 metadata if present
    local meta_mode="" meta_cursor="" meta_pushline="" meta_message="" meta_prefix=""
    if [[ -n "$meta_out" ]]; then
        local line
        while IFS= read -r line; do
            case "$line" in
                mode:*)     meta_mode="${line#mode:}" ;;
                cursor:*)   meta_cursor="${line#cursor:}" ;;
                pushline:*) meta_pushline="${line#pushline:}" ;;
                message:*)  meta_message="${line#message:}" ;;
                prefix:*)   meta_prefix="${line#prefix:}" ;;
            esac
        done <<< "$meta_out"
    fi

    # Use fd 3 metadata if mode is set, otherwise fall back to exit codes
    if [[ -n "$meta_mode" ]]; then
        case "$meta_mode" in
            replace)
                if [[ -n "$result" ]]; then
                    BUFFER="${result%$'\n'}"
                    if [[ -n "$meta_cursor" ]]; then
                        CURSOR="$meta_cursor"
                    else
                        CURSOR="${_ze_positions[$token_idx]}"
                    fi
                fi
                ;;
            display)
                if [[ -n "$result" ]]; then
                    print
                    print -r -- "$result"
                    print
                fi
                ;;
            pushline)
                BUFFER="${result%$'\n'}"
                CURSOR="${_ze_positions[$token_idx]}"
                zle push-line
                BUFFER="$meta_pushline"
                CURSOR="${meta_cursor:-${#BUFFER}}"
                ;;
            pushline-exec)
                BUFFER="${result%$'\n'}"
                zle push-line
                BUFFER="$meta_pushline"
                zle accept-line
                ;;
            error)
                zle -M "zledit: ${meta_message:-action failed}"
                return 1
                ;;
            deferred)
                typeset -g _ze_deferred=1
                typeset -g _ze_deferred_prefix="$meta_prefix"
                return 0
                ;;
        esac
        return 0
    fi

    # Legacy: fall back to exit code behavior
    case $exit_code in
        0)  # Apply stdout as new buffer (CURSOR:N overrides, else token position)
            if [[ -n "$result" ]]; then
                local last_line="${result##*$'\n'}"
                if [[ "$last_line" =~ ^CURSOR:([0-9]+)$ ]]; then
                    BUFFER="${result%$'\n'*}"
                    CURSOR="${match[1]}"
                else
                    BUFFER="${result%$'\n'}"  # Strip trailing newline
                    CURSOR="${_ze_positions[$token_idx]}"  # Default to token position
                fi
            fi
            ;;
        1)  # Error
            [[ -n "$stderr_out" ]] && zle -M "zledit: action failed: $stderr_out"
            return 1
            ;;
        2)  # Display mode - show output in terminal
            if [[ -n "$result" ]]; then
                print
                print -r -- "$result"
                print
            fi
            ;;
        3)  # Push-line mode - for variable extraction
            if [[ "$result" == *"---ZJ_PUSHLINE---"* ]]; then
                local new_buffer="${result%%---ZJ_PUSHLINE---*}"
                local pushed_line="${result#*---ZJ_PUSHLINE---}"
                new_buffer="${new_buffer%$'\n'}"
                pushed_line="${pushed_line#$'\n'}"
                BUFFER="$new_buffer"
                CURSOR="${_ze_positions[$token_idx]}"
                zle push-line
                # Check for CURSOR:N in pushed_line
                local last_line="${pushed_line##*$'\n'}"
                if [[ "$last_line" =~ ^CURSOR:([0-9]+)$ ]]; then
                    BUFFER="${pushed_line%$'\n'*}"
                    CURSOR="${match[1]}"
                else
                    BUFFER="$pushed_line"
                    CURSOR=${#BUFFER}
                fi
            fi
            ;;
        4)  # Push-line + auto-execute
            if [[ "$result" == *"---ZJ_PUSHLINE---"* ]]; then
                local new_buffer="${result%%---ZJ_PUSHLINE---*}"
                local pushed_line="${result#*---ZJ_PUSHLINE---}"
                new_buffer="${new_buffer%$'\n'}"
                pushed_line="${pushed_line#$'\n'}"
                BUFFER="$new_buffer"
                zle push-line
                BUFFER="$pushed_line"
                zle accept-line
            fi
            ;;
    esac
}

zle -N zledit-widget

# ------------------------------------------------------------------------------
# Keybindings
# ------------------------------------------------------------------------------

zledit-setup-bindings() {
    emulate -L zsh

    if zstyle -t ':zledit:' disable-bindings; then
        return 0
    fi

    local key
    zstyle -s ':zledit:' binding key || key='^[/'  # Alt+/ (fzf uses Alt+C pattern)
    bindkey "$key" zledit-widget
}

# Bind once at load (covers non-interactive shells / scripted reloads),
# then re-assert via a one-time precmd hook so we win against compinit and
# other plugins (e.g. zsh-syntax-highlighting) that may overwrite the binding later.
zledit-setup-bindings

_zledit_deferred_setup() {
    emulate -L zsh
    (( $+functions[zledit-setup-bindings] )) && zledit-setup-bindings
}
autoload -Uz add-zsh-hook
add-zsh-hook precmd _zledit_deferred_setup

# ------------------------------------------------------------------------------
# List registered actions/previewers
# ------------------------------------------------------------------------------

zledit-list() {
    emulate -L zsh
    local i val
    print "Config:"
    print "  plugin:  ${Zledit[dir]}"
    zstyle -s ':zledit:' config val && print "  config:  $val"
    print "  picker:  ${Zledit[picker]}"
    print "  binding: $(bindkey | grep zledit-widget | awk '{print $1}')"
    print "\nActions:"
    for i in {1..${#_ze_action_bindings[@]}}; do
        printf "  %-10s %-10s %s\n" "${_ze_action_bindings[$i]}" "${_ze_action_descriptions[$i]}" "${_ze_action_scripts[$i]}"
    done
    print "\nPreviewers:"
    for i in {1..${#_ze_previewer_patterns[@]}}; do
        printf "  %-12s %s\n" "${_ze_previewer_descriptions[$i]}" "${_ze_previewer_scripts[$i]}"
    done
}

# ------------------------------------------------------------------------------
# Unload (for plugin managers like zinit)
# ------------------------------------------------------------------------------

zledit-unload() {
    emulate -L zsh

    zle -D zledit-widget 2>/dev/null

    add-zsh-hook -d precmd _zledit_deferred_setup

    unfunction zledit-widget _zledit_load_config \
               _zledit_load_default_actions _zledit_deferred_setup \
               _zledit_invoke_picker _zledit_tokenize \
               _zledit_is_balanced _zledit_find_composite_spans \
               _zledit_supports_binds _zledit_do_jump \
               _zledit_do_custom_action \
               _zledit_adapter_fzf _zledit_adapter_fzf-tmux \
               _zledit_adapter_sk _zledit_adapter_peco \
               _zledit_adapter_percol _zledit_adapter_fzflike \
               _zledit_adapter_simple _zledit_extract_index \
               _zledit_build_overlay _zledit_hint_to_index \
               _zledit_highlight_hints _zledit_build_preview_cmd \
               _zledit_parse_toml _zledit_save_toml_item \
               _zledit_token_counts _zledit_batch_replace \
               _zledit_binding_to_byte _zledit_find_action_by_key \
               zledit-setup-bindings zledit-list zledit-unload 2>/dev/null

    unset '_ze_words' '_ze_positions' '_ze_is_composite' \
          '_ze_composite_symmetric' '_ze_composite_opens' '_ze_composite_closes' \
          '_ze_result_key' '_ze_result_selection' \
          '_ze_invoke_prompt' '_ze_invoke_header' '_ze_invoke_binds' \
          '_ze_invoke_preview_args' '_ze_hint_keys' \
          '_ze_previewer_patterns' '_ze_previewer_descriptions' '_ze_previewer_scripts' \
          '_ze_action_bindings' '_ze_action_descriptions' '_ze_action_scripts' \
          '_ze_token_counts' '_ze_single_mode' '_ze_deferred' '_ze_deferred_prefix'
    unset Zledit

    return 0
}

# Register unload hook if zinit supports it
if (( $+functions[@zsh-plugin-run-on-unload] )); then
    @zsh-plugin-run-on-unload 'zledit-unload'
fi

return 0
