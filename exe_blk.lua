-- Usage: 

-- 0. prepare the traces: test/*_rob.log, test/cpu?-dinero. The
-- *_rob.log is the execution trace output by mrb_private_L1.lua, and
-- the cpu?-dinero are output from Dinero, which is invoked by
-- test_cache.sh

-- 1. luajit clk_cnt.lua


local miss_delay = 1

function exe_blocks(core_num, rob_exe_log, miss_log)

    local clkcount = 0
    local addr, current_core = 0, 1     -- current_core is the current core id (cid in meta_rob.lua)
    local icount_sb = 0
    local accesstype, daddr, dsize
    local misscnt_sb = 0

    -- #core = #miss_log
    local core = {}
    for i=1, core_num do
        core[i] = {icount = 0, delay_count = 0, clk_pend = 0}
    end

    -- local first_flag=true

    issue_num=0

    for line in rob_exe_log:lines() do
        if line:sub(1,1) ~= "#" then	 
            if line:sub(1,5) == "ISSUE" then
                -- a line of blocks get issued
                local max_clk = 0
                -- io.write("EXE ")

--                 issue_num=issue_num+1
--                 io.stderr:write("ISSUE No.",issue_num,"\n")
--                 for _, c in ipairs(core) do
--                     io.stderr:write(c.clk_pend," ")
--                 end

                for _, c in ipairs(core) do
                    if max_clk < c.clk_pend then max_clk = c.clk_pend end
                    -- io.write(string.format("%d ", c.clk_pend))
                    c.clk_pend = 0
                end
                clkcount = clkcount + max_clk

                -- print(' CLK', max_clk)

                -- io.stderr:write("\nclkcount:",clkcount,"\n") 
                -- local icount=0
                -- for _, v in pairs(core) do
                --     icount = icount + v.icount
                -- end
                -- io.stderr:write("icount:",icount,"\nipc:", icount/clkcount,"\n")

            elseif line:sub(1,2) == "SB" then
                addr, current_core, _icount = string.match(line:sub(4), "(%x+) (%d+) (%d+)")
                icount_sb = tonumber(_icount)

                -- io.stderr:write("SB: ", addr, " " , current_core, " ", icount_sb,"\n")

                -- summarize the previous SB 1st  -- it's wrong. it will miss the last SB
                local c = core[tonumber(current_core)]
                c.icount = c.icount + icount_sb
                c.delay_count = c.delay_count + misscnt_sb * miss_delay     -- unused
                c.clk_pend = c.clk_pend + icount_sb + misscnt_sb * miss_delay

                -- 

            elseif miss_log and #miss_log > 0 then
                -- now it is a memory reference, let's check the miss log
                -- and see how much latency it causes

                local mlog = miss_log[tonumber(current_core)]
                local miss_record = mlog:read("*line")
                if not miss_record then break end
                misscnt_sb = misscnt_sb + tonumber(miss_record:sub(6))
            end
            -- else
            --     io.stderr:write('Yes!')
        end

    end				-- for exe in rob_exe_log.lines()

    -- io.stderr:write('TEST STDERR')

    local icount, delaycount = 0, 0

    for k, v in pairs(core) do
        icount = icount + v.icount
        delaycount = delaycount + v.delay_count
    end
    print(string.format("executed %d insts in %d clks: CPI=", icount, clkcount), clkcount/icount)   

end



function open_traces(sched, ...)
    local _sched = assert(io.open(sched, "r"))

    local _mref = {}
    for i, v in ipairs{...} do
        _mref[i] = assert(io.open(v, "r"))
    end

    return _sched, _mref
end

-- clk_add_delay(4, open_traces("./test/date_rob.log", "./test/cpu1.dinero", "./test/cpu2.dinero", "./test/cpu3.dinero", "./test/cpu4.dinero"))
-- exe_blocks(4, open_traces("./test/date_rob.log"))
exe_blocks(arg[1], open_traces(arg[2]))

