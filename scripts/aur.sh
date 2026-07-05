aur() {
    #local tmpuser helper packages sudoersfile
    failed=() # failed is later overridden in aurupdate, do ssth

    # temp user, trap
    tmpuser="aurbuild-temporary-user"
    sudoersfile="/etc/sudoers.d/$tmpuser"
    sudo useradd -m "$tmpuser"
    sudo passwd -d "$tmpuser"
    echo "$tmpuser ALL=(ALL) NOPASSWD: /usr/bin/pacman*" | sudo tee "$sudoersfile"
    sudo chmod 0440 "$sudoersfile"  # Standard permissions for sudoers.d files

    # trap
    trapfunction() {
        sleep 2
        sudo pkill -TERM -u "$tmpuser" || true
        sleep 2
        sudo pkill -KILL -u "$tmpuser" || true

        sudo userdel -r "$tmpuser" || true
        sudo rm -f "$sudoersfile"
    }
    trap trapfunction EXIT SIGINT SIGTERM SIGHUP SIGQUIT SIGABRT SIGALRM


    # run command as the temp user, safe quoting with "$@"
    runastmp() { sudo -u "$tmpuser" -- "$@"; }

    # determine the aur helper, default to paru
    helper=$(command -v paru || command -v yay)
    if [[ -z "$helper" ]]; then
        echo "aur(): this script requires yay or paru"
        return 1
    fi

    helper=${helper##*/}

    packages=( $(runastmp "$helper" -Quq --aur) )

    if [ ${#packages[@]} -eq 0 ]; then
        echo "aurupdate(): nothing to update"
        return 0
    fi

    echo "aur(): using $helper, updating this many packages: ${#packages[@]}"

    aurupdate() {
        failed=()

        if runastmp "$helper" -Syu --aur --noconfirm; then
            echo "aurupdate(): AUR update completed"
            return 0
        fi

        for pkg in "${packages[@]}"; do
            if runastmp "$helper" -S --noconfirm "${pkg}"; then
                echo "aurupdate(): successfully installed ${pkg}"
            else
                echo "aurupdate(): failed to install ${pkg}"
                [[ " ${failed[*]} " =~ " $pkg " ]] || failed+=("$pkg")
            fi
        done

        if [ ${#failed[@]} -ne 0 ]; then
            return 1
        fi
        return 0
    }

    aurrecovery() {
        if ! internetconnection; then
            echo "aurrecovery(): no internet connection"
            return 1
        fi

        # some systems (e.g., firewalled networks) might block ICMP
        if ! ping -c 3 -W 10 -w 20 aur.archlinux.org && \
           ! curl -s --head https://aur.archlinux.org ; then
            echo "aurrecovery(): AUR is down"
            return 1
        fi

        if ! gpg --refresh-keys; then
            echo "aurrecovery(): failed to refresh GPG keys"
            return 1
        fi

        if aurupdate; then
            echo "aurrecovery(): AUR update completed after recovery"
            return 0
        fi

        echo "aurrecovery(): AUR update failed after recovery"
        return 1
    }

    if aurupdate || aurrecovery; then
        echo "all set."
        return 0
    else
        if [ ${#failed[@]} -eq ${#packages[@]} ]; then
            echo "all attempts to update AUR packages failed."
        else
            echo "failed to update ${#failed[@]} out of ${#packages[@]} outdated packages"
        fi
    fi
    echo "${failed[@]}"
}
