#!/bin/bash

# Prepare a directory for a ssh chroot
ssh_chroot_set_directory () {
	local chroot_dir="$1"
	# Create binaries directories
	sudo mkdir -p $chroot_dir/{bin,lib,lib64}

	# Copy the ld-linux file, according to the architecture
	copy_ld-linux () {
		test -e "$1" && sudo cp "$1" $chroot_dir/lib/
	}
	copy_ld-linux /lib/ld-linux.so.2
	copy_ld-linux /lib64/ld-linux-x86-64.so.2
	copy_ld-linux /lib/ld-linux-armhf.so.3
}

# Copy binary and its libraries into the chroot.
ssh_chroot_copy_binary () {
	local chroot_dir="$2"
	echo "Add the binary $1 in the chroot directory"
	# Find and copy the binary file
	sudo cp `which $1` $chroot_dir/bin/$1
	# Then search for its libraries
	while read lib_file
	do
		# Filter lib without path
		if echo "$lib_file" | grep --quiet "=> /"
		then
			# Keep only the path of this lib
			local lib_path=$(echo "$lib_file" | awk '{print $3}')
			sudo cp $lib_path $chroot_dir/lib/
		fi
	done <<< "$(ldd `which $1`)"
}

# Set permissions
ssh_chroot_set_permissions () {
	local chroot_dir="$1"
	local user="$2"

	sudo chown $user: -R "$chroot_dir"
	sudo chown root: -R "$chroot_dir/"{bin,lib,lib64}
	# The parent directory shall be handled by root. It's necessary for chroot.
	sudo chown root: "$chroot_dir"
}

# Set the chroot in the ssh config for this user
ssh_chroot_add_chroot_config () {
	local chroot_dir="$1"
	local user="$2"

	echo "
	Match User $user # Automatically added for the user $user
	ChrootDirectory $chroot_dir # Automatically added for the user $user
	AllowTcpForwarding no # Automatically added for the user $user
	X11Forwarding no # Automatically added for the user $user" | sudo tee -a /etc/ssh/sshd_config

	# Reload ssh service
	sudo systemctl reload ssh
}
