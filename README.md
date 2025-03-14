# Install Docker Engine

## Prerequisites

**Ensure** you have `curl`by: 

$ `curl --version`

- If the output is `curl 8.5.0 (x86_64-pc-linux-gnu)...` you can skip the next steps.

- If the output is `bash: curl: command not found` It means `curl` is not installed. Follow the instructions below to install it:

    - For Debian / Ubuntu: 
    
    $ `sudo apt update && sudo apt install curl`

    - For Fedora / RHEL: 
    
    $ `sudo dnf install curl`

**WARNING**: If you have previously installed Docker, containerd, runc, or any other container-related software, it is recommended to remove them first to avoid conflicts during installation. 

To ensure a clean install, run the following command: 

- For Debian / Ubuntu: 

$ `for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove $pkg; done`

- For Fedora / RHEL: 

$ `sudo dnf remove docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-selinux docker-engine-selinux docker-engine podman runc`

## Install using the convenience script

This method ensures you get the **latest stable** version directly from **Docker’s official repository** and works on almost any Linux distribution.

$ `curl -fsSL https://get.docker.com -o get-docker.sh`

$ `sudo sh ./get-docker.sh`

## Install Docker from Distribution Repositories

**WARNING**: Skip this step if you used the convenience script.

If you prefer to download from the distribution repositories, use the following commands :

- For Debian / Ubuntu / Mint: 

$ `sudo apt install docker.io`

- For Fedora / CentOS / RHEL: 

$ `sudo dnf install docker`


# Post-Installation

After installation, you **might** want to run Docker commands without sudo. To do this, add your user to the docker group.

**WARNING**: The docker group grants root privileges, which may pose security risks.

1) Create the docker group.

    $ `sudo groupadd docker`

2) Add your user to the docker group.

    $ `sudo usermod -aG docker $USER`

3) Apply the group changes:

    $ `newgrp docker`

4) Verify that you can run Docker commands without sudo:

    $ `docker run hello-world`

# Uninstall Docker Engine

To completely remove Docker Engine from your system:

- For Debian / Ubuntu: 

$ `sudo apt-get purge docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras`

- For Fedora / RHEL / CentOS: 

$ `sudo dnf remove docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras`

To remove all Docker data (containers, images, volumes):

$ `sudo rm -rf /var/lib/docker`

$ `sudo rm -rf /var/lib/containerd`

# Disclaimer

This project is not affiliated with, endorsed by, or associated with Docker, Inc. The script provided in this repository is intended solely for educational purposes. The author disclaims any liability for any direct or indirect damages or issues that may arise from the use of this script or the installation of Docker.
