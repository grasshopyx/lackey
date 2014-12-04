#!/usr/bin/env lua

-- input: trace from lackey tool of valgrind

-- output: trace of code block reordering/scheduling 


local List = require "list"

function logd(...)
    print(...)
end

-- the parameters that affects the parallelism 
local core_num = 16
local rob_w = 16
local rob_d = 8
local sb_size = 50
local sb_merge = false
local quit_at = 300000
local reg_sync_delay = 4

for i, v in ipairs(arg) do
    --print(type(v))
    if (v:sub(1,2) == "-c") then
        --print("core number:")
        core_num = tonumber(v:sub(3))
        -- elseif (v:sub(1,2) == "-w") then
        --    --print("ROB width:")
        --    rob_w = tonumber(v:sub(3))
    elseif (v:sub(1,2) == "-d") then
        --print("ROB depth:")
        rob_d = tonumber(v:sub(3))
    elseif (v:sub(1,2) == "-s") then
        --print("minimum superblock size:")
        sb_size = tonumber(v:sub(3))
    elseif (v:sub(1,2) == "-q") then
        --print("minimum superblock size:")
        quit_at = tonumber(v:sub(3))
    elseif (v:sub(1,2) == "-mg") then	-- I think it should be v:sub(1,3) here
        --print("minimum superblock size:")
        sb_merge = true
    end
end

-- collection of all the buffered sb's, key is the addr, val is the sb
-- not all the sb, but buffered
local sbs = {}
local sbs_run = {}

-- re-order buffer that contains the super blocks awaiting for issuing
local rob = {}

function init_rob(rob, MAX, WIDTH)
    -- the rob.buf is a list of list, as each level of the rob shall
    -- contain several sb's that with the same depth
    -- E.g. with MAX=3 and WIDTH=2, it looks like
    -- {{l00,l01},{l10,l11},{l20,l21}}
    rob.buf = List.new()
    rob.MAX = MAX
    rob.WIDTH = WIDTH
end

-- to record which SB writes to a specific memory address
local mem_writer = {}
-- to record which SB writes to a specific register
local reg_writer = {}
--
-- the memory access sequence of current merged-SB, I think
local mem_access = {}

-- data input of the current SB
local mem_input = {}
local reg_input = {}

local sb_addr = 0
-- the SB on which the current sb depends
local deps = {}		-- it is a subset of sbs
local sb_weight = 0

-- current SB
local reg_out_offset = {}
local reg_in_offset = {}
local reg_io = {}

local blk_seq = 0   -- unused

-- we are entering a new superblock
function start_sb(addr)
    -- print("SB "..addr)
    sb_addr = addr
end

local issue_num=1
local sb_num=0

-- place the superblock in the rob
function place_sb(rob, sb)

    -- the sb should be placed after all of its depending sb's
    local buf = rob.buf
    -- d is the depth, i.e. in which level/line of the rob the sb should be put
    local d = buf.first
    local i = 0
    -- io.stderr:write("place sb_num:", sb.sb_num, " ")
    for k, v in pairs(deps) do
        i = i + 1
        -- logd(sb.addr, d)
        if d <= v.d then 
            d = v.d 
            -- io.stderr:write("dep.sb_num=",v.sb_num," dep.depth=", v.d, " ")
            -- dep_flag=true
        end
        -- logd(k, v.d)
        -- logd(sb.addr, d)
    end

    -- for _,dep in pairs(deps) do
    --     io.stderr:write("dep.sb_num", dep.sb_num, " ")
    -- end

    -- io.stderr:write(" depth=", d, " ")


    if next(deps) then    -- the deps is not empty
        d=d+1
    end

    -- look for a non-full line which can hold the sb
    found_slot = false
    local l
    for i=d, buf.last do
        l = buf[i]
        -- if #l < rob.WIDTH then 
        if List.size(l) < rob.WIDTH then
            found_slot = true 
            d = i
            break
        end
    end

    if not found_slot then
        List.pushright(buf, List.new())
        --List.pushright(buf, {})
        d = buf.last
        l = buf[d]
    end

    -- io.stderr:write("adapted depth=", d, "\n")
    -- if dep_flag == true then
    --     io.stderr:write("Yes\n")
    -- end

    -- place the sb in the proper level of the rob
    sb['d'] = d 
    -- l[#l + 1] = sb		-- the line is a List
    List.pushright(l, sb)
    -- logd('place:', sb.addr, d)

end				
-- function place_sb(rob, sb)

-- issue a line of sb's from the rob when necessary
sum_weight=0
function issue_sb(rob)
    local buf = rob.buf
    -- if List.size(buf) > rob.MAX then
    -- count=0
    -- I confirmed that this while will do once at most.
    while List.size(buf) > rob.MAX do

        -- count=count+1
        -- logd("count=",count)

        local l = List.popleft(buf)
        local w_sum = 0
        local w_max = 0     -- unused
        local width = 0

        -- TODO add a switch verbose or terse
        issue_num=issue_num+1
        print('ISSUE', List.size(l)," No.",issue_num)

        local cid = 1
        while List.size(l) > 0 do
            v = List.popleft(l)
            --for k, v in ipairs(l) do
            width = width + 1   -- unused
            w_sum = w_sum + v.w
            if w_max < 0 + v.w then
                w_max = 0 + v.w
            end


            -- if v.sb_num == 10282 then
                -- io.stderr:write("\nsb_num=",v.sb_num, "\n")
                -- for _,dep in pairs(deps) do
                --     io.stderr:write(dep.sb_num,' ')
                -- end
            -- end

            print(string.format('SB %s %d %d %d', v.addr, cid, v.w, v.sb_num))
            cid = cid + 1

            -- MEM is unused in sequent phase
            -- for _, mem_rw in ipairs(v.mem_access) do
            --     print(string.format('MEM %d %x', mem_rw.type, mem_rw.addr))
            -- end	 
            -- sum_weight = sum_weight + v.w

            sbs_run[v.addr] = sbs[v.addr]
            sbs[v.addr] = nil
        end      

        -- TODO add a switch verbose or terse
        -- logd(Core.clocks, w_sum, w_max, width, w_sum/w_max)
    end
end

function emptying_rob(rob)
    local buf = rob.buf
    while List.size(buf) > 0 do

        -- count=count+1
        -- logd("count=",count)

        local l = List.popleft(buf)
        local w_sum = 0
        local w_max = 0     -- unused
        local width = 0

        -- TODO add a switch verbose or terse
        issue_num=issue_num+1
        print('ISSUE', List.size(l)," No.",issue_num)

        local cid = 1
        while List.size(l) > 0 do
            v = List.popleft(l)
            --for k, v in ipairs(l) do
            width = width + 1   -- unused
            w_sum = w_sum + v.w
            if w_max < 0 + v.w then
                w_max = 0 + v.w
            end

            print(string.format('SB %s %d %d %d', v.addr, cid, v.w, v.sb_num))
            cid = cid + 1

            -- MEM is unused in sequent phase
            -- for _, mem_rw in ipairs(v.mem_access) do
            --     print(string.format('MEM %d %x', mem_rw.type, mem_rw.addr))
            -- end	 
            -- sum_weight = sum_weight + v.w

            sbs_run[v.addr] = sbs[v.addr]
            sbs[v.addr] = nil
        end      

        -- TODO add a switch verbose or terse
        -- logd(Core.clocks, w_sum, w_max, width, w_sum/w_max)
    end
end

-- the current superblock ends, we'll analyze it here
function end_sb()
    -- build the superblock
    local sb = {}

    sb.seq = blk_seq
    blk_seq = blk_seq + 1

    sb_num = sb_num + 1
    sb['sb_num'] = sb_num + 1

    sb['addr'] = sb_addr
    sb['w'] = sb_weight
    sb['deps'] = deps

    -- io.stderr:write("End_sb():sb_num=",sb.sb_num,' ')
    -- for addr,dep in pairs(deps) do
    --     io.stderr:write("addr ", addr, " dep:",dep.sb_num," ")
    -- end
    -- io.stderr:write("\n")

    sb['mem_access'] = mem_access
    

    local dep_mem_cnt, dep_reg_cnt = 0, 0
    for k, v in pairs(mem_input) do
        dep_mem_cnt = dep_mem_cnt + v
    end
    for k, v in pairs(reg_input) do
        dep_reg_cnt = dep_reg_cnt + v
    end   

    sb.dep_mem_cnt = dep_mem_cnt
    sb.dep_reg_cnt = dep_reg_cnt

    sb.reg_out_offset = reg_out_offset
    sb.reg_in_offset = reg_in_offset
    sb.reg_io = reg_io

    sbs[sb_addr] = sb
    -- io.write(sb_addr.."<=")
    -- for k, v in pairs(deps) do
    --    io.write(k.." ")
    -- end
    -- print(' M:'..dep_mem_cnt..' R:'..dep_reg_cnt)
    place_sb(rob, sb)
    issue_sb(rob)

    -- FIXME do this in the init_sb()
    deps = {}
    mem_input = {}
    mem_access = {}
    reg_input = {}
    reg_out_offset = {}
    reg_in_offset = {}
    reg_io = {}

end				
-- end_sb()

-- the table deps is a set, we use addr as key, so searching it is
-- efficient
function add_depended(addr)
    deps[addr] = sbs[addr]
    -- print('add_depended:', addr)
end

function set_sb_weight(w)
    sb_weight = w
end

function parse_lackey_log(sb_size, sb_merge)	-- sb_merge is unused
    local i = 0
    local weight_accu = 0
    local first_sb_flag=true
    for line in io.lines() do
        if line:sub(1,2) ~= '==' then
            i = i + 1
            local k = line:sub(1,2)
            if k == 'SB' then
                if first_sb_flag then
                    start_sb(line:sub(4))
                    first_sb_flag=false
                end
                -- if not sb_merge or
                if weight_accu >= sb_size then
                    set_sb_weight(weight_accu)
                end_sb()
                start_sb(line:sub(4))	       
                weight_accu = 0
            end
            -- elseif k == 'I ' then	    
        elseif k == ' S' then
            -- local d_addr = tonumber(line:sub(4,11), 16)	-- why 11?
            local d_addr, _ = string.match(line:sub(4), "(%w+),(%d+)")	-- I think it's unnecessary to use number type
            d_addr=tonumber(d_addr,16)

            -- if mem_writer[d_addr] ~= nil then
            -- logd(string.format("%x",d_addr),"origin:",mem_writer[d_addr])
            -- end
            -- Let there be two SBs, A and B, which are independent. Both A and B writes to d_addr. 
            -- Suppose B is subsequent to A in the trace. B can be scheduled before A.
            -- I think it is necessary to distinguish the two writes to d_addr.
            mem_writer[d_addr] = sb_addr
            -- if mem_writer[d_addr] ~= nil then
            -- logd(string.format("%x",d_addr),"new:", mem_writer[d_addr])
            -- end
            mem_access[#mem_access + 1] = {type=1, addr=d_addr}
            -- logd("S", string.format("%x",d_addr))
        elseif k == ' L' then
            -- local d_addr = tonumber(line:sub(4,11), 16)
            local d_addr, mem_size = string.match(line:sub(4), "(%w+),(%d+)")	-- I think it's unnecessary to use number type
            d_addr=tonumber(d_addr,16)
            -- logd(line)
            -- logd(d_addr,mem_size)
            -- logd("L", string.format("%x",d_addr))
            mem_access[#mem_access + 1] = {type=0, addr=d_addr}

            local dep = mem_writer[d_addr]
            if dep and dep ~= sb_addr then 
                -- io.write("L "..line:sub(4,11).." ")
                -- add_depended(dep) 
                -- mem_input[d_addr] = tonumber(line:sub(14))	-- why 13?
                mem_input[d_addr] = tonumber(mem_size)
                -- logd("L",mem_input[d_addr])
            end
        elseif k == ' P' then
            local reg_o, offset_sb = string.match(line:sub(4), "(%d+) (%d+)")
            reg_writer[tonumber(reg_o)] = sb_addr
            -- reg_writer_seq[tonumber(reg_o)] = blk_seq
            reg_out_offset[reg_o] = offset_sb
            reg_io[#reg_io + 1] = {io='o', reg=reg_o}
            -- logd("P", sb_addr, reg_o, offset_sb, reg_out_offset)
        elseif k == ' G' then
            reg_i, offset_sb = string.match(line:sub(4), "(%d+) (%d+)")
            local d_addr = tonumber(reg_i)
            local dep = reg_writer[d_addr]
            -- if dep and dep ~= sb_addr and blk_seq ~= reg_writer_seq[d_addr] then
            if dep and dep ~= sb_addr then 
                -- io.write("G "..line:sub(4).." ")
                add_depended(dep) 	-- add dep to the deps
                reg_input[d_addr] = 1
                reg_in_offset[reg_i] = offset_sb
                reg_io[#reg_io + 1] = {io='i', reg=reg_i, dep=dep}	-- the dep is an address
            end
            -- logd("G", sb_addr, reg_i, offset_sb, dep)
            -- elseif k == ' D' then
            --    add_depended(line:sub(4))
        elseif k == ' W' then
            weight_accu = weight_accu + tonumber(line:sub(4))
        end
    end
end
-- TODO add a switch verbose or terse
-- logd(i)
end			
--  function parse_lackey_log()

rob_w = core_num
init_rob(rob, rob_d, rob_w)
parse_lackey_log(sb_size, sb_merge)
emptying_rob(rob)
