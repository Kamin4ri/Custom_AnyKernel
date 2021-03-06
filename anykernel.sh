# AnyKernel 2.0 Ramdisk Mod Script 
# osm0sis @ xda-developers
# Modified for the Moto G by KingKaminari @ xda-developers

# Device variables
device=`getprop ro.product.device`;
prodname=`grep ^ro.product.name /system/build.prop | cut -d= -f2`;
filesystem=`mount | grep /data | cut -c37-40`;

# shell variables
block=/dev/block/platform/msm_sdcc.1/by-name/boot;

## end setup

## AnyKernel methods (DO NOT CHANGE)
# set up extracted files and directories
ramdisk=/tmp/anykernel/ramdisk;
bin=/tmp/anykernel/tools;
split_img=/tmp/anykernel/split_img;
patch=/tmp/anykernel/patch;

chmod -R 755 $bin;
mkdir -p $ramdisk $split_img;
cd $ramdisk;

OUTFD=`ps | grep -v "grep" | grep -oE "update(.*)" | cut -d" " -f3`;
ui_print() { echo "ui_print $1" >&$OUTFD; echo "ui_print" >&$OUTFD; }

# dump boot and extract ramdisk
dump_boot() {
    dd if=$block of=/tmp/anykernel/boot.img;
    $bin/unpackbootimg -i /tmp/anykernel/boot.img -o $split_img;
    if [ $? != 0 ]; then
        ui_print " "; ui_print "Dumping/unpacking image failed. Aborting...";
        echo "Dumping/unpacking image failed. Aborting..." > /tmp/anykernel/error;
        echo 1 > /tmp/anykernel/exitcode; exit;
    fi;
    gunzip -c $split_img/boot.img-ramdisk.gz | cpio -i;
}

# repack ramdisk then build and write image
write_boot() {
    cd $split_img;
    cmdline=`cat *-cmdline`;
    board=`cat *-board`;
    base=`cat *-base`;
    pagesize=`cat *-pagesize`;
    kerneloff=`cat *-kerneloff`;
    ramdiskoff=`cat *-ramdiskoff`;
    tagsoff=`cat *-tagsoff`;
    if [ -f *-second ]; then
        second=`ls *-second`;
        second="--second $split_img/$second";
        secondoff=`cat *-secondoff`;
        secondoff="--second_offset $secondoff";
    fi;
    # Falcon requires a zImage with the device tree(s) appended, so let's use it
    if [ -f /tmp/anykernel/zImage-dtb ]; then
        kernel=/tmp/anykernel/zImage-dtb; 
    else
        kernel=`ls *-zImage-dtb`;
        kernel=$split_img/$kernel;
	fi;
	cd $ramdisk;
    find . | cpio -H newc -o | gzip > /tmp/anykernel/ramdisk-new.cpio.gz;
    $bin/mkbootimg --kernel $kernel --ramdisk /tmp/anykernel/ramdisk-new.cpio.gz $second --cmdline "$cmdline" --board "$board" --base $base --pagesize $pagesize --kernel_offset $kerneloff --ramdisk_offset $ramdiskoff $secondoff --tags_offset $tagsoff --output /tmp/anykernel/boot-new.img;
    if [ $? != 0 -o `wc -c < /tmp/anykernel/boot-new.img` -gt `wc -c < /tmp/anykernel/boot.img` ]; then
        ui_print " "; ui_print "Repacking image failed. Aborting...";
        echo "Repacking image failed. Aborting..." > /tmp/anykernel/error;        
        echo 1 > /tmp/anykernel/exitcode; exit;
    fi;
    dd if=/tmp/anykernel/boot-new.img of=$block;
}

# backup_file <file>
backup_file() { cp $1 $1~; }

# replace_string <file> <if search string> <original string> <replacement string>
replace_string() {
  if [ -z "$(grep "$2" $1)" ]; then
      sed -i "s;${3};${4};" $1;
  fi;
}

# insert_line <file> <if search string> <before/after> <line match string> <inserted line>
insert_line() {
  if [ -z "$(grep "$2" $1)" ]; then
    case $3 in
      before) offset=0;;
      after) offset=1;;
    esac;
    line=$((`grep -n "$4" $1 | cut -d: -f1` + offset));
    sed -i "${line}s;^;${5};" $1;
  fi;
}

# replace_line <file> <line replace string> <replacement line>
replace_line() {
  if [ ! -z "$(grep "$2" $1)" ]; then
    line=`grep -n "$2" $1 | cut -d: -f1`;
    sed -i "${line}s;.*;${3};" $1;
  fi;
}

# remove_line <file> <line match string>
remove_line() {
	if [ ! -z "$(grep "$2" $1)" ]; then
    	line=`grep -n "$2" $1 | cut -d: -f1`;
		sed -i "${line}d" $1;
	fi;
}

# prepend_file <file> <if search string> <patch file>
prepend_file() {
	if [ -z "$(grep "$2" $1)" ]; then
    	echo "$(cat $patch/$3 $1)" > $1;
	fi;
}

# append_file <file> <if search string> <patch file>
append_file() {
	if [ -z "$(grep "$2" $1)" ]; then
		echo -ne "\n" >> $1;
		cat $patch/$3 >> $1;
		echo -ne "\n" >> $1;
	fi;
}

# replace_file <file> <permissions> <patch file>
replace_file() {
	cp -fp $patch/$3 $1;
	chmod $2 $1;
}

## end methods


## AnyKernel permissions
# set permissions for included files
chmod -R 755 $ramdisk;

## AnyKernel install
dump_boot;

# begin ramdisk changes
# Patch init.rc to add init.d support & execute tweak script
replace_file init.rc 750 init.rc;
# Patch init.mmi.rc to avoid I/O scheduler override
replace_file init.mmi.rc 750 init.mmi.rc;
# Use modified fstab
replace_file fstab.qcom 640 fstab.qcom;

# end ramdisk changes
write_boot;

## end install

