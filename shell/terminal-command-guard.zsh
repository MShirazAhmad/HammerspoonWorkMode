# Source this file from ~/.zshrc to gate Terminal commands during Hammerspoon
# BLOCK mode. Hammerspoon answers prompts through hammerspoon://terminal-check-prompt.

if [[ -o interactive ]]; then
  zmodload zsh/datetime 2>/dev/null || true

  typeset -gr _research_geofence_state_file="${RESEARCH_GEOFENCE_STATE_FILE:-$HOME/.hammerspoon/manage-py-geofence.state}"
  typeset -gr _research_geofence_max_age_seconds="${RESEARCH_GEOFENCE_MAX_AGE_SECONDS:-180}"
  typeset -gr _research_messages_file="${RESEARCH_MESSAGES_FILE:-$HOME/.hammerspoon/config/messages.yaml}"
  typeset -gr _terminal_command_guard_state_file="${TERMINAL_COMMAND_GUARD_STATE_FILE:-$HOME/.hammerspoon/terminal-command-guard.state}"
  typeset -g _terminal_command_guard_reason=""
  typeset -gi _terminal_command_guard_remaining_seconds=0
  typeset -gi _terminal_command_guard_last_prompt_request=0
  typeset -gi _terminal_command_guard_needs_prompt=0

  _research_message() {
    local key="$1" fallback="$2" value=""

    if [[ -r "$_research_messages_file" ]]; then
      value="$(
        awk -v lookup="$key" '
          function trim(value) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            return value
          }
          function depth_of(indent) {
            return int(length(indent) / 2)
          }
          function dotted_key(depth, key,    out, i) {
            out = ""
            for (i = 0; i < depth; i++) {
              if (stack[i] == "") continue
              out = out == "" ? stack[i] : out "." stack[i]
            }
            return out == "" ? key : out "." key
          }
          function decode(value) {
            value = trim(value)
            if ((substr(value, 1, 1) == "\"" && substr(value, length(value), 1) == "\"") ||
                (substr(value, 1, 1) == "'"'"'" && substr(value, length(value), 1) == "'"'"'")) {
              value = substr(value, 2, length(value) - 2)
            }
            gsub(/\\n/, "\n", value)
            gsub(/\\"/, "\"", value)
            gsub(/\\'\''/, "'\''", value)
            return value
          }
          {
            line = $0
            sub(/[[:space:]]+#.*$/, "", line)
            idx = index(line, ":")
            if (idx < 1) next
            match(line, /^[[:space:]]*/)
            indent = substr(line, RSTART, RLENGTH)
            depth = depth_of(indent)
            key = trim(substr(line, 1, idx - 1))
            val = substr(line, idx + 1)
            sub(/^[[:space:]]*/, "", key)
            val = trim(val)
            if (val == "") {
              stack[depth] = key
              for (i = depth + 1; i < 20; i++) delete stack[i]
              next
            }
            full_key = dotted_key(depth, key)
            if (full_key != lookup && key != lookup) next
            print decode(val)
            exit
          }
        ' "$_research_messages_file"
      )"
    fi

    print -r -- "${value:-$fallback}"
  }

  _terminal_command_guard_format() {
    local template="$1" detail="$2" remaining="$3"
    template="${template//\{detail\}/$detail}"
    template="${template//\{remaining\}/$remaining}"
    print -r -- "$template"
  }

  _terminal_command_guard_osascript_string() {
    print -r -- "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
  }

  _research_geofence_is_relaxed() {
    local allow="" relaxed="" updated_at="" key value

    [[ -r "$_research_geofence_state_file" ]] || return 1

    while IFS='=' read -r key value; do
      case "$key" in
        allow) allow="$value" ;;
        relaxed) relaxed="$value" ;;
        updated_at) updated_at="$value" ;;
      esac
    done < "$_research_geofence_state_file"

    [[ "$relaxed" == "1" || "$allow" == "1" ]] || return 1
    [[ "$updated_at" == <-> ]] || return 1
    (( EPOCHSECONDS - updated_at <= _research_geofence_max_age_seconds )) || return 1
    return 0
  }

  _terminal_command_guard_request_prompt() {
    if (( EPOCHSECONDS - _terminal_command_guard_last_prompt_request < 2 )); then
      return
    fi
    _terminal_command_guard_last_prompt_request=$EPOCHSECONDS
    command open -g "hammerspoon://terminal-check-prompt" >/dev/null 2>&1 &!
  }

  _terminal_command_guard_is_blocked() {
    local mode="" until_epoch="" reason="" key value
    _terminal_command_guard_needs_prompt=0

    if [[ ! -r "$_terminal_command_guard_state_file" ]]; then
      if ! _research_geofence_is_relaxed; then
        _terminal_command_guard_reason="$(_research_message "shell.awaiting_confirmation" "shell.awaiting_confirmation")"
        _terminal_command_guard_remaining_seconds=0
        _terminal_command_guard_needs_prompt=1
        return 0
      fi
      return 1
    fi

    while IFS='=' read -r key value; do
      case "$key" in
        mode) mode="$value" ;;
        until_epoch) until_epoch="$value" ;;
        reason) reason="$value" ;;
      esac
    done < "$_terminal_command_guard_state_file"

    if [[ "$mode" == "block" && "$until_epoch" == <-> ]] && (( EPOCHSECONDS < until_epoch )); then
      _terminal_command_guard_reason="${reason:-$(_research_message "shell.blocked_default" "shell.blocked_default")}"
      _terminal_command_guard_remaining_seconds=$((until_epoch - EPOCHSECONDS))
      return 0
    fi

    if [[ "$mode" == "none" ]]; then
      _terminal_command_guard_reason="${reason:-$(_research_message "shell.decision_required" "shell.decision_required")}"
      _terminal_command_guard_remaining_seconds=0
      _terminal_command_guard_needs_prompt=1
      return 0
    fi

    if [[ "$mode" == "allow" && "$until_epoch" == <-> ]] && (( EPOCHSECONDS >= until_epoch )); then
      if _research_geofence_is_relaxed; then
        return 1
      fi
      _terminal_command_guard_reason="$(_research_message "shell.decision_expired" "shell.decision_expired")"
      _terminal_command_guard_remaining_seconds=0
      _terminal_command_guard_needs_prompt=1
      return 0
    fi

    if ! _research_geofence_is_relaxed && [[ "$mode" != "allow" ]]; then
      _terminal_command_guard_reason="$(_research_message "shell.decision_required" "shell.decision_required")"
      _terminal_command_guard_remaining_seconds=0
      _terminal_command_guard_needs_prompt=1
      return 0
    fi

    return 1
  }

  _terminal_command_guard_remaining_label() {
    local seconds=${_terminal_command_guard_remaining_seconds:-0}
    (( seconds < 0 )) && seconds=0
    printf '%dm %02ds' $(( seconds / 60 )) $(( seconds % 60 ))
  }

  _terminal_command_guard_message() {
    local remaining detail title body escaped_title escaped_body
    remaining="$(_terminal_command_guard_remaining_label)"
    detail="${_terminal_command_guard_reason}"
    title="$(_research_message "shell.command_blocked.title" "shell.command_blocked.title")"
    body="$(_terminal_command_guard_format "$(_research_message "shell.command_blocked.detail" "{detail} {remaining}")" "$detail" "$remaining")"
    escaped_title="$(_terminal_command_guard_osascript_string "$title")"
    escaped_body="$(_terminal_command_guard_osascript_string "$body")"
    print -P -- "%F{red}${title}%f"
    print -P -- "%F{red}${body}%f"
    command osascript -e "display notification \"${escaped_body}\" with title \"${escaped_title}\"" >/dev/null 2>&1 &!
  }

  _terminal_command_guard_print_allow_status_if_active() {
    local mode="" until_epoch="" key value

    [[ -r "$_terminal_command_guard_state_file" ]] || return
    while IFS='=' read -r key value; do
      case "$key" in
        mode) mode="$value" ;;
        until_epoch) until_epoch="$value" ;;
      esac
    done < "$_terminal_command_guard_state_file"

    if [[ "$mode" == "allow" && "$until_epoch" == <-> ]] && (( EPOCHSECONDS < until_epoch )); then
      if _research_geofence_is_relaxed; then
        return
      fi
      _terminal_command_guard_remaining_seconds=$((until_epoch - EPOCHSECONDS))
      print -P -- "%F{cyan}$(_terminal_command_guard_format "$(_research_message "shell.allowed_status" "{remaining}")" "" "$(_terminal_command_guard_remaining_label)")%f"
      _terminal_command_guard_last_prompt_request=0
    fi
  }

  _terminal_command_guard_preexec() {
    local command_line="$1"
    [[ -n "${command_line//[[:space:]]/}" ]] || return
    _terminal_command_guard_print_allow_status_if_active
  }

  _terminal_command_guard_accept_line() {
    if [[ -n "${BUFFER//[[:space:]]/}" ]] && _terminal_command_guard_is_blocked; then
      if (( _terminal_command_guard_needs_prompt )); then
        _terminal_command_guard_request_prompt
      fi
      _terminal_command_guard_message
      zle reset-prompt
      return 0
    fi

    zle .accept-line
  }

  zle -N accept-line _terminal_command_guard_accept_line
  autoload -Uz add-zsh-hook
  add-zsh-hook preexec _terminal_command_guard_preexec
fi
