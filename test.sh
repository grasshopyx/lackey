#!/bin/bash

TFOLD=../../noc/data

LACKEY_LOG="$TFOLD/lackey".log
META_ROB_LOG="$TFOLD/meta_rob".log

[ -e $META_ROB_LOG ] || mkfifo $META_ROB_LOG

#-c number of cores; -s merged/minimum code block size; -d reorder-buffer depth
core_num_max=128
sb_size_max=200
rob_depth_max=512
for (( i=2; i<=core_num_max; i=i*2 ));do

	for (( j=25; j<=sb_size_max; j=j+25 )); do
		for (( k=16; k<=rob_depth_max; k=k*2 ));do
			echo -e "core_num=$i \t sb_size=$j \t rob_depth=$k"
			luajit meta_rob.lua -c$i -s$j -d$k < $LACKEY_LOG > $META_ROB_LOG &
			luajit exe_blk.lua $i $META_ROB_LOG
		done
	done
done

