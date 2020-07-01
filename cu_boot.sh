#!/bin/busybox sh
# TODO
# remove ramdisk part from mount_dev
# unused if at the end of set_variables ?
# add cryptsetup check in key generation
# failed kernel config should clean up!
#btus
# ADD BTUSB
# Add Hidraw
# , kernel driver, bluez deprecated and pulseaudio flag
# ###
#
# Configurable settings can be found in "set_variables" function.
#fbtus
# Messages:
# blue - verbose
# light_blue - regular
# red - error
# white - requires user action
# yellow - warning, also requiring user attention
#
# Functions:
# eg. - example
# (value1|value2) - value must be either value1 or value2
#
# build_kernel
#   action:
#       builds a bzImage
#   arguments:
#       architecture (arm|x86_64)
#   usage:
#       build_kernel "arm"
#
# cecho
#   action:
#       echoes out a given string in color
#   arguments:
#       string
#       color (blue|-blue|default|-default|green|-green|light_blue|-light_blue|red|-red|yellow|-yellow)
#           -: no new line
#   usage:
#       cecho "Command has failed!" "red"
#
# check_for_program
#   action:
#       checks for a program, exits if not found
#   arguments:
#       program with options, must return 0
#   usage:
#       check_for_program "dd --help"
#
# check_if_argument_empty
#   action:
#       checks given variables, exits if is empty
#   arguments:
#       a list of variables to be chcecked
#   usage:
#       check_if_argument_empty "$color" "$message"
#
# get_dev_geometry
#   action:
#       obtains block device geometry
#   arguments:
#       a list of block devices
#   exports:
#       detected geometry for each device given:
#           block_count_$(basename $argument)
#           block_size_$(basename $device) (512|2048|4096)
#   usage:
#       get_dev_geometry "/dev/sda" "/dev/$device"
#
# run_command - executes a command if a given condition is true
#   arguments:
#       command
#       condition to check before command execution (eg. [ -n "${variable:-}" ])
#       error_message shown when $? ~= 0
#       message shown when $? = 0
#       permissible, do not fail when codition not true (do_not_fail_on_condition|fail_on_condition)
#       resource to clean on script exit (device/mountpoint/process)
#
# ###

function back_up_root {
    local backup_dir="$(echo $backup_lv | sed s:/:-:)"
    local root_dir="$(echo $root_lv | sed s:/:-:)"
    check_lvm "no" "$backup_lv"
    mount_dev "/dev/mapper/$backup_dir"
    
    cecho "default" "Please enter the backup file name, extension(.tar.bz2) and date(MMDDYY format) will be added automatically."
    local name
    read name
    rm /mnt/"$root_dir"/back_up
    cecho "blue" "Compressing..."
    if [ -x /bin/tar -a -x /usr/bin/pigz ]; then
        cecho "red" "using parallel"
        time /bin/tar c -f /mnt/"$backup_dir"/${name}.tar.gz -C /mnt/"$root_dir" -I pigz --exclude ./dev --exclude ./lost+found --exclude ./media --exclude ./proc --exclude ./run --exclude ./sys --exclude ./tmp --exclude ./var/tmp .
    else
        time tar c -f /mnt/"$backup_dir"/${name}.tar.bz2 -C /mnt/"$root_dir" -j --exclude ./dev --exclude ./lost+found --exclude ./media --exclude ./proc --exclude ./run --exclude ./sys --exclude ./tmp --exclude ./var/tmp .
    fi

}

function build_kernel {
    check_number_of_arguments "build_kernel" "$#" "1"
    local arch="${1:-}"
    verbose "blue" "function build_kernel [architecture: $arch]"
    check_if_argument_empty "$arch"
    if [ "$arch" == "x86_64" -o "$arch" == "mvebu_v5" ]; then
        local config="${arch}_defconfig"
    else
        cecho "red" "Not supported architecture set in arch variable[$arch] passed to build_kernel function. Please set to x86_64|mvebu_v5 and try again, exiting!"
        exit_error
    fi
    
    local cores_num="$(cat /proc/cpuinfo | grep processor | wc -l)"
    
    if [ ! -d /usr/src/linux-$arch ]; then
        prep_kernel_sources "$arch"
    fi

    cecho "-light_blue" "Configuring the kernel [$arch]..."
    run_command "make -C /usr/src/linux-$arch $config 1>&3 2>&4" "[ -d /usr/src/linux-$arch ]" "" "" "fail_on_condition" ""
    cecho "green" "OK"
        
    create_initramfs "$arch"

    cecho "-light_blue" "Building $arch kernel version $(cat /usr/src/linux-$arch/include/config/kernel.release)..."
    run_command "make -C /usr/src/linux-$arch -j$cores_num olddefconfig 1>&3 2>&4" "[ -d /usr/src/linux-$arch ]" "" "" "fail_on_condition" ""
    run_command "make -C /usr/src/linux-$arch -j$cores_num modules 1>&3 2>&4" "[ -d /usr/src/linux-$arch ]" "" "" "fail_on_condition" ""
    	mkdir -p  $initramfs_dir/lib/modules
    	cp -r /lib/modules/$(cat /usr/src/linux-$arch/include/config/kernel.release) "$initramfs_dir"/lib/modules/
    run_command "make -C /usr/src/linux-$arch -j$cores_num bzImage 1>&3 2>&4" "[ -d /usr/src/linux-$arch ]" "" "" "fail_on_condition" ""
    cecho "green" "OK"

    cecho "-light_blue" "Installing the kernel [$arch]..."
	
    get_dev_name "$serial_boot"
    if eval [ -z "\${dev_$serial_boot:-}" ]; then
        run_command "cp /usr/src/linux-$arch/arch/$arch/boot/bzImage $(pwd)/kernel+initramfs" "[ -f /usr/src/linux-$arch/arch/$arch/boot/bzImage ]" "Copying the bzImage to $(pwd)" "Failed to copy /usr/src/linux-$arch/arch/$arch/boot/bzImage to $(pwd)" "fail_on_condition" ""
    else
        run_command "make -C /usr/src/linux-$arch install 1>&3 2>&4" "[ -d /usr/src/linux-$arch ]" "" "" "fail_on_condition" ""
        run_command "make -C /usr/src/linux-$arch modules_install 1>&3 2>&4" "[ -d /usr/src/linux-$arch ]" "" "" "fail_on_condition" ""
    fi
    cecho "green" "OK"
}

# checked
function cecho {
    if [ "$#" == "2" ]; then
        local color="${1:-}"
        local message="${2:-}"

        local blue="\e[034m"
        local default="\e[0m"
        local green="\e[032m"
        local light_blue="\e[094m"
        local red="\e[031m"
        local yellow="\e[033m"

        if [ -n "$message" ]; then
            if [ "$color" == "-blue" -o "$color" == "-green" -o "$color" == "-light_blue" -o "$color" == "-red" -o "$color" == "-yellow" ]; then
                eval "echo -e -n \$${color#-}\$message\$default"
            elif [ "$color" == "blue" -o "$color" == "green" -o "$color" == "light_blue" -o "$color" == "red" -o "$color" == "yellow" ]; then
                eval "echo -e \$$color\$message\$default"
            elif [ "$color" == "default" ]; then
                eval "echo -e \$message"
            else
                cecho "red" "Please set the \"color\" argument for \"cecho\" function properly and try again, exiting!"
                exit_error
            fi
        else
            cecho "red" "Please set the \"message\" argument for \"cecho\" function properly and try again, exiting!"
            exit_error
        fi
    else
        cecho "red" "[ $# != 2 ]\nPlease set the arguments for \"cecho\" function properly and try again, exiting!"
        exit_error
    fi
}

function check_if_device_with_serial_exists {
        check_number_of_arguments "check_if_device_with_serial_exists" "$#" "1"
        local serial="${1:-}"
        verbose "blue" "function check_if_device_with_serial_exists[serial: $serial]"
        
        if eval [ ! -b $(eval echo \${dev_$serial:-}) ]; then
            get_dev_name "$serial"
        fi
        
        until get_dev_name "$serial"; [ -b $(eval echo \${dev_$serial:-}) ]; do
            cecho "yellow" "\nDevice with serial $serial not found, please make sure it is plugged in and the serial/uuid is set correctly, then press any key"
            read
        done
}

function check_number_of_arguments {
    local function_name="${1:-}"
    local number_of_arguments="${2:-}"
    local number_of_arguments_expected="${3:-}"
    check_if_argument_empty "$function_name" "$number_of_arguments" "$number_of_arguments_expected"
    verbose "blue" "function check_number_of_arguments [ function_name: $function_name, number_of_arguments: $number_of_arguments, number_of_arguments_expected: $number_of_arguments_expected]"
    if [ "$number_of_arguments" != "$number_of_arguments_expected" ]; then
        cecho "red" "Number of arguments given[$number_of_arguments] doesn't equal number_of_arguments_expected[$number_of_arguments_expected], please set the arguments for \"$function_name\" function properly and try again, exiting!"
        exit_error
    fi
}

# checked
function check_for_program {
    check_number_of_arguments "check_for_program" "$#" "1"
    local command="${1:-}"
    local program=$(echo $command | cut -f1 -d " ")
    check_if_argument_empty "command" "program"
    verbose "blue" "function check_for_program [command: $command, program: $program]"

    if ! ($command 1>&3 2>&4); then
        cecho "red" "Please install $program and try again, exiting!"
        exit_error
    fi
}

# checked
function check_if_argument_empty {
    local args="${@:-}"
    verbose "blue" "function check_if_argument_empty [args: $args]"

    if [ -n "$args" ]; then
        local arg
        for arg in "$args"; do
            if [ -z "$arg" ]; then
                cecho "red" "[ ! -n $arg ]\nEmpty argument detected by  \"check_if_argument_empty\" function. Please set the arguments for the preceeding function correctly and try again, exiting!"
                exit_error
            fi
        done
    else
        cecho "red" "[ ! -n $args ]\nNo arguments passed to  \"check_if_argument_empty\" function. Please set the arguments for the preceeding function correctly and try again, exiting!"
        exit_error
    fi
}

function check_install_options {
    local memory=$(free -g | head -n2 | tail -n1 | awk '{ print $4 }')
    if [ "$memory" -lt "$((${root_size%G} + 1))" -a ! -b "/dev/mapper/$serial_root" ]; then
        cecho "red" "Less than ${root_size%G} + 1 GB of memory available and /dev/mapper/$serial_root not found, no install options available, exiting!"
        exit_error
    elif [ "$memory" -lt "$((${root_size%G} + 1))" -a -b "/dev/mapper/$serial_root" ]; then
        cecho "default" "Less than ${root_size%G} + 1 GB of memory available, installing on /dev/mapper/$serial_root is the only option."
        check_lvm "yes" "$root_lv"
    elif [ "$memory" -ge "$((${root_size%G} + 1))" -a ! -b "/dev/mapper/$serial_root" ]; then
        cecho "default" "More than ${root_size%G} + 1 GB of memory available and /dev/mapper/$serial_root not present, installing in RAMdisk is the only option."
        mount_ramdisk "/mnt/laptop-root" "$root_size"
        install_os "/mnt/laptop-root"
    elif [ "$memory" -ge "$((${root_size%G} + 1))" -a -b "/dev/mapper/$serial_root" ]; then
        cecho "default" "More than ${root_size%G} + 1 GB of memory available and /dev/mapper/$serial_root present. Would you like to install in RAM(d)isk or (r)ecreate LVM label/VG/LV on /dev/mapper/$serial_root and then do it?[d/r]"
        local answer
        read answer
        while [ "$answer" != "d" -a "$answer" != "r" ]; do
            cecho "yellow" "Please enter a correct answer![RAM(d)isk/(r)ecreate]"
            read answer
        done
        if [ "$answer" == "d" ]; then
            mount_ramdisk "/mnt/laptop-root" "$root_size"
            install_os "/mnt/laptop-root"
        elif [ "$answer" == "r" ]; then
            check_lvm "yes" "$root_lv"
        fi
    fi
}

function check_lvm {
    local recreate="${1:-}"
    local vg_lv="${2:-}"
    verbose "blue" "function check_lvm [recreate: $recreate, VG/LV: $vg_lv]"

    local vg=${vg_lv%/*}
    local lv=${vg_lv#*/}
    check_if_argument_empty "$lv" "$recreate" "$vg" "$vg_lv"

    check_for_program "lvm help"

    cecho "-light_blue" "Checking for /dev/mapper/$serial_root..."
    if [ -b "/dev/mapper/$serial_root" ]; then   
        cecho "green" "OK"
        cecho "-light_blue" "Checking for LVM label on /dev/mapper/$serial_root..."
        if (lvm pvck /dev/mapper/"$serial_root" 1>&3 2>&4); then
            cecho "green" "OK"
            cecho "-light_blue" "Checking for $vg VG..."
            if (lvm vgck "$vg" 1>&3 2>&4); then
                cecho "green" "OK"
                cecho "-light_blue" "Checking for $lv LVs..."
                if (lvm lvs $vg_lv 1>&3 2>&4); then
                    cecho "green" "OK"
                    cecho "-light_blue" "Checking if $vg_lv Logical Volume is active..."
                    if [ -b /dev/$vg_lv ]; then
                        cecho "green" "OK"
                    else
                        cecho "-light_blue" "activating..."
                        if DM_DISABLE_UDEV=1 lvm lvchange -ay $vg_lv 1>&3 2>&4; then
                            cecho "green" "OK"
                        else
                            cecho "red" "FAILED!"
                            check_install_options
                        fi
                    fi
                else
                    cecho "red" "NOT_FOUND!"
                    cecho "default" "$lv LV has not been found in $vg VG, would you like to recreate?[no/yes]"
                    get_answer
                    if [ "$answer" == "yes" ]; then
                        cecho "-light_blue" "Creating $vg_lv..."
                        if [ "$lv" == "backup" ]; then
                            run_command "lvm lvcreate -l$backup_size -n $lv $vg 1>&3 2>&4" "" "Creating $vg_lv" "Failed to create $vg_lv" "do_not_fail_on_condition" ""
                        elif [ "$lv" == "root" ]; then
                            run_command "lvm lvcreate -L$root_size -n $lv $vg 1>&3 2>&4" "" "Creating $vg_lv" "Failed to create $vg_lv" "do_not_fail_on_condition" ""
                        fi
                        cecho "green" "OK"
                    else
                        check_install_options
                    fi
                fi
            else
                cecho "red" "NOT_FOUND!"
                if [ "$recreate" != "yes" ]; then
                    check_install_options
                else
                    cecho "default" "$vg VG has not been found, would you like to create it?[no/yes]"
                    get_answer
                    if [ "$answer" == "yes" ]; then
                        cecho "-light_blue" "Creating $vg VG on /dev/mapper/$serial_root..."
                        run_command "lvm vgcreate $vg /dev/mapper/$serial_root 1>&3 2>&4" "" "Creating $vg VG on /dev/mapper/$serial_root" "Failed to create $vg VG on /dev/mapper/$serial_root" "fail_on_condition" ""
                        cecho "green" "OK"
                        check_lvm "$@"
                    else
                        check_install_options
                    fi
                fi
            fi
        else
            cecho "red" "NOT_FOUND!"
            if [ "$recreate" != "yes" ]; then
                check_install_options
            else
                cecho "default" "LVM label not found on /dev/mapper/$serial_root, would you like to recreate it?[no/yes]"
                get_answer
                if [ "$answer" == "yes" ]; then
                    if [ "$hardened" == "yes" ]; then
                        erase_dev "/dev/mapper/$serial_root"
                    fi
                    cecho "-light_blue" "Creating LVM label on /dev/mapper/$serial_root..."
                    run_command "lvm pvcreate /dev/mapper/$serial_root 1>&3 2>&4" "" "Creating LVM label on /dev/mapper/$serial_root" "Failed to create LVM label on /dev/mapper/$serial_root" "do_not_fail_on_condition" ""
                    cecho "green" "OK"
                    check_lvm "$@"
                else
                    check_install_options
                fi
            fi
        fi
    else
        cecho "red" "NOT_FOUND!"
        check_install_options
    fi
        
}

function check_status {
    local status="$?"
    check_number_of_arguments "check_status" "$#" "2"
    local error_message="${1:-}"
    local resource="${2:-}"
    verbose "blue" "function check_status [resource: $resource, status: $status]"

    if [ "$status" == "0" ]; then
        verbose "green" "OK"
        if [ -n "$resource" ]; then
            verbose "blue" "Adding $resource to the clean_up list"
            resources_to_clean=$(echo "$resource ${resources_to_clean:-}")
        fi
    else
        if [ -z "$error_message" ]; then
            cecho "red" "Failed, exiting!"
        else
            cecho "red" "$error_message"
        fi
        exit 0
    fi
}

# checking
function clean_up {
    verbose "blue" "function clean_up"

    until [ -z $(echo ${resources_to_clean:-} | tr -d " ") ]; do
        verbose "blue" "Resources to clean: ${resources_to_clean:-}"
        for resource in ${resources_to_clean:-}; do
            if (mountpoint "$resource" 1>&3 2>&3); then
                if [ "$resource" != "/mnt/laptop-root" ] && [ "$resource" != "/mnt/livedvd" ]; then
                    verbose "-blue" "[umount $resource]"
                    umount "$resource"
                    resources_to_clean=$(echo "${resources_to_clean:-}" | sed s:"$resource::")
                else
                    resources_to_clean=$(echo "${resources_to_clean:-}" | sed s:"$resource::")
                fi
            elif [ -d "$resource" ]; then
                #if [ "$resource" != "/boot" ]; then
                verbose "-blue" "[rmdir $resource]"
                if [ "$resource" == "/mnt/$serial_keys" ]; then                
                    rm -rf "$resource"
                else
                    rmdir "$resource"
                fi
                    check_status "" ""
                    resources_to_clean=$(echo "${resources_to_clean:-}" | sed s:"$resource::")
                #fi
            elif (cryptsetup status /dev/mapper/$(basename "$resource") 1>&3 2>&4); then
                if [ "$resource" == "/dev/mapper/${serial_root:-}" ]; then
                    resources_to_clean=$(echo "${resources_to_clean:-}" | sed s:"$resource::")
                else
		    verbose "-blue" "cryptsetup close $resource"
                    cryptsetup close /dev/mapper/$(basename "$resource")
                    check_status "" ""
                    resources_to_clean=$(echo "${resources_to_clean:-}" | sed s:"$resource::")
                fi
            elif [ $(ps aux | grep $resource | wc -l) -ge "2" ]; then
                verbose "-blue" "killing $resource"
                killall $resource
                check_status "" ""
                while [ $(ps aux | grep $resource | wc -l) -ge "2" ]; do
                    verbose "blue" "Waiting for $resource process to die..."
                    sleep 1
                done
                resources_to_clean=$(echo "${resources_to_clean:-}" | sed s:"$resource::")
            elif [ -n "$(ifconfig | grep $resource)" ]; then
                run_command "ifconfig $resource down" "" "" "Bringing $resource down" "fail_on_condition" ""
                resources_to_clean=$(echo "${resources_to_clean:-}" | sed s:"$resource::")                
            else
                verbose "red" "Cleaning up $resource has failed!"
            fi
        done
    done
}

# checked
function configure_terminal {
    verbose "blue" "function configure_terminal"
    cecho "-light_blue" "Configuring terminal..."

    if [ "$verbose" == "yes" ]; then
        exec 3>/dev/null
        if [ "$debug" == "yes" ]; then
            exec 4>&2
        elif [ "$debug" == "no" ]; then
            exec 4>/dev/null
        else
            cecho "red" "Please set \"debug\" global variable in \"set_variables\" function and try again, exiting!"
            exit_error
        fi
    elif [ "$verbose" == "no" ]; then
        exec 3>/dev/null 4>/dev/null
    else
        cecho "red" "[ $verbose != no -a $verbose != yes ]\nPlease set the \"verbose\" global variable in the \"set_variables\" function properly and try again, exiting!"
        exit_error
    fi

    run_command "set -o errexit" "" "" "Setting -o errorexit" "fail_on_condition" ""
    run_command "set -o noglob" "" "" "Setting -o noglob" "fail_on_condition" ""
    run_command "set -o nounset" "" "" "Setting -o nonset" "fail_on_condition" ""
    run_command "set -o pipefail" "" "" "Setting -o pipefail" "fail_on_condition" ""

    # # #
    # Supported only by bash!
    # # #
    # if [ "$debug" == "yes" ]; then
    #     run_command "set -o verbose" "" "" "Setting -o verbose" "fail_on_condition" ""
    #     exec 3>&1
    # elif [ "$debug" != "no" -a "$debug" != "yes" ]; then
    #     cecho "red" "[ $debug != no -a $debug != yes ]\nPlease set the \"debug\" global variable properly and try again, exiting!"
    #     exit_error
    # fi
    # # #
    
    trap exit_trap EXIT
    
    cecho "green" "OK"
}

function copy_executable {
    check_number_of_arguments "copy_executable" "$#" "2"
    local destination="${1:-}"
    local executable="${2:-}"
    check_if_argument_empty "$destination" "$executable"

    check_for_program "which which"
    local location=$(which $executable)
    
    verbose "blue" "function copy_executable [destination: $destination, executable: $executable]"
    
    if [ -x "$location" ]; then
        if (ldd $location 1>&3 2>&4); then
            verbose "blue" "$location is a dynamic executable, additional files will be copied"
            check_for_program "ldd --version"
            for file in $(lddtree -l $location); do
                run_command "mkdir -p $destination${file%/*}" "[ ! -d $destination${file%/*} ]" "" "Creating $destination${file%/*} directory" "do_not_fail_on_condition" ""
                cp $file $destination$file
            done
        else
            verbose "-blue" "Copying $location to $destination$location"
            run_command "mkdir -p $destination${location%/*}" "[ ! -d $destination${location%/*} ]" "" "Creating $destination${location%/*} directory" "do_not_fail_on_condition" ""
            cp $location $destination$location
        fi
    fi
}

function copy_executables {
    check_number_of_arguments "copy_executables" "$#" "2"
    local destination="${1:-}"
    local executables="${2:-}"
    check_if_argument_empty "$destination" "$executables"

    verbose "blue" "function copy_executable [destination: $destination, executable: $executables]"

    for executable in $executables; do
        copy_executable "$destination" "$executable"
    done
}

function create_dirs {
    destination="${1:-}"
    dirs="${2:-}"
    verbose "blue" "function create_dirs [destination: $destination, dirs: $dirs]"
    check_if_argument_empty "$destination" "$dirs"
    
    for directory in $dirs; do
        if [ -d "$destination/$directory" ]; then
            verbose "blue" "Directory $destination/$directory already exists, skipping"
        else
            verbose "-blue" "Creating directory $destination/$directory"
            mkdir -p "$destination"/"$directory"
            check_status "" ""
        fi
    done
}

function create_initramfs {
    check_number_of_arguments "create_initramfs" "$#" "1"
    local arch="${1:-}"
    verbose "blue" "function create_initramfs [arch: $arch]"
    check_if_argument_empty "$arch"

    initramfs_dir="/usr/src/linux-$arch/initramfs"

    local kernel_config="CONFIG_INITRAMFS_SOURCE=\"/usr/src/linux-$arch/initramfs\"\n\
CONFIG_INITRAMFS_ROOT_UID=0\n\
CONFIG_INITRAMFS_ROOT_GID=0\n\
CONFIG_INPUT_TOUCHSCREEN=n"

    local initramfs_dirs="dev etc home mnt opt $(if [ -n "$initramfs_keys" ]; then echo "$keys_dir"; fi) proc sys"
    local initramfs_files="busybox \
                           dd \
                           mkfs.ext4 \
                           sg_vpd"
    
    if [ "$initramfs_dns" == "yes" ]; then
        local initramfs_files="$initramfs_files \
                                /etc/host.conf \
                                /etc/hosts \
                                /etc/ld.so.cache \
                                /etc/nsswitch.conf \
                                /etc/resolv.conf \
                                /lib64/libnss_dns.so.2 \
                                /lib64/libnss_files.so.2 \
                                /usr/share/udhcpc/default.script"
    fi
    
    if [ "$initramfs_wireless" == "yes" ]; then
        local initramfs_files="$initramfs_files \
                                /etc/wpa_supplicant/wpa_supplicant.conf \
                                /lib/firmware/ath9k_htc \
                                /lib/firmware/ath9k_htc/htc_7010-1.4.0.fw \
                                /lib/firmware/ath9k_htc/htc_9271-1.4.0.fw \
                                /lib/firmware/iwlwifi-6000g2a-5.ucode \
                                /lib/firmware/mt7601u.bin \
                                /usr/sbin/wpa_supplicant"

        local kernel_config="$kernel_config\n\
CONFIG_ATH9K_BTCOEX_SUPPORT=n\n\
CONFIG_ATH9K_HTC=y\n\
CONFIG_ATH9K_HTC_DEBUGFS=n\n\
CONFIG_IWLWIFI=y\n\
CONFIG_IWLDVM=y\n\
CONFIG_IWLMVM=n\n\
CONFIG_IWLWIFI_DEBUG=n\n\
CONFIG_IWLWIFI_DEVICE_TRACING=n\n\
CONFIG_MT7601U=y"
    fi

    if [ "$initramfs_b43" == "yes" ]; then
        local kernel_config="$kernel_config\n\
CONFIG_B43=m\n\
CONFIG_B43_PHY_LP=y\n\
CONFIG_B43_DEBUG=y\n\
CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE=y"
    fi

    if [ "$initramfs_usb_tethering" == "yes" ]; then
        local kernel_config="$kernel_config\n\
CONFIG_USB_USBNET=y\n\
CONFIG_USB_NET_CDCETHER=y\n\
CONFIG_USB_NET_CDCEEM=y\n\
CONFIG_USB_NET_RNDIS_HOST=y\n\
CONFIG_USB_NET_CDC_SUBSET=y\n\
CONFIG_USB_ARMLINUX=y"
    fi

    if [ "$initramfs_r8169" == "yes" ]; then
        local kernel_config="$kernel_config\n\
CONFIG_R8169=y"
    fi

    if [ "$initramfs_dell_t7500_audio" == "yes" ]; then
        local kernel_config="$kernel_config\n\
CONFIG_SND_HDA_CODEC_ANALOG=y"
    fi

    if [ "$initramfs_dell_t7500_card_reader" == "yes" ]; then
        local kernel_config="$kernel_config\n\
CONFIG_USB_UAS=y"
    fi

    if [ "$initramfs_uvc_camera" == "yes" ]; then
        local kernel_config="$kernel_config\n\
CONFIG_MEDIA_SUPPORT=m\n\
CONFIG_USB_GSPCA=n\n\
CONFIG_MEDIA_USB_SUPPORT=y\n\
CONFIG_MEDIA_CAMERA_SUPPORT=y\n\
CONFIG_MEDIA_ANALOG_TV_SUPPORT=n\n\
CONFIG_MEDIA_DIGITAL_TV_SUPPORT=n\n\
CONFIG_MEDIA_RADIO_SUPPORT=n\n\
CONFIG_MEDIA_SDR_SUPPORT=n\n\
CONFIG_MEDIA_RC_SUPPORT=n\n\
CONFIG_MEDIA_CEC_SUPPORT=n\n\
CONFIG_VIDEO_ADV_DEBUG=n\n\
CONFIG_VIDEO_FIXED_MINOR_RANGES=n\n\
CONFIG_MEDIA_PCI_SUPPORT=n\n\
CONFIG_USB_VIDEO_CLASS=m"
    fi

    if [ "$initramfs_sdhci" == "yes" ]; then
        local kernel_config="$kernel_config\n\
CONFIG_MMC=y\n\
CONFIG_MMC_SDHCI=y\n\
CONFIG_MMC_SDHCI_PCI=y\n\
CONFIG_MMC_SDHCI_ACPI=y\n\
CONFIG_MMC_SDHCI_PLTFM=y"
    fi

    if [ "$initramfs_squashfs" == "yes" ]; then
        local kernel_config="$kernel_config\n\
CONFIG_SQUASHFS=y\n\
CONFIG_SQUASHFS_FILE_CACHE=n\n\
CONFIG_SQUASHFS_FILE_DIRECT=y\n\
CONFIG_SQUASHFS_DECOMP_SINGLE=n\n\
CONFIG_SQUASHFS_DECOMP_MULTI=n\n\
CONFIG_SQUASHFS_DECOMP_MULTI_PERCPU=y\n\
CONFIG_SQUASHFS_XATTR=y\n\
CONFIG_SQUASHFS_ZLIB=y\n\
CONFIG_SQUASHFS_LZ4=y\n\
CONFIG_SQUASHFS_LZO=y\n\
CONFIG_SQUASHFS_XZ=y\n\
CONFIG_SQUASHFS_4K_DEVBLK_SIZE=y\n\
CONFIG_SQUASHFS_EMBEDDED=n"
        local initramfs_files="$initramfs_files \
                                /usr/bin/unsquashfs"
    fi

    if [ "$initramfs_cryptsetup" == "yes" ]; then
        local initramfs_files="$initramfs_files \
                                /sbin/cryptsetup"
        local kernel_config="$kernel_config\n\
CONFIG_CRYPTO_XTS=y\n\
CONFIG_DM_CRYPT=y"
    fi

    if [ "$initramfs_curl" == "yes" ]; then
        local initramfs_files="$initramfs_files \
                                /usr/bin/curl"
    fi

    if [ "$initramfs_docker" == "yes" ]; then
        local kernel_config="$kernel_config\n\
CONFIG_CGROUP_DEVICE=y\n\
CONFIG_MEMCG=y\n\
CONFIG_VETH=y\n\
CONFIG_BRIDGE_NETFILTER=y\n\
CONFIG_NF_NAT=y\n\
CONFIG_NF_NAT_IPV4=y\n\
CONFIG_IP_NF_TARGET_MASQUERADE=y\n\
CONFIG_NETFILTER_XT_MATCH_ADDRTYPE=y\n\
CONFIG_IP_NF_NAT=y\n\
CONFIG_USER_NS=y\n\
CONFIG_CGROUP_PIDS=y\n\
CONFIG_MEMCG_SWAP=y\n\
CONFIG_MEMCG_SWAP_ENABLED=y\n\
CONFIG_BLK_CGROUP=y\n\
CONFIG_DEBUG_BLK_CGROUP=y\n\
CONFIG_BLK_DEV_THROTTLING=y\n\
CONFIG_BLK_DEV_THROTTLING_LOW=n\n\
CONFIG_CFQ_GROUP_IOSCHED=y\n\
CONFIG_CGROUP_PERF=y\n\
CONFIG_CGROUP_HUGETLB=y\n\
CONFIG_NET_CLS_CGROUP=y\n\
CONFIG_CFS_BANDWITH=y\n\
CONFIG_RT_GROUP_SCHED=y\n\
CONFIG_IP_VS=y\n\
CONFIG_IP_VS_IPV6=n\n\
CONFIG_IP_VS_DEBUG=n\n\
CONFIG_IP_VS_TAB_BITS=12\n\
CONFIG_IP_VS_SH_TAB_BITS=8\n\
CONFIG_IP_VS_FTP=n\n\
CONFIG_IP_VS_NFCT=n\n\
CONFIG_IP_VS_PE_SIP=n\n\
CONFIG_IP_VS_PROTO_TCP=y\n\
CONFIG_IP_VS_PROTO_UDP=y\n\
CONFIG_IP_VS_PROTO_ESP=n\n\
CONFIG_IP_VS_PROTO_AH=n\n\
CONFIG_IP_VS_PROTO_SCTP=n\n\
CONFIG_IP_VS_RR=n\n\
CONFIG_IP_VS_WRR=n\n\
CONFIG_IP_VS_LC=n\n\
CONFIG_IP_VS_WLC=n\n\
CONFIG_IP_VS_FO=n\n\
CONFIG_IP_VS_OVF=n\n\
CONFIG_IP_VS_LBLC=n\n\
CONFIG_IP_VS_LBLCR=n\n\
CONFIG_IP_VS_DH=n\n\
CONFIG_IP_VS_SH=n\n\
CONFIG_IP_VS_SED=n\n\
CONFIG_IP_VS_NQ=n\n\
CONFIG_IP_VS_NFCT=y\n\
CONFIG_VXLAN=y\n\
CONFIG_IPVLAN=y\n\
CONFIG_GENEVE=n\n\
CONFIG_GTP=n\n\
CONFIG_MACVLAN=y\n\
CONFIG_MACVTAP=n\n\
CONFIG_DUMMY=y\n\
CONFIG_CGROUP_NET_PRIO=y\n\
CONFIG_DM_THIN_PROVISIONING=y\n\
CONFIG_DM_DEBUG_BLOCK_STACK_TRACING=n"
    fi

    if [ "$initramfs_fuse" == "yes" ]; then
        kernel_config="$kernel_config\n
CONFIG_FUSE_FS=y"
    fi

    if [ "$initramfs_kvm" == "yes" ]; then
        kernel_config="$kernel_config\n
CONFIG_KVM=y\n\
CONFIG_KVM_INTEL=y\n\
CONFIG_KVM_AMD=n\n\
CONFIG_KVM_MMU_AUDIT=n\n\
CONFIG_KVM_DEVICE_ASSIGNMENT=n\n\
CONFIG_VHOST_NET=y\n\
CONFIG_TUN=y\nCONFIG_BRIDGE=y\n\
CONFIG_BRIDGE_NF_EBTABLES=n\n\
CONFIG_BRIDGE_IGMP_SNOOPING=y"
    fi

    if [ "$initramfs_lsblk" == "yes" ]; then
        local initramfs_files="$initramfs_files \
                                /bin/lsblk"
    fi

    if [ "$initramfs_lspci" == "yes" ]; then
        local initramfs_files="$initramfs_files \
                                /etc/udev/hwdb.bin \
                                /usr/sbin/lspci \
                                /usr/share/misc/pci.ids \
                                /usr/share/misc/pci.ids.gz"
    fi

    if [ "$initramfs_lsusb" == "yes" ]; then
        local initramfs_files="$initramfs_files \
                                /etc/udev/hwdb.bin \
                                /usr/bin/lsusb \
                                /usr/share/misc/pci.ids \
                                /usr/share/misc/pci.ids.gz"
    fi

    if [ "$initramfs_lvm" == "yes" ]; then
        local initramfs_files="$initramfs_files \
                                /sbin/lvm"
        kernel_config="$kernel_config\n\
CONFIG_DM_DEBUG_BLOCK_MANAGER_LOCKING=n"
    fi

    if [ "$initramfs_mdadm" == "yes" ]; then
        local initramfs_files="$initramfs_files \
                                /sbin/mdadm"
    fi

    if [ "$initramfs_nv" == "yes" ]; then
        kernel_config="$kernel_config\n\
# .config
CONFIG_IKCONFIG=y\n\
CONFIG_IKCONFIG_PROC=y\n\
# nvidia-drivers
CONFIG_ZONE_DMA=y\n\
CONFIG_MTRR=y\n\
CONFIG_SYSVIPC=y"
    fi

    if [ "$initramfs_pbzip2" == "yes" ]; then
        local initramfs_files="$initramfs_files \
                                pbzip2 \
                                tar"
    fi

    if [ "$initramfs_pigz" == "yes" ]; then
        local initramfs_files="$initramfs_files \
                                pigz \
                                tar"
    fi

    if [ "$initramfs_raid1" == "yes" ]; then
        local kernel_config="$kernel_config\n\
CONFIG_MD_RAID1=y"
    fi

    if [ "$initramfs_dm_raid" == "yes" ]; then
        local kernel_config="$kernel_config\n\
CONFIG_DM_RAID=y"
    fi

    if [ "$initramfs_raid6" == "yes" ]; then
        local kernel_config="$kernel_config\n\
CONFIG_MD_RAID456=y\n\
CONFIG_ASYNC_RAID6_TEST=n"
    fi

    if [ "$initramfs_rsync" == "yes" ]; then
        local initramfs_files="$initramfs_files \
                                /usr/bin/rsync"
    fi

    if [ "$initramfs_sas" == "yes" ]; then
        local kernel_config="$kernel_config\n\
CONFIG_FUSION=y\n\
CONFIG_FUSION_SPI=y\n\
CONFIG_FUSION_SAS=y\n\
CONFIG_FUSION_MAX_SGE=128\n\
CONFIG_FUSION_CTL=y\n\
CONFIG_FUSION_LOGGING=y"
    fi

    if [ "$initramfs_strace" == "yes" ]; then
        local initramfs_files="$initramfs_files \
                                /usr/bin/strace"
    fi

    echo -e "$kernel_config" >> /usr/src/linux-$arch/.config

    mount_ramdisk "$initramfs_dir" "ramfs"
# clean up? Not necessarry? mkdir -p and mount filesystems?
    create_dirs "$initramfs_dir" "$initramfs_dirs"
    copy_executables "$initramfs_dir" "$initramfs_files"

    get_dev_name "$serial_keys"
    if [ -n "$initramfs_keys" ]; then
        if [ -b "$(eval echo \${dev_$serial_keys:-})" ]; then
            open_luks "$serial_keys"
            mount_dev "/dev/mapper/$serial_keys"
            mount_dev "$initramfs_keys"
        else
            cecho "-light_blue" ".."
            cecho "green" "OK"
            #gen_keys "$serial_keys" "$initramfs_keys"
            #mount_dev "$initramfs_keys"
        fi
    fi

    run_command "mknod -m 600 $initramfs_dir/dev/console c 5 1" "[ ! -c $initramfs_dir/dev/console ]" "Failed creating /dev/console, already exists!" "Creating /dev/console." "fail_on_condition" ""
    run_command "touch $initramfs_dir/etc/mtab" "[ ! -f $initramfs_dir/etc/mtab ]" "Failed creating $initramfs_dir/etc/mtab, already exists!" "Creating $initramfs_dir/etc/mtab." "fail_on_condition" ""
    run_command "cp $0 $initramfs_dir/cu_boot.sh" "[ ! -f $initramfs_dir/cu_boot.sh ]" "Failed creating $initramfs_dir/cu_boot.sh, already exists!" "Creating $initramfs_dir/cu_boot.sh" "fail_on_condition" ""
    run_command "ln -s cu_boot.sh $initramfs_dir/init" "[ ! -f $initramfs_dir/init ]" "Failed creating $initramfs_dir/init link, already exists!" "Creating $initramfs_dir/init link" "fail_on_condition" ""
    }

function create_partitions {
    serial="$1"
    verbose "blue" "function create_partitions [serial: $serial]"

    if eval [ -z \${dev_$serial:-} ]; then
        get_dev_name "$serial"
    fi

    verbose "-blue" "Searching for 128MB boot partition"
    if [ $(eval "blockdev --getsz \${dev_$serial}1") == "251200" ]; then
        check_status "" ""
    else
        echo -e "o\nn\np\n1\n2048\n+128M\nN\na\n1\nw" | eval "fdisk \$dev_$serial"
        sleep 1
    fi
    sleep 5
}

function del_key {
    local serial="${1:-}"
    verbose "yellow" "function del_key[serial: $serial]"
    check_if_argument_empty "$serial"

    local key_names=""
    if [ -z "$key_names" ]; then
        cecho "light_blue" "Available keys:"
        list_keys /mnt/"$serial_keys"
        echo "Please enter key name(s) [aaa bbb] to delete"
        read key_names
        while [ -z "$key_names" ]; do
            cecho "yellow" "no key name provided, please try again"
            read key_names
        done
    fi

    local key_name
    for key_name in $key_names; do
        if [ -d /mnt/"$serial"/"$key_name" ]; then
            cecho "-light_blue" "Deleting key $key_name..."
            run_command "rm -r /mnt/$serial/$key_name" "" "" "Deleteing key $key_name" "fail_on_condition" ""
            cecho "green" "OK"
        else
            cecho "yellow" "key $key_name not found, please try again"
        fi
    done
}

function exit_error {
    verbose "blue" "function error_exit"
    cecho "red" "Press ENTER to continue..."
    exit 0
}

function exit_trap {
    local exit_code="$?"
    verbose "red" "function exit_trap [$exit_code]"

    if [ "$verbose" == "yes" -a "$exit_code" == "0" ]; then
        verbose "blue" "Exiting gracefully"
    elif [ "$verbose" == "yes" -a "$exit_code" != "0" ]; then
        verbose "yellow" "A command has exited with code [$exit_code], dropping into a shell"; exec sh
    elif [ "$exit_code" != "0" ]; then
        cecho "red" "An error has occured, please enable verbose mode for more information and try again"
        exec sh
    fi

    clean_up
}

# checked
function erase_dev {
    local devices="$@"
    verbose "blue" "function erase_dev [devices: $devices]"
    check_if_argument_empty "$devices"

    check_for_program "/bin/dd --version"

    if [ "$devices" == "choose" ]; then
        lsblk -o+serial
        while (local device; for device in $devices; do [ ! -b $device ]; done); do
            cecho "default" "Please enter space separated list of devices to erase."
            read devices
        done
    fi

    get_dev_geometry "$devices"

    if [ "$hardened" == "no" ]; then
        verbose "blue" "[ hardened=no ], using /dev/zero"
        local source=/dev/zero
    elif [ "$hardened" == "yes" ]; then
        verbose "blue" "[ hardened=yes ], using /dev/urandom"
        local source=/dev/urandom
    else
        cecho "red" "[ $hardened !=no -a $hardened != yes ]\nPlease set \"hardened\" variable properly and try again, exiting!"
        exit_error
    fi
            
    for device in $devices; do
        if (/bin/dd count=1 if=/dev/zero of=/dev/null status=progress 1>&3 2>&4); then
            local dd_opts="oflag=direct status=progress"
        fi

        local block_count=$(eval echo \$sector_count_$(basename $device))
        local block_size=$(eval echo \$block_size_$(basename $device))
        cecho "default" "About to erase device $device with $block_count ${block_size}B blocks using $source, would you like to continue? [no/yes]"
        get_answer
        if [ "$answer" == "yes" ]; then
            cecho "light_blue" "Erasing device $device with $block_count ${block_size}B blocks using $source..."
            /bin/dd if=$source of=$device bs=$block_size count=$block_count ${dd_opts:-}
            cecho "green" "OK"
        elif [ "$answer" == "no" ]; then
            cecho "red" "Operation aborted, exiting!"
            exit_error
        else
            cecho "red" "[ $answer != no -a $answer!= yes ]\nInvalid value of \"answer\" variable returned, exiting!"
            exit_error
        fi
    done
}

# checked
function format_dev {
    if [ "$#" == "2" ]; then

        local device="${1:-}"
        local fstype="${2:-}"
        verbose "blue" "function format_dev [device: $device, filesystem: $fstype]"

        check_if_argument_empty "$device" # [ -b ... ]?
        verbose "blue" "Using $device"

        if [ -z "$fstype" ]; then
            cecho "default" "\nPlease choose the file system type to use[ext2/ext4/luks]:"
            local fstype
            read fstype
            while [ "${fstype:-}" != "ext2" -a "${fstype:-}" != "ext4" -a "${fstype:-}" != "luks" ]; do
                cecho "yellow" "Incorrect filesystem type has been chosen [$fstype], please choose [ext2/ext4/luks]!"
                read fstype
            done
            format_dev "$device" "$fstype"
        elif [ "$fstype" == "ext2" -o "$fstype" == "ext4" ]; then
#            check_for_program " --help" # busybox?
            if (eval "fsck.$fstype $device" 1>&3 2>&4); then
                cecho "default" "The device $device seems to already be formatted, would you like to format anyway [no/yes]?"
                get_answer
                run_command "mkfs.$fstype -q $device" "[ -b $device ] && [ $answer == yes ]" "Failed to format $device with $fstype" "Formatting $device with $fstype" "do_not_fail_on_condition" ""
            else
                run_command "mkfs.$fstype -q $device" "[ -b $device ]" "" "Formatting $device as $fstype" "fail_on_condition" ""
            fi
        elif [ "$fstype" == "luks" ]; then
            check_for_program "cryptsetup --version"
            if eval cryptsetup isLuks $device; [ "$?" == "0" ]; then
                cecho "default" "$device seems to be already LUKS formatted, would you like to format anyway [no/yes]?"
                get_answer
                if [ "$answer" == "no" ]; then
                    cecho "yellow" "Skipping $device"
                    return 0
                fi
            fi
            cecho "light_blue" "Formatting device $device as LUKS..."
            until cryptsetup luksFormat $device; do
                cecho "yellow" "cryptsetup has failed, please try again"
            done
        else
            cecho "red" "Please set the \"fstype\" argument for \"format_dev\" function properly and try again, exiting!"
            exit_error
        fi
    else
        cecho "red" "Please set the arguments for \"format_dev\" function properly and try again, exiting!"
        exit_error
    fi
}

function gen_keys {
        check_number_of_arguments "gen_keys" "$#" "2"
        local key_drive_serial="${1:-}"
        local key_names="${2:-}"

        verbose "blue" "function gen_keys [key_drive_serial: $key_drive_serial, key_names: $key_names]"
        check_if_argument_empty "$key_drive_serial"
        check_for_program "cryptsetup --version"

        while [ -z "$key_names" ]; do
            get_dev_name "none"
            local device
            for device in $(ls /sys/block | grep -e dm -e loop -v); do
                local device_listed="no"
                if [ -n "$(eval echo \${serial_vpd_pg80_$device:-})" ]; then
                    if [ "$device_listed" == "no" ]; then
                        cecho "yellow" "${device}:"
                        device_listed="yes"
                    fi
                    cecho "yellow" "$(eval echo \${serial_vpd_pg80_$device:-} from /sys/block/$device/device/vpd_pg80)"
                fi
                if [ -n "$(eval echo \${serial_lsblk_$device:-})" ]; then
                    if [ "$device_listed" == "no" ]; then
                        cecho "yellow" "${device}:"
                        device_listed="yes"
                    fi
                    cecho "yellow" "$(eval echo \${serial_lsblk_$device:-} from lsblk -o+serial)"
                fi
                if [ -n "$(eval echo \${serial_sg_vpd_$device:-})" ]; then
                    if [ "$device_listed" == "no" ]; then
                        cecho "yellow" "${device}:"
                        device_listed="yes"
                    fi
                    cecho "yellow" "$(eval echo \${serial_sg_vpd_$device:-} from sg_vpd -p sn -r /dev/$device)"
                fi
                if [ -n "$(eval echo \${serial_mdadm_$device:-})" ]; then
                    if [ "$device_listed" == "no" ]; then
                        cecho "yellow" "${device}:"
                        device_listed="yes"
                    fi
                    cecho "yellow" "$(eval echo \${serial_mdadm_$device:-} from mdadm -D /dev/$device\n)"
                fi
            done
            cecho "default" "Please enter key name(s) [aaa bbb]"
            read key_names
        done

        if [ -z "$key_names" ] && [ -n "$(ls -A /mnt/$key_drive_serial | sed 's/lost+found//')" ]; then
            cecho "light_blue" "Existing keys:"
            list_keys /mnt/$key_drive_serial
        fi

        if [ "$hardened" == "no" ]; then
            local device="/dev/urandom"
        elif [ "$hardened" == "yes" ]; then
            local device="/dev/random"
        else
            cecho "red" "Please set \"hardened\" variable in \"set_variables\" function correctly and try again, exiting!"
            exit_error
        fi

#        if [ -n "$password" ]; then
#            run_command "mkdir -p /mnt/$serial_keys" "[ ! -f /mnt/$serial_keys ]" "" "" "fail_on_condition" "/mnt/$serial_keys"
#        fi
        if [ ! -d "/mnt/$key_drive_serial" ]; then
            run_command "mkdir /mnt/$key_drive_serial" "[ ! -d /mnt/$key_drive_serial ]" "Failed to create /mnt/$key_drive_serial, already exists!" "Creating /mnt/$key_drive_serial..." "fail_on_condition" "/mnt/$key_drive_serial"
        fi

        local key_name
        for key_name in $key_names; do
            if [ ! -d /mnt/"$key_drive_serial"/"$key_name" ]; then
                cecho "-light_blue" "Generating $key_name key..."
                run_command "mkdir /mnt/$key_drive_serial/$key_name" "[ ! -d /mnt/$key_drive_serial/$key_name ]" "Failed to create /mnt/$key_drive_serial/$key_name!" "Creating /mnt/$key_drive_serial/$key_name directory" "fail_on_condition" ""

                run_command "dd if=/dev/zero of=/mnt/$key_drive_serial/$key_name/$key_name bs=1k count=1032" "[ ! -f /mnt/$key_drive_serial/$key_name/$key_name ]" "Failed to create /mnt/$key_drive_serial/$key_name/$key_name directory, already exists!" "Creating /mnt/$key_drive_serial/$key_name/$key_name directory..." "fail_on_condition" ""

#                if [ -n "$password" ]; then
#                    run_command "echo $password | cryptsetup luksFormat --align-payload=2056 --key-file - -q /mnt/$key_drive_serial/$key_name/$key_name" "[ -f /mnt/$key_drive_serial/$key_name/$key_name ]" "Failed to format /mnt/$key_drive_serial/$key_name/$key_name as LUKS" "Formatting /mnt/$key_drive_serial/$key_name/$key_name as LUKS" "fail_on_condition" ""
                    
#                    run_command "echo $password | cryptsetup luksOpen --key-file - /mnt/$key_drive_serial/$key_name/$key_name key_$key_name" "[ -f /mnt/$key_drive_serial/$key_name/$key_name ]" "Failed to open /mnt/$key_drive_serial/$key_name/$key_name as LUKS" "Openning /mnt/$key_drive_serial/$key_name/$key_name as LUKS" "fail_on_condition" "key_$key_name"
#                else
                    if (/bin/dd count=1 if=/dev/zero of=/dev/null status=progress 1>&3 2>&4); then
                        local dd_opts="status=progress"
                    fi
                    
                    run_command "/bin/dd if=$device of=/mnt/$key_drive_serial/$key_name/$key_name.key bs=1 count=4096 ${dd_opts:-}" "[ ! -f /mnt/$key_drive_serial/$key_name/$key_name.key ]" "Failed to create /mnt/$key_drive_serial/$key_name/$key_name.key, already exists!" "Creating /mnt/$key_drive_serial/$key_name/$key_name.key..." "fail_on_condition" ""
                    
                    run_command "cryptsetup luksFormat --use-urandom --align-payload=2056 --key-file /mnt/$key_drive_serial/$key_name/$key_name.key -q /mnt/$key_drive_serial/$key_name/$key_name" "[ -f /mnt/$key_drive_serial/$key_name/$key_name.key ] && [ -f /mnt/$key_drive_serial/$key_name/$key_name ]" "Failed to format /mnt/$key_drive_serial/$key_name/$key_name as LUKS" "Formatting /mnt/$key_drive_serial/$key_name/$key_name as LUKS" "fail_on_condition" ""
                    
                    run_command "cryptsetup luksOpen --key-file /mnt/$key_drive_serial/$key_name/$key_name.key /mnt/$key_drive_serial/$key_name/$key_name key_$key_name" "[ -f /mnt/$key_drive_serial/$key_name/$key_name.key ] && [ -f /mnt/$key_drive_serial/$key_name/$key_name ]" "Failed to open /mnt/$key_drive_serial/$key_name/$key_name as LUKS" "Openning /mnt/$key_drive_serial/$key_name/$key_name as LUKS" "fail_on_condition" "key_$key_name"
#                fi

# improve?
                if [ -f $key_name ] && [ -f "$key_name".header ]; then
                    cecho  "-light_blue" "Importing $(pwd)/$key_name..."
                    dd if="$key_name" of=/dev/mapper/key_"$key_name" bs=1 count=4096 1>&2 2>&4
                    cecho  "-light_blue" "$(pwd)/$key_name.header..."
                    cp "$key_name".header /mnt/"$key_drive_serial"/"$key_name"/"$key_name".header
                else
                    run_command "/bin/dd if=$device of=/dev/mapper/key_$key_name bs=1 count=4096 ${dd_opts:-}" "[ -b /dev/mapper/key_$key_name ]" "Failed to create the key material for a key named $key_name, the file exists!" "Creating the key material for the key named $key_name" "fail_on_condition" ""
                    run_command "dd if=/dev/zero of=/mnt/$key_drive_serial/$key_name/$key_name.header bs=1k count=1028 1>&3 2>&4" "[ -b /dev/mapper/key_$key_name ]" "Failed to create the header for the key named $key_name" "Creating key header for the key named $key_name" "fail_on_condition" ""
#                    if [ -n "$password" ]; then
#                    ls /dev/mapper/ -l
#                    ls /mnt/$key_drive_serial/$key_name -l
#                        run_command "cryptsetup luksFormat --header /mnt/$key_drive_serial/$key_name/$key_name.header --key-file /dev/mapper/key_$key_name -q /dev/loop0" "[ -f /mnt/$key_drive_serial/$key_name/$key_name.header ] && [ -b /dev/mapper/key_$key_name ]" "Failed to store the key material for key $key_name" "Storing the key material for the key $key_name" "fail_on_condition" "/mnt/$key_drive_serial/$key_name"
#                    else
                        run_command "cryptsetup luksFormat --use-urandom --header /mnt/$key_drive_serial/$key_name/$key_name.header --key-file /dev/mapper/key_$key_name -q /dev/loop0" "[ -f /mnt/$key_drive_serial/$key_name/$key_name.header ] && [ -b /dev/mapper/key_$key_name ]" "Failed to store the key material for key $key_name" "Storing the key material for the key $key_name" "fail_on_condition" "" # check
#                    fi
                fi
                cecho "green" "OK"
            else
                cecho "yellow" "key $key_name already exists, please choose (a) different name(s)"
                gen_keys "$@"
            fi
        done
}

# checked
function get_answer {
    read answer
    while [ "$answer" != "no" -a "$answer" != "yes" ]; do
        cecho "yellow" "Please type in a correct answer[no/yes]!"
        read answer
    done
}

# checked
function get_dev_geometry {
    devices="$@"
	verbose "blue" "function get_dev_geometry [devices: $devices]"

	check_if_argument_empty "$devices"
	
	local device
	for device in $devices; do
        cecho "-light_blue" "Obtaining drive geometry for device $device..."

		verbose "-blue" "Obtaining block size..."
		local block_size=$(eval "blockdev --getbsz $device")
		export block_size_$(basename $device)="$block_size"
		cecho "-light_blue" "${block_size}B x "

		verbose "-blue" "Obtaining sector count..."
		local sector_count=$(eval "blockdev --getsz $device")
		if [ "$block_size" == "512" ]; then
            export sector_count_$(basename $device)="$sector_count"
            cecho "-light_blue" "${sector_count}..."
		elif [ "$block_size" == "2048" ]; then
            export sector_count_$(basename $device)="$(($sector_count/4))"
            cecho "-light_blue" "$(($sector_count/4))..."
		elif [ "$block_size" == "4096" ]; then
            export sector_count_$(basename $device)="$(($sector_count/8))"
            cecho "-light_blue" "$(($sector_count/8))..."
        else
            cecho "red" "Block size $block_size not supported, exiting!"
            exit_error
        fi
	done
	cecho "green" "OK"
}

function get_dev_name {
    local serials="${@:-}"
    verbose "blue" "function get_dev_name [serials: $serials]"
    check_if_argument_empty "$serials"
    
    for serial in $serials; do
        if [ "$serials" != "none" ]; then
            cecho "-light_blue" "Searching for device with serial $serial..."
        elif [ "$serials" == "none" ]; then
            cecho "yellow" "You might find the below, automatically detected serial numbers helpful:"
        fi
        
        local device
        local found="0"
        for device in $(ls /sys/block/ | grep -v loop); do
            verbose "blue" "Obtaining serial for $device."
            if [ "$found" == "0" ]; then
                if [ -n "$(cat /sys/block/$device/device/vpd_pg80 2>&4 | cut -c2- | tail -n1 | tr -d '[:space:]')" ]; then
                    local serial_vpd_pg80=$(cat /sys/block/$device/device/vpd_pg80 | cut -c2- | tail -n1 | tr -d '[:space:]')
                    verbose "blue" "Found $serial_vpd_pg80 via vpd_pg80."
                    if [ "$serial" != "none" -a "$serial" == "$serial_vpd_pg80" ]; then
                        verbose "blue" "[ $serial == $serial_vpd_pg80 ]"
                        found="1"
                        export dev_$serial="/dev/$device"
                        break
                    elif [ "$serial" != "none" -a "$serial" != "$serial_vpd_pg80" ]; then
                        verbose "blue" "[ $serial != $serial_vpd_pg80 ]"
                    elif [ "$serial" == "none" -a -n "$serial_vpd_pg80" ]; then
                        export serial_vpd_pg80_$device="$serial_vpd_pg80"
                    fi
                else
                    verbose "blue" "Failed $serial via vpd_pg80"       
                fi
                if [ -n "$(lsblk -ndoname,serial | grep $device | awk '{print $2}')" ]; then
                    local serial_lsblk=$(lsblk -ndoname,serial | grep $device | awk '{print $2}')
                    verbose "blue" "Found serial $serial_lsblk via lsblk."
                    if [ "$serial" != "none" -a "$serial" == "$serial_lsblk" ]; then
                        verbose "blue" "[ $serial == $serial_lsblk ]"
                        found="1"
                        export dev_$serial="/dev/$device"
                        break
                    elif [ "$serial" != "none" -a "$serial" != "$serial_lsblk" ]; then
                        verbose "blue" "[ $serial != $serial_lsblk ]"
                    elif [ "$serial" == "none" -a -n "$serial_lsblk" ]; then
                        export serial_lsblk_$device="$serial_lsblk"
                    fi
                else
                    verbose "blue" "Failed $serial via lsblk"
                fi
                if (sg_vpd -p sn -r /dev/$device 1>&3 2>&4); then
                    serial_sg_vpd="$(sg_vpd -p sn -r /dev/$device | cut -d $'\003' -f2 | tr -cd '\060-\132' | cut -c-24)"
                    verbose "blue" "Found serial $serial_sg_vpd via sg_vpd"
                    if [ "$serial" != "none" -a "$serial" == "$serial_sg_vpd" ]; then
                        verbose "blue" "[ $serial == $serial_sg_vpd ]"
                        found="1"
                        export dev_$serial="/dev/$device"
                        break
                    elif [ "$serial" != "none" -a "$serial" != "$serial_sg_vpd" ]; then
                        verbose "blue" "[ $serial != $serial_sg_vpd ]"
                    elif [ "$serial" == "none" -a -n "$serial_sg_vpd" ]; then
                        export serial_sg_vpd_$device="$serial_sg_vpd"
                    fi
                else
                    verbose "blue" "Failed $serial via sg_vpd"
                fi
                if (mdadm -D /dev/$device 1>&3 2>&4); then
                    serial_mdadm=$(mdadm -D /dev/$device | grep UUID | tr -d "UUID| |:")
                    verbose "blue" "Found UUID $serial_mdadm via mdadm"
                    if [ "$serial" != "none" -a "$serial" == "$serial_mdadm" ]; then
                        verbose "blue" "[ $serial == $serial_mdadm ]"
                        found="1"
                        export dev_$serial="/dev/$device"
                        break
                    elif [ "$serial" != "none" -a "$serial" != "$serial_mdadm" ]; then
                        verbose "blue" "[ $serial != $serial_mdadm ]"
                    elif [ "$serial" == "none" -a -n "$serial_mdadm" ]; then
                        export serial_mdadm_$device="$serial_mdadm"
                    fi
                else
                    verbose "blue" "Failed $serial via mdadm"
                fi
            fi
        done
        if [ "$found" == "1" ]; then
            cecho "-light_blue" "$device..."
            cecho "green" "OK"
        else
            if [ "$serials" != "none" ]; then
                cecho "red" "NOT_FOUND"
            fi
        fi
    done
}

function init_array {
    verbose "blue" "function init_array"
    cecho "-light_blue" "Starting mdadm..."

    run_command "mdadm --assemble --scan" "" "Failed to assemble the array" "Array assembled" "do_not_fail_on_condition" ""

    cecho "green" "OK"
}

function init_net {
    verbose "blue" "function init_net [interfaces: $(ls /sys/class/net), wired_devices_mask: $wired_devices_mask, wireless_devices_mask: $wireless_devices_mask]"
    cecho "-light_blue" "Configuring network interfaces..."

    while [ -n "$wired_devices_mask" ] && [ -z $(ls /sys/class/net | grep $wired_devices_mask) ]; do
        cecho "blue" "Waiting for ${wired_devices_mask}x device(s) to become active"
        sleep 1
    done
    local wired_devices=$(ls /sys/class/net | grep ${wired_devices_mask:-empty})
    
    while [ -n "$wireless_devices_mask" ] && [ -z $(ls /sys/class/net | grep $wireless_devices_mask) ]; do
        cecho "blue" "Waiting for ${wireless_devices_mask}x device(s) to become active"
        sleep 1
    done
    local wireless_devices=$(ls /sys/class/net | grep ${wireless_devices_mask:-empty})
    
    check_if_argument_empty "wired_devices wireless_devices"
    
    local wired_device
    for wired_device in $wired_devices; do
        cecho "-light_blue" "$wired_device..."
        if [ $(ps aux | grep udhcpc | wc -l) -lt "2" ]; then
            local resource="udhcpc"
        else
            local resource=""           
        fi
        run_command "udhcpc -i $wired_device 1>&3 2>&4 &" "[ -n "$wired_device" ]" "" "Starting udhcpc DHCP client on $wired_device"  "fail_on_condition" "${resource:-}"
    done
        
    local wireless_device
    for wireless_device in $wireless_devices; do
        cecho "-light_blue" "$wireless_device..."
        if [ -n "$wireless_device" ] && [ -f /etc/wpa_supplicant/wpa_supplicant.conf ]; then
            if [ $(ps aux | grep wpa_supplicant | wc -l) -lt "2" ]; then
                local resource="wpa_supplicant"
            else
                local resource=""
            fi
            check_for_program "wpa_supplicant --help"
            run_command "wpa_supplicant -Dnl80211 -i$wireless_device -c/etc/wpa_supplicant/wpa_supplicant.conf &" "" "" "Starting wpa_supplicant" "fail_on_condition" "${resource:-}"
            if [ $(ps aux | grep udhcpc | wc -l) -lt "2" ]; then
                local resource="udhcpc"
            else
                local resource=""
            fi
            run_command "udhcpc -i $wireless_device 1>&3 2>&4 &" "" "" "Starting udhcpc DHCP client on $wireless_device" " 0" "$resource"
        else
            verbose "yellow" "device [$wireless_device] does not exist or configuration file missing, could not start wpa_supplicant"
        fi
    done
    cecho "green" "OK"
}

function install_busybox {
    local destination="${1:-}"
    verbose "blue" "function install_busybox"

    cecho "-light_blue" "Installing busybox..."

    if [ -n "$destination" ]; then
        create_dirs "$destination" "bin dev etc init.d proc sbin sys"
        run_command "cp /bin/busybox $destination/bin/busybox" "[ -x /bin/busybox ]" "Failed to copy /bin/busybox, doesn't exist or not executable!" "Copying /bin/busybox to $destination/bin" "fail_on_condition" ""
        run_command "chroot $destination /bin/busybox --install" "[ -x /bin/busybox ]" "" "Installing busybox" "fail_on_condition" ""
        echo -e \#!/bin/busybox sh\nexec sh > $destination/init.d/rcS
        run_command "chmod +x $destination/init.d/rcS" "[ ! -x $destination/init ]" "Failed to make $destination/init.d/rcS executable, already is!" "Making $destination/init.d/rcS executable..." "fail_on_condition" ""  
        echo "dev     /dev    devtmpfs    defaults    0 0" >> $destination/etc/fstab
        echo "proc    /proc   proc        defaults    0 0" >> $destination/etc/fstab
        echo "sys     /sys    sysfs       defaults    0 0" >> $destination/etc/fstab
    else
        run_command "/bin/busybox --install" "[ -x /bin/busybox ]" "" "Installing busybox" "fail_on_condition" ""
    fi

    cecho "green" "OK"
}
    
function install_gentoo {
    check_number_of_arguments "install_gentoo" "$#" "1"
    local destination="${1:-}"
    #local files_to_copy="${2:-}"
    #local packages_to_emerge="${3:-}"
    verbose "blue" "function install_gentoo [destination: $destination]"
    check_if_argument_empty "$destination"
    
    local cores_num=$(cat /proc/cpuinfo | grep processor | wc -l)
    
    until (nc -z google.com 80); do
        cecho "yellow" "Waiting for the network to become available"
        sleep 1
    done

    if ! wget -P "$destination" "$http_server"/stage3-amd64-20170907.tar.bz2; then
        wget -P "$destination" http://distfiles.gentoo.org/releases/amd64/autobuilds/$(curl http://distfiles.gentoo.org/releases/amd64/autobuilds/latest-stage3.txt | grep stage3-amd64-$(date +%Y) | cut -d " " -f1)
    fi
    set +f
    if [ -x /bin/tar -a -x /usr/bin/pbzip2 ]; then
        cecho "red" "using parallel"
        time /bin/tar -xpf "$destination"/stage3-amd64-*.tar.* -I pbzip2 -C "$destination" # will get depracated, stupid idea # check for verbose
    else
        EXTRACT_UNSAFE_SYMLINKS=1 time tar -xpf "$destination"/stage3-amd64-*.tar.* -C "$destination" # will get depracated, stupid idea # check for verbose
    fi
    rm "$destination"/stage3-amd64-*.tar.*
    if ! wget -P "$destination" "$http_server"/portage-latest.tar.bz2; then
       wget -P "$destination" http://distfiles.gentoo.org/snapshots/portage-latest.tar.bz2
    fi
    if [ -x /bin/tar -a -x /usr/bin/pbzip2 ]; then
        cecho "red" "using parallel"
        /bin/tar -xf "$destination"/portage-latest.tar.bz2 -I pbzip2 -C "$destination"/usr # check for verbose # uncomment
    else
        tar -xf "$destination"/portage-latest.tar.bz2 -C "$destination"/usr # check for verbose # uncomment
    fi
    rm "$destination"/portage-latest.tar.bz2
    set -f

    sed -i  "s/*//" "$destination"/etc/shadow

    cp /etc/resolv.conf "$destination"/etc/
    ln -sv /proc/self/fd /dev/fd

    run_command "mount -o bind /dev $destination/dev" "" "aaab" "aaa" "do_not_fail_on_condition" "$destination/dev"

    mount -t proc none $destination/proc
    check_status "" "$destination/proc"
    mount -o bind /dev/shm $destination/dev/shm
    check_status "" "$destination/dev/shm"

    echo -e "MAKEOPTS=\"-j$cores_num -l$cores_num\"\nEMERGE_DEFAULT_OPTS=\"--jobs=$cores_num --load-average=$cores_num --with-bdeps y\"" >> $destination/etc/portage/make.conf 

    if (echo ${installation:-} | grep basic); then
        packages="eix \
                  mdadm \
                  ufed"
        post_commands="eix-update;"
    fi

    if (echo $installation | grep cu_boot); then
        packages="${packages:-} \
                  cryptsetup \
                  dev-vcs/git \
                  lvm2"
    fi

    if (echo $installation | grep graphical); then
        pre_commands="\
            eselect profile set 12; \
            sed -i s:bindist:bindist\ -abi_x86_32: /etc/portage/make.conf; \
            sed -i s:mmx:mmx\ mmxext: /etc/portage/make.conf; \
            echo VIDEO_CARDS=nvidia >> /etc/portage/make.conf; \
            echo L10N=\"pl\" >> /etc/portage/make.conf; \
            mkdir -p /etc/portage/package.mask; \
            echo \>x11-drivers/nvidia-drivers-340.104 >> /etc/portage/package.mask/nvidia-drivers; \
            emerge gentoolkit gentoo-sources; \
            zcat /proc/config.gz > /usr/src/linux-\$(uname -r | cut -d- -f1)-gentoo/.config; \
            make -C /usr/src/linux-\$(uname -r | cut -d- -f1)-gentoo -j$(cat /proc/cpuinfo | grep processor | wc -l) modules; \
            make -C /usr/src/linux-\$(equery which gentoo-sources | cut -d- -f5 | rev | cut -d. -f2- | rev)-gentoo -j$(cat /proc/cpuinfo | grep processor | wc -l) modules_install; \
            emerge -uNDv world;"
        packages="$packages \
            xorg-x11 \
            plasma-desktop \
            sddm"
        post_commands="$post_commands \
            sed -i s:xdm:sddm: /etc/conf.d/xdm; \
            rc-update add xdm default; \
            depmod -a; \
            modprobe nvidia; \
            nvidia-xconfig; \
            useradd -p \"\" user; \
            gpasswd -a user wheel; \
            service xdm restart;"
    fi

    if (echo $installation | grep plasma_programs); then
        pre_commands="$pre_commands \
            mount -o remount,size=20G; \
            echo \>=dev-lang/python-2.7.12:2.7 sqlite > /etc/portage/package.use/firefox;"

        packages="\
            firefox \
            kde-apps/dolphin \
            kmix \
            systemsettings \
            yakuake"
    fi
    
    # plasma-meta
    if (echo $installation | grep virtualization); then
        packages="$packages \
            qemu"
    fi

            #app-emulation/docker \
            #"
#        post_commands="$post_commands \
#            rc-update add docker default;"


    if (echo $installation | grep wireless); then
        packages="$packages \
            wpa_supplicant"
        post_commands="$post_commands \
        rc-update add wpa_supplicant default;"
    fi
    
    if [ -n "${installation:-}" ]; then
        chroot "$destination" su -l -c "env-update; source /etc/profile; ${pre_commands:-} emerge $packages; $post_commands"
    fi
    
    cecho "green" "OK"
}

function install_os {
    destination="${1:-}"
    check_number_of_arguments "install_os" "$#" "1"
    check_if_argument_empty "$destination"
    
    cecho "default" "Would you like to install the (b)usybox system, (g)entoo from stage3?"
    local answer=""
    read answer
    while [ "$answer" != "b" -a "$answer" != "g" ]; do
        cecho "yellow" "Please enter a correct answer [(b)usybox/(g)entoo]"
        read answer
    done
    if [ "$answer" == "b" ]; then
        install_busybox "$destination"
    elif [ "$answer" == "g" ]; then
        install_gentoo "$destination"
    else
        cecho "red" "Something went wrong[answer ~= b|g], exiting!"
        exit_error
    fi
}

function mount_filesystems {
    verbose="yes"
    verbose "blue" "function mount_filesystems"
    
    cecho "-light_blue" "Mounting /dev, /proc, /sys filesystems..."

    if [ -f /etc/mtab ]; then
        run_command "mount -t devtmpfs none /dev" "[ -d /dev ]" "" "Mounting /dev" "fail_on_condition" "/dev"
        run_command "mkdir -p /dev/shm" "[ ! -d /dev/shm ]" "" "Creating /dev/shm directory" "fail_on_condition" "/dev/shm"
        run_command "mkdir -p /run/shm" "[ ! -d /run/shm ]" "" "Creating /run/shm directory" "fail_on_condition" "/run/shm"
        run_command "mount -o mode=1777 -t tmpfs shm /dev/shm" "[ -d /dev/shm ]" "" "Mounting /dev/shm" "fail_on_condition" "/dev/shm"
        run_command "mkdir /dev/pts" "[ ! -d /dev/pts ]" "" "" "fail_on_condition" "/dev/pts"
        run_command "mount -o gid=5 -t devpts devpts /dev/pts" "" "" "" "fail_on_condition" "/dev/pts"
        run_command "mount -t proc none /proc" "[ -d /proc ]" "" "Mounting /proc" "fail_on_condition" "/proc"
        run_command "mount -t sysfs none /sys" "[ -d /sys ]" "" "Mounting /sys" "fail_on_condition" "/sys"
    else
        cecho "red" "/etc/mtab not found, exiting!"
        exit_error
    fi

        if (cat /proc/cmdline | grep verbose); then
        verbose="yes"
    else
        verbose="no"
    fi

    if (cat /proc/cmdline |  grep debug); then
        debug="yes"
    else
        debug="no"
    fi


    cecho "green" "OK"
}

# checked
function list_keys {
    if [ "$#" == "1" ]; then
        local directory="${1:-}"
        check_if_argument_empty "$directory"
        if [ -n "$(ls -A $directory/ | sed 's/lost+found//')" ]; then
            cecho "light_blue" "Existing keys:"
            local key
            for key in $(ls -1 $directory | sed 's/lost+found//'); do
                cecho "yellow" "$key"
                cecho "yellow" "$(ls -1 $directory/$key)\n"
            done
        else
            cecho "yellow" "No keys found in $directory directory."
        fi
    else
        cecho "red" "Please set the \"directory\" arguments for \"list_keys\" function properly and try again, exiting!"
        exit_error
    fi
}

function mount_home {
    local vg_lv="${1:-}"
    verbose "blue" "function mount_home [VG/LV: $vg_lv]"

    check_if_argument_empty "$vg_lv"

    cecho "-light_blue" "Checking the home filesystem integrity..."
    #if (fsck.ext4 /dev/"$vg_lv"); then
    #    cecho "green" "OK"
    #else
    #    cecho "default" "Filesystem integrity check has failed, would you like to recreate from backup?[no/yes]"
#        get_answer  # check
#        restore_root "${vg_lv}_backup" "$vg_lv" "yes"
#        mount_root "$@"
    #fi
    if (mountpoint /home 1>&3 2>&4); then
        verbose "blue" "/home already mounted, skipping"
    else
	run_command "DM_DISABLE_UDEV=1 lvm lvchange -ay $vg_lv" "[ ! -b /dev/$vg_lv ]" "" "Activating $vg_lv" "do_not_fail_on_condition" ""
	mount /dev/"$vg_lv" /home
    fi
}

function mount_root {
    local lv="${1:-}"
    local mount_dir="$(echo $lv | sed s:/:-:)"
    verbose "blue" "function mount_root [LV: $lv, mount_dir: $mount_dir]"

    check_if_argument_empty "$lv" "$mount_dir"

    if (mountpoint /mnt/"$mount_dir" 1>&3 2>&4); then
        cecho "-yellow" "/mnt/$mount_dir already mounted, skipping..."
    else
        mount_dev /dev/mapper/"$mount_dir"
        if [ ! -f "/mnt/$mount_dir/sbin/init" ]; then
            cecho "default" "Operating System(OS) not found."
            install_os "/mnt/$mount_dir"
        fi
        if [ -f "/mnt/$mount_dir/back_up" ]; then
            back_up_root
        fi
        if [ -f "/mnt/$mount_dir/restore" ]; then
            cecho "default" "/restore file exists, would you like to restore from backup?[no/yes]"
            get_answer
            if [ "$answer" == "yes" ]; then
                restore_root
            else
                cecho "yellow" "Deleting /restore and skipping."
                run_command "/mnt/laptop-root/restore" "[ -f /mnt/laptop-root/restore ]" "Failed to delete /mnt/laptop-root/restore" "Deleting /mnt/laptop-root/restore" "fail_on_condition" ""
            fi
       fi
    fi
}

function open_devices {
    verbose "blue" "function open_devices"

    if [ -z "$(ls $keys_dir)" ]; then
        cecho "default" "No keys found in initramfs, would you like to generate some? Otherwise the storage options will be limited to volatile Random Access Memory(RAM) only.[no/yes]"
        get_answer
        if [ "$answer" == "no" ]; then
            ram_only=1
        elif [ "$answer" == "yes" ]; then
            while get_dev_name "$serial_keys" 1>&3 2>&4; [ ! -b "$(eval echo \${dev_$serial_keys:-})" ]; do
                cecho "yellow" "Please insert the device with serial \"$serial_keys\" to continue..."
                sleep 3
            done
            open_luks "$serial_keys"
            mount_dev "/dev/mapper/$serial_keys"
            gen_keys "$serial_keys" ""
            ./cu_boot.sh
        fi
    else
        local serial
        for serial in $(ls $keys_dir); do
            get_dev_name "$serial"
            if [ -b "$(eval echo \${dev_$serial:-})" ]; then
                cecho "-light_blue" "Attempting to open $(eval echo \${dev_$serial:-}) with serial $serial..."
                open_luks "$keys_dir/$serial/$serial"
                run_command "cryptsetup luksOpen --header $keys_dir/$serial/$serial.header --key-file /dev/mapper/key_$serial \$dev_$serial $serial" "[ -b \$dev_$serial ]" "Failed to open \$dev_$serial $serial using $keys_dir/$serial" "Openning device \$dev_$serial $serial using $keys_dir/$serial" "fail_on_condition" ""
                cecho "green" "OK"
            else
                cecho "yellow" "Device with serial $serial doesn't exist, skipping."
            fi
        done
    fi
}

# checked
function mount_dev {
    local devices_mountpoints="$@"
    verbose "blue" "function mount_dev [devices_mountpoints: $devices_mountpoints]"
    check_if_argument_empty "$devices_mountpoints"

    for device_mountpoint in $devices_mountpoints; do
        if [ -d "/mnt/$serial_keys/$device_mountpoint" ]; then
            local key="$device_mountpoint"
            cecho "-light_blue" "Mounting $key key at /usr/src/linux-$arch/initramfs/$keys_dir/$key..."
            run_command "mkdir /usr/src/linux-$arch/initramfs/$keys_dir/$key" "[ ! -d /usr/src/linux-$arch/initramfs/$keys_dir/$key ]" "Failed to create /usr/src/linux-$arch/initramfs/$keys_dir/$key directory, exiting!" "Creating /usr/src/linux-$arch/initramfs/$keys_dir/$key directory" "fail_on_condition" "/usr/src/linux-$arch/initramfs/$keys_dir/$key"
            run_command "mount -o bind /mnt/$serial_keys/$key /usr/src/linux-$arch/initramfs/$keys_dir/$key" "[ -d /usr/src/linux-$arch/initramfs/$keys_dir/$key ]" "Failed to mount /mnt/$serial_keys/$key at /usr/src/linux-$arch/initramfs/$keys_dir/$key directory, exiting!" "Mounting /mnt/$serial_keys/$key at /usr/src/linux-$arch/initramfs/$keys_dir/$key" "fail_on_condition" "/usr/src/linux-$arch/initramfs/$keys_dir/$key"
        elif eval [ -b "$device_mountpoint" ]; then
            local device="$device_mountpoint"
            if [ "$device" == "/dev/mapper/$(eval basename \${dev_$serial_boot:-}1)" ]; then
                mount_point="/boot"
            else
                eval local mount_point="/mnt/${device##*/}"
            fi
            cecho "-light_blue" "Mounting $device at $mount_point..."
            run_command "mkdir $mount_point" "[ ! -d $mount_point ]" "Failed to create $mount_point directory, exiting!" "Creating $mount_point directory" "do_not_fail_on_condition" "$mount_point"
            if (eval mount $device $mount_point 1>&3 2>&4); then
                if [ "${device##*/}" != "laptop-root" ]; then
                    check_status "" "$mount_point"
                fi
            else
                cecho "red" "FAILED"
                cecho "yellow" "Failed, device $device not formatted!"
                format_dev "$device" ""
                cecho "green" "OK"
                mount_dev "$device" ""
            fi
        else
            cecho "red" "$device_mountpoint not found, exiting!"
            exit_error
        fi
        cecho "green" "OK"
        done
}

function mount_ramdisk {
    if [ "$#" == "2" ]; then
        local mountpoint="$1"
        local size="$2"
        verbose "blue" "function mount_ramdisk [moutpoint: $mountpoint, size: $size]"
        check_if_argument_empty "$mountpoint" "$size"
    
        cecho "-light_blue" "Mounting $size RAMdisk at $mountpoint..."
        if [ ! -d $mountpoint ]; then
            run_command "mkdir $mountpoint" "[ ! -d $mountpoint ]" "Failed to create $mountpoint directory, exiting!" "Creating $mountpoint directory" "fail_on_condition" "$mountpoint"
        fi
        if [ "$size" == "ramfs" ]; then
            run_command "mount -t ramfs ramfs $mountpoint" "[ -d $mountpoint ]" "Failed to mount $size RAMdisk at $mountpoint, exiting!" "Mounting $size RAMdisk at $mountpoint" "fail_on_condition" "$mountpoint"
        else
            run_command "mount -o size=$size -t tmpfs tmpfs $mountpoint" "[ -d $mountpoint ]" "Failed to mount $size RAMdisk at $mountpoint, exiting!" "Mounting $size RAMdisk at $mountpoint" "fail_on_condition" "$mountpoint"
        fi
        cecho "green" "OK"
    else
        cecho "red" "[ $# != 2 ]\nPlease set the arguments for \"mount_ramdisk\" function properly and try again, exiting!"
    fi
}

# checked
function open_luks {
    local serials_devices_keys="$@"
    verbose "blue" "function open_luks [serials_devices_keys: $serials_devices_keys]"
    check_if_argument_empty "$serials_devices_keys"

    check_for_program "cryptsetup --version"

    local serial_device_key
    for serial_device_key in $serials_devices_keys; do
        if [ "${serial_device_key:0:5}" == /dev/ ]; then
            local device="$serial_device_key"
            local name=$(basename $device)
        elif [ -f "$serial_device_key" ]; then
            local device="$serial_device_key"
            local name=key_$(basename $device)
            local cryptsetup_opts="--key-file=${device}.key"
        elif [ -n "$serial_device_key" ]; then # improvement, -b on dev_$serial should be more appropriate
            local serial="$serial_device_key"
            local name="$serial"
            check_if_device_with_serial_exists "$serial"
            local device=$(eval echo \$dev_$serial)
        else
            cecho "red" "[ $serial_device_key:0:5 != /dev/ -a !-f $serial_device_key -a !=n $serial_device_key ]\nPlease specify the arguments for \"open_luks\" function properly and try again, exiting!"
            exit_error
        fi

        if (cryptsetup isLuks $device); then
            run_command "cryptsetup luksOpen ${cryptsetup_opts:-} $device $name" "[ ! -b /dev/mapper/$name ]" "Could not open $device, exiting!" "" "fail_on_condition" "/dev/mapper/$name"
        else
            if [ "$hardened" == "yes" ]; then
                erase_dev "$device"
            fi
            format_dev "$device" "luks"
            open_luks "$serial_device_key"
            if [ "$hardened" == "yes" ]; then
                erase_dev "/dev/mapper/$name"
            fi
        fi
    done
}

function prep_kernel_sources {
    local arch="${1:-}"
    verbose "blue" "function prep_kernel_sources [arch:$arch]"
    check_if_argument_empty "$arch"
    
    if [ ! -L /usr/src/linux-"$arch" ]; then
        verbose "blue" "/usr/src/linux/kernel-$arch symlink does not exist, checking for kernel sources"
        if [ -d /usr/src/linux ]; then
            verbose "blue" "kernel sources found in /usr/src/"
        else 
            cecho "red" "Missing /usr/src/linux symlink, please install kernel sources, exiting!"
            exit_error
        fi
        local kernel_dir=$(readlink /usr/src/linux)
        run_command "cp -Hr /usr/src/$kernel_dir /usr/src/$kernel_dir-$arch" "" "Copying kernel sources from /usr/src/$kernel_dir to /usr/src/$kernel_dir-$arch has failed!" "Kernel sources have been successfully copied from /usr/src/$kernel_dir to /usr/src/$kernel_dir-$arch" "do_not_fail_on_condition" ""
        run_command "ln -s /usr/src/$kernel_dir-$arch /usr/src/linux-$arch" "" "Creating /usr/src/linux-$arch symlink has failed!" "/usr/src/linux-$arch symlink has been created successfully" "do_not_fail_on_condition" ""
    fi
}

# checked
function run_command {
    if [ "$#" == "6" ]; then
        local command="${1:-}"
        local condition="${2:-}"
        local error_message="${3:-}"
        local message="${4:-}"
        local permissible="${5:-}"
        local resource="${6:-}"
    
        verbose "blue" "function run_command [command: $command, condition: $condition, error_message: $error_message, message: $message, permissible: $permissible, resource: $resource]"

        check_if_argument_empty "$command" "$permissible"

        if eval $condition 1>&3 2>&4; then
            if [ -z "$message" ]; then
                verbose "blue" "Executing command [$command]..."
            else
                verbose "blue" "$message..."
            fi
            if [ -z "$error_message" ]; then
                eval "$command"
                check_status "$command" "$resource"
            else
                eval "$command"
                check_status "$error_message" "$resource"
            fi
        else
            if [ "$permissible" == "fail_on_condition" ]; then
                cecho "red" "[ ! $condition ]\n Please set the \"condition\" argument for \"run-command\" function correctly and try again, exiting!"
                exit_error
            elif [ "$permissible" != "do_not_fail_on_condition" -a "$permissible" != "fail_on_condition" ]; then
                cecho "red" "[ $permissible != do_not_fail_on_condition -a $permissible != fail_on_condition ]\n Please set the \"condition\" argument for \"run-command\" function correctly and try again, exiting!"
                exit_error
            fi
        fi
    else
        cecho "red" "[ $# != 6 ]\nPlease set the arguments for \"run_command\" function properly and try again, exiting!"
    fi
}

function format_root {
    umount "/mnt/$root_dir"
    run_command "mkfs.ext4 -F /dev/mapper/$root_dir" "[ -b /dev/mapper/$root_dir ]" "" "Formatting /dev/mapper/$root_dir" "fail_on_condition" ""
    mount_dev "/dev/mapper/$root_dir"
}

function restore_root {
    verbose "blue" "function restore_root"
    local backup_dir="$(echo $backup_lv | sed s:/:-:)"
    local root_dir="$(echo $root_lv | sed s:/:-:)"
    check_lvm "no" "$backup_lv"

    check_for_program "lvm help"
    
    if ! mountpoint /mnt/"$backup_dir" 1>&3 2>&4; then
        mount_dev "/dev/mapper/$backup_dir"
    fi
    if [ -z "$(ls /mnt/$backup_dir | sed 's/lost+found//')" ]; then
        rm /mnt/"$root_dir"/restore
        cecho "red" "No backup found, exiting!"
        exit_error
    fi
    ls -1 /mnt/$backup_dir
    if [ -x /bin/tar -a -x /usr/bin/pigz ]; then
        cecho "red" "using parallel"
        local unpack_command="time /bin/tar x -I pigz -C /mnt/$root_dir -f"
    else
        local unpack_command="EXTRACT_UNSAFE_SYMLINKS=1 time tar x -C /mnt/$root_dir -j -f"
    fi
    local archive
    read archive
    until format_root; cecho "-light_blue" "Unpacking OS from $archive to /mnt/${root_dir}..."; $unpack_command /mnt/$backup_dir/$archive; do
#        ls -1 /mnt/$backup_dir | sed 's/.tar.bz2//'
        ls -1lh /mnt/$backup_dir
        read archive
    done
    if [ -f "/mnt/"$root_dir"/restore" ]; then
        rm /mnt/"$root_dir"/restore
    fi
    
    for dir in dev proc run sys; do
        if [ ! -d /mnt/$root_dir/$dir ]; then
            mkdir /mnt/$root_dir/$dir
        fi
    done
    
    if [ ! -c "/mnt/$root_dir/dev/console" ]; then
        mknod -m 600 /mnt/$root_dir/dev/console c 5 1
    fi
    
    cecho "green" "OK"
}

#function run_gentoo {
#    local destination="$1"

#    verbose "blue" "function run_gentoo"

#     run_command "wget -P /mnt/livedvd http://laptop/livedvd-amd64-multilib-20160704.iso" "" "Attempt to download livedvd iso has failed" "Downloading livedvd iso file..." "fail_on_condition" ""

#     run_command "mkdir /mnt/iso" "" "Failed to create /mnt/iso directory" "Creating /mnt/iso directory..." "fail_on_condition" ""
#     run_command "mount /mnt/livedvd/livedvd-amd64-multilib-20160704.iso /mnt/iso" "" "Failed to mount livedvd ISO at /mnt/iso" "Mounted livedvd ISO at /mnt/iso" "fail_on_condition" ""

#     run_command "mkdir /mnt/squashfs" "" "Failed to create /mnt/squashfs" "Created /mnt/squashfs" "fail_on_condition" ""
#     run_command "unsquashfs -f -d $destination /mnt/iso/image.squashfs" "" "Failed to mount squashfs image at /mnt/squashfs" "mounted squashfs image at /mnt/squashfs" "fail_on_condition" ""
#     umount /mnt/iso
#     rm /mnt/livedvd/livedvd-amd64-multilib-20160704.iso

    #/home
    #/tmp
#     cecho "red" "deleting password"
#     sed -i "s/*//" "$destination"/etc/shadow

#     cecho "red" "Copying resolv.conf"
#     cp /etc/resolv.conf "$destination"/etc/

#     ln -sv /proc/self/fd /dev/fd
#     cecho "red" "Mounting /dev  and /proc"
#     run_command "mount -o rbind /dev $destination/dev" "" "" "" "do_not_fail_on_condition" "$destination/dev/pts $destination/dev/shm $destination/dev"
#     run_command "mount -t proc none $destination/proc" "" "" "" "do_not_fail_on_condition" "$destination/proc"
#     run_command "mount -o bind /sys $destination/sys" "" "" "" "do_not_fail_on_condition" "$destination/sys"
    #mkdir $destination/dev/pts
    #mount -o gid=5 -t devpts devpts $destination/dev/pts

#     cecho "red" "chrooting"
#     echo "MAKEOPTS=\"-j$(cat /proc/cpuinfo | grep processor | wc -l) -l$(cat /proc/cpuinfo | grep processor | wc -l)\"" >> $destination/etc/portage/make.conf
#     echo "EMERGE_DEFAULT_OPTS=\"--jobs=$(cat /proc/cpuinfo | grep processor | wc -l) --load-average=$(cat /proc/cpuinfo | grep processor | wc -l) --with-bdeps y\"" >> $destination/etc/portage/make.conf
# 
#     chroot "$destination" su -l -c "\
#     env-update && \
#     source /etc/profile && \
#     rm -rf /usr/portage && \
#     wget -P /tmp http://192.168.1.72/portage-latest.tar.bz2 && \
#     tar -xvpf /tmp/portage-latest.tar.bz2 -C /usr && \
#     eselect profile set 12 && \
#     USE=\"symlink\" emerge =gentoo-sources-\$(uname -r | cut -d- -f1) && \
#     zcat /proc/config.gz > /usr/src/linux-\$(uname -r | cut -d- -f1)-gentoo/.config && \
#     make -C /usr/src/linux-\$(uname -r | cut -d- -f1)-gentoo -j$(cat /proc/cpuinfo | grep processor | wc -l) modules && \
#     make -C /usr/src/linux-\$(uname -r | cut -d- -f1)-gentoo -j$(cat /proc/cpuinfo | grep processor | wc -l) modules_install && \
#     echo \>x11-drivers/nvidia-drivers-340.104 >> /etc/portage/package.mask/nvidia-drivers && \
#     echo =media-libs/libepoxy-1.4.3 >> /etc/portage/package.mask/libepoxy && \
#     sed -i s:VIDEO_CARDS=.*:VIDEO_CARDS=nvidia:g /etc/portage/make.conf && \
#     sed -i s:bindist:bindist\ -abi_x86_32: /etc/portage/make.conf && \
#     emerge -C xf86-video-virtualbox && \
#     USE=\"-pax_kernel\" emerge nvidia-drivers && \
#     depmod -a && \
#     modprobe nvidia && \
#     nvidia-xconfig"
    
    #chroot "$destination" su -l -c "emerge eix qemu ufed wpa_supplicant"
    #cp /etc/wpa_supplicant/wpa_supplicant.conf "$destination"/etc/wpa_supplicant/
    #chroot $destination /bin/bash
# }

function set_variables {
    verbose="yes"
    debug="yes"
    
    if (echo $@ | grep verbose); then
        verbose="yes"
    else
        verbose="no"
    fi

    if (echo $@ | grep debug); then
        debug="yes"
    else
        debug="no"
    fi

    verbose "blue" "function set_variables"
    cecho "-light_blue" "Setting variables..."
    backup_lv="laptop/backup" # Uses the remaining size of the device by default
    backup_size="100%FREE"
    root_lv="laptop/root"
    root_size="10G" # in Gs
    # # #
    # Initrams configuration
    # # #
    hardened="no"
    http_server="192.168.0.1"
    initramfs_b43="yes"
    initramfs_dell_t7500_audio="yes"
    initramfs_dell_t7500_card_reader="yes"
    initramfs_uvc_camera="yes"
    initramfs_cryptsetup="yes"
    initramfs_curl="yes"
    initramfs_dns="yes"
    initramfs_dm_raid="yes"
    initramfs_docker="no"
    initramfs_fuse="yes"
    initramfs_kvm="yes"
    initramfs_lsblk="yes"
    initramfs_lspci="yes"
    initramfs_lsusb="yes"
    initramfs_lvm="yes"
    initramfs_mdadm="yes"
    initramfs_nv="yes"
    initramfs_pbzip2="yes"
    initramfs_pigz="yes"
    initramfs_r8169="yes"
    initramfs_raid1="yes"
    initramfs_raid6="yes"
    initramfs_rsync="yes"
    initramfs_sas="yes"
    initramfs_sdhci="no"
    initramfs_squashfs="no"
    initramfs_strace="no"
    initramfs_usb_tethering="no"
    initramfs_wireless="no"
    keys_dir="opt/keys"

    # # #
    # Installation values:
    # basic: cryptsetup eix syslog_ng ufed; eix-update; rc-update add syslog-ng default
    # virtualization: emerge docker mdadm pip qemu
    # wireless: emerge wpa_supplicant; cp ...wpa_supplicant.conf $destination
    # # #
#    installation="basic cu_boot virtualization wireless graphical plasma_programs" # check
    installation="basic" # check
    # # # # 
    # Serials:
    # 1TB: S2R8J9DC911615
    # 8GB tiny: 20CF302E23E4FCA0AC111014 # remove?
    # array_dell: 2fec9a94db6275a3ab7a767de94ead0b
    # array_NAS: 9e8b7725cef416e14243b25641b2f617
    # Doc: 797CE8BB
    # HP SSD: 161173400961
    # Rachel's doc: 1D225620 
    # Samsung SSD: S2R5NB0HC09645T
    # # #
    serial_1TB="S2R8J9DC911615"
    serial_array_Dell="e778723bfac446518fc157cd3cae10df"
    serial_array_NAS="9e8b7725cef416e14243b25641b2f617"
    serial_boot="200445277107FC827AE5"
    serial_keys_backup="1D225620"
    serial_keys="797CE8BB"
    serial_laptop="BTPR142000RB080BGN"
    serial_Samsung="S2R5NB0HC09645T"
    serial_samsung="S2R5NB0HC09645T"
#    mount -t sysfs sys /sys
#    if [ "$(cat /sys/devices/virtual/dmi/id/product_serial)" == "JG9SVF1" ]; then
        serial_root="BTPR142000RB080BGN"
#        cecho "red" "Vostro"
#    elif [ "$(cat /sys/devices/virtual/dmi/id/product_serial)" == "74GTTL1" ]; then
#        serial_root="S2R5NB0HC09645T"
#        cecho "red" "Dell"
#    else
#        exit_error
#    fi
#    umount /sys
#    initramfs_keys="$serial_1TB $serial_array_NAS $serial_Samsung $serial_laptop" # automate?

#    if [ "$(cat /sys/devices/virtual/dmi/id/product_name)" == "Vostro1510" ]; then
#        serial_root="BTPR142000RB080BGN"
#    elif [ "$(cat /sys/devices/virtual/dmi/id/product_name)" == "Precision WorkStation T7500  " ]; then
#        serial_root="S2R5NB0HC09645T"
#    else

#        cecho "red" "Please add the serial number of the root device in the \"set_variables\" function and try again, exiting!"
#        lsblk -o+serial
#        exit_error
#    fi

    initramfs_keys="$serial_1TB $serial_root $serial_samsung $serial_array_NAS" # automate?
    # # #
    # Networking
    # # #
    wired_devices_mask="eth"
    wireless_devices_mask="" # remove?
    

#    if [ "$@" != "" ]; then
#        true        
#    fi
    
    cecho "green" "OK"
}

# checked
function verbose {
    if [ "$#" == "2" ]; then
        local color="${1:-default}"
        local message="${2:-}"
        
        if [ "$verbose" == "yes" ]; then
            if [ "$color" == "blue" -o "$color" == "default" -o "$color" == "green" -o "$color" == "light_blue" -o "$color" == "red" -o "$color" == "yellow" -o  "$color" == "-blue" -o "$color" == "-default" -o "$color" == "-green" -o "$color" == "-light_blue" -o "$color" == "-red" -o "$color" == "-yellow" ]; then
                if [ -n "$message" ]; then
                    cecho "$color" "$message"
                else
                    cecho "red" "[ -n $message ]\nPlease set the \"message\" argument for \"verbose\" function properly and try again, exiting!"
                    exit_error
                fi
            else
                cecho "red" "[ $color != blue -a $color != default -a $color != green -a $color != light_blue -a $color != red -a $color != yellow -a  $color != -blue -a $color != -default -a $color != -green -a $color != -light_blue -a $color != -red -a $color != -yellow ]\nPlease set the \"color\" argument for \"verbose\" function properly and try again, exiting!"
                exit_error
            fi
        elif [ "$verbose" != "no" -a "$verbose" != "yes" ]; then
            cecho "red" "[ $verbose != no -a $verbose != yes ]\nPlease set the global \"verbose\" variable in \"set_variables\" function properly and try again, exiting!"
            exit_error
        fi
    else
        cecho "red" "[ $# != 2 ]\nPlease set the arguments for \"verbose\" function properly and try again, exiting!"
        exit_error
    fi
}

if [ "$0" == "/init" ]; then
    set_variables
    configure_terminal
    mount_filesystems
        if [ "$(cat /sys/devices/virtual/dmi/id/product_name)" == "Vostro1510" ]; then
        serial_root="BTPR142000RB080BGN"
    elif [ "$(cat /sys/devices/virtual/dmi/id/product_name)" == "Precision WorkStation T7500  " ]; then
        serial_root="S2R5NB0HC09645T"
    else
        cecho "red" "Please add the serial number of the root device in the \"set_variables\" function and try again, exiting!"
        lsblk -o+serial
        exit_error
    fi
        
install_busybox
    #init_array
    open_devices
    #init_net
    check_lvm "no" "$root_lv"
    mount_root "$root_lv"
    #mount_home "laptop/home"
    clean_up
    cp -r /lib/modules/$(uname -r) /mnt/laptop-root/lib/modules/
    if [ -x "/mnt/laptop-root/sbin/init" -a -d "/mnt/laptop-root/etc/init.d/" ]; then
        cecho "light_blue" "Starting Gentoo..."
        exec switch_root /mnt/laptop-root /sbin/init
    elif [ -f "/mnt/laptop-root/bin/busybox" ]; then
        cecho "light_blue" "Starting busybox..."
        exec switch_root /mnt/laptop-root /bin/busybox sh
    else
        cecho "light_blue" "Something went wrong, no init or busybox found, exiting!"
        exit_error
    fi
elif [ "$0" == "./cu_boot.sh" ]; then
    set_variables "$@"
    configure_terminal
    while ! [ "${1:-}" == "test" -o "${1:-}" == "test verbose" ]; do
        echo "Please select an operation to perform from the list and confirm with ENTER:"
        cecho "yellow" "a) Create a key"
        cecho "yellow" "i) Import a key"
        cecho "yellow" "r) Remove a key"
        cecho "yellow" "b) Backup keys"
        cecho "yellow" "l) List keys"
        cecho "yellow" "lb) List backup keys"
        cecho "yellow" "D) Erase device"
        cecho "yellow" "B) Erase the boot drive"
        cecho "yellow" "K) Erase the key drive"
        cecho "yellow" "Kb) Erase the key backup drive"
        cecho "yellow" "L) Create laptop boot drive"
        cecho "yellow" "N) Create NAS boot drive"
        cecho "yellow" "G) Install Gentoo"
        cecho "yellow" "q) Quit"
        read input
        case $input in
            a)  open_luks "$serial_keys"
                mount_dev "/dev/mapper/$serial_keys"
                gen_keys "$serial_keys" ""
                clean_up # checking
                ;;
            i)  open_luks "$serial_keys"
                mount_dev "/dev/mapper/$serial_keys"
                gen_keys "$serial_keys" ""
                clean_up
                ;;
            l)  open_luks "$serial_keys"
                mount_dev "/dev/mapper/$serial_keys"
                list_keys /mnt/"$serial_keys"
                clean_up
                ;;
            lb) open_luks "$serial_keys_backup"
                mount_dev "/dev/mapper/$serial_keys_backup"
                list_keys /mnt/"$serial_keys_backup"
                clean_up
                ;;
            r)  open_luks "$serial_keys"
                mount_dev "/dev/mapper/$serial_keys"
                del_key "$serial_keys"
                clean_up
                ;;
            b)  open_luks "$serial_keys_backup" "$serial_keys"
                mount_dev "/dev/mapper/$serial_keys_backup" "/dev/mapper/$serial_keys" # checking
                cecho "-light_blue" "Copying keys..."
                run_command "rsync -av --exclude lost+found /mnt/$serial_keys/ /mnt/$serial_keys_backup/" "[ -d /mnt/$serial_keys/ ] && [ /mnt/$serial_keys_backup/ ]" "Failed to copy keys!" "Copying keys..." "fail_on_condition" ""
                cecho "green" "OK"
                clean_up
                ;;
            L)  create_partitions "$serial_boot"
                open_luks $(eval echo \${dev_$serial_boot}1)
                mount_dev "/dev/mapper/$(eval basename \${dev_$serial_boot}1)"
                build_kernel "x86_64"
                if [ -f /etc/default/grub ]; then
                    if [ -z $(cat /etc/default/grub | grep "GRUB_ENABLE_CRYPTODISK=y") ]; then
                        echo updating grub
                        echo "GRUB_ENABLE_CRYPTODISK=y" >> /etc/default/grub;
                    fi
                else
                    install_package "grub"
                    echo "GRUB_ENABLE_CRYPTODISK=y" >> /etc/default/grub;
                    #cecho "Install grub!" "red"
                    #exit_error
                fi
                if (eval "grub-install \$dev_$serial_boot"); then cecho "green" "OK"; else cecho "red" "grub-install has failed, exiting!"; exit_error; fi
                if (grub-mkconfig -o /boot/grub/grub.cfg); then cecho "green" "config OK"; else cecho "red" "config has failed, exiting!"; exit_error; fi
                clean_up
                ;;
            N)  create_partitions "$serial_boot"
                open_luks $(eval echo \${dev_$serial_boot}1)
                mount_dev "/dev/mapper/$(eval basename \${dev_$serial_boot}1)"
                build_kernel "arm"
                if (eval "grub-install \$dev_$serial_boot"); then echo ok; else echo grub-install has failed; clean_up; fi
                if (grub-mkconfig -o /boot/grub/grub.cfg); then echo config ok; else echo config has failed; clean_up; fi
                clean_up
                ;;
            G)  echo -e "Please choose device from the list:\n$(lvm lvs --noheadings -olv_full_name,size 2>/dev/null)"
                read device
                while (! lvm lvs $device &> /dev/null); do
                    cecho "yellow" "$device not found, please try again"
                    read device
                done
                if [ ! -b "/dev/$device" ]; then
                    DM_DISABLE_UDEV=1 lvm lvchange -ay "$device"
                fi
                format_dev "/dev/$device" ""
                mount_dev "/dev/mapper/$(echo $device | sed s:/:-:)"
                install_gentoo "/mnt/$(echo $device | sed s:/:-:)"
                unset device
                clean_up
                ;;
            D)  erase_dev "choose"
                ;;
            B)	check_if_device_with_serial_exists "$serial_boot"
                erase_dev $(eval echo \$dev_$serial_boot)
                ;;
            K)	check_if_device_with_serial_exists "$serial_keys"
                erase_dev $(eval echo \$dev_$serial_keys)
                ;;
            Kb)	check_if_device_with_serial_exists "$serial_keys_backup"
                erase_dev $(eval echo \$dev_$serial_keys_backup)
                ;;
            q) 	exit
                ;;
            *)	cecho "yellow" "Please choose a valid option from the list!"
                ;;
        esac
    done
    if [ "${1:-}" == "test" -o "${1:-}" == "test verbose" ]; then
        build_kernel "x86_64"
        clean_up
        check_for_program "qemu-system-x86_64 --version"
        qemu-system-x86_64 -kernel kernel+initramfs
        rm kernel+initramfs
    fi
else
    cecho "red" "Please execute as ./cu_boot or /init, exiting!"
fi
