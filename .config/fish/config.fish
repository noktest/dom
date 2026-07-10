set fish_greeting

if status is-interactive
    fish_vi_key_bindings 
    set -g fish_cursor_default underscore      
    set -g fish_cursor_insert underscore blink      
    set -g fish_cursor_replace_one block 
    set -g fish_cursor_visual block      

    # stop rendering vi mode prompt
    function fish_mode_prompt; end
    # writing my own prompt
    function fish_prompt
        echo ""
        switch $fish_bind_mode
            case default
                set_color --bold red; echo -n "[N] "
            case insert
                set_color --bold green; echo -n "[I] "
            case replace_one
                set_color --bold cyan; echo -n "[R] "
            case visual
                set_color --bold magenta; echo -n "[V] "
        end
        set_color normal

        set_color green
        echo -n (whoami)
        set_color normal
        echo -n " in "
        set_color blue
        echo -n (string replace (string escape --style=regex $HOME) '~' $PWD)

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
        string split -r -m 1 ' ' $history[1] | tail -n 1
    end

    function __fish_history_all_arguments
        string replace -r '^[^ ]+\s*' '' $history[1]
    end

    abbr -a !! --position anywhere --function __fish_history_last_command
    abbr -a '!$' --position anywhere --function __fish_history_last_argument
    abbr -a '!*' --position anywhere --function __fish_history_all_arguments

    alias ..='cd ..'
    alias ...='cd ../..'
    alias ....='cd ../../..'
    alias .....='cd ../../../..'

    alias ls='eza -a --color=always --group-directories-first --icons=always'
    alias la='eza -la --color=always --group-directories-first --icons=always'
    alias ll='eza -l --color=always --group-directories-first --icons=always'
    alias lt='eza -aT --color=always --group-directories-first --icons=always'
    alias l.="eza -a | grep -e '^\.'"
    alias find='fd'
    alias grep='ripgrep'
    alias cat='bat'
    alias df='duf'

    alias untar='tar -zxvf '
    alias wget='wget -c '
    alias cp='cp -ivr'
    alias mv='mv -ivr' 

    alias jctl="journalctl -p 3 -xb"
    
    abbr rebuild "sudo nixos-rebuild switch"
    abbr config "sudo nvim /etc/nixos/configuration.nix"
end
