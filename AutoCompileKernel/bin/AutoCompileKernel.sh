#!/bin/bash
cd $(dirname $(realpath $0))
# Get source value
source ./KernelCompilationSetting.txt
# Get newest version from web page
# Get all version of release
Version=($(curl -s $HardkernelWeb |egrep "href="  |egrep tar.gz |tr "\"" "\n" | tr "/" "\n"| egrep $FixVersion  |sed 's/.tar.gz//g' ))
egrep "^$FixVersion" <<< ${Version[0]} &>/dev/null
if [ "$?"  -ne "0" ]; then
    echo "Newest version not support,exit"
    exit 1
fi
# Get the last version of release
DownloadPage="${FixWeb}$(curl -s $HardkernelWeb |egrep "href="  |egrep tar.gz |tr "\"" "\n" | egrep $FixVersion |egrep ${Version[0]})"
echo "Using this web page to download newest version: $DownloadPage"
DownloadName=$(tr "\/" "\n" <<< ${DownloadPage} |egrep ".tar.gz")
echo "Download name is $DownloadName"
# Get the real patch dir
patchd=$(realpath $PatchDir)

# Create a directory for new version of kernel.

if [ -d ../${Version[0]} ]; then
    echo "Directory: ${Version[0]} already exist."
    cmd=${pwd}
    cd ../${Version[0]}
    if [ -f $DownloadName ]; then
        echo "Already download, quit."
        exit 0
    else
        if wget -c "$DownloadPage"; then
            echo "Download success."
        else
            echo "Download failed, something broken!"
            exit 1
        fi
    fi
else
    mkdir -p ../${Version[0]}
    cmd=$(pwd)
    cd ../${Version[0]}
    if wget -c "$DownloadPage"; then
        echo "Download success."
    else
        echo "Download failed, something broken!"
        exit 1
    fi
fi

# tar .tar.gz file into directory
if [ -d linux-${Version[0]} ]; then
    echo "Clean up old linux kernel directory."
    rm -r linux-${Version[0]}
fi
if [ -d ${DownloadName}-DebPkg ]; then
    echo "Deb package already build, quit."
    exit 1
fi
tar -zxf $DownloadName
cd linux-${Version[0]}
# Find patch dir
if [ -d $patchd ]; then
    echo "Found Linux kernel patch directory, check and install patch file."
    patchfiles=($( find /opt/Kernel/patch -name "*.patch" ))
    if [ "a${#patchfiles[@]}" == "a0" ]; then
        echo "No patch file found."
    else
        for file in ${patchfiles[@]}; do
            echo "Input patch file: $file"
            patch -p1 < $file
        done
    fi
else
    echo "Linux kernel patch directory not found."
fi

# Make defconfig
#Defconfig='odroidxu4_kvm_defconfig'

make ARCH=$Arch CROSS_COMPILE=$CrossCC $Defconfig

# Replace script
ReplaceFile=".config"
# Add kernel modules
for modules in $ModuleAll ; do
    echo "Add modules: $modules"
    egrep "# CONFIG_$modules is not set" $ReplaceFile &>/dev/null
    if [ "$?" -eq "0" ]; then
        sed -ir "s/# CONFIG_$modules is not set/CONFIG_$modules=m/g" $ReplaceFile
    fi
    egrep "CONFIG_$modules=[ymn]" $ReplaceFile &>/dev/null
    if [ "$?" -eq "0" ]; then
        sed -ir "s/CONFIG_$modules=[ymn]/CONFIG_$modules=m/g" $ReplaceFile
    else
        echo "CONFIG_$modules=m" >> $ReplaceFile
    fi
done
# Using make allmodconfig to force add modules into new kernel
# Add kernel yes
for kernel in $KernelAll; do
    echo "Add kernel: $kernel"
    egrep "# CONFIG_$kernel is not set" $ReplaceFile &>/dev/null
    if [ "$?" -eq "0" ]; then
        sed -ir "s/# CONFIG_$kernel is not set/CONFIG_$kernel=y/g" $ReplaceFile
    fi
    egrep "CONFIG_$kernel=[ymn]" $ReplaceFile &>/dev/null
    if [ "$?" -eq "0" ]; then
        sed -ir "s/CONFIG_$kernel=[ymn]/CONFIG_$kernel=y/g" $ReplaceFile
    else
        echo "CONFIG_$kernel=y" >> $ReplaceFile
    fi
    #sed -ir "s/^(# CONFIG_$kernel is not set|CONFIG_${kernel}=*)/CONFIG_${kernel}=y/" $ReplaceFile
done
# Using make allmodconfig to force remove modules into new kernel
# Remove kernel
for deny in $DenyAll; do
    echo "Remove kernel: $deny"
    egrep "# CONFIG_$deny is not set" $ReplaceFile &>/dev/null
    if [ "$?" -eq "0" ]; then
        sed -ir "s/# CONFIG_$deny is not set/CONFIG_$deny=n/g" $ReplaceFile
    fi
    egrep "CONFIG_$deny=[ymn]" $ReplaceFile &>/dev/null
    if [ "$?" -eq "0" ]; then
        sed -ir "s/CONFIG_$deny=[ymn]/CONFIG_$deny=n/g" $ReplaceFile
    else
        echo "CONFIG_$deny=n" >> $ReplaceFile
    fi
    #sed -ir "s/^(# CONFIG_$deny is not set|CONFIG_${deny}=*)/CONFIG_${deny}=n/" $ReplaceFile
done

# Add string into Configure file
# Add net.ifnames into cmdline
echo "Add cmdline: $cmdline"
sed -ir "s/CONFIG_CMDLINE=\"/CONFIG_CMDLINE=\"$cmdline /g" $ReplaceFile

cp $ReplaceFile ../config-${Version[0]}.orig
make ARCH=$Arch oldconfig
# Reconfig all modules into .config
echo "Start build kernel dtb, modules and zImage"
make ARCH=$Arch CROSS_COMPILE=$CrossCC -j$(($(nproc) - 1 )) dtbs zImage modules
if [ "$?" -eq "0" ]; then
    echo "Compile kernel finshed."
else
    echo "Something broken !!"
    exit 1
fi

# Build Deb package
echo "Need sudo passwd:"
sudo echo "Build DebPackage"
sudo make ARCH=$Arch CROSS_COMPILE=$CrossCC -j$(($(nproc) - 1 )) bindeb-pkg
# Create Deb Package directory
mkdir -p ../${Version[0]}-DebPkg
sudo mv ../linux-*.deb ../${Version[0]}-DebPkg
DebFile=$(realpath ../${Version[0]}-DebPkg)
make savedefconfig
cp defconfig ../${Version[0]}-OdroidXu4KvmDefconfig
sudo make ARCH=$Arch CROSS_COMPILE=$CrossCC distclean
cd ../
sudo rm -r linux-${Version[0]}
cd $cmd
sudo echo -ne "
This message is auto send by $0.
Update Date: $(date).
ARM base single board kernel message:
New kernel Version is ${Version[0]}
Kernel deb package on $DebFile
End time: $(date)
" >/etc/motd

echo -ne "
ARM base single board kernel message:
New kernel Version is ${Version[0]}
Kernel deb package on $DebFile" |sudo wall

#Mount Nfs and copy file into nfs
if [ "a$NFSPATH" == "a" ] || [ "a$NFSMOUNT" == "a" ] ; then
    echo "No nfs path set, will not copy into nfs server."
    echo "If you want to copy kernel into nfs automatic, you need to add this value into KernelCompilationSetting.txt."
    echo "NFSPATH='\$NFSIP:\$NFSDIR'"
    echo "NFSFIXPATH='Fix path after NFSPATH.'"
    echo "NFSMOUNT='/mnt/tmp'"
    exit 0
fi

if ${SUDO} mount $NFSPATH $NFSMOUNT; then
    echo "Mount NFS success on system path $NFSMOUNT."

    if [ "a$NFSFIXPATH" == "a" ]; then
        FIXdir="/${Version[0]}"
    else
        FIXdir="/$NFSFIXPATH/${Version[0]}"

    fi
    if [ ! -d $NFSMOUNT/$FIXdir ]; then
        echo "Create dir into NFS path"
        ${SUDO} mkdir -p $NFSMOUNT/$FIXdir
    fi
    echo "Copy kernel files into NFS."
    ${SUDO} cp $DebFile/*deb $NFSMOUNT/$FIXdir/
    if ${SUDO} umount $NFSMOUNT; then
        ${SUDO} /bin/bash -c "echo \"Copy kernel deb file into NFS path $NFSPATH/$FIXdir/\" >> /etc/motd"

    else
        echo "Umount failed, please check NFS mount point: $NFSMOUNT."
        exit 1
    fi

else
    echo "NFS mount failed, please check NFSPATH first."
    exit 1
fi
