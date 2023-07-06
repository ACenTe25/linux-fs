#!/bin/bash

export PROJECT_DIR=$(pwd)

# TO EXIT ON ERRORS
function check_result {

	if [ $1 -ne 0 ]
	then
		echo $2 >&2

		echo -e "\nCleaning up..."
		cd $PROJECT_DIR
		rm -rf linux-6.4.2 busybox-1.36.1 initramfs.cpio.gz initramfs fsmnt *.tar* > /dev/null 2>&1
		sudo losetup -d ${IMG_LOOP?} > /dev/null 2>&1
		echo "Done"
		exit 1
	fi
}

# DEPENDENCIES
echo -e "\nGetting dependencies for compiling and running a new Linux File System..."

sudo apt-get -y install build-essential flex bison libelf-dev libssl-dev qemu-system-x86 > /dev/null

echo -e "Dependencies installed!\n"

# DOWNLOAD AND EXTRACT SOURCES
echo -e "\nGetting Linux kernel sources. This may take a couple minutes..."
wget -q https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.4.2.tar.xz
check_result $? "error: could not download kernel source code from kernel.org"

echo "Getting Busybox sources..."
wget -q https://busybox.net/downloads/busybox-1.36.1.tar.bz2
check_result $? "error: could not download Busybox source code from busybox.net"

echo "Extracting Linux kernel sources. This may take a couple minutes..."
tar -xf linux-6.4.2.tar.xz > /dev/null
check_result $? "error: could not extract kernel sources with tar"

echo "Extracting Busybox sources..."
tar -xf busybox-1.36.1.tar.bz2 > /dev/null
check_result $? "error: could not extract Busybox sources with tar"

echo -e "Downloaded and extracted sources!\n"

# CONFIGURING AND COMPILING KERNEL AND BUSYBOX
echo -e "\nConfiguring the Linux kernel with default configuration. This may take a couple minutes..."
cd linux-6.4.2
make mrproper > /dev/null
check_result $? "error: kernel make target mrproper error"
make defconfig > /dev/null
check_result $? "error: kernel make target defconfig error"
echo "Compiling the kernel. This will take several minutes..."
make -j $(nproc) > /dev/null
check_result $? "error: could not compile the linux kernel with defconfig"
echo "Compiled the kernel!\n"
cd $PROJECT_DIR

echo -e "\nConfiguring Busybox with default configuration..."
cd busybox-1.36.1
make defconfig > /dev/null
check_result $? "error: busybox make target defconfig error"
echo "Setting CONFIG_STATIC..."
sed 's/# CONFIG_STATIC is not set/CONFIG_STATIC=yes/' .config > .config2 && mv .config2 .config
echo "Compiling Busybox. This may take a couple minutes..."
make -j $(nproc) > /dev/null
check_result $? "error: could not compile Busybox with defconfig and CONFIG_STATIC"
echo "Installing Busybox..."
make install > /dev/null
check_result $? "error: could not install Busybox"
echo -e "Installed Busybox!\n"
cd $PROJECT_DIR

# CREATING AN INITRAMFS
echo -e "\nCreating an initramfs..."
mkdir initramfs && cd initramfs
mkdir -p bin dev etc mnt/rootmnt proc run sbin sys tmp usr/bin usr/share var
cp -a ../busybox-1.36.1/_install/* .
cp ../initramfsinit ./init
check_result $? "error: could not find initramfsinit file in project directory"
chmod +x init
find . -print0 | cpio --null --create --format=newc | gzip --best > ../initramfs.cpio.gz > /dev/null
check_result $? "error: could not create initramfs"
echo -e "Created initramfs!\n"
cd $PROJECT_DIR

# CREATING THE REAL FILE SYSTEM
echo -e "\nCreating a raw image with QEMU..."
qemu-img create realfs.img 50M > /dev/null
check_result $? "error: could not create image with qemu-img"
echo "Creating its partition table and partition..."
parted -s realfs.img mktable msdos
parted -s realfs.img mkpart primary ext4 1 "100%"
parted -s realfs.img set 1 boot on
echo "Creating a loopback device with the partitioned image..."
export IMG_LOOP=$(sudo losetup -fP --show realfs.img)
export FS_LOOP="${IMG_LOOP?}p1"
echo "Formatting the device loop as ext4..."
sudo mkfs -t ext4 "${FS_LOOP?}" > /dev/null
check_result $? "error: could not format the device loop for the real file system with mkfs"
echo "Mounting the device loop to create the file system..."
mkdir fsmnt
sudo mount "${FS_LOOP?}" fsmnt > /dev/null
check_result $? "error: could not mount the image"
echo "Changing owner to USER..."
sudo chown -R ${USER?} fsmnt
echo "Creating file system..."
cd fsmnt
mkdir -p boot/grub bin dev etc lib lib64 media mnt opt proc root run sbin sys tmp usr/bin usr/sbin usr/share var
cp -a ../busybox-1.36.1/_install/* .
cp ../realinit ./init
check_result $? "error: could not find realinit file in project directory"
chmod +x init
cp ../grub.cfg boot/grub/grub.cfg
check_result $? "error: could not find grub.cfg file in project directory"
cp ../passwd etc/passwd
check_result $? "error: could not find passwd file in project directory"
cp ../group etc/group
check_result $? "error: could not find group file in project directory"
cp ../hosts etc/hosts
check_result $? "error: could not find hosts file in project directory"
echo linuxfs-test > etc/hostname
echo "Installing the bootloader..."
echo "(hd0) ${IMG_LOOP?}" > boot/grub/device.map
sudo grub-install --directory=/usr/lib/grub/i386-pc --boot-directory=boot ${IMG_LOOP?} > /dev/null
check_result $? "error: could not install bootloader GRUB2 with grub-install"
echo "Copying the kernel and initramfs into the real filesystem..."
cp ../linux-6.4.2/arch/x86_64/boot/bzImage boot/bzImage
cp ../initramfs.cpio.gz boot/initramfs.cpio.gz
echo -e "Created the real file system!\n"
cd $PROJECT_DIR
sudo umount -R fsmnt

# RUN THE BOOTABLE IMG (EXTRA POINTS, YAY!) IN QEMU AS AMD64
qemu-system-x86_64 -hda realfs.img -nographic

# WHEN THIS CLOSES, CLEAN UP AND SAY GOODBYE :)
echo -e "\nCleaning up..."
rm -rf linux* busybox* initramfs initramfs.cpio.gz realfs.img fsmnt
sudo losetup -d ${IMG_LOOP?} > /dev/null
echo -e "Done!\n"

echo -e "Hope you liked it! I'll see you soon :)\n"

# EEEEEXITOOO
exit 0
