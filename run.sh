#!/bin/bash

TFOLD="/tmp/$(basename $1).$$" # basename to get the "base name", path reduced; $$ is the PID of this proceess
mkdir -p $TFOLD

LACKEY_LOG="$TFOLD/lackey".log
META_ROB_LOG="$TFOLD/meta_rob".log

[ -e $LACKEY_LOG ] || mkfifo $LACKEY_LOG
[ -e $META_ROB_LOG ] || mkfifo $META_ROB_LOG

# $@ will expand to all the arguments of this bash script
valgrind --log-file=$LACKEY_LOG --tool=lackey --trace-mem=yes --trace-superblocks=yes $@ &

#-c number of cores; -s merged/minimum code block size; -d reorder-buffer depth
luajit meta_rob.lua -c4 -s50 -d64 < $LACKEY_LOG > $META_ROB_LOG &
luajit exe_blk.lua $META_ROB_LOG

