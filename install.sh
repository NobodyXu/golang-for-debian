#!/bin/bash

has_command() {
    /usr/bin/env $1 >/dev/null 2>&1 < /dev/null
    exit_status=$?

    if [ $exit_status -eq 127 ]; then
        return 1
    else
        return 0
    fi
}

get_newest_pkg() {
    apt list "${1}-*" 2>/dev/null | tail -n +2 | cut -d '/' -f 1 | grep -E "${1}-[[:digit:]][.]?[[:digit:]]*$" | sort -V | tail -n 1
}

get_newest_go_version() {
    git tag -l  | grep go* | sort -V | tail -n 1
}

append_line_if_not_found() {
    if ! grep -q "^${1}$" "$2"; then
        echo "$1" >> "$2"
    fi
}

GOROOT=`pwd`/goroot

# Print usage if required by user
if [ "$1" = "help" ]; then
    echo "Usage: `basename $0` [version]"
    echo "It will download and build go in the '${GOROOT}'"
    echo "It will automatically modify ~/.bashrc so that you can use go"
    exit
fi

# Create wrapper function sudo
if has_command sudo; then
    :
elif has_command su; then
    sudo() {
        su -c "$@"
    }
elif [ $UID -eq 0 ]; then
    sudo() {
        eval $@
    }
else
    echo "Cannot use sudo/su, nor am I root"
    echo "Assuming that I have enough permission"

    sudo() {
        eval $@
    }
fi

version="$1"

clang_pkg=`get_newest_pkg clang`
gcc_pkg=`get_newest_pkg gcc`
gccgo_pkg=`get_newest_pkg gccgo`

# Install the necessary softwares for downloading and building
# go
## Install apt for finding newest compiler available
sudo apt-get install -y apt
## For cloning repositories
sudo apt-get install -y git ca-certificates curl
## Build tool-chains
## gccgo is a go language compiler used for bootstrap of go,
## since go itself is writen in go.
sudo apt-get install -y build-essential $clang_pkg $gcc_pkg $gccgo_pkg

# Clone go repository and setup it to track specific version
if [ ! -d $GOROOT ]; then
    git clone https://go.googlesource.com/go $GOROOT
fi
cd $GOROOT
git checkout tags/`get_newest_go_version`

# Build go from src
## By default, use clang
CC=$clang_pkg
CXX=`echo $CC | sed 's/-/++-/'`

## Setup bootsrap environment
TMP_DIR=/tmp/go
rm -r ${TMP_DIR}
mkdir -p ${TMP_DIR}/bin
ln -s $(which `echo $gccgo_pkg | sed 's/gcc//'`) /tmp/go/bin/go

GOROOT_BOOTSTRAP=$TMP_DIR

cd src
source all.bash
echo

## Remove tmp dir
rm -r $TMP_DIR

# Add ${GOROOT}/bin to PATH
echo Adding go to PATH by modifing ~/.bashrc
## Backup
echo Backup current ~/.bashrc
bashrc_bk=~/.bashrc.bk.`date -u | sed 's/ /_/g'`
cp ~/.bashrc $bashrc_bk
## Remove previous setting of GOROOT
cat > ~/.bashrc << EOF
`grep -v "export GOROOT=$GOROOT" $bashrc_bk`
export GOROOT=$GOROOT
EOF

append_line_if_not_found 'export PATH=${GOROOT}/bin:$PATH' ~/.bashrc

source ~/.bashrc

echo
echo Please reload the configuration file by running `source ~/.bashrc` in all running bash to use `go`
