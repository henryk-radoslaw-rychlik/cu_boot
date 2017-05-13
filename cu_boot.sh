#!/bin/bash

# add bash script usage
# add colors for verbose

function build_kernel {
    verbose "function build_kernel[$(echo $@)]"
    
    kernel_type="$1"

    laptop_kernel_config="x86_64_defconfig"
    initramfs_source="CONFIG_INITRAMFS_SOURCE=\"/usr/src/$(readlink /usr/src/linux)-$kernel_type/initramfs\"
CONFIG_INITRAMFS_ROOT_UID=0
CONFIG_INITRAMFS_ROOT_GID=0"
laptop_config="$initramfs_source"
#    if [ "$2" == "update" ]; then echo "Updating the kernel..."; verbose "Deleting /usr/src/linux-$1 and /usr/src/linux-*-$1"; rm /usr/src/linux-$1; rm -r /usr/src/linux-*-$1; fi

    if [ ! -L /usr/src/linux-"$kernel_type" ]; then
        if [ -d /usr/src/linux ]; then kernel_dir=$(readlink /usr/src/linux); verbose "$kernel_dir has been found"; else echo "/usr/src/linux is missing. Please install kernel sources"; clean_up; fi
            verbose "Creating $kernel_dir-$kernel_type directory"
            mkdir /usr/src/$kernel_dir-"$kernel_type"
            verbose "Updating kernel-NAS symlink"
            ln -s /usr/src/$kernel_dir-"$kernel_type" /usr/src/linux-"$kernel_type"
            verbose "Copying $kernel_dir to $kernel_dir-$kernel_type"
            set +f
            cp -r /usr/src/$kernel_dir/* /usr/src/$kernel_dir-$kernel_type
            set -f
        fi

    kernel_dir=$(readlink /usr/src/linux)
    create_initramfs "laptop"
    echo "Building the kernel..."
    verbose "Configuring $kernel_dir-$kernel_type"
    make -C /usr/src/$kernel_dir-$kernel_type x86_64_defconfig
    echo -e "$laptop_config" >> /usr/src/$kernel_dir-$kernel_type/.config
    make -C /usr/src/$kernel_dir-$kernel_type -j 5 bzImage 
    make -C /usr/src/$kernel_dir-$kernel_type install
    sleep 1
}

function cecho {
    local color=${2:-default}
    local message="${1:-}"
            
    local blue="\e[034m"
    local default="\e[0m"
    local green="\e[032m"
    local light_blue="\e[094m"
    local red="\e[031m"
    local yellow="\e[033m"
    
    if [ -n "$message" ]; then
        if [ "$color" == "-b" ]; then
            eval "echo -e -n \${blue}${message}\$default"
        elif [ "$color" == "-d" ]; then
            eval "echo -e -n \$message"
        elif [ "$color" == "-g" ]; then
            eval "echo -e -n \${green}${message}\$default"
        elif [ "$color" == "-lb" ]; then
            eval "echo -e -n \${light_blue}${message}\$default"
        elif [ "$color" == "-r" ]; then
            eval "echo -e -n \${red}${message}\$default"
        elif [ "$color" == "-y" ]; then
            eval "echo -e -n \${yellow}${message}\$default"
        elif [ "$color" == "blue" -o "$color" == "green" -o "$color" == "light_blue" -o "$color" == "red" -o "$color" == "yellow" ]; then
            eval "echo -e \${$color}${message}\$default"
        elif [ "$color" == "default" ]; then
            eval "echo -e $message"
        else
            cecho "no color has been specified, exiting!" "red"
            exit 1
        fi
    else
        cecho "No message has been specified, exiting!" "red"
        exit 1
    fi
}

function check_status {
    local status="$?"
    local error_message="${2:-}"
    local resource="${1:-}"
    
    verbose "function check_status [error_message: $error_message, resource: $resource, status: $status]" "blue"
    
    if [ "$status" == "0" ]; then
        verbose "OK" "green"
        if [ -n "$resource" ]; then
            verbose "Adding $resource to the clean_up list" "blue"
            resources_to_clean=$(echo "$resource ${resources_to_clean:-}")
        fi
    else
        if [ -z "$error_message" ]; then
            cecho "Failed, exiting!" "red"
        else
            cecho "$error_message" "red"
        fi
        exit 1
    fi
}

function check_for_program {        
    local program=${1:-}
    verbose "function check_for_program [program: $(echo $program | cut -f1 -d " ")]" "blue"
    
    run_command "$program &> /dev/null" "" "Checking for $(echo $program | cut -f1 -d ' ')" "0" ""
}

	function check_if_empty {
        local arguments="${@:-}"
        
        verbose "function check_if_empty [arguments: $arguments]" "blue"
        
        if [ -n "$arguments" ]; then
            local argument
            for argument in "$arguments"; do
                if [ -z "$argument" ]; then
                    verbose "Argument empty, exiting!" "red"
                    exit 1
                fi
            done
        else
            verbose "arguments empty, exiting!" "red"
            exit 1
        fi
	}


function clean_up {
    verbose "function clean_up"
    
    until [ -z $(echo ${resources_to_clean:-} | tr -d " ") ]; do
        verbose "Resources to clean:${resources_to_clean:-}" "blue"
        for resource in ${resources_to_clean:-}; do
            if (mountpoint "$resource" &> /dev/null); then
                if [ "$resource" != "/mnt/laptop-root" ] && [ "$resource" != "/mnt/livedvd" ]; then
                    verbose "[umount $resource]" "-b"
                    umount "$resource"
                    check_status
                    resources_to_clean=$(echo "${resources_to_clean:-}" | sed s:"$resource::")
                else
                    resources_to_clean=$(echo "${resources_to_clean:-}" | sed s:"$resource::")
                fi
            elif [ -d "$resource" ]; then
                if [ "$resource" != "/boot" ]; then
                    verbose "[rmdir $resource]" "-b"
                    rmdir "$resource"
                    check_status
                    resources_to_clean=$(echo "${resources_to_clean:-}" | sed s:"$resource::")
                fi
            elif (cryptsetup status /dev/mapper/$(basename "$resource") &> /dev/null); then
                if [ "$resource" != "/dev/mapper/$serial_root" ]; then
                    verbose "cryptsetup close $resource" "-b"
                    cryptsetup close /dev/mapper/$(basename "$resource")
                    check_status
                    resources_to_clean=$(echo "${resources_to_clean:-}" | sed s:"$resource::")
                else
                    resources_to_clean=$(echo "${resources_to_clean:-}" | sed s:"$resource::")
                fi
            elif [ $(ps aux | grep $resource | wc -l) -ge "2" ]; then
                verbose "killing $resource" "-b"
                killall $resource
                check_status
                resources_to_clean=$(echo "${resources_to_clean:-}" | sed s:"$resource::")
            elif [ -n "$(ifconfig | grep $resource)" ]; then
                run_command "ifconfig $resource down" "" "Bringing $resource down" "0" ""
                resources_to_clean=$(echo "${resources_to_clean:-}" | sed s:"$resource::")                
            else
                verbose "Cleaning up $resource has failed!" "red"
            fi
        done
    done
}

function configure_terminal {
    verbose "function configure_terminal" "blue"
    cecho "Configuring terminal..." "-lb"

    run_command "set -o errexit" "" "Setting -o errexit" "0" ""
    run_command "set -o noglob" "" "Setting -o noglob" "0" ""
    run_command "set -o nounset" "" "Setting -o nounset" "0" ""
    run_command "set -o pipefail" "" "Setting -o pipefail" "0" ""
    
    if [ "$debug" == "yes" ]; then
        run_command "set -o verbose" "" "Setting -o verbose" "0" ""
    fi

    run_command "trap exit_trap EXIT" "" "Setting up EXIT trap" "0" ""
    cecho "OK" "green"
}

function create_dirs {
    verbose "function create_dirs"
    
    dirs="$@"
    
	for directory in $dirs; do
        if [ -d "$initramfs_temp$directory" ]; then
            verbose "Directory $initramfs_temp$directory already exists, skipping" "blue"
        else
            verbose "Creating directory $initramfs_temp$directory" "-b"
            mkdir "$initramfs_temp""$directory"
            check_status
        fi
    done
}

function create_initramfs {
    verbose "function create_initramfs[$(echo $@)]"
    
    #initramfs_dirs="/bin /dev /etc  /lib /lib/firmware /lib64 /mnt /mnt/root /proc /run /sbin /sys /usr/bin /usr/lib64 /usr/share /usr/share/udhcpc /var /var/www /var/www/cgi-bin"
    local initramfs_dirs="/bin /dev /etc /mnt /mnt/ /proc /sbin /sys"
    #initramfs_files="/etc/shadow /sbin/dhclient /bin/bash /bin/dd /bin/echo /bin/lsblk /bin/nano /sbin/cryptsetup /sbin/lvm /sbin/mdadm /usr/bin/mc /usr/bin/strace /usr/bin/curl  /lib/ld-linux.so.3 /lib/libc.so.6  /lib64/libresolv.so.2"
    local initramfs_files="/bin/busybox /usr/bin/sg_vpd /bin/dd /sbin/mkfs.ext4"
    
    if [ "$initramfs_internet" == "yes" ]; then
        # network/internet/DNS
        local initramfs_dirs=$(echo "$initramfs_dirs /lib64 /usr /usr/share /usr/share/udhcpc") 
        local initramfs_files=$(echo "$initramfs_files /etc/host.conf /etc/hosts /etc/ld.so.cache /etc/nsswitch.conf /etc/resolv.conf /lib64/libnss_dns.so.2 /lib64/libnss_files.so.2 /usr/share/udhcpc/default.script")
        
        # wpa_supplicant
        local initramfs_dirs=$(echo "$initramfs_dirs /etc/wpa_supplicant /lib /lib/firmware /usr /usr/lib64 /usr/sbin") 
        local initramfs_files=$(echo "$initramfs_files /etc/wpa_supplicant/wpa_supplicant.conf /lib/firmware/iwlwifi-6000g2a-5.ucode /lib/firmware/mt7601u.bin /usr/sbin/wpa_supplicant")
        
        laptop_config=$(echo -e "$laptop_config\nCONFIG_IWLWIFI=y\nCONFIG_IWLDVM=y\nCONFIG_IWLMVM=n\nCONFIG_IWLWIFI_DEBUG=n\nCONFIG_IWLWIFI_DEVICE_TRACING=n\nCONFIG_MT7601U=y")
        
        #squashfs
        laptop_config=$(echo -e "$laptop_config\nCONFIG_SQUASHFS=y\nCONFIG_SQUASHFS_FILE_CACHE=y\nCONFIG_SQUASHFS_FILE_DIRECT=n\nCONFIG_SQUASHFS_DECOMP_SINGLE=y\nCONFIG_SQUASHFS_DECOMP_MULTI=n\nCONFIG_SQUASHFS_DECOMP_MULTI_PERCPU=n\nCONFIG_SQUASHFS_XATTR=y\nCONFIG_SQUASHFS_ZLIB=y\nCONFIG_SQUASHFS_LZ4=y\nCONFIG_SQUASHFS_LZO=y\nCONFIG_SQUASHFS_XZ=y\nCONFIG_SQUASHFS_4K_DEVBLK_SIZE=y\nCONFIG_SQUASHFS_EMBEDDED=n")        
    fi

    if [ "$initramfs_tools" == "yes" ]; then
        # cryptsetup
        local initramfs_dirs=$(echo "$initramfs_dirs /lib64 /sbin /usr/ /usr/lib64") 
        local initramfs_files=$(echo "$initramfs_files /sbin/cryptsetup")
        laptop_config=$(echo -e "$laptop_config\nCONFIG_CRYPTO_XTS=y\nCONFIG_DM_CRYPT=y")

        # curl
        local initramfs_dirs=$(echo "$initramfs_dirs /lib64 /usr/ /usr/bin /usr/lib64") 
        local initramfs_files=$(echo "$initramfs_files /usr/bin/curl")

        # KVM
        laptop_config=$(echo -e "$laptop_config\nCONFIG_KVM=y\nCONFIG_KVM_INTEL=y\nCONFIG_KVM_AMD=n\nCONFIG_KVM_MMU_AUDIT=n\nCONFIG_KVM_DEVICE_ASSIGNMENT=n\nCONFIG_VHOST_NET=y\nCONFIG_TUN=y\nCONFIG_BRIDGE=y\nCONFIG_BRIDGE_NF_EBTABLES=n\nCONFIG_BRIDGE_IGMP_SNOOPING=y")

        # lsblk
        local initramfs_dirs=$(echo "$initramfs_dirs /lib64") 
        local initramfs_files=$(echo "$initramfs_files /bin/lsblk")
        
        # lspci
        local initramfs_dirs=$(echo "$initramfs_dirs /etc/udev /usr /usr/sbin /usr/share /usr/share/misc") 
        local initramfs_files=$(echo "$initramfs_files /etc/udev/hwdb.bin /usr/sbin/lspci /usr/share/misc/pci.ids /usr/share/misc/pci.ids.gz")
        
        # lsusb
        local initramfs_dirs=$(echo "$initramfs_dirs /etc/udev /usr /usr/bin/ /usr/share /usr/share/misc")
        local initramfs_files=$(echo "$initramfs_files /etc/udev/hwdb.bin /usr/bin/lsusb /usr/share/misc/pci.ids /usr/share/misc/pci.ids.gz")
        
        # lvm
        local initramfs_dirs=$(echo "$initramfs_dirs /lib64")
        local initramfs_files=$(echo "$initramfs_files /sbin/lvm")

        # SAS
        laptop_config=$(echo -e "$laptop_config\nCONFIG_FUSION=y\nCONFIG_FUSION_SPI=y\nCONFIG_FUSION_SAS=y\nCONFIG_FUSION_MAX_SGE=128\nCONFIG_FUSION_CTL=y\nCONFIG_FUSION_LOGGING=y")

        # strace
        local initramfs_dirs=$(echo "$initramfs_dirs /usr /usr/bin") 
        local initramfs_files=$(echo "$initramfs_files /usr/bin/strace")
    fi
    
    local initramfs_temp="/usr/src/$(readlink /usr/src/linux)-$kernel_type/initramfs"

    mount_dev "$initramfs_temp" "100M"
	create_dirs "$initramfs_dirs"
	
    if [ "$initramfs_include_keys" == "yes" ]; then
        create_dirs "/opt /opt/keys"
        open_luks "$serial_keys" "serial"
        mount_dev "$serial_keys"
        mount_dev "$serial_root"
    fi

    if [ -c "$initramfs_temp"/dev/console ]; then
        verbose "$initramfs_temp/dev/console already exists!" "red"
    else
        verbose "Creating $initramfs_temp/dev/console" "-b"
        mknod -m 600 "$initramfs_temp"/dev/console c 5 1
        check_status
    fi

    if [ -f "$initramfs_temp"/etc/mtab ]; then
        verbose "$initramfs_temp/etc/mtab already exists!" "red"
    else
        verbose "Creating $initramfs_temp/etc/mtab" "-b"
        touch "$initramfs_temp"/etc/mtab
        check_status
    fi

    
	verbose "Creating $initramfs_temp/init" "-b"
	echo '#!/bin/busybox sh
	
function cecho {
    local color=${2:-default}
    local message="${1:-}"
            
    local blue="\e[034m"
    local default="\e[0m"
    local green="\e[032m"
    local light_blue="\e[094m"
    local red="\e[031m"
    local yellow="\e[033m"
    
    if [ -n "$message" ]; then
        if [ "$color" == "-b" ]; then
            eval "echo -e -n \${blue}${message}\$default"
        elif [ "$color" == "-d" ]; then
            eval "echo -e -n \$message"
        elif [ "$color" == "-g" ]; then
            eval "echo -e -n \${green}${message}\$default"
        elif [ "$color" == "-lb" ]; then
            eval "echo -e -n \${light_blue}${message}\$default"
        elif [ "$color" == "-r" ]; then
            eval "echo -e -n \${red}${message}\$default"
        elif [ "$color" == "-y" ]; then
            eval "echo -e -n \${yellow}${message}\$default"
        elif [ "$color" == "blue" -o "$color" == "green" -o "$color" == "light_blue" -o "$color" == "red" -o "$color" == "yellow" ]; then
            eval "echo -e \${$color}${message}\$default"
        elif [ "$color" == "default" ]; then
            eval "echo -e $message"
        else
            cecho "no color has been specified, exiting!" "red"
            exit 1
        fi
    else
        cecho "No message has been specified, exiting!" "red"
        exit 1
    fi
}

function check_if_empty {
        local arguments="${@:-}"
        
        verbose "function check_if_empty [arguments: $arguments]" "blue"
        
        if [ -n "$arguments" ]; then
            local argument
            for argument in "$arguments"; do
                if [ -z "$argument" ]; then
                    verbose "Argument empty, exiting!" "red"
                    exit 1
                fi
            done
        else
            verbose "arguments empty, exiting!" "red"
            exit 1
        fi
	}
	
function check_for_program {        
    local program=${1:-}
    verbose "function check_for_program [program: $(echo $program | cut -f2 -d " ")]" "blue"
    
    run_command "$program &> /dev/null" "" "Checking for $(echo $program | cut -f1 -d '"'"' '"'"')" "0" ""
}

function mount_root {
    local vg_lv="${1:-}"
    verbose "function mount_root [VG/LV: $vg_lv]"
    
    check_if_empty "$vg_lv"
    
    cecho "Checking the root filesystem integrity" "-lb"
    if (fsck /dev/"$vg_lv"); then
        cecho "OK" "green"
    else
        cecho "Filesystem integrity check has failed, would you like to re-create from backup?[no/yes]" "default"
        get_answer
        run_command "restore_root $vg_lv ${vg_lv}_backup yes" "[ $answer == yes ]" "Restoring $vg_lv volume from ${vg_lv}_backup" "0" ""
        mount_root "$@"
	fi
	if (mountpoint /mnt/laptop-root); then
        verbose "/mnt/root already mounted, skipping" "blue"
    else
        mount_dev $(echo $vg_lv | sed s:/:-:)
    fi
}

function get_answer {
    answer=""
    while [ "${answer:-}" != "no" -a "${answer:-}" != "yes" ]; do
        cecho "Please choose the correct answer[no/yes]!" "red"
        read answer
    done
}

	function check_lvm {
        local vg_lv="${1:-}"
        
        verbose "function check_lvm [VG/LV: $vg_lv]" "blue"
        
        check_if_empty "$vg_lv"
        check_for_program "lvm help"
        
        cecho "Checking for LVM label on $serial_root" "-lb"
        if (lvm pvck /dev/mapper/"$serial_root"); then
            cecho "OK" "green"
            cecho "Checking for VG $(echo $vg_lv | cut -d / -f 1)" "-lb"
            if (lvm vgck $(echo $vg_lv | cut -d "/" -f 1) &> /dev/null); then
                cecho "OK" "green"
                cecho "Checking for LV $vg_lv" "-lb"
                if (lvm lvs $vg_lv); then
                    cecho "OK" "green"
                    run_command "lvm lvchange -ay $vg_lv &> /dev/null" "[ ! -b /dev/$vg_lv ]" "Activating $vg_lv" "permissive" ""
                else
                    cecho "root LV has not been found, would you like to re-create? [no/yes]" "default"
                    get_answer
                    run_command "lvm lvcreate -L25G -n $(echo $vg_lv | cut -d / -f 2) $(echo $vg_lv | cut -d / -f 1)" "[ $answer == yes ]" "Re-creating $(echo $vg_lv | cut -d / -f 2) LV on $(echo $vg_lv | cut -d / -f 1) VG" "0" ""
                    run_command "lvm lvcreate -L25G -n $(echo $vg_lv | cut -d / -f 2) $(echo ${vg_lv}backup | cut -d / -f 1)" "[ $answer == yes ]" "Re-creating $(echo $vg_lv | cut -d / -f 2) LV on $(echo $vg_lv | cut -d / -f 1) VG" "0" ""
                    check_lvm "$@"
                fi
            else
                cecho "$(echo $vg_lv | cut -d / -f 1) VG has not been found, would you like to re-create? [no/yes]" "default"
                get_answer
                run_command "lvm vgcreate $(echo $vg_lv | cut -d / -f 1) /dev/mapper/$serial_root" "[ $answer == yes ]" "Re-creating $(echo $vg_lv | cut -d / -f 1) VG on /dev/mapper/$serial_root" "0" ""
                check_lvm "$@"
            fi
        else
            local memory=$(free -m | head -n2 | tail -n1 | awk '"'"'{ print $4 }'"'"')
            if [ "$memory" -gt "2500" ]; then
                verbose "LVM label not found, more than 2500MiB system memory available $memory. Would you like to run Gentoo from a liveDVD, install it in a RAMdisk or re-create?[livedvd/ramdisk/re-create]" "default"
                local answer=""
                read answer
                while [ "${answer:-}" != "livedvd" -a "${answer:-}" != "ramdisk" -a "${answer:-}" != "re-create" ]; do
                    cecho "Please enter correct answer![livedvd/ramdisk/re-create]" "yellow"
                    read answer
                done
                if [ "$answer" == "livedvd" ]; then
                    mount_dev "/mnt/livedvd" "2500M"
                    run_gentoo "/mnt/root"
                elif [ "$answer" == "ramdisk" ]; then
                    mount_dev "/mnt/laptop-root" "2500M"
                    install_gentoo "/mnt/laptop-root"
                elif [ "$answer" == "re-create" ]; then
                    #erase_dev "$serial_root" "luks"
                    run_command "lvm pvcreate /dev/mapper/$serial_root" "[ -b /dev/mapper/$serial_root ]" "Creating LVM label on /dev/mapper/$serial_root" "0" ""
                    run_command "lvm vgcreate $(echo $vg_lv | cut -d / -f 1) /dev/mapper/$serial_root" "lvm pvck /dev/mapper/$serial_root" "Creating $(echo $vg_lv | cut -d / -f 1) VG on /dev/mapper/$serial_root" "0" ""
                    run_command "lvm lvcreate -L25G -n $(echo $vg_lv | cut -d / -f 2) $(echo $vg_lv | cut -d / -f 1)" "lvm vgck $(echo $vg_lv | cut -d / -f 1)" "Re-creating $(echo $vg_lv | cut -d / -f 2) LV on $(echo $vg_lv | cut -d / -f 1) VG" "0" ""
                    run_command "lvm lvcreate -L25G -n $(echo $vg_lv | cut -d / -f 2)_backup $(echo $vg_lv | cut -d / -f 1)" "lvm lvs $vg_lv" "Re-creating $(echo $vg_lv | cut -d / -f 2)_backup LV on $(echo $vg_lv | cut -d / -f 1) VG" "0" ""
                    check_lvm "$@"
                fi
            else
                verbose "LVM label not found, would you like to re-create?[no/yes]" "default"
                    get_answer
                    #erase_dev "$serial_root" "luks"
                    run_command "lvm pvcreate /dev/mapper/$serial_root" "[ -b /dev/mapper/$serial_root ]" "Creating LVM label on /dev/mapper/$serial_root" "0" ""
                    run_command "lvm vgcreate $(echo $vg_lv | cut -d / -f 1) /dev/mapper/$serial_root" "lvm pvck /dev/mapper/$serial_root" "Creating $(echo $vg_lv | cut -d / -f 1) VG on /dev/mapper/$serial_root" "0" ""
                    run_command "lvm lvcreate -L25G -n $(echo $vg_lv | cut -d / -f 2) $(echo $vg_lv | cut -d / -f 1)" "lvm vgck $(echo $vg_lv | cut -d / -f 1)" "Re-creating $(echo $vg_lv | cut -d / -f 2) LV on $(echo $vg_lv | cut -d / -f 1) VG" "0" ""
                    run_command "lvm lvcreate -L25G -n $(echo $vg_lv | cut -d / -f 2)_backup $(echo $vg_lv | cut -d / -f 1)" "lvm lvs $vg_lv" "Re-creating $(echo $vg_lv | cut -d / -f 2)_backup LV on $(echo $vg_lv | cut -d / -f 1) VG" "0" ""
                    check_lvm "$@"
            fi
        fi
    }
    
function check_status {
    local status="$?"
    local error_message="${2:-}"
    local resource="${1:-}"
    
    verbose "function check_status [error_message: $error_message, resource: $resource, status: $status]" "blue"
    
    if [ "$status" == "0" ]; then
        verbose "OK" "green"
        if [ -n "$resource" ]; then
            verbose "Adding $resource to the clean_up list" "blue"
            resources_to_clean=$(echo "$resource ${resources_to_clean:-}")
        fi
    else
        if [ -z "$error_message" ]; then
            cecho "Failed, exiting!" "red"
        else
            cecho "$error_message" "red"
        fi
        exit 1
    fi
}
    
function clean_up {
    verbose "function clean_up"
    
    until [ -z $(echo ${resources_to_clean:-} | tr -d " ") ]; do
        verbose "Resources to clean:${resources_to_clean:-}" "blue"
        for resource in ${resources_to_clean:-}; do
            if (mountpoint "$resource" &> /dev/null); then
                if [ "$resource" != "/mnt/laptop-root" ] && [ "$resource" != "/mnt/livedvd" ]; then
                    verbose "[umount $resource]" "-b"
                    umount "$resource"
                    check_status
                    resources_to_clean=$(echo "${resources_to_clean:-}" | sed s:"$resource::")
                else
                    resources_to_clean=$(echo "${resources_to_clean:-}" | sed s:"$resource::")
                fi
            elif [ -d "$resource" ]; then
                if [ "$resource" != "/boot" ]; then
                    verbose "[rmdir $resource]" "-b"
                    rmdir "$resource"
                    check_status
                    resources_to_clean=$(echo "${resources_to_clean:-}" | sed s:"$resource::")
                fi
            elif (cryptsetup status /dev/mapper/$(basename "$resource") &> /dev/null); then
                if [ "$resource" != "/dev/mapper/$serial_root" ]; then
                    verbose "cryptsetup close $resource" "-b"
                    cryptsetup close /dev/mapper/$(basename "$resource")
                    check_status
                    resources_to_clean=$(echo "${resources_to_clean:-}" | sed s:"$resource::")
                else
                    resources_to_clean=$(echo "${resources_to_clean:-}" | sed s:"$resource::")
                fi
            elif [ $(ps aux | grep $resource | wc -l) -gt "1" ]; then
                cecho "$(ps aux | grep $resource)" "red"
                verbose "killing $resource" "-b"
                killall $resource
                check_status
                while [ $(ps aux | grep $resource | wc -l) -gt "1" ]; do
                    cecho "waiting..." "red"
                    sleep 1
                done
                resources_to_clean=$(echo "${resources_to_clean:-}" | sed s:"$resource::g")
                cecho "$(ps aux | grep $resource)" "red"
            elif [ -n "$(ifconfig | grep $resource)" ]; then
                run_command "ifconfig $resource down" "" "Bringing $resource down" "0" ""
                resources_to_clean=$(echo "${resources_to_clean:-}" | sed s:"$resource::")                
            else
                verbose "Cleaning up $resource has failed!" "red"
                exit 1
            fi
        done
    done
}

    function configure_network {
        while [ -z $(ls /sys/class/net | grep $late_net_iface) ]; do
            verbose "Waiting for device $late_net_iface" "blue"
            sleep 1
        done
        
        local wired_device=$(ls /sys/class/net | grep eth)
        local wireless_device=$(ls /sys/class/net | grep wlan)
        
        verbose "function configure_network [net_devices: $(ls /sys/class/net), wired_device: $wired_device, wireless_device: $wireless_device]" "blue"

    	check_for_program "wpa_supplicant -v"
        
        if [ -n "$wireless_device" ] && [ -f /etc/wpa_supplicant/wpa_supplicant.conf ]; then
            run_command "wpa_supplicant -Dnl80211 -i$wireless_device -c/etc/wpa_supplicant/wpa_supplicant.conf &" "" "Starting wpa_supplicant" "0" "wpa_supplicant"
            run_command "udhcpc -i $wireless_device &>/dev/null &" "" "Starting udhcpc DHCP client on $wireless_device" " 0" "udhcpc"
        else
            verbose "device [$wireless_device] does not exist or configuration file missing, could not start wpa_supplicant" "yellow"
        fi
        
        if [ $(ps aux | grep udhcpc | wc -l) -lt "2" ]; then
            local udhcpc=udhcpc
        fi
        
        run_command "udhcpc -i $wired_device &>/dev/null &" "[ -n "$wired_device" ]" "Starting udhcpc DHCP client on $wired_device"  "0" "${udhcpc:-}"

}

function configure_terminal {
    verbose "function configure_terminal" "blue"
    cecho "Configuring terminal..." "-lb"

    run_command "set -o errexit" "" "Setting -o errexit" "0" ""
    run_command "set -o noglob" "" "Setting -o noglob" "0" ""
    run_command "set -o nounset" "" "Setting -o nounset" "0" ""
    run_command "set -o pipefail" "" "Setting -o pipefail" "0" ""
    
    if [ "$debug" == "yes" ]; then
        run_command "set -o verbose" "" "Setting -o verbose" "0" ""
    fi

    run_command "trap exit_trap EXIT" "" "Setting up EXIT trap" "0" ""
    cecho "OK" "green"
}
        
function verbose {
    local color=${2:-default}
    local message="${1:-}"

    if [ "$verbose" == "yes" ]; then
        cecho "$message" "$color"
    elif [ "$verbose" != "no" ] && [ "$verbose" != "yes" ]; then
        cecho "verbose not set to [no/yes], exiting!" "red"
        exit 1
    fi
}

     function erase_dev {
        local serial="${1:-}"
        local type="${2:-}"
        
        verbose "function erase_dev [serial: $serial, type: $type]" "blue"

        check_if_empty "$serial"
        
        if [ "$hardened" == "yes" ]; then
            verbose "hardened=yes, using /dev/urandom" "blue"
            local source=/dev/urandom
        elif [ "$hardened" == "no" ]; then
            verbose "hardened=no, using /dev/zero" "blue"
            local source=/dev/zero
        else
            cecho "hardened variable not set to [no/yes], exiting!" "red"
            exit 1
        fi

        get_dev_geometry "$serial"

        if [ "$type" == "luks" ]; then
            local device=/dev/mapper/$serial
        else
            local device=$(eval "echo /dev/\$dev_$serial")
        fi
        
        verbose "using device $device" "blue"
        
        check_for_program "/bin/dd --version"
        
        if (dd count=1 if=/dev/zero of=/dev/null status=progress &> /dev/null); then
            local dd_opts="status=progress"
        fi
        cecho "About to erase $device, please confirm with [ENTER]" "yellow"
        read
        cecho "Erasing device $device with $(eval echo \$sector_count_$serial) 512B sectors using $source..." "blue"
#        run_command "/bin/dd if=$source of=$device bs=512 count=\$sector_count_$serial ${dd_opts:-}" "[ -b $device ]" "0" ""
        run_command "/bin/dd if=$source of=$device bs=512 count=1 ${dd_opts:-}" "[ -b $device ]" "0" ""
        cecho "OK" "green"
    }

	function exit_trap {
		local exit_code="$?"
		
        verbose "function exit_trap [$exit_code]"

        if [ "$verbose" == "yes" ]; then
            if [ "$exit_code" == "0" ]; then verbose "Exiting gracefully"; else verbose "Something went wrong, starting terminal!" "red"; setsid cttyhack sh; fi
        else
            if [ "$exit_code" != "0" ]; then echo "Script error has occured[$exit_code], please enable verboseging for more information"; fi
        fi
        clean_up
    }
    
function format_dev {
    local ser_or_dev="${1:-}"
    local filesystem="${2:-}"
    verbose "function format_dev[ serial or device: $ser_or_dev, file system: $filesystem ]"

	if eval [ -b /dev/mapper/"$ser_or_dev" ]; then
		local device="/dev/mapper/$ser_or_dev"
	elif eval [ -b /dev/"$ser_or_dev" ]; then
		local device="/dev/$ser_or_dev"
	elif eval "[ -b /dev/\$dev_$ser_or_dev ]"; then
		local device="/dev/\$dev_$ser_or_dev"
	fi
	verbose "Using $device" "blue"
	
	if [ -z "$filesystem" ]; then
        local fstype
        while [ "${fstype:-}" != "ext2" -a "${fstype:-}" != "ext4" ]; do
            echo "Please choose filesystem type[ext2/ext4]."
            read fstype
        done
        verbose "Formatting $device with $fstype"
        eval mkfs."$fstype" "$device" > /dev/null
	elif [ "$filesystem" == "ext2" ]; then
        if (eval "fsck $device"); then
            verbose "echo $device seems to already formatted, would you like to format again[no/yes]?" "blue"
			local answer
            read answer
			if [ "$answer" == "yes" ]; then
                eval "mkfs.ext2 -q $device"
			elif [ "$answer" != "no" -a "$answer" != "yes" ]; then
				format_dev "$@"
			fi
        else
            run_command "eval mkfs.ext2 -q $device" "" "Formatting $device as ext2" "0" ""
        fi
	elif [ "$filesystem" == "ext4" ]; then
		verbose "Formatting $device with ext4 filesystem"
        local fstype=$(eval "blkid -o value -s TYPE $device")
        if [ "$fstype" == "ext4" ]; then
            verbose "echo $device seems to already formatted, would you like to format again[yes/no]?" "blue"
			local answer="no"
            $(read -t 1 -p no answer; true)
            #echo answer:$answer
			if [ "$answer" == "yes" ]; then
                eval "mkfs.ext4 -q $device"
			elif [ "$answer" != "yes" -a "$answer" != "no" ]; then
				format_dev "$@"
			fi
        else
            eval "mkfs.ext4 -q $device"
        fi
	elif [ "$filesystem" == "luks" ]; then
		local exit_code=$(eval "cryptsetup isLuks $device"; echo "$?")
		if [ "$exit_code" == "0" ]; then
			verbose "$device seems to be a LUKS device already, would you like to format anyway[no/yes]?" "blue"
			local answer="no"
            $(read -t 1 answer; true)
			if [ "$answer" == "yes" ]; then
				run_command "cryptsetup luksFormat $device" "" "Formatting $device as LUKS" "$device" "0" ""
			elif [ "$answer" != "yes" -a "$answer" != "no" ]; then
				format_dev "$@"
			fi
		else
            run_command "cryptsetup luksFormat $device" "" "Formatting $device as LUKS" "0" ""
		fi
	fi
}

function get_dev_geometry {
    serial=${1:-}
    check_if_empty "$serial"
	verbose "function get_dev_geometry [serial: $serial]" "blue"
	
	get_dev_name "$@"
	
	for serial in $@; do
		verbose "Obtaining sector count for $serial" "blue"
		local sector_count=$(eval "blockdev --getsz /dev/\$dev_$serial")
		export sector_count_$serial="$sector_count"
	done
}

function get_dev_name {
        local serials=${@:-}
        verbose "function get_dev_name [serials: $serials]" "blue"
        check_if_empty "$serials"
        
        check_for_program "lsblk --version"
        check_for_program "sg_vpd --help"
        
        sleep 2
        
        for serial in $serials; do
            local found="0"

            cecho "Searching for device with serial $serial..." "-lb"
            local device
            for device in $(ls /sys/block/); do
                verbose "Trying $device" "blue"
                if [ -n "$(cat /sys/block/$device/device/vpd_pg80 2>/dev/null | cut -c2- | tail -n1 | tr -d '"'"'[:space:]'"'"')" ]; then
                    local serial2=$(cat /sys/block/$device/device/vpd_pg80 | cut -c2- | tail -n1 | tr -d '"'"'[:space:]'"'"')
                    if [ "$serial" == "$serial2" ]; then
                        verbose "Found device: $device, serial: $serial, serial2: $serial2 from vpd_pg80" "blue"
                        export dev_$serial="$device"
                        found="1"
                        continue
                    fi
                elif [ -n "$(lsblk -ndoname,serial | grep $device | awk '"'"'{print $2}'"'"')" ] && [ "$found" == "0" ]; then
                    local serial2=$(lsblk -ndoname,serial | grep $device | awk '"'"'{print $2}'"'"')
                    verbose "Found device: $device, serial: $serial, serial2: $serial2 from lsblk" "blue"
                    if [ "$serial" == "$serial2" ]; then
                        verbose "Found device: $device, serial: $serial, serial2: $serial2 from lsblk" "blue"
                        export dev_$serial="$device"
                        found="1"
                        continue
                    fi
                elif (sg_vpd /dev/$device &> /dev/null) && [ "$found" == "0" ]; then
                    serial2="$(sg_vpd -p sn -r /dev/$device)"
                    serial2=$(echo "$serial2" | cut -c4- | rev | cut -c2- | rev)
                    if [ "$serial" == "$serial2" ]; then
                        verbose "Found device: $device, serial: $serial, serial2: $serial2 from sg_vpd" "blue"
                        export dev_$serial="$device"
                        found="1"
                        continue
                    fi
                fi
            done

            if [ "$found" == "1" ]; then
                check_status
            else
                check_status "" "Device with serial $serial not found!"
            fi
        done
}

function install_busybox {
        verbose "function install_busybox"
    	
     	run_command "[ -x /bin/busybox ]" "" "Checking for /bin/busybox" "0" ""
     	run_command "[ -d /sbin ]" ""  "Checking for /sbin directory" "0" ""
        run_command "/bin/busybox --install" "" "Installing busybox..." "0" ""
    }
    
    function install_gentoo {
        local destination="${1:-}"
        
        verbose "function install_gentoo [$(echo destination: $destination)]"
        
        check_if_empty "$destination"
        
        #wget -P "$destination" http://distfiles.gentoo.org/releases/amd64/autobuilds/$(curl http://distfiles.gentoo.org/releases/amd64/autobuilds/latest-stage3.txt | grep stage3-amd64-2017 | cut -d " " -f1)
        wget -P "$destination" http://10.0.0.1/stage3-amd64-20170406.tar.bz2
        set +f
        tar -xpf "$destination"/stage3-amd64-*.tar.bz2 -C "$destination"
        rm "$destination"/stage3-amd64-*.tar.bz2
        #wget -P "$destination" http://distfiles.gentoo.org/snapshots/portage-latest.tar.bz2
        wget -P "$destination" http://10.0.0.1/portage-latest.tar.bz2
        tar -xf "$destination"/portage-latest.tar.bz2 -C "$destination"/usr
        rm "$destination"/portage-latest.tar.bz2
        set -f
                
        sed -i "s/*//" "$destination"/etc/shadow
        
        cp /etc/resolv.conf "$destination"/etc/
        ln -sv /proc/self/fd /dev/fd
                
        mount -o bind /dev $destination/dev
        check_status "$destination/dev"

        mount -t proc none $destination/proc
        check_status "$destination/proc"

        echo -e "MAKEOPTS=\"-j24 -l24\"\nEMERGE_DEFAULT_OPTS=\"--jobs=24 --load-average=24.0 --with-bdeps y\"" >> $destination/etc/portage/make.conf 
        
        # CHECK FOR INTERNET CONNECTION
        # basic
        #chroot "$destination" su -l -c "emerge eix ufed; eix-update"
        
        # virtualization
        #chroot "$destination" su -l -c "emerge qemu"

        # wireless
        #chroot "$destination" su -l -c "emerge wpa_supplicant; rc-update add wpa_supplicant default"
        #exec sh
        #chroot "$destination" su -l -c "emerge wpa_supplicant"
        
        #cp /etc/wpa_supplicant/wpa_supplicant.conf "$destination"/etc/wpa_supplicant/
        
    }
    
function mount_dev {
	local serials="${1:-}"
	local size="${2:-}"

	verbose "function mount_dev [serials: $serials, size: $size]" "blue"

	for serial in $serials; do
	cecho "Mounting $(eval echo $serial...)" "-lb"
	if [ -n "$size" ]; then
        local mount_point="$serial"
        run_command "mkdir $mount_point" "[ ! -d $mount_point ]" "$mount_point does not exist, creating" "permissive" "$mount_point"
        run_command "mount -o size=$size -t tmpfs tmpfs $mount_point" "" "Creating $size RAMdisk at $mount_point" "0" "$mount_point"
	elif [ "$serial" == "$serial_root" ]; then
        verbose "Mounting mount -o bind /mnt/$serial_keys/$serial_root/ /usr/src/$(readlink /usr/src/linux)-laptop/initramfs/$serial_root"
        if [ ! -d /usr/src/$(readlink /usr/src/linux)-laptop/initramfs/"$serial_root" ]; then
            mkdir /usr/src/$(readlink /usr/src/linux)-laptop/initramfs/opt/keys/"$serial_root"
        fi
        mount -o bind /mnt/"$serial_keys"/"$serial_root" /usr/src/$(readlink /usr/src/linux)-laptop/initramfs/opt/keys/"$serial_root"
        if [ "$?" == "0" ]; then
            resources_to_clean=$(echo /usr/src/$(readlink /usr/src/linux)-laptop/initramfs/opt/keys/"$serial_root" ${resources_to_clean:-})
        fi
	elif [ -b /dev/mapper/"$serial" ]; then
        run_command "mkdir /mnt/$serial" "[ ! -d /mnt/$serial ]" "/mnt/$serial does not exist, creating..." "permissive" "/mnt/$serial"
        verbose "Mounting /dev/mapper/$serial at /mnt/$serial" "blue"        
        if (mount /dev/mapper/$serial /mnt/$serial &> /dev/null); then
            if [ "$serial" != "laptop-root" ]; then
                check_status "/mnt/$serial"
            fi
        else
            format_dev "$serial"
            mount_dev "$serial"
		fi
	elif eval [ "$serial" == "\${dev_$serial_boot}1" ]; then
        verbose "Mounting /dev/mapper/$serial at /boot" "blue"
        if (eval mount /dev/mapper/$serial /boot &> /dev/null); then
            check_status "/boot"
        else
            format_dev "$serial"
            mount_dev "$serial"
		fi
    else
        cecho "$serial not found, exiting!" "red"
    fi
    cecho "OK" "green"
    done
}

    function mount_filesystems {
        verbose "function mount_filesystems"
        
        run_command "[ -f /etc/mtab ]" "" "Checking for /etc/mtab" "0" ""
        run_command "mount -t devtmpfs none /dev" "[ -d /dev ]" "Mounting /dev" "0" "/dev"
        run_command "mount -t proc none /proc" "[ -d /proc ]" "Mounting /proc" "0" "/proc"
        run_command "mount -t sysfs none /sys" "[ -d /sys ]" "Mounting /sys" "0" "/sys"
    }
    
    function open_devices {
        verbose "function open_devices" "blue"
        cecho "opening devices..." "-lb"
        
        local serial
		for serial in $(ls /opt/keys); do
			get_dev_name "$serial"
			open_luks "$serial" "key"
			eval "cryptsetup luksOpen --header /opt/keys/"$serial"/"$serial".header --key-file /dev/mapper/key_$serial /dev/\$dev_$serial $serial"
			#	verbose "lvm not found, initializing httpd"
			#	export serial_id
			#	httpd -h /var/www
			#	sleep 180;
			#	while (pgrep -f "busybox dd"); do sleep 1; done
			#	killall httpd
			#	if [ -f /var/www/dd.log ]; then lvm pvcreate /dev/mapper/$serial_id; fi
			#fi
		done
		
		cecho "OK" "green"
	}
	
function open_luks {	
	local arguments="${1:-}"
	local type="$2"
	verbose "function open_luks [arguments: $arguments, type: $type]" "blue"
    check_if_empty "$arguments" "$type"    
    check_for_program "cryptsetup --version"
    
    for argument in $arguments; do
    cecho "Openning $(eval echo $argument...)" "-lb"
    if [ "$type" == "device" ]; then
        if eval [ -b /dev/"$argument" ]; then
            verbose "Attempting to open device /dev/$argument as /dev/mapper/$argument" "-b"
            eval cryptsetup luksOpen /dev/"$argument" "$argument"
            check_status $(eval echo "$argument")
        else
            verbose "/dev/$argument does not exist, exiting!" "red"
            exit 1
        fi
    elif [ "$type" == "serial" ]; then
        get_dev_name "$argument"
        run_command "[ -b /dev/\$dev_$argument ]" "" "Checking if $( eval echo \$dev_$argument) exists" "0" ""
        if (eval cryptsetup isLuks /dev/\$dev_$argument); then
            run_command "cryptsetup luksOpen /dev/\$dev_$argument $argument" "" "Attempting to open /dev/\$dev_$argument as /dev/mapper/$argument" "0" "/dev/mapper/$argument"
        else
            if [ "$hardened" == "yes" ]; then
                erase_dev "$argument"
            fi
            format_dev "$argument" "luks"
            open_luks "$argument" "serial"
            if [ "$hardened" == "yes" ]; then
                erase_dev "$argument" "luks"
            fi
        fi
    elif [ "$type" == "key" ]; then
        verbose "Attempting to open key $argument as /dev/mapper/key_$argument" "-b"
        if [ -d /opt/keys/"$argument" ]; then
            cryptsetup luksOpen --key-file=/opt/keys/"$argument"/"$argument".key /opt/keys/"$argument"/"$argument" "key_$argument"
            check_status "key_$argument"
        elif [ -n "$serial_keys" ] && [ -d /mnt/"$serial_keys"/"$argument" ]; then
            cryptsetup luksOpen --key-file=/mnt/"$serial_keys"/"$argument"/"$argument".key /mnt/"$serial_keys"/"$argument"/"$argument" "key_$argument"
            check_status " $argument"
        else
            cecho "key $argument does not exist, exiting!" "red"
            exit 1
        fi
    fi
    cecho "OK" "green"
    done
}

function run_command {    
    local command="${1:-}"
    local condition="${2:-}"
    local message="${3:-}"
    local permissible="${4:-}"
    local resource="${5:-}"
    
    verbose "function run_command [command: $command, condiftion: $condition, message: $message, permissible: $permissible: $permissible, resource: $resource]" "blue"

    check_if_empty "$command"
    
    if $condition; then
        if [ -z "$message" ]; then
            verbose "executing command [$command]..." "-b"
        else
            verbose "$message..." "-b"
        fi
        eval "$command"
        check_status "$resource"
    else
        if [ "$permissible" == 0 ]; then
            cecho "$condition not true, exiting!" "red"
            exit 1
        fi
    fi
}

function restore_root {
    local dst="${2:-}"
    local src="${1:-}"
    local format="${3:-}"
    
    verbose "function restore_root [destination: $dst, format: $format, source: $src]" "blue"
    
    check_if_empty "$src" "$dst"
    check_for_program "lvm help"
    
    run_command "lvm lvs $dst" "" "Checking if destination LVM volume $dst exists" "0" ""
    run_command "lvm lvs $src" "" "Checking if source LVM volume $src exists" "0" ""
    run_command "lvm lvchange -ay $dst &> /dev/null" "[ ! -b /dev/$dst ]" "Activating $dst" "permissive" ""
    run_command "lvm lvchange -ay $src &> /dev/null" "[ ! -b /dev/$src ]" "Activating $src" "permissive" ""
    if (mountpoint /mnt/$(echo $src | sed s:/:-:)); then
        true
    else
        mount_dev "$(echo $src | sed s:/:-:)"
    fi
    if (mountpoint /mnt/$(echo $dst | sed s:/:-:)); then
        true
    else
        if [ "$format" == yes ]; then
            run_command "mkfs.ext4 /dev/$dst" "[ -b /dev/$dst ]" "Formatting $dst" "0" ""
        fi
        mount_dev "$(echo $dst | sed s:/:-:)"
    fi
    if [ -f "/mnt/$(echo $src | sed s:/:-:)/sbin/init" ]; then
        run_command "rsync -aAXv --delete --exclude={/dev/*,/proc/*,/sys/*,/tmp/*,/run/*,/mnt/*,/media/*,/lost+found} /mnt/$(echo $src | sed s:/:-:) /mnt/$(echo $dst | sed s:/:-:)" "mountpoint /mnt/$(echo $src | sed s:/:-:) && mountpoint /mnt/$(echo $dst | sed s:/:-:)" "Copying the files from $src to $dst" "0" ""
        umount /mnt/$(echo $src | sed s:/:-:)
        run_command "lvm lvchange -an $src &> /dev/null" "[ -b /dev/src ]" "Deactivating $src" "0" ""
    else
        install_gentoo "/mnt/$(echo $dst | sed s:/:-:)"
    fi
}

    function run_gentoo {
        local destination="$1"

        verbose "function run_gentoo [$(echo destination: $destination)]"
                
        wget -P /mnt/livedvd http://10.0.0.1/livedvd-amd64-multilib-20160704.iso
        
        mkdir /mnt/squashfs
        mount /mnt/livedvd/livedvd-amd64-multilib-20160704.iso /mnt/squashfs
        
        mkdir /mnt/root
        mount /mnt/squashfs/image.squashfs "$destination"
        
        #/home
        #/tmp
        
        #sed -i "s/*//" "$destination"/etc/shadow
        
        #cp /etc/resolv.conf "$destination"/etc/
        
        #ln -sv /proc/self/fd /dev/fd
                
        #mount -o bind /dev /mnt/root/dev
        #check_status "/mnt/root/dev"

        #mount -t proc none /mnt/root/proc
        #check_status "/mnt/root/proc"
        
        #chroot "$destination" su -l -c "emerge eix qemu ufed wpa_supplicant"
        #cp /etc/wpa_supplicant/wpa_supplicant.conf "$destination"/etc/wpa_supplicant/
    }

	function set_variables {
    	debug="no"
	    verbose="yes"

        verbose "function set_variables" "blue"
    	cecho "Setting variables..." "-lb"
    	
    	hardened="no"
    	late_net_iface="wlan0"
        # 8GB tiny: 20CF302E23E4FCA0AC111014
        # HP SSD: 161173400961
        # Rachel doc: 1D225620
        # Samsung SSD: S2R5NB0HC09645T 
        serial_root="S2R5NB0HC09645T"
        cecho "OK" "green"
        echo aaa
	}
	
function verbose {
    local color=${2:-default}
    local message="${1:-}"

    if [ "$verbose" == "yes" ]; then
        cecho "$message" "$color"
    elif [ "$verbose" != "no" ] && [ "$verbose" != "yes" ]; then
        cecho "verbose not set to [no/yes], exiting!" "red"
        exit 1
    fi
}
    
    set_variables
    configure_terminal
    mount_filesystems
	install_busybox
    configure_network
	open_devices "$serial_root"
	check_lvm "laptop/root"
	mount_root "laptop/root"    
    run_command "restore_root laptop/root_backup laptop/root yes" "[ ! -f /mnt/laptop-root/sbin/init ]" "Checking if /mnt/laptop-root/sbin/init exists" "" ""
    clean_up
    exec switch_root /mnt/laptop-root /sbin/init' > "$initramfs_temp"/init
	check_status
	
	if [ -x "$initramfs_temp/init" ]; then
        verbose "$initramfs_temp/init already executable!" "red"
    else
        verbose "Making $initramfs_temp/init executable" "-b"
        chmod +x $initramfs_temp/init
        check_status
    fi
        
    for executable in $initramfs_files; do
        verbose "Checking for $executable in the system" "-b"
        if [ -f "$executable" ]; then
            verbose "OK" "green"
            if (ldd $executable &> /dev/null); then
                verbose "$executable is a dynamic executable, additional files will be copied" "blue"
                for file in $(lddtree -l $executable); do
                    verbose "copying $file to $initramfs_temp$file" "-b"
                    cp $file $initramfs_temp$file
                    check_status
                done
            else
                verbose "Copying $executable to $initramfs_temp$executable" "-b"
                cp $executable $initramfs_temp$executable
                check_status
            fi
        else
            verbose "Failed!" "red"
        fi
    done
            
# https://hbr.org/2016/08/germanys-midsize-manufacturers-outperform-its-industrial-giants

#CONFIG_NOUVEAU_DEBUG=y
#CONFIG_NOUVEAU_DEBUG_DEFAULT=3
#CONFIG_DRM_I2C_CH7006=y
#CONFIG_DRM_I2C_SIL164=y
#CONFIG_DRM_I2C_NXP_TDA998X=y
#CONFIG_DRM_NOUVEAU=y
#CONFIG_DRM_VGEM=y
#CONFIG_FB_VGA16=y
#CONFIG_FB_UVESA=y
#CONFIG_FB_VESA=y
#CONFIG_FB_RIVA=y
#CONFIG_SENSORS_CORETEMP=y
#CONFIG_CPU_THERMAL=y
#CONFIG_SENSORS_CORETEMP=y
#CONFIG_SENSORS_I5500=y
#CONFIG_FB_NVIDIA_I2C=y
#CONFIG_FB_NVIDIA_DEBUG=n
#CONFIG_FB_NVIDIA_BACKLIGHT=y
#CONFIG_NFSD_BLOCKLAYOUT=y
#CONFIG_NFSD_SCSILAYOUT=y
#CONFIG_NFSD_FLEXFILELAYOUT=y
#CONFIG_FB_NVIDIA=y
#CONFIG_CRYPTO_PCRYPT=y
#CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE=y
#CONFIG_CRYPTO_XTS=y
#CONFIG_DM_CRYPT=y
#ONFIG_INITRAMFS_ROOT_GID=0
#CONFIG_NFSD=y
#CONFIG_NFSD_V4=y
#CONFIG_NFSD_V3_ACL=n
#CONFIG_NFSD_PNFS=n
#CONFIG_NFSD_V4_SECURITY_LABEL=n
#CONFIG_NFSD_FAULT_INJECTION=n
#CONFIG_R8169=y
#CONFIG_RT2X00=y
# CONFIG_RT2400PCI is not set
# CONFIG_RT2500PCI is not set
# CONFIG_RT61PCI is not set
# CONFIG_RT2800PCI is not set
# CONFIG_RT2500USB is not set
# CONFIG_RT73USB is not set
#CONFIG_RT2800USB=y
# CONFIG_RT2800USB_RT33XX is not set
# CONFIG_RT2800USB_RT35XX is not set
# CONFIG_RT2800USB_RT3573 is not set
# CONFIG_RT2800USB_RT53XX is not set
# CONFIG_RT2800USB_RT55XX is not set
# CONFIG_RT2800USB_UNKNOWN is not set
# CONFIG_RT2X00_DEBUG is not set
#CONFIG_SND_HDA_CODEC_REALTEK=y
#
# USB port drivers
#
#CONFIG_USB_SERIAL=y
# CONFIG_USB_SERIAL_CONSOLE is not set
# CONFIG_USB_SERIAL_GENERIC is not set
# CONFIG_USB_SERIAL_SIMPLE is not set
# CONFIG_USB_SERIAL_AIRCABLE is not set
# CONFIG_USB_SERIAL_ARK3116 is not set
# CONFIG_USB_SERIAL_BELKIN is not set
#CONFIG_USB_SERIAL_CH341=y
# CONFIG_USB_SERIAL_WHITEHEAT is not set
# CONFIG_USB_SERIAL_DIGI_ACCELEPORT is not set
# CONFIG_USB_SERIAL_CP210X is not set
# CONFIG_USB_SERIAL_CYPRESS_M8 is not set
# CONFIG_USB_SERIAL_EMPEG is not set
# CONFIG_USB_SERIAL_FTDI_SIO is not set
# CONFIG_USB_SERIAL_VISOR is not set
# CONFIG_USB_SERIAL_IPAQ is not set
# CONFIG_USB_SERIAL_IR is not set
# CONFIG_USB_SERIAL_EDGEPORT is not set
# CONFIG_USB_SERIAL_EDGEPORT_TI is not set
# CONFIG_USB_SERIAL_F81232 is not set
# CONFIG_USB_SERIAL_GARMIN is not set
# CONFIG_USB_SERIAL_IPW is not set
# CONFIG_USB_SERIAL_IUU is not set
# CONFIG_USB_SERIAL_KEYSPAN_PDA is not set
# CONFIG_USB_SERIAL_KEYSPAN is not set
# CONFIG_USB_SERIAL_KLSI is not set
# CONFIG_USB_SERIAL_KOBIL_SCT is not set
# CONFIG_USB_SERIAL_MCT_U232 is not set
# CONFIG_USB_SERIAL_METRO is not set
# CONFIG_USB_SERIAL_MOS7720 is not set
# CONFIG_USB_SERIAL_MOS7840 is not set
# CONFIG_USB_SERIAL_MXUPORT is not set
# CONFIG_USB_SERIAL_NAVMAN is not set
# CONFIG_USB_SERIAL_PL2303 is not set
# CONFIG_USB_SERIAL_OTI6858 is not set
# CONFIG_USB_SERIAL_QCAUX is not set
# CONFIG_USB_SERIAL_QUALCOMM is not set
# CONFIG_USB_SERIAL_SPCP8X5 is not set
# CONFIG_USB_SERIAL_SAFE is not set
# CONFIG_USB_SERIAL_SIERRAWIRELESS is not set
# CONFIG_USB_SERIAL_SYMBOL is not set
# CONFIG_USB_SERIAL_TI is not set
# CONFIG_USB_SERIAL_CYBERJACK is not set
# CONFIG_USB_SERIAL_XIRCOM is not set
# CONFIG_USB_SERIAL_OPTION is not set
# CONFIG_USB_SERIAL_OMNINET is not set
# CONFIG_USB_SERIAL_OPTICON is not set
# CONFIG_USB_SERIAL_XSENS_MT is not set
# CONFIG_USB_SERIAL_WISHBONE is not set
# CONFIG_USB_SERIAL_SSU100 is not set
# CONFIG_USB_SERIAL_QT2 is not set
# CONFIG_USB_SERIAL_DEBUG is not set'
    #if [ -f /usr/src/$(readlink /usr/src/linux)-$kernel_type/usr/initramfs_data.cpio.gz ]; then
    #    rm /usr/src/$(readlink /usr/src/linux)-$kernel_type/usr/initramfs_data.cpio.gz
    #    if [ "$?" == "0" ]; then
    #        echo "deleted cpio"
    #    fi
    #fi
}

function create_partitions {
    verbose "function create_partitions [$(echo $@)]" "yellow"
    
    verbose "Searching for 64MB boot partition" "-b"
    if [ $(eval "blockdev --getsz /dev/\${dev_$serial_boot}1") == "131072" ]; then
        check_status
        #echo "blkdev size $(eval "blockdev --getsz /dev/\${dev_$serial_boot}1")"
    else
        echo -e "d\n1\nn\np\n1\n2048\n+64M\na\nw" | eval "fdisk /dev/\$dev_$serial_boot"
        sleep 1
    fi
}

function run_command {    
    local command="${1:-}"
    local condition=${2:-}
    local message="${3:-}"
    local permissible="${4:-}"
    local resource="${5:-}"
    
    verbose "function run_command [command: $command, condiftion: $condition, message: $message, permissible: $permissible, resource: $resource]" "blue"

    check_if_empty "$command"
    
    if $condition; then
        if [ -z "$message" ]; then
            verbose "executing command [$command]..." "-b"
        else
            verbose "$message..." "-b"
        fi
        eval "$command"
        check_status "$resource"
    else
        cecho "$condition not true, exiting!" "red"
        if [ "$permissible" == 0 ]; then
        exit 1
        fi
    fi
}

function set_variables {
    debug="no"
    verbose="yes"
    
    verbose "function set_variables" "blue"
    cecho "Setting variables..." "-lb"
    
    hardened="no"
    initramfs_include_keys="yes"
    initramfs_internet="yes"
    initramfs_tools="yes"
    # 8GB tiny: 20CF302E23E4FCA0AC111014
    # HP SSD: 161173400961
    # Rachels doc: 1D225620 
    # Samsung SSD: S2R5NB0HC09645T 
    serial_boot="20CF302E23E4FCA0AC111014"
    serial_keys="797CE8BB"
    serial_keys_backup="20CF302E23E4FCA0AC111014"
    serial_root="S2R5NB0HC09645T"
    cecho "OK" "green"
}


function del_key {
    local serial="${1:-}"
    verbose "function del_key[serial: $serial]" "yellow"
    check_if_empty "$serial"
    
    ls -lhRI lost+found /mnt/"$serial"
    echo "Enter name of the key to delete:"
    local key_name
    read key_name
    
    if [ -n "$key_name" ]; then
        if [ -d /mnt/"$serial"/"$key_name" ]; then
            run_command "rm -r /mnt/$serial/$key_name" "" "Deleteing key $key_name" "0" ""
        else
            cecho "key not found, please try again" "yellow"
        fi
    else
        cecho "key name empty, please try again" "yellow"
        del_key "$serial"
    fi
}

     function erase_dev {
        local serial="${1:-}"
        local type="${2:-}"
        
        verbose "function erase_dev [serial: $serial, type: $type]" "blue"

        check_if_empty "$serial"
        
        if [ "$hardened" == "yes" ]; then
            verbose "hardened=yes, using /dev/urandom" "blue"
            local source=/dev/urandom
        elif [ "$hardened" == "no" ]; then
            verbose "hardened=no, using /dev/zero" "blue"
            local source=/dev/zero
        else
            cecho "hardened variable not set to [no/yes], exiting!" "red"
            exit 1
        fi

        get_dev_geometry "$serial"

        if [ "$type" == "luks" ]; then
            local device=/dev/mapper/$serial
        else
            local device=$(eval "echo /dev/\$dev_$serial")
        fi
        
        verbose "using device $device" "blue"
        
        check_for_program "/bin/dd --version"
        
        if (dd count=1 if=/dev/zero of=/dev/null status=progress &> /dev/null); then
            local dd_opts="status=progress"
        fi
        cecho "About to erase $device, please confirm with [ENTER]" "yellow"
        read
        cecho "Erasing device $device with $(eval echo \$sector_count_$serial) 512B sectors using $source..." "light_blue"
#        run_command "/bin/dd if=$source of=$device bs=512 count=\$sector_count_$serial ${dd_opts:-}" "[ -b $device ]" "0" ""
        run_command "/bin/dd if=$source of=$device bs=512 count=1 ${dd_opts:-}" "[ -b $device ]" "0" ""
        cecho "OK" "green"
    }

function exit_trap {
	local exit_code="$?"
    
    verbose "function exit_trap [$exit_code]" "yellow"
    
	if [ "$verbose" == "yes" ]; then
		if [ "$exit_code" == "0" ]; then verbose "Exiting gracefully" "green"; else verbose "Command [$BASH_COMMAND] has exited with code [$exit_code]" "red"; fi
	else
		if [ "$exit_code" != "0" ]; then echo "/init error has occured, please enable verboseging for more information"; fi
	fi
	
	clean_up
}

function format_dev {
    local ser_or_dev="${1:-}"
    local filesystem="${2:-}"
    verbose "function format_dev[ serial or device: $ser_or_dev, file system: $filesystem ]"

	if eval [ -b /dev/mapper/"$ser_or_dev" ]; then
		local device="/dev/mapper/$ser_or_dev"
	elif eval [ -b /dev/"$ser_or_dev" ]; then
		local device="/dev/$ser_or_dev"
	elif eval "[ -b /dev/\$dev_$ser_or_dev ]"; then
		local device="/dev/\$dev_$ser_or_dev"
	fi
	verbose "Using $device" "blue"
	
	if [ -z "$filesystem" ]; then
        local fstype
        while [ "${fstype:-}" != "ext2" -a "${fstype:-}" != "ext4" ]; do
            echo "Please choose filesystem type[ext2/ext4]."
            read fstype
        done
        verbose "Formatting $device with $fstype"
        eval mkfs."$fstype" "$device" > /dev/null
	elif [ "$filesystem" == "ext2" ]; then
        if (eval "fsck $device"); then
            verbose "echo $device seems to already formatted, would you like to format again[no/yes]?" "blue"
			local answer
            read answer
			if [ "$answer" == "yes" ]; then
                eval "mkfs.ext2 -q $device"
			elif [ "$answer" != "no" -a "$answer" != "yes" ]; then
				format_dev "$@"
			fi
        else
            run_command "eval mkfs.ext2 -q $device" "" "Formatting $device as ext2" "0" ""
        fi
	elif [ "$filesystem" == "ext4" ]; then
		verbose "Formatting $device with ext4 filesystem"
        local fstype=$(eval "blkid -o value -s TYPE $device")
        if [ "$fstype" == "ext4" ]; then
            verbose "echo $device seems to already formatted, would you like to format again[yes/no]?" "blue"
			local answer="no"
            $(read -t 1 -p no answer; true)
            #echo answer:$answer
			if [ "$answer" == "yes" ]; then
                eval "mkfs.ext4 -q $device"
			elif [ "$answer" != "yes" -a "$answer" != "no" ]; then
				format_dev "$@"
			fi
        else
            eval "mkfs.ext4 -q $device"
        fi
	elif [ "$filesystem" == "luks" ]; then
		local exit_code=$(eval "cryptsetup isLuks $device"; echo "$?")
		if [ "$exit_code" == "0" ]; then
			verbose "$device seems to be a LUKS device already, would you like to format anyway[no/yes]?" "blue"
			local answer="no"
            $(read -t 1 answer; true)
			if [ "$answer" == "yes" ]; then
				run_command "cryptsetup luksFormat $device" "" "Formatting $device as LUKS" "0" "$device"
			elif [ "$answer" != "yes" -a "$answer" != "no" ]; then
				format_dev "$@"
			fi
		else
            run_command "cryptsetup luksFormat $device" "" "Formatting $device as LUKS" "0" ""
		fi
	fi
}

function gen_key {
    local serial=${1:-}
    verbose "function gen_key[serial: $serial]" "blue"
    check_if_empty "$serial"
    
    echo "Please enter new key name:"
    local key_name
    read key_name
    if [ -n "$key_name" ]; then
        if [ ! -d /mnt/"$serial"/"$key_name" ]; then
            mkdir /mnt/"$serial"/"$key_name"
            
            if [ "$hardened" == "no" ]; then
                local device="/dev/urandom"
            elif [ "$hardened" == "yes" ]; then
                local device="/dev/random"
            else
                cecho "hardened variable not set[no/yes], exiting!" "red"
                exit 1
            fi
            
            cecho "Creating key $key_name..." "-lb"
            dd if=/dev/zero of=/mnt/"$serial"/"$key_name"/"$key_name" bs=1k count=1032 &> /dev/null
            dd if="$device" of=/mnt/"$serial"/"$key_name"/"$key_name".key bs=1 count=4096 status=progress

            dd if=/dev/zero of=/mnt/"$serial"/"$key_name"/"$key_name".header bs=1k count=1028 &> /dev/null
            
            cryptsetup luksFormat --align-payload=2056 --key-file /mnt/"$serial"/"$key_name"/"$key_name".key -q /mnt/"$serial"/"$key_name"/"$key_name"
            cryptsetup luksOpen --key-file /mnt/"$serial"/"$key_name"/"$key_name".key /mnt/"$serial"/"$key_name"/"$key_name" "$key_name"
            check_status "$key_name"

            if [ -f $key_name ]; then
                verbose "Importing key" "blue"
                dd if="$key_name" of=/dev/mapper/"$key_name" bs=1 count=4096 status=progress
            else
                verbose "Creating key" "blue"
                dd if="$device" of=/dev/mapper/"$key_name" bs=1 count=4096 status=progress
            fi
            
            cryptsetup luksFormat --header /mnt/"$serial"/"$key_name"/"$key_name".header --key-file /dev/mapper/"$key_name" -q /dev/loop0
            cecho "OK" "green"
        else
            cecho "key $key_name already exists!" "red"
            exit 1
        fi
    else
        cecho "no key name provided, please try again" "yellow"
        gen_key "$serial"
    fi
}
	
function get_dev_name {
        local serials=${@:-}
        verbose "function get_dev_name [serials: $serials]" "blue"
        check_if_empty "$serials"
        
        check_for_program "lsblk --version"
        check_for_program "sg_vpd --help"
        
        sleep 2
        
        for serial in $serials; do
            local found="0"

            cecho "Searching for device with serial $serial..." "-lb"
            local device
            for device in $(ls /sys/block/); do
                verbose "Trying $device" "blue"
                if [ -n "$(cat /sys/block/$device/device/vpd_pg80 2>/dev/null | cut -c2- | tail -n1 | tr -d '[:space:]')" ]; then
                    local serial2=$(cat /sys/block/$device/device/vpd_pg80 | cut -c2- | tail -n1 | tr -d '[:space:]')
                    if [ "$serial" == "$serial2" ]; then
                        verbose "Found device: $device, serial: $serial, serial2: $serial2 from vpd_pg80" "blue"
                        export dev_$serial="$device"
                        found="1"
                        continue
                    fi
                elif [ -n "$(lsblk -ndoname,serial | grep $device | awk '{print $2}')" ] && [ "$found" == "0" ]; then
                    local serial2=$(lsblk -ndoname,serial | grep $device | awk '{print $2}')
                    if [ "$serial" == "$serial2" ]; then
                        verbose "Found device: $device, serial: $serial, serial2: $serial2 from lsblk" "blue"
                        export dev_$serial="$device"
                        found="1"
                        continue
                    fi
                elif (sg_vpd /dev/$device &> /dev/null) && [ "$found" == "0" ]; then
                    serial2="$(sg_vpd -p sn -r /dev/$device)"
                    serial2=$(echo "$serial2" | cut -c4- | rev | cut -c2- | rev)
                    if [ "$serial" == "$serial2" ]; then
                        verbose "Found device: $device, serial: $serial, serial2: $serial2 from sg_vpd" "blue"
                        export dev_$serial="$device"
                        found="1"
                        continue
                    fi
                fi
            done

            if [ "$found" == "1" ]; then
                cecho "OK" "green"
            else
                check_status "" "Device with serial $serial not found!"
            fi
        done
}

function get_dev_geometry {
    serial=${1:-}
    check_if_empty "$serial"
	verbose "function get_dev_geometry [serial: $serial]" "blue"
	
	get_dev_name "$@"
	
	for serial in $@; do
		verbose "Obtaining sector count for $serial" "blue"
		local sector_count=$(eval "blockdev --getsz /dev/\$dev_$serial")
		export sector_count_$serial="$sector_count"
	done
}

function open_luks {	
	local arguments="${1:-}"
	local type="$2"
	verbose "function open_luks [arguments: $arguments, type: $type]" "blue"
    check_if_empty "$arguments" "$type"    
    check_for_program "cryptsetup --version"
    
    for argument in $arguments; do
    cecho "Openning $(eval echo $argument...)" "-lb"
    if [ "$type" == "device" ]; then
        if eval [ -b /dev/"$argument" ]; then
            verbose "Attempting to open device /dev/$argument as /dev/mapper/$argument" "-b"
            eval cryptsetup luksOpen /dev/"$argument" "$argument"
            check_status $(eval echo "$argument")
        else
            verbose "/dev/$argument does not exist, exiting!" "red"
            exit 1
        fi
    elif [ "$type" == "serial" ]; then
        get_dev_name "$argument"
        run_command "[ -b /dev/\$dev_$argument ]" "" "Checking if $( eval echo \$dev_$argument) exists" "0" ""
        if (eval cryptsetup isLuks /dev/\$dev_$argument); then
            run_command "cryptsetup luksOpen /dev/\$dev_$argument $argument" "" "Attempting to open /dev/\$dev_$argument as /dev/mapper/$argument" "0" "/dev/mapper/$argument"
        else
            if [ "$hardened" == "yes" ]; then
                erase_dev "$argument"
            fi
            format_dev "$argument" "luks"
            open_luks "$argument" "serial"
            if [ "$hardened" == "yes" ]; then
                erase_dev "$argument" "luks"
            fi
        fi
    elif [ "$type" == "key" ]; then
        verbose "Attempting to open key $argument as /dev/mapper/key_$argument" "-b"
        if [ -d /opt/keys/"$argument" ]; then
            cryptsetup luksOpen --key-file=/opt/keys/"$argument"/"$argument".key /opt/keys/"$argument"/"$argument" "key_$argument"
            check_status "key_$argument"
        elif [ -n "$serial_keys" ] && [ -d /mnt/"$serial_keys"/"$argument" ]; then
            cryptsetup luksOpen --key-file=/mnt/"$serial_keys"/"$argument"/"$argument".key /mnt/"$serial_keys"/"$argument"/"$argument" "key_$argument"
            check_status " $argument"
        else
            cecho "key $argument does not exist, exiting!" "red"
            exit 1
        fi
    fi
    cecho "OK" "green"
    done
}

function mount_dev {
	local serials="${1:-}"
	local size="${2:-}"

	verbose "function mount_dev [serials: $serials, size: $size]" "blue"

	for serial in $serials; do
	cecho "Mounting $(eval echo $serial...)" "-lb"
	if [ -n "$size" ]; then
        local mount_point="$serial"
        run_command "mkdir $mount_point" "[ ! -d $mount_point ]" "$mount_point does not exist, creating" "0" "$mount_point"
        run_command "mount -o size=$size -t tmpfs tmpfs $mount_point" "" "Creating $size RAMdisk at $mount_point" "0" "$mount_point"
	elif [ "$serial" == "$serial_root" ]; then
        verbose "Mounting mount -o bind /mnt/$serial_keys/$serial_root/ /usr/src/$(readlink /usr/src/linux)-laptop/initramfs/$serial_root"
        if [ ! -d /usr/src/$(readlink /usr/src/linux)-laptop/initramfs/"$serial_root" ]; then
            mkdir /usr/src/$(readlink /usr/src/linux)-laptop/initramfs/opt/keys/"$serial_root"
        fi
        mount -o bind /mnt/"$serial_keys"/"$serial_root" /usr/src/$(readlink /usr/src/linux)-laptop/initramfs/opt/keys/"$serial_root"
        if [ "$?" == "0" ]; then
            resources_to_clean=$(echo /usr/src/$(readlink /usr/src/linux)-laptop/initramfs/opt/keys/"$serial_root" ${resources_to_clean:-})
        fi
	elif [ -b /dev/mapper/"$serial" ]; then
        run_command "mkdir /mnt/$serial" "[ ! -d /mnt/$serial ]" "/mnt/$serial does not exist, creating..." "" "/mnt/$serial"
        verbose "Mounting /dev/mapper/$serial at /mnt/$serial" "blue"        
        if (mount /dev/mapper/$serial /mnt/$serial &> /dev/null); then
            if [ "$serial" != "laptop-root" ]; then
                check_status "/mnt/$serial"
            fi
        else
            format_dev "$serial"
            mount_dev "$serial"
		fi
	elif eval [ "$serial" == "\${dev_$serial_boot}1" ]; then
        verbose "Mounting /dev/mapper/$serial at /boot" "blue"
        if (eval mount /dev/mapper/$serial /boot &> /dev/null); then
            check_status "/boot"
        else
            format_dev "$serial"
            mount_dev "$serial"
		fi
    else
        cecho "$serial not found, exiting!" "red"
    fi
    cecho "OK" "green"
    done
}

function verbose {
    local color=${2:-default}
    local message="${1:-}"

    if [ "$verbose" == "yes" ]; then
        cecho "$message" "$color"
    elif [ "$verbose" != "no" ] && [ "$verbose" != "yes" ]; then
        cecho "verbose not set to [no/yes], exiting!" "red"
        exit 1
    fi
}

function build_NAS {
    #arm_root="/home/user/diskless"
    #keys="array S2R8J9DC911615"
    #NAS_kernel_config="mvebu_v5_defconfig"
    #kernel_load_address=0x200000

function exit_trap {
	local exit_code=$?
        if [ $exit_code != 0 ]; then echo "Command [$BASH_COMMAND] exited with code [$exit_code]"
        	verbose "Cleaning up!"
        	#if [ -d $initramfs_temp ]; then verbose "Deleting $initramfs_temp"; rm -r $initramfs_temp; fi
        	#if [[ -n $(cat /proc/mounts | grep $temp) ]]; then umount $temp; fi
        	#if [ -e $temp ]; then rm -r $temp; fi
        	#if [[ -n $(cat /proc/mounts | grep /dev/mappper/keys) ]]; then umount /dev/mapper/keys; fi
        	#if [ -b /dev/mapper/keys ]; then cryptsetup close /dev/mapper/keys; fi
        	#if [ -b /dev/mapper/$boot_serial ]; then cryptsetup close /dev/mapper/$boot_serial; fi
	fi
}


if [ "$1" == "update" ]; then echo "Updating the kernel..."; verbose "Deleting /usr/src/linux-NAS and /usr/src/linux-*-NAS"; rm /usr/src/linux-NAS; rm -r /usr/src/linux-*-NAS; fi

if [ ! -L /usr/src/linux-NAS ]; then
	if [ -d /usr/src/linux ]; then kernel_dir=$(readlink /usr/src/linux); verbose "$kernel_dir has been found"; else echo "/usr/src/linux is missing. Please install kernel sources"; exit 0; fi

	verbose "Creating $kernel_dir-NAS directory"
	mkdir /usr/src/$kernel_dir-NAS

	verbose "Updating kernel-NAS symlink"
	ln -s /usr/src/$kernel_dir-NAS /usr/src/linux-NAS

	verbose "Copying $kernel_dir to $kernel_dir-NAS"
	cp -r /usr/src/$kernel_dir/* /usr/src/$kernel_dir-NAS/
fi

echo "Building the kernel..."

verbose "Entering /usr/src/linux-NAS"
cd /usr/src/linux-NAS

verbose "Configuring $kernel_dir"
ARCH="arm" make $kernel_config


verbose "Applying configuration changes needed for the NAS"
# Cross compiler
sed -i 's/CONFIG_CROSS_COMPILE=""/CONFIG_CROSS_COMPILE="armv5te-softfloat-linux-gnueabi-"/g' /usr/src/linux-NAS/.config
# Initramfs
if [[ $initramfs == y ]]; then
	echo 'CONFIG_BLK_DEV_INITRD=y' >> /usr/src/linux-NAS/.config
	echo 'CONFIG_INITRAMFS_SOURCE="/tmp/initramfs"' >> /usr/src/linux-NAS/.config
	echo 'CONFIG_RD_GZIP=y' >> /usr/src/linux-NAS/.config
	echo 'CONFIG_RD_BZIP2=n' >> /usr/src/linux-NAS/.config
	echo 'CONFIG_RD_LZMA=n' >> /usr/src/linux-NAS/.config
	echo 'CONFIG_RD_XZ=n' >> /usr/src/linux-NAS/.config
	echo 'CONFIG_RD_LZO=n' >> /usr/src/linux-NAS/.config
	echo 'CONFIG_RD_LZ4=n' >> /usr/src/linux-NAS/.config
	echo 'CONFIG_INITRAMFS_ROOT_UID=0' >> /usr/src/linux-NAS/.config
	echo 'CONFIG_INITRAMFS_ROOT_GID=0' >> /usr/src/linux-NAS/.config
fi
# Size optimalization
echo 'CONFIG_CC_OPTIMIZE_FOR_SIZE=y' >> /usr/src/linux-NAS/.config
# MD/crypto

echo 'CONFIG_MD=y
CONFIG_BLK_DEV_MD=y
CONFIG_MD_AUTODETECT=y
CONFIG_MD_LINEAR=n
CONFIG_MD_RAID0=n
CONFIG_MD_RAID1=y
CONFIG_MD_RAID10=n
CONFIG_MD_RAID456=n
CONFIG_MD_MULTIPATH=y
# CONFIG_MD_FAULTY is not set
# CONFIG_BCACHE is not set
CONFIG_BLK_DEV_DM=y
CONFIG_DM_MQ_DEFAULT=y
# CONFIG_DM_DEBUG is not set
CONFIG_DM_CRYPT=y
CONFIG_DM_SNAPSHOT=y
# CONFIG_DM_THIN_PROVISIONING is not set
# CONFIG_DM_CACHE is not set
# CONFIG_DM_ERA is not set
CONFIG_DM_MIRROR=y
# CONFIG_DM_LOG_USERSPACE is not set
CONFIG_DM_RAID=y
# CONFIG_DM_ZERO is not set
CONFIG_DM_MULTIPATH=y
# CONFIG_DM_MULTIPATH_QL is not set
# CONFIG_DM_MULTIPATH_ST is not set
# CONFIG_DM_DELAY is not set
CONFIG_DM_UEVENT=y
# CONFIG_DM_FLAKEY is not set
# CONFIG_DM_VERITY is not set
# CONFIG_DM_SWITCH is not set
# CONFIG_DM_LOG_WRITES is not set
CONFIG_ASYNC_RAID6_TEST=n
# XTS
CONFIG_CRYPTO_XTS=y' >> /usr/src/linux-NAS/.config

if [[ $initramfs == y ]]; then
	verbose "Creating $initramfs_temp"
	if [ ! -d $initramfs_temp ]; then
        mkdir $initramfs_temp;
    fi

	for directory in $initramfs_dirs; do verbose "Creating $initramfs_temp$directory..."; mkdir $initramfs_temp$directory; done

	echo "Copying files"
	for executable in $initramfs_files; do echo "Copying $arm_root$executable"; cp $arm_root$executable $initramfs_temp$executable; done
	mv $initramfs_temp/sbin/lvm.static $initramfs_temp/sbin/lvm

	verbose "Creating $initramfs_temp/init"
	echo '#!/bin/busybox sh

	get_keys () {
		local key_id="$1"
		verbose "Downloading key $key_id"
		tftp -g -l /opt/keys/$key_id/$key_id -r keys/$key_id/$key_id $NAT &> /dev/null || continue
		verbose "Downloading header $serial.header"
		tftp -g -l /opt/keys/$key_id/$key_id.header -r keys/$key_id/$key_id.header $NAT &> /dev/null || continue
	}

	open_luks () {
        local device
		for device in $(ls /dev/[m,s]d?); do
			verbose "Searching for $device key ID"
			if [ $device == /dev/md0 ]; then verbose "Found array"; local key_id="array"; get_keys "$key_id"
			else
				if (cat /sys/block/$(basename $device)/device/vpd_pg80 &> /dev/null); then local key_id=$(cat /sys/block/$(basename $device)/device/vpd_pg80 | cut -c2- | tr -d "\n" | tr -d " "); verbose "Found $key_id"; get_keys "$key_id"
				else
					local key_id=$(cat /sys/block/$(basename $device)/device/model | tr -d " ")
					if [ -n "$key_id" ]; then verbose "Found $key_id"; get_keys "$key_id"; else continue; fi
				fi
			fi
			verbose "Attempting to open keys $key_id"
			cryptsetup luksOpen --header /opt/keys/$key_id/$key_id.header --key-file /opt/keys/$key_id/$key_id.key /opt/keys/$key_id/$key_id key_$key_id
			verbose "Creating /mnt/$key_key_id directory"
			mkdir /mnt/key_$key_id
			verbose "Mounting key_$key_id in /mnt/key_$key_id"
			mount /dev/mapper/key_$key_id /mnt/key_$key_id
			verbose "Openning $key_id"
			cryptsetup luksOpen --header /mnt/key_$key_id/$key_id.header --key-file /mnt/key_$key_id/$key_id.key $device $key_id || continue
			verbose "Umounting key_$serial"
			umount /dev/mapper/key_$key_id
			verbose "Deleting /mnt/key_$serial directory"
			rmdir /mnt/key_$key_id
			cryptsetup close key_$key_id
			if (lvm pvck /dev/mapper/$key_id); then
				verbose "lvm on $key_id OK"
			else
				verbose "lvm not found, initializing httpd"
				export key_id
				httpd -h /var/www
				sleep 180;
				while (pgrep -f "busybox dd"); do sleep 1; done
				killall httpd
				if [ -f /var/www/dd.log ]; then lvm pvcreate /dev/mapper/$key_id; fi
			fi
		done
	}

	rescue_shell () {
		local exit_code=$?
		echo "Something went wrong[$exit_code], dropping into a shell"
		exec sh
	}

	verbose "Installing busybox..."
	/bin/busybox --install || rescue_shell

	verbose "Mounting /dev..."
	mount -t devtmpfs none /dev || rescue_shell
	verbose "Mounting /proc..."
	mount -t proc none /proc || rescue_shell
	verbose "Mounting /sys..."
	mount -t sysfs none /sys || rescue_shell

	verbose "Trying to assemble the array..."
	#mdadm --assemble --scan --name=0
	#sleep 10

	#open_luks

	#lvm lvchange -ay 1TB/root
	#lvm vgscan --mknodes
	#fsck.ext4 /dev/1TB/root
	sh
	mount /dev/1TB/root /mnt/root || rescue_shell

	verbose -e "Cleaning up\numounting /dev..."
	umount /dev || rescue_shell
	verbose -e "Umounting /proc..."
	umount /proc 
	verbose -e "Umounting /sys..."
	umount /sys
	exec switch_root /mnt/root /sbin/init' > $initramfs_temp/init

	echo "Making $initramfs_temp/init executable"
	chmod +x $initramfs_temp/init

	verbose "Creating $initramfs_temp/etc/mtab"
	touch $initramfs_temp/etc/mtab

	mknod -m 600 $initramfs_temp/dev/console c 5 1

echo '<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta http-equiv="refresh" content="0;url=./cgi-bin/index.sh">
<title>NAS administration</title>
</head>

<body>
<p>Automatically redirecting to the CGI script</p>
</body>

</html>' >> $initramfs_temp/var/www/index.html

echo '#!/bin/busybox sh' >> $initramfs_temp/var/www/cgi-bin/index.sh
echo 'echo "Content-type: text/html"' >> $initramfs_temp/var/www/cgi-bin/index.sh
echo 'echo ""' >> $initramfs_temp/var/www/cgi-bin/index.sh
echo 'echo "<p> $key_id doesnt contain a valid lvm label. Please initialize the drive.<br> WARNING! This will erase all data on the drive </p>"' >> $initramfs_temp/var/www/cgi-bin/index.sh
echo 'echo "<form action="./format.sh">
    <input type="submit" value="Format the drive" />
</form>"' >> $initramfs_temp/var/www/cgi-bin/index.sh
chmod +x $initramfs_temp/var/www/cgi-bin/index.sh

echo '#!/bin/busybox sh
echo ""
echo "<!DOCTYPE html>"
echo "<html>"
echo "<head>"
echo "<title>Title of the document</title>"
echo "</head>"

echo "<body>"
if [ ! -f /var/www/dd.log ]; then
        busybox dd if=/dev/zero of=/dev/mapper/$key_id bs=1M > /var/www/dd.log 2>&1 &
fi
kill -USR1 $(pgrep -f "busybox dd")
echo "<pre>"
cat /var/www/dd.log
echo "</pre>"
echo "" > /var/www/dd.log
echo "</body>"
echo "</html>"' >> $initramfs_temp/var/www/cgi-bin/format.sh
chmod +x $initramfs_temp/var/www/cgi-bin/format.sh
fi

echo "Compiling linux-NAS"

ARCH="arm" make uImage LOADADDR=$kernel_load_address

if [[ $initramfs == y ]]; then
	umount /tmp/initramfs
	#rm -r /tmp/initramfs
fi

verbose "Compiling dtbs"
ARCH="arm" make dtbs

verbose "copying ftd file"
#cp /usr/src/linux-NAS/arch/arm/boot/dts/kirkwood-db-88f6282.dtb /usr/src/linux-NAS/arch/arm/boot/board.dtb
cp /usr/src/linux-NAS/arch/arm/boot/dts/kirkwood-d2net.dtb /usr/src/linux-NAS/arch/arm/boot/board.dtb

verbose "Updating /etc/conf.d/atftpd"
echo '# Config file for tftp server

TFTPD_ROOT="/usr/src/linux-NAS/arch/arm/boot/"
TFTPD_OPTS="--daemon --user nobody --group nobody"' > /etc/conf.d/atftp
}

set_variables
configure_terminal
for (( ; ; )); do
	echo "Select an operation to perform from the list"
	echo "a) Add a key"
	echo "i) Import a key"
	echo "l) List keys"
    echo "lb) List backup keys"
	echo "r) Remove a key"
	echo "b) Backup keys"
	echo "L) Create laptop boot partition"
	echo "N) Create NAS key partition"
	echo "B) Erase the boot drive"
	echo "K) Erase the key drive"
	echo "Kb) Erase the key drive"
	echo "7) Update the kernel"
	echo "9) Generate new key/header pair"
	echo "q) Quit"
	read input
	case $input in
		a)  open_luks "$serial_keys" "serial"
            mount_dev "$serial_keys"
            gen_key "$serial_keys"
            clean_up
            ;;
		i)  open_luks "$serial_keys" "serial"
            mount_dev "$serial_keys"
            gen_key "$serial_keys"
            clean_up
            ;;
		l)  open_luks "$serial_keys" "serial"
            mount_dev "$serial_keys"
            cecho "Existing keys:" "light_blue"
            ls -lhRI lost+found /mnt/"$serial_keys"
            clean_up
            ;;
		lb) open_luks "$serial_keys_backup" "serial"
            mount_dev "$serial_keys_backup"
            cecho "Existing keys:" "light_blue"
            ls -lhRI lost+found /mnt/"$serial_keys_backup"
            clean_up
            ;;
		r)  open_luks "$serial_keys" "serial"
            mount_dev "$serial_keys"
            del_key "$serial_keys"
            clean_up
            ;;
        b)  open_luks "$serial_keys $serial_keys_backup" "serial"
            mount_dev "$serial_keys $serial_keys_backup"
            run_command "rsync -av --exclude lost+found /mnt/$serial_keys/ /mnt/$serial_keys_backup/" "" "Copying keys..." "0" ""
            clean_up
            ;;
		L)  create_partitions "$serial_boot"
            format_dev "\${dev_$serial_boot}1" "luks"
			open_luks "\${dev_$serial_boot}1" "device"
            mount_dev "\${dev_$serial_boot}1"
			build_kernel "laptop"
            if (eval "grub-install /dev/\$dev_$serial_boot"); then echo ok; else echo grub-install has failed; clean_up; fi
			if (grub-mkconfig -o /boot/grub/grub.cfg); then echo config ok; else echo config has failed; clean_up; fi
			clean_up
			;;
		N)	#kernel=$(readlink /usr/src/linux | sed 's/linux/kernel/g')
#serial=$(lsblk -noserial /dev/$boot)
			verbose "Checking if /dev/mapper/keys is mounted"; if [[ -n $(cat /proc/mounts | grep "/dev/mapper/keys") ]]; then verbose "Umounting"; umount /dev/mapper/keys; fi
			verbose "Checking if \$dev_$boot_serial is open"; if [ -b /dev/mapper/keys ]; then verbose "Closing"; cryptsetup close keys; fi
			if (eval "test -b /dev/\${dev_$boot_serial}2"); then verbose "The 100M boot partition has been found."; else echo -e "n\np\n2\n67584\n+100M\nw" | eval "fdisk /dev/\$dev_$boot_serial"; fi
			verbose "Checking for /opt/keys/$boot_serial"; if [ ! -d /opt/keys ]; then mkdir /opt/keys; fi; if [ ! -d /opt/keys/$boot_serial ]; then mkdir /opt/keys/$boot_serial; fi
			verbose "Creating $boot_serial header/key pair"; if [ $hardened == yes ]; then r_device=/dev/random; else r_device=/dev/urandom; fi; dd if=$r_device of=/opt/keys/$boot_serial/$boot_serial.key bs=512 count=8; dd if=/dev/zero of=/opt/keys/$boot_serial/$boot_serial.header bs=1k count=1028
			verbose "Formatting /dev/mapper/$boot_serial"; eval cryptsetup luksFormat -q /dev/\${dev_$boot_serial}2 --header /opt/keys/$boot_serial/${boot_serial}.header --key-file /opt/keys/$boot_serial/${boot_serial}.key
			verbose "Openning /dev/mapper/$boot_serial"; eval cryptsetup luksOpen /dev/\${dev_$boot_serial}2 --header /opt/keys/$boot_serial/${boot_serial}.header --key-file /opt/keys/$boot_serial/${boot_serial}.key $boot_serial
			if [ $hardened == yes ]; then verbose "Erasing /dev/mapper/$boot_serial"; dd if=/dev/zero of=/dev/mapper/keys; fi
			if (e2fsck /dev/mapper/$boot_serial); then verbose "filesystem on /dev/mapper/$boot_serial OK"; else verbose "Creating ext2 filesystem on /dev/mapper/$boot_serial"; mkfs.ext2 /dev/mapper/$boot_serial; fi
			if [ ! -d /mnt/$boot_serial ]; then verbose "Creating $boot_serial mount directory"; mkdir /mnt/$boot_serial; fi
			#if [[ -n $(cat /proc/mounts | grep $boot_serial) ]]; then verbose "Mounting $boot_serial"; 
			mount /dev/mapper/$boot_serial /mnt/$boot_serial #; fi

			if [[ ! -d "$initramfs_temp" ]]; then verbose "Creating $initramfs_temp directory"; mkdir /tmp/initramfs; fi
			mount -o size=50M -t tmpfs tmpfs /tmp/initramfs
			mkdir /tmp/initramfs/opt
			mkdir /tmp/initramfs/opt/keys
			eval "cryptsetup luksOpen /dev/\$dev_$serial_keys $serial_keys"
			mkdir /mnt/$serial_keys
			mount /dev/mapper/$serial_keys /mnt/$serial_keys

			for key in $keys; do
				mkdir /tmp/initramfs/opt/keys/$key
				dd if=/dev/urandom of=/tmp/initramfs/opt/keys/$key/${key}.key bs=512 count=8
				mkdir /mnt/$boot_serial/$key
				dd if=/dev/zero of=/mnt/$boot_serial/$key/${key}.header bs=1k count=1028
				dd if=/dev/zero of=/mnt/$boot_serial/$key/$key bs=512 count=8192
				cryptsetup luksFormat -q /mnt/$boot_serial/$key/$key --key-file /tmp/initramfs/opt/keys/$key/${key}.key --header /mnt/$boot_serial/$key/${key}.header
				cryptsetup luksOpen /mnt/$boot_serial/$key/$key --key-file /tmp/initramfs/opt/keys/$key/${key}.key --header /mnt/$boot_serial/$key/${key}.header $key
				mkfs.ext2 /dev/mapper/$key
				mkdir /mnt/$key
				mount /dev/mapper/$key /mnt/$key
				cp /mnt/$serial_keys/$key/$key* /mnt/$key/
				umount /mnt/$key
				rmdir /mnt/$key
				cryptsetup luksClose $key
			done

			umount /mnt/$serial_keys
			rmdir /mnt/$serial_keys
			cryptsetup luksClose $serial_keys

			umount /mnt/$boot_serial
			rmdir /mnt/$boot_serial
			cryptsetup close $boot_serial

			build_NAS
			;;
		B)	erase_dev "$serial_boot"
			;;
		K)	erase_dev "$serial_keys"
			;;
		Kb)	erase_dev "$serial_keys_backup"
			;;
		7)	cd /usr/src/linux \
			&& make \
			&& make menuconfig \
			&& cryptsetup luksOpen /dev/${boot}1 boot \
			&& mount /dev/mapper/boot /boot \
			&& cp /usr/src/linux/arch/x86_64/boot/bzImage /boot/$kernel \
			&& grub-mkconfig -o /boot/grub/grub.cfg \
			&& umount /boot \
			&& cryptsetup luksClose boot
			;;
		9)	gen_new_key "$serial_keys"
			;;
		q) 	exit
			;;
		*)	echo "Invalid option"
			;;
	esac
done
