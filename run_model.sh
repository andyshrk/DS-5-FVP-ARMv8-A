#!/bin/bash

# Copyright (c) 2015, ARM Limited and Contributors. All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# Redistributions of source code must retain the above copyright notice, this
# list of conditions and the following disclaimer.
#
# Redistributions in binary form must reproduce the above copyright notice,
# this list of conditions and the following disclaimer in the documentation
# and/or other materials provided with the distribution.
#
# Neither the name of ARM nor the names of its contributors may be used
# to endorse or promote products derived from this software without specific
# prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

err=0

function usage
{
	echo "usage: $0 [--aarch32] [rundir]"
	echo "Options:"
	echo "  --aarch32    run the model in Aarch32 mode, if available"
	echo "  [rundir]     the script will run from a directory specified on the commandline"
	echo "               otherwise it will run from the current working directory"
	echo "               use this to tell the model where to find the binaries you want"
	echo "               to load if they aren't in the current directory."
	exit
}

while [ "$1" != "" ]; do
	case $1 in
		"-h" | "-?" | "-help" | "--help" | "--h" | "help" )
			usage
			exit
			;;
		"--aarch32" | "--Aarch32" | "--AARCH32" )
			model_arch=aarch32
			;;
		"--aarch64" | "--Aarch64" | "--AARCH64" )
			model_arch=aarch64
			;;
		*)
			if [ "$rundir" == "" ]
			then
				rundir=$1
			fi
			;;
	esac
	shift
done

model_arch=${model_arch:-aarch64}
rundir=${rundir:-.}

if [ -e $rundir ]; then
	cd $rundir
else
	echo "ERROR: the run directory to $rundir, however that path does not exist"
	exit 1
fi

CLUSTER0_NUM_CORES=${CLUSTER0_NUM_CORES:-1}
CLUSTER1_NUM_CORES=${CLUSTER1_NUM_CORES:-1}

# Check for obvious errors and set err=1 if we encounter one
if [ ! -e "$MODEL" ]; then
	echo "ERROR: you should set variable MODEL to point to a valid FVP model binary, currently it is set to \"$MODEL\""
	err=1
else
	# Check if we are running the foundation model or the AEMv8 model
	version=$($MODEL --version)
	echo version: $version

	case $version in
		*Foundation* )
			model_type=foundation
			DTB=${DTB:-foundation-v8-gicv3.dtb}
			;;
		*Cortex_A32* )
			model_type=cortex-a32
			DTB=${DTB:-fvp-base-aemv8a-aemv8a.dtb}
			;;
		* )
			model_type=aemv8
			DTB=${DTB:-fvp-base-aemv8a-aemv8a.dtb}
			if [ "$model_arch" == "aarch32" ]; then
				arch_params="	-C cluster0.cpu0.CONFIG64=0                                 \
						-C cluster0.cpu1.CONFIG64=0                                 \
						-C cluster0.cpu2.CONFIG64=0                                 \
						-C cluster0.cpu3.CONFIG64=0                                 \
						-C cluster1.cpu0.CONFIG64=0                                 \
						-C cluster1.cpu1.CONFIG64=0                                 \
						-C cluster1.cpu2.CONFIG64=0                                 \
						-C cluster1.cpu3.CONFIG64=0                                 \
						"
			fi
			cores="-C cluster0.NUM_CORES=$CLUSTER0_NUM_CORES \
				-C cluster1.NUM_CORES=$CLUSTER1_NUM_CORES"
			;;
	esac
fi

# Set some sane defaults before continuing to error check
BL1=${BL1:-bl1.bin}
FIP=${FIP:-fip.bin}
IMAGE=${IMAGE:-Image}
INITRD=${INITRD:-ramdisk.img}

# Continue error checking...
if [ ! -e "$BL1" ]; then
	echo "ERROR: you should set variable BL1 to point to a valid BL1 binary, currently it is set to \"$BL1\""
	err=1
fi

if [ ! -e "$FIP" ]; then
	echo "ERROR: you should set variable FIP to point to a valid FIP binary, currently it is set to \"$FIP\""
	err=1
fi

if [ ! -e "$IMAGE" ]; then
	echo "WARNING: you should set variable IMAGE to point to a valid kernel image, currently it is set to \"$IMAGE\""
	IMAGE=
	warn=1
fi
if [ ! -e "$INITRD" ]; then
	echo "WARNING: you should set variable INITRD to point to a valid initrd/ramdisk image, currently it is set to \"$INITRD\""
	INITRD=
	warn=1
fi
if [ ! -e "$DTB" ]; then
	echo "WARNING: you should set variable DTB to point to a valid device tree binary (.dtb), currently it is set to \"$DTB\""
	DTB=
	warn=1
fi

# Exit if any obvious errors happened
if [ $err == 1 ]; then
	exit 1
fi

# check for warnings, like no disk specified.
# note: busybox variants don't need a disk, so it may be OK for DISK to be empty/missing
if [ ! -e "$DISK" ]; then
	echo "WARNING: you should set variable DISK to point to a valid disk image, currently it is set to \"$DISK\""
	warn=1
fi

# Optional VARS arg.
# If a filename is given in the VARS variable, use it to set the contents of the
# 2nd bank of NOR flash: where UEFI stores it's config
if [ "$VARS" != "" ]; then
	# if the $VARS file doesn't exist, create it
	touch $VARS
	VARS="-C bp.flashloader1.fname=$VARS -C bp.flashloader1.fnameWrite=$VARS"
else
	VARS=""
fi

SECURE_MEMORY=${SECURE_MEMORY:-0}

echo "Running FVP Base Model with these parameters:"
echo "MODEL=$MODEL"
echo "model_arch=$model_arch"
echo "rundir=$rundir"
echo "BL1=$BL1"
echo "FIP=$FIP"
echo "IMAGE=$IMAGE"
echo "INITRD=$INITRD"
echo "DTB=$DTB"
echo "VARS=$VARS"
echo "DISK=$DISK"
echo "CLUSTER0_NUM_CORES=$CLUSTER0_NUM_CORES"
echo "CLUSTER1_NUM_CORES=$CLUSTER1_NUM_CORES"
echo "SECURE_MEMORY=$SECURE_MEMORY"
echo "NET=$NET"

kern_addr=0x80080000
dtb_addr=0x82000000
initrd_addr=0x84000000

if [ "$model_type" == "foundation" ]; then
	GICV3=${GICV3:-1}
	echo "GICV3=$GICV3"

	if [ "$NET" == "1" ]; then
		# The Foundation Model MAC address appears to be 00:02:F7:EF
		# followed by the last two bytes of the host's MAC address.
		net="--network bridged --network-bridge=ARM$USER"
	fi

	if [ "$DISK" != "" ]; then
		disk_param=" --block-device=$DISK " 
	fi

	if [ "$SECURE_MEMORY" == "1" ]; then
		secure_memory_param=" --secure-memory"
	else
		secure_memory_param=" --no-secure-memory"
	fi

	if [ "$GICV3" == "1" ]; then
		gic_param=" --gicv3"
	else
		gic_param=" --no-gicv3"
	fi

	if [ "$IMAGE" != "" ]; then
		image_param="--data=${IMAGE}@${kern_addr}"
	fi
	if [ "$INITRD" != "" ]; then
		initrd_param="--data=${INITRD}@${initrd_addr}"
	fi
	if [ "$DTB" != "" ]; then
		dtb_param="--data=${DTB}@${dtb_addr}"
	fi

	cmd="$MODEL \
	--cores=$CLUSTER0_NUM_CORES \
	$secure_memory_param \
	--visualization \
	--use-real-time \
	$gic_param \
	--data=${BL1}@0x0 \
	--data=${FIP}@0x8000000 \
	$image_param \
	$dtb_param \
	$initrd_param \
	$disk_param \
	$net \
	"
else
	CACHE_STATE_MODELLED=${CACHE_STATE_MODELLED:=0}
	echo "CACHE_STATE_MODELLED=$CACHE_STATE_MODELLED"

	if [ "$NET" == "1" ]; then
		if [ "$MACADDR" == "" ]; then
			# if the user didn't supply a MAC address, generate one
			MACADDR=`echo -n 00:02:F7; dd bs=1 count=3 if=/dev/random 2>/dev/null |hexdump -v -e '/1 ":%02X"'`
			echo MACADDR=$MACADDR
		fi

		net="-C bp.hostbridge.interfaceName=ARM$USER \
		-C bp.smsc_91c111.enabled=true \
		-C bp.smsc_91c111.mac_address=${MACADDR}"
	fi

	if [ "$DISK" != "" ]; then
		disk_param=" -C bp.virtioblockdevice.image_path=$DISK "
	fi

	if [ "$IMAGE" != "" ]; then
		image_param="--data cluster0.cpu0=${IMAGE}@${kern_addr}"
	fi
	if [ "$INITRD" != "" ]; then
		initrd_param="--data cluster0.cpu0=${INITRD}@${initrd_addr}"
	fi
	if [ "$DTB" != "" ]; then
		dtb_param="--data cluster0.cpu0=${DTB}@${dtb_addr}"
	fi

	# Create log files with date stamps in the filename
	# also create a softlink to these files with a static filename, eg, uart0.log
	datestamp=`date +%s%N`

	UART0_LOG=uart0-${datestamp}.log
	touch $UART0_LOG
	uart0log=uart0.log
	rm -f $uart0log
	ln -s $UART0_LOG $uart0log

	UART1_LOG=uart1-${datestamp}.log
	touch $UART1_LOG
	uart1log=uart1.log
	rm -f $uart1log
	ln -s $UART1_LOG $uart1log

	echo "UART0_LOG=$UART0_LOG"
	echo "UART1_LOG=$UART1_LOG"

	cmd="$MODEL \
	-C pctl.startup=0.0.0.0 \
	-C bp.secure_memory=$SECURE_MEMORY \
	$cores \
	-C cache_state_modelled=$CACHE_STATE_MODELLED \
	-C bp.pl011_uart0.untimed_fifos=1 \
        -C bp.pl011_uart0.out_file=$UART0_LOG \
        -C bp.pl011_uart1.out_file=$UART1_LOG \
	-C bp.secureflashloader.fname=$BL1 \
	-C bp.flashloader0.fname=$FIP \
	$image_param \
	$dtb_param \
	$initrd_param \
	-C bp.ve_sysregs.mmbSiteDefault=0 \
	-C bp.ve_sysregs.exit_on_shutdown=1 \
	$disk_param \
	$VARS \
	$net \
	$arch_params
	"
fi

echo "Executing Model Command:"
echo "  $cmd"

$cmd
