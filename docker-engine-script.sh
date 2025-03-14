#!/bin/sh
set -e

SCRIPT_COMMIT_SHA="4c94a56999e10efcf48c5b8e3f6afea464f9108e"

VERSION="${VERSION#v}"

DEFAULT_CHANNEL_VALUE="stable"
if [ -z "$CHANNEL" ]; then
	CHANNEL=$DEFAULT_CHANNEL_VALUE
fi

DEFAULT_DOWNLOAD_URL="https://download.docker.com"
if [ -z "$DOWNLOAD_URL" ]; then
	DOWNLOAD_URL=$DEFAULT_DOWNLOAD_URL
fi

DEFAULT_REPO_FILE="docker-ce.repo"
if [ -z "$REPO_FILE" ]; then
	REPO_FILE="$DEFAULT_REPO_FILE"
fi

mirror=''
DRY_RUN=${DRY_RUN:-}
while [ $# -gt 0 ]; do
	case "$1" in
		--channel)
			CHANNEL="$2"
			shift
			;;
		--dry-run)
			DRY_RUN=1
			;;
		--mirror)
			mirror="$2"
			shift
			;;
		--version)
			VERSION="${2#v}"
			shift
			;;
		--*)
			echo "Illegal option $1"
			;;
	esac
	shift $(( $# > 0 ? 1 : 0 ))
done

case "$mirror" in
	Aliyun)
		DOWNLOAD_URL="https://mirrors.aliyun.com/docker-ce"
		;;
	AzureChinaCloud)
		DOWNLOAD_URL="https://mirror.azure.cn/docker-ce"
		;;
	"")
		;;
	*)
		>&2 echo "unknown mirror '$mirror': use either 'Aliyun', or 'AzureChinaCloud'."
		exit 1
		;;
esac

case "$CHANNEL" in
	stable|test)
		;;
	*)
		>&2 echo "unknown CHANNEL '$CHANNEL': use either stable or test."
		exit 1
		;;
esac

command_exists() {
	command -v "$@" > /dev/null 2>&1
}

version_gte() {
	if [ -z "$VERSION" ]; then
			return 0
	fi
	version_compare "$VERSION" "$1"
}

version_compare() (
	set +x

	yy_a="$(echo "$1" | cut -d'.' -f1)"
	yy_b="$(echo "$2" | cut -d'.' -f1)"
	if [ "$yy_a" -lt "$yy_b" ]; then
		return 1
	fi
	if [ "$yy_a" -gt "$yy_b" ]; then
		return 0
	fi
	mm_a="$(echo "$1" | cut -d'.' -f2)"
	mm_b="$(echo "$2" | cut -d'.' -f2)"

	mm_a="${mm_a#0}"
	mm_b="${mm_b#0}"

	if [ "${mm_a:-0}" -lt "${mm_b:-0}" ]; then
		return 1
	fi

	return 0
)

is_dry_run() {
	if [ -z "$DRY_RUN" ]; then
		return 1
	else
		return 0
	fi
}

is_wsl() {
	case "$(uname -r)" in
	*microsoft* ) true ;; # WSL 2
	*Microsoft* ) true ;; # WSL 1
	* ) false;;
	esac
}

is_darwin() {
	case "$(uname -s)" in
	*darwin* ) true ;;
	*Darwin* ) true ;;
	* ) false;;
	esac
}

deprecation_notice() {
	distro=$1
	distro_version=$2
	echo
	printf "\033[91;1mDEPRECATION WARNING\033[0m\n"
	printf "    This Linux distribution (\033[1m%s %s\033[0m) reached end-of-life and is no longer supported by this script.\n" "$distro" "$distro_version"
	echo   "    No updates or security fixes will be released for this distribution, and users are recommended"
	echo   "    to upgrade to a currently maintained version of $distro."
	echo
	printf   "Press \033[1mCtrl+C\033[0m now to abort this script, or wait for the installation to continue."
	echo
	sleep 10
}

get_distribution() {
	lsb_dist=""
	if [ -r /etc/os-release ]; then
		lsb_dist="$(. /etc/os-release && echo "$ID")"
	fi
	echo "$lsb_dist"
}

echo_docker_as_nonroot() {
	if is_dry_run; then
		return
	fi
	if command_exists docker && [ -e /var/run/docker.sock ]; then
		(
			set -x
			$sh_c 'docker version'
		) || true
	fi

	echo
	echo "================================================================================"
	echo
	if version_gte "20.10"; then
		echo "To run Docker as a non-privileged user, consider setting up the"
		echo "Docker daemon in rootless mode for your user:"
		echo
		echo "    dockerd-rootless-setuptool.sh install"
		echo
		echo "Visit https://docs.docker.com/go/rootless/ to learn about rootless mode."
		echo
	fi
	echo
	echo "To run the Docker daemon as a fully privileged service, but granting non-root"
	echo "users access, refer to https://docs.docker.com/go/daemon-access/"
	echo
	echo "WARNING: Access to the remote API on a privileged Docker daemon is equivalent"
	echo "         to root access on the host. Refer to the 'Docker daemon attack surface'"
	echo "         documentation for details: https://docs.docker.com/go/attack-surface/"
	echo
	echo "================================================================================"
	echo
}

check_forked() {

	if command_exists lsb_release; then
		set +e
		lsb_release -a -u > /dev/null 2>&1
		lsb_release_exit_code=$?
		set -e

		if [ "$lsb_release_exit_code" = "0" ]; then
			cat <<-EOF
			You're using '$lsb_dist' version '$dist_version'.
			EOF

			lsb_dist=$(lsb_release -a -u 2>&1 | tr '[:upper:]' '[:lower:]' | grep -E 'id' | cut -d ':' -f 2 | tr -d '[:space:]')
			dist_version=$(lsb_release -a -u 2>&1 | tr '[:upper:]' '[:lower:]' | grep -E 'codename' | cut -d ':' -f 2 | tr -d '[:space:]')

			cat <<-EOF
			Upstream release is '$lsb_dist' version '$dist_version'.
			EOF
		else
			if [ -r /etc/debian_version ] && [ "$lsb_dist" != "ubuntu" ] && [ "$lsb_dist" != "raspbian" ]; then
				if [ "$lsb_dist" = "osmc" ]; then
					lsb_dist=raspbian
				else
					lsb_dist=debian
				fi
				dist_version="$(sed 's/\/.*//' /etc/debian_version | sed 's/\..*//')"
				case "$dist_version" in
					12)
						dist_version="bookworm"
					;;
					11)
						dist_version="bullseye"
					;;
					10)
						dist_version="buster"
					;;
					9)
						dist_version="stretch"
					;;
					8)
						dist_version="jessie"
					;;
				esac
			fi
		fi
	fi
}

do_install() {
	echo "# Executing docker install script, commit: $SCRIPT_COMMIT_SHA"

	if command_exists docker; then
		cat >&2 <<-'EOF'
			Warning: the "docker" command appears to already exist on this system.

			If you already have Docker installed, this script can cause trouble, which is
			why we're displaying this warning and provide the opportunity to cancel the
			installation.

			If you installed the current Docker package using this script and are using it
			again to update Docker, you can ignore this message, but be aware that the
			script resets any custom changes in the deb and rpm repo configuration
			files to match the parameters passed to the script.

			You may press Ctrl+C now to abort this script.
		EOF
		( set -x; sleep 20 )
	fi

	user="$(id -un 2>/dev/null || true)"

	sh_c='sh -c'
	if [ "$user" != 'root' ]; then
		if command_exists sudo; then
			sh_c='sudo -E sh -c'
		elif command_exists su; then
			sh_c='su -c'
		else
			cat >&2 <<-'EOF'
			Error: this installer needs the ability to run commands as root.
			We are unable to find either "sudo" or "su" available to make this happen.
			EOF
			exit 1
		fi
	fi

	if is_dry_run; then
		sh_c="echo"
	fi

	lsb_dist=$( get_distribution )
	lsb_dist="$(echo "$lsb_dist" | tr '[:upper:]' '[:lower:]')"

	if is_wsl; then
		echo
		echo "WSL DETECTED: We recommend using Docker Desktop for Windows."
		echo "Please get Docker Desktop from https://www.docker.com/products/docker-desktop/"
		echo
		cat >&2 <<-'EOF'

			You may press Ctrl+C now to abort this script.
		EOF
		( set -x; sleep 20 )
	fi

	case "$lsb_dist" in

		ubuntu)
			if command_exists lsb_release; then
				dist_version="$(lsb_release --codename | cut -f2)"
			fi
			if [ -z "$dist_version" ] && [ -r /etc/lsb-release ]; then
				dist_version="$(. /etc/lsb-release && echo "$DISTRIB_CODENAME")"
			fi
		;;

		debian|raspbian)
			dist_version="$(sed 's/\/.*//' /etc/debian_version | sed 's/\..*//')"
			case "$dist_version" in
				12)
					dist_version="bookworm"
				;;
				11)
					dist_version="bullseye"
				;;
				10)
					dist_version="buster"
				;;
				9)
					dist_version="stretch"
				;;
				8)
					dist_version="jessie"
				;;
			esac
		;;

		centos|rhel)
			if [ -z "$dist_version" ] && [ -r /etc/os-release ]; then
				dist_version="$(. /etc/os-release && echo "$VERSION_ID")"
			fi
		;;

		*)
			if command_exists lsb_release; then
				dist_version="$(lsb_release --release | cut -f2)"
			fi
			if [ -z "$dist_version" ] && [ -r /etc/os-release ]; then
				dist_version="$(. /etc/os-release && echo "$VERSION_ID")"
			fi
		;;

	esac

	check_forked

	case "$lsb_dist.$dist_version" in
		centos.8|centos.7|rhel.7)
			deprecation_notice "$lsb_dist" "$dist_version"
			;;
		debian.buster|debian.stretch|debian.jessie)
			deprecation_notice "$lsb_dist" "$dist_version"
			;;
		raspbian.buster|raspbian.stretch|raspbian.jessie)
			deprecation_notice "$lsb_dist" "$dist_version"
			;;
		ubuntu.bionic|ubuntu.xenial|ubuntu.trusty)
			deprecation_notice "$lsb_dist" "$dist_version"
			;;
		ubuntu.mantic|ubuntu.lunar|ubuntu.kinetic|ubuntu.impish|ubuntu.hirsute|ubuntu.groovy|ubuntu.eoan|ubuntu.disco|ubuntu.cosmic)
			deprecation_notice "$lsb_dist" "$dist_version"
			;;
		fedora.*)
			if [ "$dist_version" -lt 40 ]; then
				deprecation_notice "$lsb_dist" "$dist_version"
			fi
			;;
	esac

	case "$lsb_dist" in
		ubuntu|debian|raspbian)
			pre_reqs="ca-certificates curl"
			apt_repo="deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] $DOWNLOAD_URL/linux/$lsb_dist $dist_version $CHANNEL"
			(
				if ! is_dry_run; then
					set -x
				fi
				$sh_c 'apt-get -qq update >/dev/null'
				$sh_c "DEBIAN_FRONTEND=noninteractive apt-get -y -qq install $pre_reqs >/dev/null"
				$sh_c 'install -m 0755 -d /etc/apt/keyrings'
				$sh_c "curl -fsSL \"$DOWNLOAD_URL/linux/$lsb_dist/gpg\" -o /etc/apt/keyrings/docker.asc"
				$sh_c "chmod a+r /etc/apt/keyrings/docker.asc"
				$sh_c "echo \"$apt_repo\" > /etc/apt/sources.list.d/docker.list"
				$sh_c 'apt-get -qq update >/dev/null'
			)
			pkg_version=""
			if [ -n "$VERSION" ]; then
				if is_dry_run; then
					echo "# WARNING: VERSION pinning is not supported in DRY_RUN"
				else
					pkg_pattern="$(echo "$VERSION" | sed 's/-ce-/~ce~.*/g' | sed 's/-/.*/g')"
					search_command="apt-cache madison docker-ce | grep '$pkg_pattern' | head -1 | awk '{\$1=\$1};1' | cut -d' ' -f 3"
					pkg_version="$($sh_c "$search_command")"
					echo "INFO: Searching repository for VERSION '$VERSION'"
					echo "INFO: $search_command"
					if [ -z "$pkg_version" ]; then
						echo
						echo "ERROR: '$VERSION' not found amongst apt-cache madison results"
						echo
						exit 1
					fi
					if version_gte "18.09"; then
							search_command="apt-cache madison docker-ce-cli | grep '$pkg_pattern' | head -1 | awk '{\$1=\$1};1' | cut -d' ' -f 3"
							echo "INFO: $search_command"
							cli_pkg_version="=$($sh_c "$search_command")"
					fi
					pkg_version="=$pkg_version"
				fi
			fi
			(
				pkgs="docker-ce${pkg_version%=}"
				if version_gte "18.09"; then
						pkgs="$pkgs docker-ce-cli${cli_pkg_version%=} containerd.io"
				fi
				if version_gte "20.10"; then
						pkgs="$pkgs docker-compose-plugin docker-ce-rootless-extras$pkg_version"
				fi
				if version_gte "23.0"; then
						pkgs="$pkgs docker-buildx-plugin"
				fi
				if ! is_dry_run; then
					set -x
				fi
				$sh_c "DEBIAN_FRONTEND=noninteractive apt-get -y -qq install $pkgs >/dev/null"
			)
			echo_docker_as_nonroot
			exit 0
			;;
		centos|fedora|rhel)
			repo_file_url="$DOWNLOAD_URL/linux/$lsb_dist/$REPO_FILE"
			(
				if ! is_dry_run; then
					set -x
				fi
				if command_exists dnf5; then
					$sh_c "dnf -y -q --setopt=install_weak_deps=False install dnf-plugins-core"
					$sh_c "dnf5 config-manager addrepo --overwrite --save-filename=docker-ce.repo --from-repofile='$repo_file_url'"

					if [ "$CHANNEL" != "stable" ]; then
						$sh_c "dnf5 config-manager setopt \"docker-ce-*.enabled=0\""
						$sh_c "dnf5 config-manager setopt \"docker-ce-$CHANNEL.enabled=1\""
					fi
					$sh_c "dnf makecache"
				elif command_exists dnf; then
					$sh_c "dnf -y -q --setopt=install_weak_deps=False install dnf-plugins-core"
					$sh_c "rm -f /etc/yum.repos.d/docker-ce.repo  /etc/yum.repos.d/docker-ce-staging.repo"
					$sh_c "dnf config-manager --add-repo $repo_file_url"

					if [ "$CHANNEL" != "stable" ]; then
						$sh_c "dnf config-manager --set-disabled \"docker-ce-*\""
						$sh_c "dnf config-manager --set-enabled \"docker-ce-$CHANNEL\""
					fi
					$sh_c "dnf makecache"
				else
					$sh_c "yum -y -q install yum-utils"
					$sh_c "rm -f /etc/yum.repos.d/docker-ce.repo  /etc/yum.repos.d/docker-ce-staging.repo"
					$sh_c "yum-config-manager --add-repo $repo_file_url"

					if [ "$CHANNEL" != "stable" ]; then
						$sh_c "yum-config-manager --disable \"docker-ce-*\""
						$sh_c "yum-config-manager --enable \"docker-ce-$CHANNEL\""
					fi
					$sh_c "yum makecache"
				fi
			)
			pkg_version=""
			if command_exists dnf; then
				pkg_manager="dnf"
				pkg_manager_flags="-y -q --best"
			else
				pkg_manager="yum"
				pkg_manager_flags="-y -q"
			fi
			if [ -n "$VERSION" ]; then
				if is_dry_run; then
					echo "# WARNING: VERSION pinning is not supported in DRY_RUN"
				else
					if [ "$lsb_dist" = "fedora" ]; then
						pkg_suffix="fc$dist_version"
					else
						pkg_suffix="el"
					fi
					pkg_pattern="$(echo "$VERSION" | sed 's/-ce-/\\\\.ce.*/g' | sed 's/-/.*/g').*$pkg_suffix"
					search_command="$pkg_manager list --showduplicates docker-ce | grep '$pkg_pattern' | tail -1 | awk '{print \$2}'"
					pkg_version="$($sh_c "$search_command")"
					echo "INFO: Searching repository for VERSION '$VERSION'"
					echo "INFO: $search_command"
					if [ -z "$pkg_version" ]; then
						echo
						echo "ERROR: '$VERSION' not found amongst $pkg_manager list results"
						echo
						exit 1
					fi
					if version_gte "18.09"; then
						search_command="$pkg_manager list --showduplicates docker-ce-cli | grep '$pkg_pattern' | tail -1 | awk '{print \$2}'"
						cli_pkg_version="$($sh_c "$search_command" | cut -d':' -f 2)"
					fi
					pkg_version="-$(echo "$pkg_version" | cut -d':' -f 2)"
				fi
			fi
			(
				pkgs="docker-ce$pkg_version"
				if version_gte "18.09"; then
					if [ -n "$cli_pkg_version" ]; then
						pkgs="$pkgs docker-ce-cli-$cli_pkg_version containerd.io"
					else
						pkgs="$pkgs docker-ce-cli containerd.io"
					fi
				fi
				if version_gte "20.10"; then
					pkgs="$pkgs docker-compose-plugin docker-ce-rootless-extras$pkg_version"
				fi
				if version_gte "23.0"; then
						pkgs="$pkgs docker-buildx-plugin"
				fi
				if ! is_dry_run; then
					set -x
				fi
				$sh_c "$pkg_manager $pkg_manager_flags install $pkgs"
			)
			echo_docker_as_nonroot
			exit 0
			;;
		sles)
			if [ "$(uname -m)" != "s390x" ]; then
				echo "Packages for SLES are currently only available for s390x"
				exit 1
			fi
			repo_file_url="$DOWNLOAD_URL/linux/$lsb_dist/$REPO_FILE"
			pre_reqs="ca-certificates curl libseccomp2 awk"
			(
				if ! is_dry_run; then
					set -x
				fi
				$sh_c "zypper install -y $pre_reqs"
				$sh_c "rm -f /etc/zypp/repos.d/docker-ce-*.repo"
				$sh_c "zypper addrepo $repo_file_url"

				opensuse_factory_url="https://download.opensuse.org/repositories/security:/SELinux/openSUSE_Factory/"
				if ! zypper lr -d | grep -q "${opensuse_factory_url}"; then
					opensuse_repo="${opensuse_factory_url}security:SELinux.repo"
					if ! is_dry_run; then
						cat >&2 <<- EOF
							WARNING!!
							openSUSE repository ($opensuse_repo) will be enabled now.
							Do you wish to continue?
							You may press Ctrl+C now to abort this script.
						EOF
						( set -x; sleep 20 )
					fi
					$sh_c "zypper addrepo $opensuse_repo"
				fi
				$sh_c "zypper --gpg-auto-import-keys refresh"
				$sh_c "zypper lr -d"
			)
			pkg_version=""
			if [ -n "$VERSION" ]; then
				if is_dry_run; then
					echo "# WARNING: VERSION pinning is not supported in DRY_RUN"
				else
					pkg_pattern="$(echo "$VERSION" | sed 's/-ce-/\\\\.ce.*/g' | sed 's/-/.*/g')"
					search_command="zypper search -s --match-exact 'docker-ce' | grep '$pkg_pattern' | tail -1 | awk '{print \$6}'"
					pkg_version="$($sh_c "$search_command")"
					echo "INFO: Searching repository for VERSION '$VERSION'"
					echo "INFO: $search_command"
					if [ -z "$pkg_version" ]; then
						echo
						echo "ERROR: '$VERSION' not found amongst zypper list results"
						echo
						exit 1
					fi
					search_command="zypper search -s --match-exact 'docker-ce-cli' | grep '$pkg_pattern' | tail -1 | awk '{print \$6}'"
					cli_pkg_version="$($sh_c "$search_command")"
					pkg_version="-$pkg_version"
				fi
			fi
			(
				pkgs="docker-ce$pkg_version"
				if version_gte "18.09"; then
					if [ -n "$cli_pkg_version" ]; then
						pkgs="$pkgs docker-ce-cli-$cli_pkg_version containerd.io"
					else
						pkgs="$pkgs docker-ce-cli containerd.io"
					fi
				fi
				if version_gte "20.10"; then
					pkgs="$pkgs docker-compose-plugin docker-ce-rootless-extras$pkg_version"
				fi
				if version_gte "23.0"; then
						pkgs="$pkgs docker-buildx-plugin"
				fi
				if ! is_dry_run; then
					set -x
				fi
				$sh_c "zypper -q install -y $pkgs"
			)
			echo_docker_as_nonroot
			exit 0
			;;
		*)
			if [ -z "$lsb_dist" ]; then
				if is_darwin; then
					echo
					echo "ERROR: Unsupported operating system 'macOS'"
					echo "Please get Docker Desktop from https://www.docker.com/products/docker-desktop"
					echo
					exit 1
				fi
			fi
			echo
			echo "ERROR: Unsupported distribution '$lsb_dist'"
			echo
			exit 1
			;;
	esac
	exit 1
}

do_install
