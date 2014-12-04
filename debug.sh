LACKEY_LOG=../../noc/data/lackey.log
META_ROB_LOG=../../noc/data/meta_rob$1.log

[ -e $META_ROB_LOG ] || mkfifo $META_ROB_LOG

# core_num=16
luajit meta_rob.lua -c$1 -s75 -d32 < $LACKEY_LOG > $META_ROB_LOG &
luajit exe_blk.lua $1 $META_ROB_LOG
# lua 1''12
# luajit 37''
