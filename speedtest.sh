LACKEY_LOG=../../noc/data/lackey.log
META_ROB_LOG=../../noc/data/meta_rob.log

core_num=64
luajit meta_rob.lua -c$core_num -s50 -d64 < $LACKEY_LOG > $META_ROB_LOG
luajit exe_blk.lua $core_num $META_ROB_LOG
# lua 1''12
# luajit 37''
