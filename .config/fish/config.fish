set fish_greeting

if status is-interactive
    function fish_prompt
        echo ""
        set_color green
        echo -n (whoami)
        set_color normal
        echo -n " in "
        set_color blue
        echo -n (string replace (string escape --style=regex $HOME) '~' $PWD)
        #echo -n (prompt_pwd)

        echo ""

        set_color white
        echo -n "> "
        set_color normal
    end

    function fish_right_prompt
        set_color grey
        date "+%H:%M:%S"
        set_color normal
    end

    function __fish_history_last_command
        echo $history[1]
    end

    function __fish_history_last_argument
        # last element
        string split -r -m 1 ' ' $history[1] | tail -n 1
    end

    function __fish_history_all_arguments
        # arguments
        string replace -r '^[^ ]+\s*' '' $history[1]
    end

    abbr -a !! --position anywhere --function __fish_history_last_command
    abbr -a '!$' --position anywhere --function __fish_history_last_argument
    abbr -a '!*' --position anywhere --function __fish_history_all_arguments

    alias ls='eza -a --color=always --group-directories-first --icons=always'  # preferred listing
    alias la='eza -la --color=always --group-directories-first --icons=always' # all files and dirs
    alias ll='eza -l --color=always --group-directories-first --icons=always'  # long format
    alias lt='eza -aT --color=always --group-directories-first --icons=always' # tree listing
    alias l.="eza -a | grep -e '^\.'"                                          # show only dotfiles
    alias find='fd'
    alias grep='ripgrep'
    alias cat='bat'
    alias df='duf'

    alias untar='tar -zxvf '
    alias wget='wget -c '

    alias jctl="journalctl -p 3 -xb" # get the error messages from journalctl

    alias unlock="sudo rm /var/lib/pacman/db.lck"

    alias cp='cp -iv'
    alias mv='mv -iv'

    alias ..='cd ..'
    alias ...='cd ../..'
    alias ....='cd ../../..'
    alias .....='cd ../../../..'
end
