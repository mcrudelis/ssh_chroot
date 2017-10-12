#!/bin/bash

# Prepare a directory for a ssh chroot
ssh_chroot_set_directory () {
	local chroot_dir="$1"
	# Create binaries directories
	sudo mkdir -p "$chroot_dir/"{bin,lib,lib64,data}

	# Copy the ld-linux file, according to the architecture
	copy_ld-linux () {
		! test -e "$1" || sudo cp "$1" "$chroot_dir/$2/"
	}
	copy_ld-linux /lib/ld-linux.so.2 lib
	copy_ld-linux /lib64/ld-linux-x86-64.so.2 lib64
	copy_ld-linux /lib/ld-linux-armhf.so.3 lib
}

# Copy binary and its libraries into the chroot.
ssh_chroot_copy_binary () {
	local chroot_dir="$2"
	echo "Add the binary $1 in the chroot directory"
	# Find and copy the binary file
	sudo cp `which $1` "$chroot_dir/bin/$(basename $1)"
	# Then search for its libraries
	while read lib_file
	do
		# Filter lib without path
		if echo "$lib_file" | grep --quiet "=> /"
		then
			# Keep only the path of this lib
			local lib_path=$(echo "$lib_file" | awk '{print $3}')
			sudo cp $lib_path "$chroot_dir/lib/"
		fi
	done <<< "$(ldd `which $1`)"
}

# Copy some usual binaries in the chroot
ssh_chroot_standard_binaries () {
	local chroot_dir="$1"
	ssh_chroot_copy_binary bash "$chroot_dir"
	ssh_chroot_copy_binary cat "$chroot_dir"
	ssh_chroot_copy_binary cp "$chroot_dir"
	ssh_chroot_copy_binary du "$chroot_dir"
	ssh_chroot_copy_binary ls "$chroot_dir"
	ssh_chroot_copy_binary mkdir "$chroot_dir"
	ssh_chroot_copy_binary mv "$chroot_dir"
	ssh_chroot_copy_binary rm "$chroot_dir"
	ssh_chroot_copy_binary rmdir "$chroot_dir"
	ssh_chroot_copy_binary sftp "$chroot_dir"
	ssh_chroot_copy_binary /usr/lib/openssh/sftp-server "$chroot_dir"
}


# Set permissions
ssh_chroot_set_permissions () {
	local chroot_dir="$1"
	local user="$2"

	sudo chown root: -R "$chroot_dir"
	sudo chown $user: -R "$chroot_dir/data"
	# The parent directory shall be handled by root. It's necessary for chroot.
# 	sudo chown root: "$chroot_dir"
}

# Set the chroot in the ssh config for this user
ssh_chroot_add_chroot_config () {
	local chroot_dir="$1"
	local user="$2"

	echo -e "
	Match User $user\t# Automatically added for the user $user
	ChrootDirectory \"$chroot_dir\"\t# Automatically added for the user $user
	AllowTcpForwarding no\t# Automatically added for the user $user
	X11Forwarding no\t# Automatically added for the user $user
	AuthorizedKeysFile \"$chroot_dir/.ssh/authorized_keys\"\t# Automatically added for the user $user" | sudo tee -a /etc/ssh/sshd_config

	# Reload ssh service
	sudo systemctl reload ssh
}
