#!/bin/bash

set -eu

#=================================================
# GET THE SCRIPT'S DIRECTORY
#=================================================

script_dir="$(dirname $(realpath $0))"

#=================================================
# IMPORT FUNCTIONS
#=================================================

source "$script_dir/ssh_chroot/ssh_chroot.sh"
source "$script_dir/unix_quotas/unix_quotas.sh"

#=================================================
# GENERAL ECHOS
#=================================================

bold_echo () {
	echo -e "\e[1m$1\e[0m"
}

error_echo () {
	bold_echo "\e[31m$1" >&2
}

#=================================================
# HELP INFOS
#=================================================

help_notice () {
	exit_code=$1
	echo -e "\e[1m\nUsage of chroot_manager\e[0m
chroot_manager.sh
                  {adduser,deluser,purge,quota,passwd,pubkey,help}

\e[1m  * adduser\e[0m
	Add a new chroot directory for a new user.

\e[1m	-n, --name NAME\e[0m
		Username of the new user.
\e[1m	-p, --password PASSWORD\e[0m
		\e[4mOptional\e[0m. A password for this user.
		You can specify a ssh key instead.
\e[1m	-s, --sshkey SSH_KEY\e[0m
		\e[4mOptional\e[0m. Public ssh key for this user.
		You can specify a password instead. But a ssh key is more secured.
\e[1m	-d, --directory DIRECTORY\e[0m
		Directory where the user will be chrooted.
\e[1m	-q, --quota QUOTA\e[0m
		Maximum space available for this user.
		Default Ko, Use M, G or T to specified another unit.
\e[1m	-h, --help\e[0m
		Show this help message and exit.

\e[1m  * deluser\e[0m
	Delete an user

\e[1m	-n, --name NAME1 [NAME2] [...]\e[0m
		Username of the user to delete.
		You can specify multiple user by simply separate them by a space. (user1 user2 user3 ...)
		To select all the chrooted users, use ALL_USERS instead of any name.
\e[1m	-z, --remove_dir\e[0m
		\e[4mOptional\e[0m. Remove also the directory of this user.
\e[1m	-h, --help\e[0m
		Show this help message and exit.

\e[1m  * purge\e[0m
	Purge the directory of an user by removing all his data.
	Do not remove the directory nor the user. Use 'deluser' to do that.

\e[1m	-n, --name NAME1 [NAME2] [...]\e[0m
		Username of the user to purge.
		You can specify multiple user by simply separate them by a space. (user1 user2 user3 ...)
		To select all the chrooted users, use ALL_USERS instead of any name.
\e[1m	-h, --help\e[0m
		Show this help message and exit.

\e[1m  * quota\e[0m
	Modify, remove or print the quotas for specify users or all users.

\e[1m	-n, --name NAME1 [NAME2] [...]\e[0m
		Username of the user.
		You can specify multiple user by simply separate them by a space. (user1 user2 user3 ...)
		To select all the chrooted users, use ALL_USERS instead of any name.
\e[1m	-w, --watch_quota\e[0m
		\e[4mOptional\e[0m. Print the quotas for the selected users.
\e[1m	-c, --change_quota NEW_QUOTA\e[0m
		\e[4mOptional\e[0m. Modify the quotas for the selected users.
		Default Ko, Use M, G or T to specified another unit.
\e[1m	-r, --remove_quota\e[0m
		\e[4mOptional\e[0m. Remove the quotas for the selected users.
		Be careful, with this option, the selected users will not have any spaces restrictions anymore.
\e[1m	-h, --help\e[0m
		Show this help message and exit.

\e[1m  * passwd\e[0m
	Change the password for an user.

\e[1m	-n, --name NAME\e[0m
		Username of the new user.
\e[1m	-p, --password PASSWORD\e[0m
		New password for this user.
\e[1m	-h, --help\e[0m
		Show this help message and exit.

\e[1m  * pubkey\e[0m
	Change the ssh public key for an user.

\e[1m	-n, --name NAME\e[0m
		Username of the new user.
\e[1m	-s, --sshkey SSH_KEY\e[0m
		New public ssh key for this user.
\e[1m	-h, --help\e[0m
		Show this help message and exit.

\e[1m  * help\e[0m
	Show this help message and exit.
"

	exit $exit_code
}

#=================================================
# CHECK AND READ CLI ARGUMENTS
#=================================================

parse_cli_arguments () {
	# If no arguments provided
	if [ "$#" -eq 0 ]
	then
		# Print the help and exit
		help_notice 1
	else
		# Store arguments in a array to keep each argument separated
		local arguments=("$@")

		# Read the array value per value
		for i in `seq 0 $(( ${#arguments[@]} -1 ))`
		do
			# For each argument in the array, reduce to short argument for getopts
			arguments[$i]=${arguments[$i]//--change_quota/-c}
			arguments[$i]=${arguments[$i]//--directory/-d}
			arguments[$i]=${arguments[$i]//--help/-h}
			arguments[$i]=${arguments[$i]//--name/-n}
			arguments[$i]=${arguments[$i]//--password/-p}
			arguments[$i]=${arguments[$i]//--quota/-q}
			arguments[$i]=${arguments[$i]//--remove_quota/-r}
			arguments[$i]=${arguments[$i]//--sshkey/-s}
			arguments[$i]=${arguments[$i]//--watch_quota/-w}
			arguments[$i]=${arguments[$i]//--remove_dir/-z}
		done

		# Read and parse all the arguments
		# Use a function here, to use standart arguments $@ and be able to use shift.
		parse_arg () {
			while [ $# -ne 0 ]
			do
				# Initialize the index of getopts
				OPTIND=1
				# Parse with getopts only if the argument begin by -
				getopts ":c:d:n:p:q:s:hrwz" parameter || true
				case $parameter in
					c)
						# --change_quota new_quota
						quota_change="$OPTARG"
						shift_value=2
						;;
					d)
						# --directory directory_to_chroot_to
						user_directory="$OPTARG"
						shift_value=2
						;;
					h)
						# --help
						help_notice 0
						;;
					n)
						# --name user_name1 user_name2 user_name3
						users[0]="$OPTARG"
						shift_value=2
						# Read all other arguments to find multiple value for this option.
						# Load args in a array
						all_args=("$@")
						# Read the array value per value
						for i in `seq 2 $(( ${#all_args[@]} -1 ))`
						do
							if [ "${arguments[$i]:0:1}" == "-" ]
							then
								# If this argument is an option, end here.
								break
							else
								# Else, add this user name to this option, by adding a new value to the array
								users+=("${arguments[$i]}")
								shift_value=$(( shift_value + 1 ))
							fi
						done
						;;
					p)
						# --password user_password
						user_password="$OPTARG"
						shift_value=2
						;;
					q)
						# --quota quota_limits
						user_quota="$OPTARG"
						shift_value=2
						;;
					r)
						# --remove_quota
						quota_remove=1
						shift_value=1
						;;
					s)
						# --sshkey ssh_public_key
						user_key="$OPTARG"
						shift_value=2
						;;
					w)
						# --watch_quota
						quota_check=1
						shift_value=1
						;;
					z)
						# --remove_dir
						deldir=1
						shift_value=1
						;;
					\?)
						error_echo "Invalid argument: -${OPTARG:-}"
						help_notice 1
						;;
					:)
						error_echo "-$OPTARG parameter requires an argument."
						help_notice 1
						;;
				esac
				# Shift the parameter and its argument
				shift $shift_value
			done
		}

		# Call parse_arg and pass the modified list of args as a array of arguments.
		parse_arg "${arguments[@]}"

	fi
}

#=================================================
# GLOBAL FUNCTIONS
#=================================================

# Get the chroot directory in the ssh config
find_user_directory () {
	user_directory=$(eval echo $(grep "^[^#].*ChrootDirectory.*$user_name" /etc/ssh/sshd_config | awk '{print $2}'))
}

# Check if this user exist
is_user_exist () {
	if ! getent passwd "$user_name" > /dev/null; then
		error_echo "The user $user_name doesn't exist."
		return 1
	fi
}

# Check if this user is chrooted
is_user_chrooted () {
	if ! grep --quiet "^[^#].*Match User $user_name.*added for the user $user_name" /etc/ssh/sshd_config; then
		error_echo "The user $user_name isn't in a chroot."
		return 1
	fi
}

# Check if the arguments asks for all users
is_all_user () {
	if echo "${users[@]}" | grep --quiet "ALL_USERS"
	then
		users=()	# Purge the array of users
		local user
		while read user
		do
			# Then add each users to the array
			users+=("$user")
		done <<< "$(grep "^[^#].*Match User.*added for the user.*" /etc/ssh/sshd_config | awk '{print $3}')"
	fi
}

#=================================================
#=================================================
# ADD AN USER WITH A CHROOT DIR
#=================================================
#=================================================

add_user () {
	#=================================================
	# CHECK AND READ CLI ARGUMENTS
	#=================================================

	# Init arguments value
	local users[0]=""
	local user_name=""
	local user_password=""
	local user_key=""
	local user_directory=""
	local user_quota=""

	parse_cli_arguments "$@"

	# Check arguments
	if [ -z "$users" ]; then
		error_echo "An user name is required."
		help_notice 1
	fi
	if [ -z "$user_directory" ]; then
		error_echo "An directory is required for this user."
		help_notice 1
	fi
	if [ -z "$user_password" ] && [ -z "$user_key" ]; then
		error_echo "At least a password or a ssh key is required."
		help_notice 1
	fi

	# Work on the first user only
	user_name=${users[0]}

	#=================================================
	# CREATE THE USER
	#=================================================

	user_name=${user_name//[^[:alnum:].\-_]/_}

	if ! getent passwd "$user_name" > /dev/null
	then
		bold_echo "Create the user $user_name."
		sudo useradd -d "/data" --system --user-group $user_name --shell /bin/bash
		# The home directory for this user is /data, relative to its chroot directory, $user_dir
	else
		error_echo "The user $user_name already exist"
		exit 1
	fi

	#=================================================
	# ADD A PASSWORD FOR THIS USER
	#=================================================

	if [ -n "$user_password" ]
	then
		echo $user_name:$user_password | sudo chpasswd
	fi

	#=================================================
	# ADD THE SSH PUBLIC KEY
	#=================================================

	if [ -n "$user_key" ]
	then
		sudo mkdir -p "$user_directory/.ssh"
		# Secure the ssh key
		echo -n "no-port-forwarding,no-X11-forwarding,no-agent-forwarding " | sudo tee -a "$user_directory/.ssh/authorized_keys" > /dev/null
		# Then add the key
		echo "$user_key" | sudo tee -a "$user_directory/.ssh/authorized_keys" > /dev/null
	fi

	#=================================================
	# SET THE QUOTA FOR THIS USER
	#=================================================

	if [ -n "$user_quota" ]
	then
		quotas_set_for_user $user_name "$user_directory" $user_quota
	fi

	#=================================================
	# SET THE CHROOT DIRECTORY
	#=================================================

	# Build the chroot
	ssh_chroot_set_directory "$user_directory"

	# Copy some binaries in the chroot
	ssh_chroot_standard_binaries "$user_directory"
	ssh_chroot_copy_binary rsync "$user_directory"

	# Set permissions
	ssh_chroot_set_permissions "$user_directory" $user_name

	# Set the chroot in the ssh config
	ssh_chroot_add_chroot_config "$user_directory" $user_name
}


#=================================================
#=================================================
# REMOVE AN USER
#=================================================
#=================================================

remove_user () {
	#=================================================
	# CHECK AND READ CLI ARGUMENTS
	#=================================================

	# Init arguments value
	local users[0]=""
	local user_name=""
	local deldir=0
	local shift_value=1

	parse_cli_arguments "$@"

	# Check arguments
	if [ -z "$users" ]; then
		error_echo "An user name is required."
		help_notice 1
	fi

	# Check if the arguments asks for all users
	is_all_user

	# Work on each specified user
	for i in `seq 0 $(( ${#users[@]} -1 ))`
	do
		user_name=${users[$i]}

		is_user_exist || continue
		is_user_chrooted || continue

		#=================================================
		# REMOVE USER DIR
		#=================================================

		if [ $deldir -eq 1 ]
		then
			# Get the chroot directory in the ssh config
			local user_directory
			find_user_directory
			if [ -n "$user_directory" ]
			then
				bold_echo "Remove the directory $user_directory for the user $user_name."
				sudo rm --force --recursive --one-file-system --preserve-root "$user_directory"
			fi
		fi

		#=================================================
		# REMOVE SSH CHROOT CONFIG
		#=================================================

		sudo sed -i "/# Automatically added for the user $user_name/d" /etc/ssh/sshd_config

		# Reload ssh service
		sudo systemctl reload ssh
		
		#=================================================
		# DELETE THE USER
		#=================================================

		bold_echo "Delete the user $user_name."
		sudo userdel $user_name
	done
}


#=================================================
#=================================================
# CLEAN THE DIRECTORY OF AN USER
#=================================================
#=================================================

purge_dir_user () {
	#=================================================
	# CHECK AND READ CLI ARGUMENTS
	#=================================================

	# Init arguments value
	local users[0]=""
	local user_name=""

	parse_cli_arguments "$@"

	# Check arguments
	if [ -z "$users" ]; then
		error_echo "An user name is required."
		help_notice 1
	fi

	# Check if the arguments asks for all users
	is_all_user

	# Work on each specified user
	for i in `seq 0 $(( ${#users[@]} -1 ))`
	do
		user_name=${users[$i]}

		is_user_exist || continue
		is_user_chrooted || continue

		#=================================================
		# PURGE USER DIR
		#=================================================

		# Get the chroot directory in the ssh config
		local user_directory=""
		find_user_directory
		if [ -n "$user_directory" ]
		then
			bold_echo "Purge the directory $user_directory for the user $user_name."
			sudo rm --recursive --one-file-system --preserve-root "$user_directory/data"

			sudo mkdir "$user_directory/data"
			sudo chown $user_name: -R "$user_directory/data"
		fi
	done
}


#=================================================
#=================================================
# CHECK OR CHANGE THE QUOTA FOR USERS
#=================================================
#=================================================

quota_check () {
	#=================================================
	# CHECK AND READ CLI ARGUMENTS
	#=================================================

	# Init arguments value
	local users[0]=""
	local user_name=""
	local quota_check=0
	local quota_change=""
	local quota_remove=0

	parse_cli_arguments "$@"

	# Check arguments
	if [ -z "$users" ]; then
		# If there're no users name specified, do only a check
		quota_check=1
	fi
	if [ -n "$quota_change" ] && [ $quota_remove -eq 1 ]; then
		error_echo "You have to choose between --change_quota and --remove_quota."
		help_notice 1
	fi

	# Check if the arguments asks for all users
	is_all_user

	# Work on each specified user
	for i in `seq 0 $(( ${#users[@]} -1 ))`
	do
		user_name=${users[$i]}

		is_user_exist || continue
		is_user_chrooted || continue

		#=================================================
		# CHANGE THE QUOTAS
		#=================================================

		if [ -n "$quota_change" ]
		then

			# Get the chroot directory in the ssh config
			local user_directory
			find_user_directory

			quotas_set_for_user $user_name "$user_directory" $quota_change
		fi

		#=================================================
		# REMOVE THE QUOTAS
		#=================================================

		if [ "$quota_remove" -eq 1 ]
		then

			# Get the chroot directory in the ssh config
			local user_directory
			find_user_directory

			quotas_set_for_user $user_name "$user_directory" 0
		fi

		#=================================================
		# CHECK THE QUOTAS
		#=================================================

		quotas_check_user $user_name
		# If --watch_quota is specified, print only the quotas, nothing else.
		continue

	done
}


#=================================================
#=================================================
# CHANGE THE PASSWORD FOR AN USER
#=================================================
#=================================================

passwd_change () {
	#=================================================
	# CHECK AND READ CLI ARGUMENTS
	#=================================================

	# Init arguments value
	local users[0]=""
	local user_name=""
	local user_password=""

	parse_cli_arguments "$@"

	# Check arguments
	if [ -z "$users" ]; then
		error_echo "An user name is required."
		help_notice 1
	fi
	if [ -z "$user_password" ]; then
		error_echo "A password is required."
		help_notice 1
	fi

	# Work on the first user only
	user_name=${users[0]}

	is_user_exist || exit 1
	is_user_chrooted || exit 1

	#=================================================
	# CHANGE THE PASSWORD FOR THIS USER
	#=================================================

	bold_echo "Change password for user $user_name"
	echo $user_name:$user_password | sudo chpasswd
}


#=================================================
#=================================================
# CHANGE THE SSH KEY FOR AN USER
#=================================================
#=================================================

pubkey_change () {
	#=================================================
	# CHECK AND READ CLI ARGUMENTS
	#=================================================

	# Init arguments value
	local users[0]=""
	local user_name=""
	local user_key=""

	parse_cli_arguments "$@"
	
	# Check arguments
	if [ -z "$users" ]; then
		error_echo "An user name is required."
		help_notice 1
	fi
	if [ -z "$user_key" ]; then
		error_echo "A ssk key is required."
		help_notice 1
	fi

	# Work on the first user only
	user_name=${users[0]}

	is_user_exist || exit 1
	is_user_chrooted || exit 1

	#=================================================
	# ADD THE SSH PUBLIC KEY
	#=================================================

	bold_echo "Change ssh public key for user $user_name"

	# Get the chroot directory in the ssh config
	local user_directory
	find_user_directory

	sudo mkdir -p "$user_directory/.ssh"
	# Secure the ssh key
	echo -n "no-port-forwarding,no-X11-forwarding,no-agent-forwarding " | sudo tee "$user_directory/.ssh/authorized_keys" > /dev/null
	# Then add the key
	echo "$user_key" | sudo tee -a "$user_directory/.ssh/authorized_keys" > /dev/null
	bold_echo "New ssh public key:\n\e[0m$user_key"
}


#=================================================
# HANDLE MAIN COMMANDS
#=================================================

if [ $# -gt 0 ]; then
	command=$1
else
	help_notice 1
fi

case $command in
	adduser)
		shift 1
		add_user "$@"
		;;
	deluser)
		shift 1
		remove_user "$@"
		;;
	purge)
		shift 1
		purge_dir_user "$@"
		;;
	quota)
		shift 1
		quota_check "$@"
		;;
	passwd)
		shift 1
		passwd_change "$@"
		;;
	pubkey)
		shift 1
		pubkey_change "$@"
		;;
	help)
		help_notice 0
		;;
	*)
		error_echo "Invalid argument: $command" >&2
		help_notice 1
		;;
esac
