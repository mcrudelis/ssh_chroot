#!/bin/bash

# Set up quotas system
quotas_install () {
	# Install quota tools
	sudo apt-get install -y quota quotatool

	# Add the quota_v2 module in the kernel
	sudo modprobe quota_v2 || echo "Unable to load quota_v2 module with modprobe" >&2

	if ! grep --quiet "quota_v2" /etc/modules; then
		echo 'quota_v2' | sudo tee -a /etc/modules
	fi
}

quotas_find_mount_point () {
	local directory_to_find="$1"
	quotas_mount_point=""

	# Find a mount point in fstab
	mount_point_finder () {
		if mount | grep -q " on $1 "; then
			quotas_mount_point=$(findmnt "$1" --nofsroot --uniq --output source --noheadings --first-only)
		fi
	}

	while test -z "$quotas_mount_point"
	do
		mount_point_finder "$directory_to_find"
		if [ -z "$quotas_mount_point" ]
		then
			echo "Unable to find $directory_to_find in mounted devices"
			if [ "$directory_to_find" == "/" ]; then
				echo "Unable to find any entry in mounted devices"; exit 1
			fi
			directory_to_find=$(dirname "$directory_to_find")
			echo "Try to find $directory_to_find instead"
		fi
	done
	echo "Found $directory_to_find in mounted devices"
}

quotas_int_fstab_failed () {
	# Restore the backup of fstab
	sudo cp /etc/fstab_backup_$app /etc/fstab
	sudo mount -a
	echo "Failed to modify fstab automatically."
	echo "Please add ',usrjquota=aquota.user,jqfmt=vfsv0' to the mount option for $mount_point_to_find"
}

quotas_int_fstab_find_line () {
	local mount_point_to_find="$1"

	# Get other values for this mount point
	local uuid=$(sudo blkid $mount_point_to_find -o value -s UUID)
	local partuuid=$(sudo blkid $mount_point_to_find -o value -s PARTUUID)

	# Find an entry in fstab
	fstab_finder () {
		if [ -n "$1" ]
		then
			if grep -q "$1" /etc/fstab; then
				fstab_line=$(grep -m1 "^[^#]*$1" /etc/fstab) || true
			fi
		fi
	}

	while test -z "$fstab_line"
	do
		fstab_finder "$mount_point_to_find"
		if [ -z "$fstab_line" ]
		then
			echo "Unable to find $mount_point_to_find in fstab"
			if [ "$mount_point_to_find" == "$1" ] && [ -n "$uuid" ]; then
				mount_point_to_find="$uuid"
			elif [ "$mount_point_to_find" == "$uuid" ] && [ -n "$partuuid" ]; then
				mount_point_to_find="$partuuid"
			else
				echo "Unable to find any entry for this mount point in fstab"; exit 1
			fi
			echo "Try to find $mount_point_to_find instead"
		fi
	done
	echo "Found $mount_point_to_find in fstab"
}

quotas_set_fstab () {
	local mount_point_to_find="$1"
	local fstab_line=""

	quotas_int_fstab_find_line "$mount_point_to_find"

	# Check if this fstab entry has already the quota option.
	if ! echo "$fstab_line" | grep -q "quota"
	then
		# Get only the options for this mount point
		fstab_option=$(echo "$fstab_line" | awk '{print $4}')
		# Then only the device
		fstab_device=$(echo "$fstab_line" | awk '{print $1}')
		echo "A backup of your fstab will be made in /etc/fstab_backup_$app before any modification"
		sudo cp /etc/fstab /etc/fstab_backup_$app
		# Modify only the option for this mount point
		sudo sed -i "s@^\($fstab_device.*$fstab_option\)\(.*\)@\1,usrjquota=aquota.user,jqfmt=vfsv0\2@" /etc/fstab
		# Try fstab
		sudo mount -o remount $1 || quotas_int_fstab_failed
		sudo mount -a || quotas_int_fstab_failed
	fi
}

quotas_clean_fstab () {
	local mount_point_to_find="$1"
	local fstab_line=""

	quotas_int_fstab_find_line "$mount_point_to_find"

	# Then only the device
	fstab_device=$(echo "$fstab_line" | awk '{print $1}')
	echo "A backup of your fstab will be made in /etc/fstab_backup_$app before any modification"
	sudo cp /etc/fstab /etc/fstab_backup_$app
	# Remove only the options for this mount point
	sudo sed -i "s@^\($fstab_device.*\),usrjquota=aquota.user,jqfmt=vfsv0\(.*\)@\1\2@" /etc/fstab

	# Try fstab
	sudo mount -o remount $1 || quotas_int_fstab_failed
	sudo mount -a || quotas_int_fstab_failed

}

quotas_activate () {
	local mount_point="$1"

	quotas_deactivate "$mount_point"

	# Activate quotas
	sudo quotacheck --verbose --all --group --user --no-remount 2>&1

	sudo quotaon $mount_point
}

quotas_deactivate () {
	local mount_point="$1"

	sudo quotaoff $mount_point
}

quotas_set_for_user () {
	local user=$1
	local directory=$2
	local quota=$3

	quotas_find_mount_point "$directory" > /dev/null

	sudo quotatool -v -u $user -b -l "$quota" $quotas_mount_point 2>&1
}

quotas_check_user () {
	local user=$1

	repquota_out=$(sudo repquota --verbose --all --human-readable --user | grep "^$user *--")
	echo "Quota report for $user:"
	echo -e "\tUsed: $(echo $repquota_out | awk '{print $3}')"
	echo -e "\tLimit: $(echo $repquota_out | awk '{print $5}')"
}
