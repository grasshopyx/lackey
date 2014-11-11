#!/bin/bash

TFOLD="/tmp/$(basename $1).$$" # basename to get the "base name", path reduced; $$ is the PID of this proceess
mkdir -p $TFOLD

LACKEY_LOG="$TFOLD/lackey".log
META_ROB_LOG="$TFOLD/meta_rob".log

[ -e $LACKEY_LOG ] || touch $LACKEY_LOG
[ -e $META_ROB_LOG ] || touch $META_ROB_LOG

# $@ will expand to all the arguments of this bash script
valgrind --log-file=$LACKEY_LOG --tool=lackey --trace-mem=yes --trace-superblocks=yes $@ #&

#-c number of cores; -s merged/minimum code block size; -d reorder-buffer depth
core_num_max=128
sb_size_max=200
rob_depth_max=512
for (( i=2; i<=core_num_max; i=i*2 ));do

	for (( j=25; j<=sb_size_max; j=j+25 )); do
		for (( k=16; k<=rob_depth_max; k=k*2 ));do
			echo -e "core_num=$i \t sb_size=$j \t rob_depth=$k"
			luajit meta_rob.lua -c$i -s$j -d$k < $LACKEY_LOG > $META_ROB_LOG #&
			luajit exe_blk.lua $i $META_ROB_LOG
		done
	done
done

