local random = math.random

local modname = core.get_current_modname()
local modpath = core.get_modpath(modname)
_G[modname] = {}

local S = core.get_translator(modname)
local Stnt = core.get_translator("tnt")

local enable_tnt = core.settings:get_bool("enable_tnt", true)
if

local tnt_radius = tonumber(core.settings:get("tnt_radius") or 3)

local cid_data = {}
core.register_on_mods_loaded(function()
	for name, def in pairs(core.registered_nodes) do
		cid_data[core.get_content_id(name)] = {
			name = name,
			drops = def.drops,
			flammable = def.groups and (def.groups.flammable or 0) ~= 0,
			on_blast = def.on_blast,
		}
	end
end)

local function escape_argument(tex)
	return tex:gsub(".", {["\\"] = "\\\\", ["^"] = "\\^", [":"] = "\\:"})
end

local function getburningtexture(main)
    local texture = ""
    texture = texture .. "([combine:16x64:0,0=" .. escape_argument(main) .. ")^"
    texture = texture .. "([combine:16x64:0,16=" .. escape_argument(main) .. ")^"
    texture = texture .. "([combine:16x64:0,32=" .. escape_argument(main) .. ")^"
    texture = texture .. "([combine:16x64:0,48=" .. escape_argument(main) .. ")^"
    return texture .. "^" .. modname .. "_burning.png"
end

local function particle_texture(name)
	local ret = {name = name}
	if core.features.particle_blend_clip then
		ret.blend = "clip"
	end
	return ret
end

local function check_surround_tnt(pos, radius, owner)
    for x = -radius, radius do
        for y = -radius, radius do
            for z = -radius, radius do
                local check = {
                    x = pos.x + x,
                    y = pos.y + y,
                    z = pos.z + z
                }

                if not vector.equals(check, pos) then
                    local node = core.get_node(check)
                    local def = core.registered_nodes[node.name]

                    if def and def.groups and def.groups.tnt then
                        if not core.is_protected(check, owner) and not string.find(node.name, "_burning") then
                            local meta = core.get_meta(check)
                            meta:set_string("owner", owner)
                            local burn_def = core.registered_nodes[node.name]
                            if burn_def and burn_def.on_blast then
                                burn_def.on_blast(check)
                            end
                        end
                    end
                end
            end
        end
    end
end

local function removetnt(pos, radius, owner)
    core.remove_node(pos)
    check_surround_tnt(pos, radius, owner:is_player() and owner:get_player_name() or owner)
end

local function add_effects(pos, radius, owner, without)
    if not (without == false) then check_surround_tnt(pos, radius, owner:get_player_name()) end
	core.add_particle({
		pos = pos,
		velocity = vector.new(),
		acceleration = vector.new(),
		expirationtime = 0.4,
		size = radius * 10,
		collisiondetection = false,
		vertical = false,
		texture = particle_texture("tnt_boom.png"),
		glow = 15,
	})
	core.add_particlespawner({
		amount = 64,
		time = 0.5,
		minpos = vector.subtract(pos, radius / 2),
		maxpos = vector.add(pos, radius / 2),
		minvel = {x = -10, y = -10, z = -10},
		maxvel = {x = 10, y = 10, z = 10},
		minacc = vector.new(),
		maxacc = vector.new(),
		minexptime = 1,
		maxexptime = 2.5,
		minsize = radius * 3,
		maxsize = radius * 5,
		texture = particle_texture("tnt_smoke.png"),
	})
end

local function add_drops_effects(pos, radius, drops)
	core.add_particle({
		pos = pos,
		velocity = vector.new(),
		acceleration = vector.new(),
		expirationtime = 0.4,
		size = radius * 10,
		collisiondetection = false,
		vertical = false,
		texture = particle_texture("tnt_boom.png"),
		glow = 15,
	})
	core.add_particlespawner({
		amount = 64,
		time = 0.5,
		minpos = vector.subtract(pos, radius / 2),
		maxpos = vector.add(pos, radius / 2),
		minvel = {x = -10, y = -10, z = -10},
		maxvel = {x = 10, y = 10, z = 10},
		minacc = vector.new(),
		maxacc = vector.new(),
		minexptime = 1,
		maxexptime = 2.5,
		minsize = radius * 3,
		maxsize = radius * 5,
		texture = particle_texture("tnt_smoke.png"),
	})

	-- we just dropped some items. Look at the items and pick
	-- one of them to use as texture.
	local texture = "tnt_blast.png" -- fallback
	local node
	local most = 0
	for name, stack in pairs(drops) do
		local count = stack:get_count()
		if count > most then
			most = count
			local def = core.registered_nodes[name]
			if def then
				node = { name = name }
				if def.tiles and type(def.tiles[1]) == "string" then
					texture = def.tiles[1]
				end
			end
		end
	end

	core.add_particlespawner({
		amount = 64,
		time = 0.1,
		minpos = vector.subtract(pos, radius / 2),
		maxpos = vector.add(pos, radius / 2),
		minvel = {x = -3, y = 0, z = -3},
		maxvel = {x = 3, y = 5,  z = 3},
		minacc = {x = 0, y = -10, z = 0},
		maxacc = {x = 0, y = -10, z = 0},
		minexptime = 0.8,
		maxexptime = 2.0,
		minsize = radius * 0.33,
		maxsize = radius,
		texture = texture,
		-- ^ only as fallback for clients without support for `node` parameter
		node = node,
		collisiondetection = true,
	})
end

local function rand_pos(center, pos, radius)
	local def
	local reg_nodes = core.registered_nodes
	local i = 0
	repeat
		-- Give up and use the center if this takes too long
		if i > 4 then
			pos.x, pos.z = center.x, center.z
			break
		end
		pos.x = center.x + random(-radius, radius)
		pos.z = center.z + random(-radius, radius)
		def = reg_nodes[core.get_node(pos).name]
		i = i + 1
	until def and not def.walkable
end

local disallowed_multiplier = {
    "mesecons",
    "stone_with_",
    "diamond",
    "iron",
    "bronze",
    "tin",
    "gold",
    "coal",
    "carpet",
    "snow",
    "bones:bones",
    "chest",
    "chest_locked",
    modname .. ":poison",
    "butterflies",
    "_source",
    "_flowing"
}

local function check_multiply(name)
    for _, find in pairs(disallowed_multiplier) do
        if string.find(name, find) then
            return false
        end
    end
    return true
end

local function eject_drops(drops, pos, radius, multiply)
    if not multiply then multiply = 1 end
	local drop_pos = vector.new(pos)
	for _, item in pairs(drops) do
		local count = math.min(item:get_count(), item:get_stack_max())
		while count > 0 do
			local take = math.max(1,math.min(radius * radius,
					count,
					item:get_stack_max()))
			rand_pos(pos, drop_pos, radius)
			local dropitem = ItemStack(item)
            if check_multiply(item:get_name()) then
			    dropitem:set_count(take * multiply)
            else
			    dropitem:set_count(take)
            end
			local obj = core.add_item(drop_pos, dropitem)
			if obj then
				obj:get_luaentity().collect = true
				obj:set_acceleration({x = 0, y = -10, z = 0})
				obj:set_velocity({x = random(-3, 3),
						y = random(0, 10),
						z = random(-3, 3)})
			end
			count = count - take
		end
	end
end

local function add_drop(drops, item)
	item = ItemStack(item)
	-- Note that this needs to be set on the dropped item, not the node.
	-- Value represents "one in X will be lost"
	local lost = item:get_definition()._tnt_loss or 0
	if lost > 0 and (lost == 1 or random(1, lost) == 1) then
		return
	end

	local name = item:get_name()
	local drop = drops[name]
	if drop == nil then
		drops[name] = item
	else
		drop:set_count(drop:get_count() + item:get_count())
	end
end

local basic_flame_on_construct -- cached value
local function destroy(drops, npos, cid, c_air, c_fire,
		on_blast_queue, on_construct_queue,
		ignore_protection, ignore_on_blast, owner)
	if not ignore_protection and core.is_protected(npos, owner) then
		return cid
	end

	local def = cid_data[cid]

	if not def then
		return c_air
	elseif not ignore_on_blast and def.on_blast then
		on_blast_queue[#on_blast_queue + 1] = {
			pos = vector.new(npos),
			on_blast = def.on_blast
		}
		return cid
	elseif def.flammable then
		on_construct_queue[#on_construct_queue + 1] = {
			fn = basic_flame_on_construct,
			pos = vector.new(npos)
		}
		return c_fire
	else
		local node_drops = core.get_node_drops(def.name, "")
		for _, item in pairs(node_drops) do
			add_drop(drops, item)
		end
		return c_air
	end
end

local function calc_velocity(pos1, pos2, old_vel, power)
	-- Avoid errors caused by a vector of zero length
	if vector.equals(pos1, pos2) then
		return old_vel
	end

	local vel = vector.direction(pos1, pos2)
	vel = vector.normalize(vel)
	vel = vector.multiply(vel, power)

	-- Divide by distance
	local dist = vector.distance(pos1, pos2)
	dist = math.max(dist, 1)
	vel = vector.divide(vel, dist)

	-- Add old velocity
	vel = vector.add(vel, old_vel)

	-- randomize it a bit
	vel = vector.add(vel, {
		x = random() - 0.5,
		y = random() - 0.5,
		z = random() - 0.5,
	})

	-- Limit to terminal velocity
	dist = vector.length(vel)
	if dist > 250 then
		vel = vector.divide(vel, dist / 250)
	end
	return vel
end

local function entity_physics(pos, radius, drops)
	local objs = core.get_objects_inside_radius(pos, radius)
	for _, obj in pairs(objs) do
		local obj_pos = obj:get_pos()
		if obj_pos then
		local dist = math.max(1, vector.distance(pos, obj_pos))

		local damage = (4 / dist) * radius
		if obj:is_player() then
			local dir = vector.normalize(vector.subtract(obj_pos, pos))
			local moveoff = vector.multiply(dir, 2 / dist * radius)
			obj:add_velocity(moveoff)

			obj:set_hp(obj:get_hp() - damage)
		else
			local luaobj = obj:get_luaentity()

			-- object might have disappeared somehow
			if luaobj then
				local do_damage = true
				local do_knockback = true
				local entity_drops = {}
				local objdef = core.registered_entities[luaobj.name]

				if objdef and objdef.on_blast then
					do_damage, do_knockback, entity_drops = objdef.on_blast(luaobj, damage)
				end

				if do_knockback then
					local obj_vel = obj:get_velocity()
					obj:set_velocity(calc_velocity(pos, obj_pos,
							obj_vel, radius * 10))
				end
				if do_damage then
					if not obj:get_armor_groups().immortal then
						obj:punch(obj, 1.0, {
							full_punch_interval = 1.0,
							damage_groups = {fleshy = damage},
						}, nil)
					end
				end
				for _, item in pairs(entity_drops) do
					add_drop(drops, item)
				end
			end
		end
		end
	end
end

local function tnt_explode(pos, radius, ignore_protection, ignore_on_blast, owner, explode_center, no_fire, circular)
	pos = vector.round(pos)
	-- scan for adjacent TNT nodes first, and enlarge the explosion
	local vm1 = VoxelManip()
	local p1 = vector.subtract(pos, 2)
	local p2 = vector.add(pos, 2)
	local minp, maxp = vm1:read_from_map(p1, p2)
	local a = VoxelArea:new({MinEdge = minp, MaxEdge = maxp})
	local data = vm1:get_data()
	local count = 0
	local c_tnt
	local c_tnt_burning = core.get_content_id("tnt:tnt_burning")
	local c_tnt_boom = core.get_content_id("tnt:boom")
	local c_air = core.CONTENT_AIR
	local c_ignore = core.CONTENT_IGNORE
	if enable_tnt then
		c_tnt = core.get_content_id("tnt:tnt")
	else
		c_tnt = c_tnt_burning -- tnt is not registered if disabled
	end
	-- make sure we still have explosion even when centre node isnt tnt related
	if explode_center then
		count = 1
	end

	for z = pos.z - 2, pos.z + 2 do
	for y = pos.y - 2, pos.y + 2 do
		local vi = a:index(pos.x - 2, y, z)
		for x = pos.x - 2, pos.x + 2 do
			local cid = data[vi]
			if cid == c_tnt or cid == c_tnt_boom or cid == c_tnt_burning then
				count = count + 1
				data[vi] = c_air
			end
			vi = vi + 1
		end
	end
	end

	vm1:set_data(data)
	vm1:write_to_map()
	if vm1.close ~= nil then
		vm1:close()
	end

	-- recalculate new radius
	radius = math.floor(radius * math.pow(count, 1/3))

	-- perform the explosion
	local vm = VoxelManip()
	local pr = PseudoRandom(os.time())
	p1 = vector.subtract(pos, radius)
	p2 = vector.add(pos, radius)
	minp, maxp = vm:read_from_map(p1, p2)
	a = VoxelArea:new({MinEdge = minp, MaxEdge = maxp})
	data = vm:get_data()

	local drops = {}
	local on_blast_queue = {}
	local on_construct_queue = {}
	basic_flame_on_construct = core.registered_nodes["fire:basic_flame"].on_construct

	-- Used to efficiently remove metadata of nodes that were destroyed.
	-- Metadata is probably sparse, so this may save us some work.
	local has_meta = {}
	for _, p in ipairs(core.find_nodes_with_meta(p1, p2)) do
		has_meta[a:indexp(p)] = true
	end

	local c_fire = core.get_content_id("fire:basic_flame")
    if not circular then
        for z = -radius, radius do
        for y = -radius, radius do
        local vi = a:index(pos.x + (-radius), pos.y + y, pos.z + z)
        for x = -radius, radius do
            local r = vector.length(vector.new(x, y, z))
            if (radius * radius) / (r * r) >= (pr:next(80, 125) / 100) then
                local cid = data[vi]
                local p = {x = pos.x + x, y = pos.y + y, z = pos.z + z}
                if cid ~= c_air and cid ~= c_ignore then
                    local new_cid = destroy(drops, p, cid, c_air, c_fire,
                        on_blast_queue, on_construct_queue,
                        ignore_protection, ignore_on_blast, owner)

                    if new_cid ~= data[vi] then
                        if ((new_cid == c_fire) and not no_fire) or (new_cid ~= c_fire) then
                            data[vi] = new_cid
                        end
                        if has_meta[vi] then
                            core.get_meta(p):from_table(nil)
                        end
                    end
                end
            end
            vi = vi + 1
        end
        end
        end
    else
        pos = vector.round(pos)
        local p1 = vector.subtract(pos, radius)
        local p2 = vector.add(pos, radius)
        for z = p1.z, p2.z do
            for y = p1.y, p2.y do
                for x = p1.x, p2.x do
                    local current_pos = vector.new(x, y, z)
                    if not core.is_protected(current_pos, player_name) then
                        local vi = a:index(x, y, z)
                        local cid = data[vi]
                        local distance_sq = vector.distance(pos, current_pos) ^ 2
                        if distance_sq <= radius ^ 2 then
                            if cid ~= c_air and cid ~= c_ignore then
                                local new_cid = destroy(drops, p, cid, c_air, c_fire,
                                    on_blast_queue, on_construct_queue,
                                    ignore_protection, ignore_on_blast, owner)

                                if new_cid ~= data[vi] then
                                    if ((new_cid == c_fire) and not no_fire) or (new_cid ~= c_fire) then
                                        data[vi] = new_cid
                                    end
                                    if has_meta[vi] then
                                        core.get_meta(p):from_table(nil)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

	vm:set_data(data)
	vm:write_to_map()
	vm:update_liquids()
	if vm.close ~= nil then
		vm:close()
	end

	-- call check_single_for_falling for everything within 1.5x blast radius
	for y = -radius * 1.5, radius * 1.5 do
	for z = -radius * 1.5, radius * 1.5 do
	for x = -radius * 1.5, radius * 1.5 do
		local rad = {x = x, y = y, z = z}
		local s = vector.add(pos, rad)
		local r = vector.length(rad)
		if r / radius < 1.4 then
			core.check_single_for_falling(s)
		end
	end
	end
	end

	for _, queued_data in pairs(on_blast_queue) do
		local dist = math.max(1, vector.distance(queued_data.pos, pos))
		local intensity = (radius * radius) / (dist * dist)
		local node_drops = queued_data.on_blast(queued_data.pos, intensity)
		if node_drops then
			for _, item in pairs(node_drops) do
				add_drop(drops, item)
			end
		end
	end

	for _, queued_data in pairs(on_construct_queue) do
		queued_data.fn(queued_data.pos)
	end

	core.log("action", "TNT owned by " .. owner .. " detonated at " ..
		core.pos_to_string(pos) .. " with radius " .. radius)

	return drops, radius
end

_G[modname].boom = function(pos, def)
	def = def or {}
	def.radius = def.radius or 1
	def.damage_radius = def.damage_radius or def.radius * 2
	local meta = core.get_meta(pos)
	local owner = meta:get_string("owner")
	if not def.explode_center and def.ignore_protection ~= true then
		core.set_node(pos, {name = "tnt:boom"})
	end
	local sound = def.sound or "tnt_explode"
	core.sound_play(sound, {pos = pos, gain = 2.5,
			max_hear_distance = math.min(def.radius * 20, 128)}, true)
	local drops, radius = tnt_explode(pos, def.radius, def.ignore_protection,
			def.ignore_on_blast, owner, def.explode_center, def.no_fire, def.circular)
	-- append entity drops
	local damage_radius = (radius / math.max(1, def.radius)) * def.damage_radius
	entity_physics(pos, damage_radius, drops)
	if not def.disable_drops then
		eject_drops(drops, pos, radius, def.multiplier)
	end
	add_drops_effects(pos, radius, drops)
	core.log("action", "A TNT explosion occurred at " .. core.pos_to_string(pos) ..
		" with radius " .. radius)
end

_G[modname].square_explode = function(pos, radius, replace, player_name)
    local replace_id = core.CONTENT_AIR
    if replace and core.registered_nodes[replace] then
        replace_id = core.get_content_id(replace)
    end
    
    pos = vector.round(pos)
    local p1 = vector.subtract(pos, radius)
    local p2 = vector.add(pos, radius)
    local vm = VoxelManip()
    local minp, maxp = vm:read_from_map(p1, p2)
    local a = VoxelArea:new({MinEdge = minp, MaxEdge = maxp})
    local data = vm:get_data()

    data[a:index(pos.x, pos.y, pos.z)] = core.CONTENT_AIR

    for z = p1.z, p2.z do
        for y = p1.y, p2.y do
            for x = p1.x, p2.x do
                local current_pos = vector.new(x, y, z)
                if not core.is_protected(current_pos, player_name) then
                    local vi = a:index(x, y, z)
                    local cid = data[vi]
                    if cid ~= core.CONTENT_AIR and cid ~= core.CONTENT_IGNORE then
                        data[vi] = replace_id
                    end
                end
            end
        end
    end

    vm:set_data(data)
    vm:write_to_map()
    vm:update_liquids()
    if vm.close then
        vm:close()
    end

    core.log("action", "Square explosion at " .. core.pos_to_string(pos) ..
              " with radius " .. radius .. " by player " .. player_name)
end

_G[modname].circular_explode = function(pos, radius, action, replace, player_name)
    local replace_id = core.CONTENT_AIR
    if replace and core.registered_nodes[replace] then
        replace_id = core.get_content_id(replace)
    end
    
    pos = vector.round(pos)
    local p1 = vector.subtract(pos, radius)
    local p2 = vector.add(pos, radius)
    local vm = VoxelManip()
    local minp, maxp = vm:read_from_map(p1, p2)
    local a = VoxelArea:new({MinEdge = minp, MaxEdge = maxp})
    local data = vm:get_data()

    data[a:index(pos.x, pos.y, pos.z)] = core.CONTENT_AIR

    for z = p1.z, p2.z do
        for y = p1.y, p2.y do
            for x = p1.x, p2.x do
                local current_pos = vector.new(x, y, z)
                if not core.is_protected(current_pos, player_name) then
                    local vi = a:index(x, y, z)
                    local cid = data[vi]
                    local distance_sq = vector.distance(pos, current_pos) ^ 2
                    if distance_sq <= radius ^ 2 then
                        if not action then
                            if cid ~= core.CONTENT_AIR and cid ~= core.CONTENT_IGNORE then
                                data[vi] = replace_id
                            end
                        elseif action == "random" then
                            if cid ~= core.CONTENT_AIR and cid ~= core.CONTENT_IGNORE and random(1,3) == 3 then
                                data[vi] = replace_id
                            end
                        end
                    end
                end
            end
        end
    end

    vm:set_data(data)
    vm:write_to_map()
    vm:update_liquids()
    if vm.close then
        vm:close()
    end

    core.log("action", "Circular explosion at " .. core.pos_to_string(pos) ..
              " with radius " .. radius .. " by player " .. player_name)
end

_G[modname].register_tnt = function(def, custom)
	local name
	if not def.name:find(':') then
		name = modname .. ":" .. def.name
	else
		name = def.name
		def.name = def.name:match(":([%w_]+)")
	end
	if not def.tiles then def.tiles = {} end
    if not def.radius then def.radius = tnt_radius end
	local tnt_top = def.tiles.top or def.name .. "_top.png"
	local tnt_bottom = def.tiles.bottom or def.name .. "_bottom.png"
	local tnt_side = def.tiles.side or def.name .. "_side.png"
	local tnt_burning = def.tiles.burning or def.name .. "_top_burning_animated.png"
    if not custom then
        tnt_burning = {
            name = tnt_burning,
            animation = {
                type = "vertical_frames",
                aspect_w = 16,
                aspect_h = 16,
                length = 1,
            }
        }
    end
	if not def.damage_radius then def.damage_radius = def.radius * 2 end

    local explode = (def.boom and function(pos)
        local owner = core.get_player_by_name(core.get_meta(pos):get_string("owner"))
        if owner then
            def.boom(pos, def, owner)
        end
    end) or function(pos)
        tnt.boom(pos, def)
    end

    local normal_def = {
        description = def.description,
        tiles = {
            (def.flip and tnt_bottom or tnt_top),
            (def.flip and tnt_top or tnt_bottom),
            tnt_side
        },
        is_ground_content = def.is_ground_content or false,
        paramtype = def.paramtype or nil,
        use_texture_alpha = def.use_texture_alpha or nil,
        groups = {dig_immediate = 2, mesecon = 2, tnt = 1, flammable = 5},
        sounds = def.sounds or default.node_sound_wood_defaults(),
        light_source = def.light_source or 0,
        on_construct = def.on_construct or nil,
        drawtype = def.drawtype or nil,
        on_dig = def.on_dig or nil,
        drops = def.drops or nil,
        after_place_node = function(pos, placer)
            if placer and placer:is_player() then
                local meta = core.get_meta(pos)
                meta:set_string("owner", placer:get_player_name())
                meta:set_string("owner2", placer:get_player_name())
            end
        end,
        on_punch = function(pos, node, puncher)
            if puncher:get_wielded_item():get_name() == "default:torch" then
                core.swap_node(pos, {name = name .. "_burning"})
                core.registered_nodes[name .. "_burning"].on_construct(pos)
                default.log_player_action(puncher, "ignites", node.name, "at", pos)
            end
        end,
        on_blast = function(pos)
            core.after(0.1, function()
                explode(pos)
            end)
        end,
        mesecons = {effector =
            {action_on =
                function(pos)
                    explode(pos)
                end
            }
        },
        on_burn = function(pos)
            core.swap_node(pos, {name = name .. "_burning"})
            core.registered_nodes[name .. "_burning"].on_construct(pos)
        end,
        on_ignite = function(pos, igniter)
            core.swap_node(pos, {name = name .. "_burning"})
            core.registered_nodes[name .. "_burning"].on_construct(pos)
            if igniter and igniter:is_valid() and igniter:is_player() then
                local meta = core.get_meta(pos)
                meta:set_string("owner", igniter:get_player_name())
            end
        end,
    }

    if enable_tnt then
        core.register_node(":" .. name, normal_def)

        if def.craft then
            local recipe = table.copy(def.craft)
            if not recipe["output"] then recipe["output"] = name end
            core.register_craft(recipe)
        end
    end
    local light = def.light_source and (def.light_source + 5) or 5
    if light > 14 then light = 14 end

    local burn_def = table.copy(normal_def)
    -- im sure there's a better way to do this, but idc tbh
    burn_def.light_source = light
    burn_def.description = nil
    burn_def.mesecons = nil
    burn_def.drop = ""
    burn_def.on_timer = explode
    burn_def.groups = {falling_node = 1, not_in_creative_inventory = 1}
    burn_def.tiles = {
        (def.flip and tnt_bottom or tnt_burning),
        (def.flip and tnt_burning or tnt_bottom),
        tnt_side
    }
    burn_def.on_burn = nil
    burn_def.on_ignite = nil
    burn_def.on_punch = nil
    burn_def.after_place_node = nil
    burn_def.on_blast = function() end
    burn_def.on_construct = function(pos)
        local meta = core.get_meta(pos)
        if def.on_ignite then def.on_ignite(pos, core.get_player_by_name(meta:get_string("owner"))) end
        core.sound_play("tnt_ignite", {pos = pos}, true)
        core.get_node_timer(pos):start(def.ignite_timer or 4)
        core.check_for_falling(pos)
    end

	core.register_node(":" .. name .. "_burning", burn_def)
end

local function get_highest(pos, name)
    local highest_y = pos.y
    local current_y = pos.y

    while current_y > -50 do
        local npos = {x = pos.x, y = current_y, z = pos.z}
        local bnpos = {x = pos.x, y = current_y - 1, z = pos.z}
        local node = core.get_node(npos)
        local bnode = core.get_node(bnpos)

        local ndef = core.registered_nodes[node.name]
        if ((node.name == "air" or ndef.buildable_to) and bnode.name ~= "air") or (name and node.name == name or false) then
            highest_y = current_y
            break
        end

        if node.name == "air" and bnode.name == "air" then
            current_y = current_y - 1
        else
            current_y = current_y + 1
        end
    end

    return {x = pos.x, y = math.floor(highest_y), z = pos.z}
end

local function scatter(pos, name, max, density, owner)
    for radius = 1, max do
        local count = math.floor(density / radius)
        if count < 1 then
            break
        end
        for i = 1, count do
            local angle = random() * 2 * math.pi
            local offsetx = math.cos(angle) * radius
            local offsetz = math.sin(angle) * radius
            
            local new_pos = get_highest({
                x = pos.x + offsetx,
                y = pos.y,
                z = pos.z + offsetz
            }, name)
            
            local node = core.get_node(new_pos)
            if (node.name ~= name) and not core.is_protected(pos, owner) then
                core.set_node(new_pos, {name = name})
                core.check_for_falling(new_pos)
            end
        end
    end
end

local function scatterboom(pos, name, max, density, owner)
    for radius = 1, max do
        local count = math.floor(density / radius)
        if count < 1 then
            break
        end
        for i = 1, count do
            local angle = random() * 2 * math.pi
            local offsetx = math.cos(angle) * radius
            local offsetz = math.sin(angle) * radius
            
            local new_pos = get_highest({
                x = pos.x + offsetx,
                y = pos.y,
                z = pos.z + offsetz
            }, name)

            new_pos.y = new_pos.y
            
            local node = core.get_node(new_pos)
            if (node.name ~= name) and not core.is_protected(pos, owner) then
                core.set_node(new_pos, {name = name})
                local _, obj = core.spawn_falling_node(new_pos)
                local dx = new_pos.x - pos.x
                local dz = new_pos.z - pos.z

                local dist = math.sqrt(dx * dx + dz * dz)

                local dirx, dirz = 0, 0
                if dist > 0 then
                    dirx = dx / dist
                    dirz = dz / dist
                end

                local falloff = 1 - (dist / max)

                local vertical_power = 24 * falloff
                local horizontal_power = dist * 2

                obj:add_velocity({
                    x = dirx * horizontal_power,
                    y = vertical_power + randomFloat(0, 2),
                    z = dirz * horizontal_power
                })
            end
        end
    end
end

local snow_def = table.copy(core.registered_nodes["default:snow"])
snow_def.groups["not_in_creative_inventory"] = 1
snow_def.drop = ""
snow_def.tiles = {{name = "default_snow.png", color = "lime"}}
snow_def.damage_per_second = 1
core.register_node(modname .. ":poison", snow_def)

local function texture(color, icon)
    if icon then icon = "^" .. icon else icon = "" end
    return {
        top = modname .. "_bottom.png^" .. color .. "^" .. modname .. "_top.png",
        side = modname .. "_side.png^" .. color .. icon,
        bottom = modname .. "_bottom.png^" .. color,
        burning = getburningtexture(modname .. "_bottom.png^" .. color),
    }
end

local function texture_top(color, icon, top)
    if icon then icon = "^" .. icon else icon = "" end
    if top then top = "^" .. top else top = "" end
    return {
        top = modname .. "_bottom.png^" .. color .. top .. "^" .. modname .. "_top.png",
        side = modname .. "_side.png^" .. color .. icon,
        bottom = modname .. "_bottom.png^" .. color .. top,
        burning = getburningtexture(modname .. "_bottom.png^" .. color),
    }
end

core.register_craftitem(modname..":demon_core", {
    description = S("Demon Core"),
    inventory_image = modname.."_demon_core.png"
})

core.register_craft({
    output = modname..":demon_core",
    recipe = {
        {"uraniumstuff:uranium_gem", "default:steel_ingot", "uraniumstuff:uranium_gem"},
        {"default:steel_ingot", "uraniumstuff:uranium_protection_gem", "default:steel_ingot"},
        {"uraniumstuff:uranium_gem", "default:steel_ingot", "uraniumstuff:uranium_gem"}
    }
})

core.register_craftitem(modname..":atomic_bomb", {
    description = S("Atomic Bomb"),
    inventory_image = modname.."_atomic_bomb.png"
})

core.register_craft({
    output = modname..":atomic_bomb",
    recipe = {
        {"basic_materials:steel_strip", "tnt:tnt", "basic_materials:steel_strip"},
        {"uraniumstuff:uranium_protection_gem", modname..":demon_core", "uraniumstuff:uranium_protection_gem"},
        {"basic_materials:steel_strip", "tnt:tnt", "basic_materials:steel_strip"}
    }
})

_G[modname].register_tnt({
	name = modname..":nuke",
	description = S("Nuclear TNT"),
	radius = 64,
    tiles = texture("[multiply:#ffff00", modname.."_nuke_side_overlay.png"),
    ignite_timer = 10,
    craft = {
        recipe = {
            {"basic_materials:steel_bar", "tnt:tnt", "basic_materials:steel_bar"},
            {"basic_materials:steel_wire", modname..":atomic_bomb", "basic_materials:steel_wire"},
            {modname..":tnt_poison", "tnt:tnt", modname..":tnt_poison"}
        }
    },
    boom = function(pos, def, owner)
        tnt.boom(pos, def)
        core.after(5, function()
            core.chat_send_all(core.colorize("red", S("ATOMIC BOMB EXPLODED BY @1!", owner:get_player_name())))
            pos.y = pos.y
            scatter(pos, modname..":poison", 100, 350, owner:get_player_name())
        end)
    end
})

core.register_craftitem(modname..":engine", {
    description = S("Engine"),
    inventory_image = modname.."_engine.png"
})

core.register_craft({
    recipe = {
        {"basic_materials:steel_strip", "basic_materials:steel_wire", "basic_materials:steel_strip"},
        {"basic_materials:gear_steel", "basic_materials:motor", "basic_materials:gear_steel"},
        {"basic_materials:steel_strip", "default:mese", "basic_materials:steel_strip"}
    },
    output = modname..":engine"
})

_G[modname].register_tnt({
	name = modname..":dig",
	description = S("Digging TNT"),
    tiles = texture("[multiply:#fa0000", modname.."_dig.png"),
    craft = {
        recipe = {
            {"basic_materials:energy_crystal_simple", modname..":engine", "basic_materials:energy_crystal_simple"},
            {"default:tin_ingot", "tnt:tnt", "default:tin_ingot"},
            {"default:steel_ingot", "bucket:bucket_water", "default:steel_ingot"}
        },
        replacements = {
            {"bucket:bucket_water", "bucket:bucket_empty"}
        }
    },
    boom = function(pos, def, owner)
        add_effects(pos, def.radius, owner)
        for i = 0, 60 do
            core.dig_node(pos, owner)
            if i > 56 then
                core.set_node(pos, {name = "default:water_source"})
            end
            pos.y = pos.y - 1
        end
    end
})

_G[modname].register_tnt({
	name = modname..":drill",
	description = S("Drilling TNT"),
    tiles = texture("[multiply:#ff4f00", modname.."_dig.png"),
    craft = {
        recipe = {
            {"basic_materials:gold_wire", modname..":engine", "basic_materials:gold_wire"},
            {"basic_materials:energy_crystal_simple", modname..":dig", "basic_materials:energy_crystal_simple"},
            {"default:gold_ingot", "default:diamond", "default:gold_ingot"}
        }
    },
    boom = function(pos, def, owner)
        add_effects(pos, def.radius, owner)
        for _ = 0, 60 do
            _G[modname].circular_explode(pos, def.radius, nil, nil, owner:get_player_name())
            pos.y = pos.y - 1
        end
    end
})

local diamond_def = table.copy(core.registered_nodes["default:diamondblock"])
diamond_def.tiles = {"default_diamond_block.png^" .. modname .. "_vignette.png"}
diamond_def.description = S("Super") .. " " .. diamond_def.description
core.register_node(modname..":super_diamondblock", diamond_def)
core.register_craft({
    recipe = {
        {"default:diamondblock", "default:diamondblock", "default:diamondblock"},
        {"default:diamondblock", "default:diamondblock", "default:diamondblock"},
        {"default:diamondblock", "default:diamondblock", "default:diamondblock"}
    },
    output = modname..":super_diamondblock"
})

core.register_craft({
    recipe = {
        {modname..":super_diamondblock"}
    },
    output = "default:diamondblock 9"
})

_G[modname].register_tnt({
	name = modname..":diamond",
	description = S("Diamond TNT"),
    tiles = {
        top = "default_stone.png^default_mineral_diamond.png^" .. modname .. "_top.png",
        bottom = "default_stone.png^default_mineral_diamond.png",
        side = "default_stone.png^default_mineral_diamond.png^" .. modname .. "_diamond_side_overlay.png",
        burning = getburningtexture("default_stone.png^default_mineral_diamond.png"),
    },
    craft = {
        recipe = {
            {modname..":super_diamondblock", modname..":super_diamondblock", modname..":super_diamondblock"},
            {modname..":super_diamondblock", "tnt:tnt", modname..":super_diamondblock"},
            {modname..":super_diamondblock", modname..":super_diamondblock", modname..":super_diamondblock"}
        }
    },
    radius = 6,
    boom = function(pos, def, owner)
        add_effects(pos, def.radius, owner)
        _G[modname].square_explode(pos, def.radius, "default:diamondblock", owner:get_player_name())
        local sound = def.sound or "tnt_explode"
        core.sound_play(sound, {pos = pos, gain = 2.5,
                max_hear_distance = math.min(def.radius * 20, 128)}, true)
    end
})

_G[modname].register_tnt({
	name = modname..":lava",
	description = S("Lava TNT"),
    tiles = {
        top = {
            name = modname.."_lava_top.png",
            animation = {
                type = "vertical_frames",
                aspect_w = 16,
                aspect_h = 16,
                length = 3,
            }
        },
        bottom = {
            name = "default_lava_source_animated.png",
            animation = {
                type = "vertical_frames",
                aspect_w = 16,
                aspect_h = 16,
                length = 3,
            }
        },
        side = {
            name = modname.."_lava_side.png",
            animation = {
                type = "vertical_frames",
                aspect_w = 16,
                aspect_h = 16,
                length = 3,
            }
        },
        burning = {
            name = modname.."_lava_burning.png",
            animation = {
                type = "vertical_frames",
                aspect_w = 16,
                aspect_h = 16,
                length = 3,
            }
        }
    },
    craft = {
        recipe = {
            {"bucket:bucket_lava", "bucket:bucket_lava", "bucket:bucket_lava"},
            {"bucket:bucket_lava", "tnt:tnt", "bucket:bucket_lava"},
            {"bucket:bucket_lava", "bucket:bucket_lava", "bucket:bucket_lava"}
        }
    },
    radius = 3,
    light_source = 10,
    boom = function(pos, def, owner)
        add_effects(pos, def.radius, owner)
        _G[modname].circular_explode(pos, def.radius, "random", "default:lava_source", owner:get_player_name())
        local sound = def.sound or "tnt_explode"
        core.sound_play(sound, {pos = pos, gain = 2.5,
                max_hear_distance = math.min(def.radius * 20, 128)}, true)
    end
}, true)

local function spawnhouse(pos, player, node)
    core.remove_node(pos)
    pos = vector.subtract(pos, {x = 2, y = 0, z = 2})

    local center = {
        x = pos.x + 2,
        y = pos.y,
        z = pos.z + 2
    }

    local ppos = player:get_pos()
    local dx = ppos.x - center.x
    local dz = ppos.z - center.z

    local door_x, door_z
    if math.abs(dx) > math.abs(dz) then
        if dx > 0 then
            door_x, door_z = 4, 2
        else
            door_x, door_z = 0, 2
        end
    else
        if dz > 0 then
            door_x, door_z = 2, 4
        else
            door_x, door_z = 2, 0
        end
    end

    local blocks = {}
    for y = 0, 4 do
        for x = 0, 4 do
            for z = 0, 4 do
                local is_wall = (y == 0 or y == 4 or x == 0 or x == 4 or z == 0 or z == 4)

                if is_wall then
                    if not (
                        x == door_x and z == door_z and (y == 1 or y == 2)
                    ) then
                        table.insert(blocks, {
                            pos = {x = pos.x + x, y = pos.y + y, z = pos.z + z},
                            name = node
                        })
                    end
                end
            end
        end
    end

    local delay = 0.075
    local minus = 0
    for i, data in ipairs(blocks) do
        local node = core.get_node(data.pos)
        if node.name == "air" or core.registered_nodes[node.name].buildable_to then
            core.after((i - minus) * delay, function()
                if not core.is_protected(data.pos, player:get_player_name()) then
                    core.sound_play(modname.."_build", {
                        pos = data.pos,
                        pitch = randomFloat(0.5, 1.5)
                    })
                    core.set_node(data.pos, {name = data.name})
                end
            end)
        else
            minus = minus + 1
        end
    end
end

local function register_fakenode(name)
    local ndef = table.copy(core.registered_items["default:" .. name])
    ndef.is_ground_content = nil
    ndef.groups["not_in_creative_inventory"] = 1
    ndef.drop = ""
    ndef.description = nil
    ndef.short_description = nil
    name = modname .. ":fake_" .. name
    core.register_node(name, ndef)
end

register_fakenode("cobble")

_G[modname].register_tnt({
	name = modname..":cobble",
	description = S("House TNT"),
    craft = {
        recipe = {
            {"default:cobble", "default:cobble", "default:cobble"},
            {"default:cobble", "tnt:tnt", "default:cobble"},
            {"default:cobble", "default:cobble", "default:cobble"}
        }
    },
    tiles = texture("default_cobble.png", modname.."_house_overlay.png"),
    boom = function(pos, def, owner)
        spawnhouse(pos, owner, modname..":fake_cobble")
    end
})

register_fakenode("wood")

_G[modname].register_tnt({
	name = modname..":wood",
	description = S("Wooden House TNT"),
    tiles = texture("default_wood.png", modname.."_house_overlay.png"),
    craft = {
        recipe = {
            {"default:wood", "default:wood", "default:wood"},
            {"default:wood", modname..":cobble", "default:wood"},
            {"default:wood", "default:wood", "default:wood"}
        }
    },
    boom = function(pos, def, owner)
        spawnhouse(pos, owner, modname..":fake_wood")
    end
})

register_fakenode("brick")

_G[modname].register_tnt({
	name = modname..":brick",
	description = S("Brick House TNT"),
    tiles = texture("default_brick.png", modname.."_house_overlay.png"),
    craft = {
        recipe = {
            {"default:brick", "default:brick", "default:brick"},
            {"default:brick", modname..":wood", "default:brick"},
            {"default:brick", "default:brick", "default:brick"}
        }
    },
    boom = function(pos, def, owner)
        spawnhouse(pos, owner, modname..":fake_brick")
    end
})

_G[modname].register_tnt({
	name = modname..":freeze",
	description = S("Freeze TNT"),
    tiles = texture("[multiply:#80c8ff", modname.."_title.png"),
    craft = {
        recipe = {
            {"default:ice", "default:ice", "default:ice"},
            {"default:ice", "tnt:tnt", "default:ice"},
            {"default:ice", "default:ice", "default:ice"}
        }
    },
    radius = 5,
    boom = function(pos, def, owner)
        add_effects(pos, def.radius, owner)
        _G[modname].circular_explode(pos, def.radius, nil, "default:ice", owner:get_player_name())
        local sound = def.sound or "tnt_explode"
        core.sound_play(sound, {pos = pos, gain = 2.5,
                max_hear_distance = math.min(def.radius * 20, 128)}, true)
    end
})

_G[modname].register_tnt({
	name = modname..":multiply",
	description = S("Multiply TNT"),
    tiles = texture("[multiply:#ffff33", modname.."_title.png"),
    multiplier = 3,
    craft = {
        recipe = {
            {"default:mese_crystal", "default:mese_crystal", "default:mese_crystal"},
            {"default:mese_crystal", "tnt:tnt", "default:mese_crystal"},
            {"default:mese_crystal", "default:mese_crystal", "default:mese_crystal"}
        }
    },
    boom = _G[modname].boom
})

local disallowed_entities = {
    "worldedit",
    "__builtin",
    "cart",
    "boat",
    "falling_node",
    "decor_api",
    "modern",
    "multidecor",
    "homedecor_common",
    "enchant"
}

local function check_entity(name)
    for _, find in pairs(disallowed_entities) do
        if string.find(name, find) then
            return false
        end
    end
    return true
end

local function entities()
    local registered = {}
    for name, _ in pairs(core.registered_entities) do
        if check_entity(name) then
            table.insert(registered, name)
        end 
    end
    return registered
end

local entity = entities()
if #entity ~= 0 then
    _G[modname].register_tnt({
        name = modname..":animal",
        description = S("Animal TNT"),
        tiles = texture("[multiply:#854b20", modname.."_title.png"),
        craft = {
            recipe = {
                {"mobs:protector2", "mobs:leather", "mobs:protector2"},
                {"mobs:leather", "tnt:tnt", "mobs:leather"},
                {"mobs:protector2", "mobs:leather", "mobs:protector2"}
            }
        },
        boom = function(pos, def, owner)
            add_effects(pos, def.radius, owner)
            removetnt(pos, def.radius, owner)
            pos.y = pos.y + 2.5
            for _ = 1, random(2, 10) do
                core.add_entity(pos, entity[random(1, #entity)])
            end
        end
    })
end

_G[modname].register_tnt({
    name = modname..":snow",
    description = S("Snow TNT"),
    sounds = default.node_sound_snow_defaults(),
    tiles = texture("[multiply:#cedbf5", modname.."_title.png"),
    craft = {
        recipe = {
            {"default:snowblock", "default:snowblock", "default:snowblock"},
            {"default:snowblock", "tnt:tnt", "default:snowblock"},
            {"default:snowblock", "default:snowblock", "default:snowblock"}
        }
    },
    boom = function(pos, def, owner)
        add_effects(pos, def.radius, owner)
        removetnt(pos, def.radius, owner)
        local sound = def.sound or "tnt_explode"
        core.sound_play(sound, {pos = pos, gain = 2.5,
                max_hear_distance = math.min(def.radius * 20, 128)}, true)
        scatter(pos, "default:snow", 10, 250, owner:get_player_name())
    end
})

_G[modname].register_tnt({
    name = modname..":sand",
    description = S("Sand Firework TNT"),
    sounds = default.node_sound_sand_defaults(),
    tiles = texture("[multiply:#fcfbb1", modname.."_title.png"),
    craft = {
        recipe = {
            {"default:sandstonebrick", "default:sandstonebrick", "default:sandstonebrick"},
            {"default:sandstonebrick", "tnt:tnt", "default:sandstonebrick"},
            {"default:sandstonebrick", "default:sandstonebrick", "default:sandstonebrick"}
        }
    },
    boom = function(pos, def, owner)
        add_effects(pos, def.radius, owner)
        removetnt(pos, def.radius, owner)
        local sound = def.sound or "tnt_explode"
        core.sound_play(sound, {pos = pos, gain = 2.5,
                max_hear_distance = math.min(def.radius * 20, 128)}, true)
        scatterboom(pos, "default:sand", 128, 16, owner:get_player_name())
    end
})

_G[modname].register_tnt({
    name = modname..":sphere",
    description = S("Sphere TNT"),
    tiles = texture("[multiply:#fa7907^" .. modname .. "_circlular_side_overlay.png", modname.."_title.png"),
    radius = 5,
    no_fire = true,
    circular = true,
    craft = {
        recipe = {
            {"default:diamond", "default:mese_crystal", "default:diamond"},
            {"default:mese_crystal", "tnt:tnt", "default:mese_crystal"},
            {"default:diamond", "default:mese_crystal", "default:diamond"}
        }
    },
    boom = _G[modname].boom
})

local function copy_area(center, radius, owner)
    local min_x = center.x - radius
    local max_x = center.x + radius
    local min_y = center.y - radius
    local max_y = center.y + radius
    local min_z = center.z - radius
    local max_z = center.z + radius

    for x = min_x, max_x do
        for y = min_y, max_y do
            for z = min_z, max_z do
                local node = core.get_node({x = x, y = y, z = z})
                local npos = {x = x, y = y + 64, z = z}
                if not core.is_protected(npos, owner) then
                    core.set_node(npos, node)
                    core.check_for_falling(npos)
                end
            end
        end
    end
end

_G[modname].register_tnt({
    name = modname..":island",
    description = S("Floating Island TNT"),
    tiles = texture("[multiply:#32cf32", modname.."_island_side_overlay.png"),
    radius = 10,
    craft = {
        recipe = {
            {"default:dirt_with_grass", "default:dirt_with_grass", "default:dirt_with_grass"},
            {"default:meselamp", "tnt:tnt", "default:meselamp"},
            {"default:mese", "default:mese", "default:mese"}
        }
    },
    boom = function(pos, def, owner)
        core.remove_node(pos)
        copy_area(pos, def.radius, owner:get_player_name())
        pos.y = pos.y + 64
        add_effects(pos, def.radius, owner)
        local sound = def.sound or "tnt_explode"
        core.sound_play(sound, {pos = pos, gain = 2.5,
                max_hear_distance = math.min(def.radius * 20, 128)}, true)
    end
})

core.register_node(modname..":meteor", {
    description = S("Meteor"),
    tiles = {modname.."_meteor.png"},
    sounds = default.node_sound_defaults(),
    groups = {cracky = 1, falling_node = 1}
})

function randomFloat(lower, greater)
    return lower + random()  * (greater - lower);
end

_G[modname].register_tnt({
    name = modname..":tnt_meteor",
    description = S("Meteor TNT"),
    sounds = default.node_sound_defaults(),
    tiles = texture(modname.."_meteor.png", modname.."_title.png"),
    craft = {
        recipe = {
            {"dye:red", "uraniumstuff:uranium_protection_gem", "dye:red"},
            {"default:obsidian", "tnt:tnt", "default:obsidian"},
            {"dye:red", "default:mese", "dye:red"}
        }
    },
    boom = function(pos, def, owner)
        local bpos = table.copy(pos)
        bpos.y = bpos.y - 1
        local bnode = core.get_node(pos)
        local max = random(5, 15)
        for i = 0, max do
            local npos = table.copy(pos)
            npos.x = npos.x + random(-32, 32)
            npos.z = npos.z + random(-32, 32)
            core.after(randomFloat(0.75, 5.0), function()
                npos = get_highest(npos, bnode.name)
                if not core.is_protected(npos, owner) then
                    tnt.boom(npos, def)
                    core.after(0.25, function()
                        core.set_node(npos, {name = modname..":meteor"})
                        core.check_for_falling(npos)
                    end)
                end
                if i == max then
                    removetnt(pos, def.radius, owner)
                end
            end)
        end
    end
})

if core.get_modpath("lucky_block") then
    local Slb = core.get_translator("lucky_block")

    -- functions from lb mod
    local function effect(pos, amount, texture, min_size, max_size, radius, gravity, glow)
        radius = radius or 2
        gravity = gravity or -10

        core.add_particlespawner({
            amount = amount,
            time = 0.25,
            minpos = pos,
            maxpos = pos,
            minvel = {x = -radius, y = -radius, z = -radius},
            maxvel = {x = radius, y = radius, z = radius},
            minacc = {x = 0, y = gravity, z = 0},
            maxacc = {x = 0, y = gravity, z = 0},
            minexptime = 0.1,
            maxexptime = 1,
            minsize = min_size or 0.5,
            maxsize = max_size or 1.0,
            texture = texture,
            glow = glow
        })
    end

    local function super_lucky(pos, player)
        if random(10) < 8 then
            effect(pos, 25, "tnt_smoke.png", 8, 8, 1, -10, 0)
            local pitch = 1.0 + random(-10, 10) * 0.005
            core.sound_play("fart1", {
                    pos = pos, gain = 1.0, max_hear_distance = 10, pitch = pitch}, true)
            if random(5) == 1 then
                pos.y = pos.y + 0.5
                core.add_item(pos, lucky_block.def_gold .. " " .. random(5))
            end
        else
            core.set_node(pos, {name = "lucky_block:lucky_block"})
        end
    end

    local super_lucky_list = {
        {"cus", super_lucky}
    }

    _G[modname].register_tnt({
        name = modname..":lucky_block",
        description = Slb("Lucky Block").. " " ..S("TNT"),
        radius = 2,
        light_source = 3,
        tiles = texture(modname.."_lucky_block_background.png", modname.."_title.png"),
        craft = {
            recipe = {
                {"lucky_block:lucky_block", "lucky_block:lucky_block", "lucky_block:lucky_block"},
                {"lucky_block:lucky_block", "tnt:tnt", "lucky_block:lucky_block"},
                {"lucky_block:lucky_block", "lucky_block:lucky_block", "lucky_block:lucky_block"}
            }
        },
        on_construct = function(pos)
            local meta = core.get_meta(pos)
            meta:set_string("infotext", Slb("Lucky Block").. " " ..S("TNT"))
        end,
        boom = function(pos, def, owner)
            removetnt(pos, def.radius, owner)
            add_effects(pos, def.radius, owner)
            for i = 1, 8 do
                core.after(i / 2, function()
                    pos.y = pos.y + 1
                    core.sound_play(modname.."_pop", {pos = pos, max_hear_distance = 64, gain = 2.0}, true)
                    lucky_block:open(pos, owner)
                end)
            end
        end
    })

    _G[modname].register_tnt({
        name = modname..":super_lucky_block",
        description = Slb("Super Lucky Block").. " " ..S("TNT"),
        radius = 2,
        light_source = 3,
        drops = {},
        tiles = texture(modname.."_super_lucky_block_background.png", modname.."_title.png"),
        craft = {
            recipe = {
                {"lucky_block:super_lucky_block", "lucky_block:super_lucky_block", "lucky_block:super_lucky_block"},
                {"lucky_block:super_lucky_block", "tnt:tnt", "lucky_block:super_lucky_block"},
                {"lucky_block:super_lucky_block", "lucky_block:super_lucky_block", "lucky_block:super_lucky_block"}
            }
        },
        on_construct = function(pos)
            local meta = core.get_meta(pos)
            meta:set_string("infotext", Slb("Super Lucky Block").. " " ..S("TNT"))
        end,
        boom = function(pos, def, owner)
            removetnt(pos, def.radius, owner)
            add_effects(pos, def.radius, owner)
            for i = 1, 8 do
                core.after(i / 2, function()
                    pos.y = pos.y + 1
                    core.sound_play(modname.."_pop", {pos = pos, max_hear_distance = 64, gain = 2.0}, true)
                    lucky_block:open(pos, owner, super_lucky_list)
                end)
            end
        end
    })
end

local basic_materials_items = {}

function string:startswith(start)
    return self:sub(1, #start) == start
end

core.register_on_mods_loaded(function()
    local i = 0
    for name, _ in pairs(core.registered_craftitems) do
        if name:startswith("basic_materials:") then
            basic_materials_items[i] = name
            i = i + 1
        end
    end
end)

_G[modname].register_tnt({
    name = modname..":technical",
    description = S("Technical TNT"),
    tiles = texture(modname.."_technical_background.png", modname.."_title.png"),
    craft = {
        recipe = {
            {"basic_materials:energy_crystal_simple", "basic_materials:ic", "basic_materials:energy_crystal_simple"},
            {modname..":multiply", "tnt:tnt", modname..":multiply"},
            {"basic_materials:gear_steel", modname..":multiply", "basic_materials:gear_steel"}
        }
    },
    sounds = default.node_sound_metal_defaults(),
    boom = function(pos, def, owner)
        local bnode = core.get_node(pos)
        local max = random(8, 40)
        for i = 0, max do
            local npos = table.copy(pos)
            npos.x = npos.x + randomFloat(-4, 4)
            npos.y = npos.y + randomFloat(16, 8)
            npos.z = npos.z + randomFloat(-4, 4)
            core.after(randomFloat(0.75, 1.5), function()
                if not core.is_protected(npos, owner) then
                    core.sound_play(modname.."_pop", {pos = npos})
                    core.add_item(npos, basic_materials_items[random(0, #basic_materials_items)])
                end
                if i == max then
                    core.remove_node(pos)
                    add_effects(pos, def.radius, owner)
                end
            end)
        end
    end
})

core.register_craftitem(modname..":unstable_particle", {
    description = S("Unstable Particle"),
    inventory_image = modname.."_unstable_particle.png"
})

if core.get_modpath("ethereal") then
    _G[modname].register_tnt({
        name = modname..":blackhole",
        description = S("Blackhole TNT"),
        tiles = texture("[multiply:#141414", modname.."_title.png"),
        craft = {
            recipe = {
                {"ethereal:etherium_dust", "ethereal:crystal_gilly_staff", "ethereal:etherium_dust"},
                {"ethereal:crystal_spike", "tnt:tnt", "ethereal:crystal_spike"},
                {"ethereal:etherium_dust", "ethereal:crystal_spike", "ethereal:etherium_dust"}
            }
        },
        radius = 12,
        ignite_timer = 10,
        on_ignite = function(pos, igniter)
            local duration = 9.75
            local interval = 0.05
            local radius = 32

            local function suck_step(time_passed)
                if time_passed >= duration then
                    return
                end

                local objects = core.get_objects_inside_radius(pos, radius)

                for _, obj in ipairs(objects) do
                    if obj:is_player() or obj:get_luaentity() then
                        local obj_pos = obj:get_pos()
                        if obj_pos then
                            local dx = pos.x - obj_pos.x
                            local dy = pos.y - obj_pos.y
                            local dz = pos.z - obj_pos.z

                            local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
                            if dist > 0 then
                                local strength = (radius - dist) * 0.25

                                obj:add_velocity({
                                    x = dx / dist * strength,
                                    y = dy / dist * strength,
                                    z = dz / dist * strength
                                })
                            end
                        end
                    end
                end

                core.after(interval, suck_step, time_passed + interval)
            end

            suck_step(0)
        end,
        boom = function(pos, def, owner)
            local radius = def.radius
            local objects = core.get_objects_inside_radius(pos, radius)
            for _, obj in ipairs(objects) do
                if obj:is_player() or obj:get_luaentity() then
                    local obj_pos = obj:get_pos()
                    if obj_pos then
                        local dx = obj_pos.x - pos.x
                        local dy = obj_pos.y - pos.y
                        local dz = obj_pos.z - pos.z

                        local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
                        if dist > 0 then
                            local strength = (radius - dist) * 4

                            obj:add_velocity({
                                x = (dx / dist * strength) * 2,
                                y = 6 + strength * 0.5,
                                z = (dz / dist * strength) * 2
                            })
                        end
                    end
                end
            end

            add_effects(pos, def.radius, owner)
            core.remove_node(pos)
            local sound = def.sound or "tnt_explode"
            core.sound_play(sound, {pos = pos, gain = 2.5,
                    max_hear_distance = math.min(def.radius * 20, 128)}, true)
        end
    })

    _G[modname].node_sound_glitch_defaults = function(tbl)
        tbl = tbl or {}
        tbl.footstep = tbl.footstep or
                {name = modname.."_glitch_footsteps", gain = 0.8}
        tbl.dug = tbl.dug or
                {name = modname.."_glitch_footsteps", gain = 1.0}
        default.node_sound_defaults(tbl)
        return tbl
    end

    local glitch_active_restores = 0
    local max_glitch_restores = 100
    
    local function restore_glitch(pos)
        local meta = core.get_meta(pos)
        if meta:get_int(modname..":restored") == 1 then return end
        meta:set_int(modname..":restored", 1)
        local raw = meta:get_string(modname..":replace_node")
        if raw and (not (raw == "")) then
            local data = core.parse_json(raw)
            if data["name"] then
                core.set_node(pos, data)
                return true
            else
                return false
            end
        else
            return false
        end
    end
    
    local function restore_chain(pos)
        if glitch_active_restores >= max_glitch_restores then
            return
        end
    
        for dz = -1, 1 do
            for dy = -1, 1 do
                for dx = -1, 1 do
                    local p = {
                        x = pos.x + dx,
                        y = pos.y + dy,
                        z = pos.z + dz
                    }
    
                    local node = core.get_node(p)
    
                    if node.name == modname..":glitch" then
                        if glitch_active_restores >= max_glitch_restores then
                            return
                        end
    
                        glitch_active_restores = glitch_active_restores + 1
                        core.after(1, function()
                            restore_glitch(p)
                            restore_chain(p)
                            glitch_active_restores = glitch_active_restores - 1
                        end)
                    end
                end
            end
        end
    end

    core.register_node(modname..":glitch", {
        tiles = {
            {
                name = modname.."_glitch_animated.png",
                animation = {
                    type = "vertical_frames",
                    aspect_w = 16,
                    aspect_h = 16,
                    length = 0.75
                }
            }
        },
        light_source = 1,
        sounds = _G[modname].node_sound_glitch_defaults(),
        description = S("Glitch Block"),
        groups = {cracky = 3},
        drops = {
            max_items = 1,
            items = {
                {
                    rarity = 4,
                    items = {modname..":unstable_particle"},
                }
            }
        },
        on_dig = function(pos)
            if restore_glitch(pos) then
                restore_chain(pos)
            else
                core.remove_node(pos)
            end
        end
    })

    core.register_craft({
        recipe = {
            {modname..":unstable_particle", modname..":unstable_particle"},
            {modname..":unstable_particle", modname..":unstable_particle"}
        },
        output = modname..":glitch 2"
    })

    core.register_craft({
        recipe = {
            {"ethereal:crystal_block", "default:mese", "ethereal:crystal_block"},
            {"default:mese", "bones:bones", "default:mese"},
            {"ethereal:crystal_block", "default:mese", "ethereal:crystal_block"}
        },
        output = modname..":unstable_particle 2"
    })

    local function glitch_explode(pos, radius, replace, player_name)
        local replace_id = core.CONTENT_AIR
        if replace and core.registered_nodes[replace] then
            replace_id = core.get_content_id(replace)
        end
        
        pos = vector.round(pos)
        local p1 = vector.subtract(pos, radius)
        local p2 = vector.add(pos, radius)
        local vm = VoxelManip()
        local minp, maxp = vm:read_from_map(p1, p2)
        local a = VoxelArea:new({MinEdge = minp, MaxEdge = maxp})
        local data = vm:get_data()

        data[a:index(pos.x, pos.y, pos.z)] = core.CONTENT_AIR

        for z = p1.z, p2.z do
            for y = p1.y, p2.y do
                for x = p1.x, p2.x do
                    local current_pos = vector.new(x, y, z)
                    if not core.is_protected(current_pos, player_name) then
                        local vi = a:index(x, y, z)
                        local cid = data[vi]
                        if cid ~= core.CONTENT_AIR and cid ~= core.CONTENT_IGNORE then
                            local old_pos = {x = x, y = y, z = z}
                            local is_empty = true
                            local inv = core.get_inventory({type="node", pos=old_pos})
                            if inv then
                                for listname, _ in pairs(inv:get_lists()) do
                                    if not inv:is_empty(listname) then
                                        is_empty = false
                                    end
                                end
                            end
                            if is_empty then
                                local old_node = core.get_node(old_pos)
                                data[vi] = replace_id
                                core.after(0, function()
                                    local meta = core.get_meta(old_pos)
                                    meta:from_table({
                                        fields = {
                                            [modname..":replace_node"] = core.write_json(old_node)
                                        }
                                    })
                                end)
                            end
                        end
                    end
                end
            end
        end

        vm:set_data(data)
        vm:write_to_map()
        vm:update_liquids()
        if vm.close then
            vm:close()
        end

        core.log("action", "Glitch explosion at " .. core.pos_to_string(pos) ..
                " with radius " .. radius .. " by player " .. player_name)
    end

    _G[modname].register_tnt({
        name = modname..":tnt_glitch",
        description = S("Glitch TNT"),
        tiles = texture(modname.."_glitch_background.png", modname.."_title.png"),
        craft = {
            recipe = {
                {modname..":unstable_particle", "basic_materials:energy_crystal_simple", modname..":unstable_particle"},
                {modname..":unstable_particle", "tnt:tnt", modname..":unstable_particle"},
                {modname..":unstable_particle", modname..":unstable_particle", modname..":unstable_particle"}
            }
        },
        radius = 6,
        sound = modname.."_glitch",
        boom = function(pos, def, owner)
            core.remove_node(pos)
            local sound = def.sound or "tnt_explode"
            core.sound_play(sound, {pos = pos, gain = 2.5,
                    max_hear_distance = math.min(def.radius * 20, 128)}, true)
            glitch_explode(pos, def.radius, modname..":glitch", owner:get_player_name())
        end
    })
end

_G[modname].register_tnt({
	name = modname..":tnt_poison",
	description = S("Poison TNT"),
    tiles = texture("[multiply:#00ff00", modname.."_poison_side_overlay.png"),
    craft = {
        recipe = {
            {"uraniumstuff:bucket_evil_goo", "uraniumstuff:bucket_evil_goo", "uraniumstuff:bucket_evil_goo"},
            {"uraniumstuff:bucket_evil_goo", "tnt:tnt", "uraniumstuff:bucket_evil_goo"},
            {"uraniumstuff:bucket_evil_goo", "uraniumstuff:bucket_evil_goo", "uraniumstuff:bucket_evil_goo"}
        }
    },
    boom = function(pos, def, owner)
        add_effects(pos, def.radius, owner)
        core.remove_node(pos)
        local sound = def.sound or "tnt_explode"
        core.sound_play(sound, {pos = pos, gain = 2.5,
                max_hear_distance = math.min(def.radius * 20, 128)}, true)
        scatter(pos, modname..":poison", 8, 48, owner:get_player_name())
    end
})

_G[modname].register_tnt({
	name = modname..":hurricane",
	description = S("Hurricane TNT"),
    tiles = texture("[multiply:#6e6e6e", modname.."_title.png"),
    craft = {
        recipe = {
            {"default:coalblock", "ethereal:etherium_dust", "default:coalblock"},
            {"ethereal:etherium_dust", "tnt:tnt", "ethereal:etherium_dust"},
            {"default:coalblock", "ethereal:etherium_dust", "default:coalblock"}
        }
    },
    radius = 14,
    ignite_timer = 15,
    on_ignite = function(pos, igniter)
        local radius = 14
        local duration = 14.75
        local interval = 0.05
        local angle = 0

        local function spawn_swirl(time_passed)
            if time_passed >= duration then return end

            for i = 1, 8 do
                local a = angle + (i * math.pi / 4)

                local x = pos.x + math.cos(a) * 5
                local z = pos.z + math.sin(a) * 5

                local p = {x = x, y = pos.y + (i - 0.5), z = z}

                core.add_particle({
                    pos = p,

                    velocity = {
                        x = -math.sin(a) * 8,
                        y = math.random() * 1.5,
                        z = math.cos(a) * 8
                    },

                    acceleration = {x = 0, y = 0.2, z = 0},

                    expirationtime = 0.5,
                    size = 10,

                    texture = modname.."_fog.png",
                    glow = 0
                })
            end

            angle = angle + 0.3

            core.after(interval, spawn_swirl, time_passed + interval)
        end

        spawn_swirl(0)

        local function swirl_step(time_passed)
            if time_passed >= duration then return end

            local objs = core.get_objects_inside_radius(pos, radius)

            for _, obj in ipairs(objs) do
                local p = obj:get_pos()
                if p then
                    local dir = vector.subtract(pos, p)
                    local dist = vector.length(dir)

                    if dist > 0.3 then
                        dir = vector.normalize(dir)

                        local tangent = {
                            x = -dir.z,
                            y = 0,
                            z = dir.x
                        }

                        local edge = (dist / radius) / 8
                        local pull = edge / 8
                        local spin = 1.25

                        if dist > radius * 0.85 then
                            obj:set_velocity({
                                x = dir.x * 20,
                                y = 2,
                                z = dir.z * 20
                            })
                        else
                            obj:add_velocity({
                                x = tangent.x * spin + dir.x * pull,
                                z = tangent.z * spin + dir.z * pull,
                                y = 1.2 + edge * 1.5
                            })
                        end
                    end
                end
            end

            core.after(interval, swirl_step, time_passed + interval)
        end

        swirl_step(0)
    end,
    boom = function(pos, def, owner)
        local radius = def.radius
        local objects = core.get_objects_inside_radius(pos, radius)
        for _, obj in ipairs(objects) do
            if obj:is_player() or obj:get_luaentity() then
                local obj_pos = obj:get_pos()
                if obj_pos then
                    local dx = obj_pos.x - pos.x
                    local dy = obj_pos.y - pos.y
                    local dz = obj_pos.z - pos.z

                    local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
                    if dist > 0 then
                        local strength = (radius - dist) * 4

                        obj:add_velocity({
                            x = (dx / dist * strength) * 2,
                            y = 6 + strength * 0.5,
                            z = (dz / dist * strength) * 2
                        })
                    end
                end
            end
        end
        add_effects(pos, def.radius, owner)
        core.remove_node(pos)
        local sound = def.sound or "tnt_explode"
        core.sound_play(sound, {pos = pos, gain = 2.5,
                max_hear_distance = math.min(def.radius * 20, 128)}, true)
    end
})

local function get_nearest_player(pos, exclude_name)
    local nearest = nil
    local nearest_dist = math.huge

    for _, player in ipairs(core.get_connected_players()) do
        local name = player:get_player_name()

        if name ~= exclude_name then
            local p = player:get_pos()
            if p then
                local dist = vector.distance(pos, p)

                if dist < nearest_dist then
                    nearest_dist = dist
                    nearest = player
                end
            end
        end
    end

    return nearest
end

local function restore(pos, def)
    core.set_node(pos, {type="node", name=modname .. ":" .. def.name})
end

_G[modname].register_tnt({
	name = modname..":switch",
	description = S("Switch TNT"),
    tiles = texture(modname.."_switch_background.png", modname.."_switch_side_overlay.png"),
    craft = {
        recipe = {
            {"wool:red", "default:obsidian", "wool:blue"},
            {"wool:red", "tnt:tnt", "wool:blue"},
            {"wool:red", "default:obsidian", "wool:blue"}
        }
    },
    boom = function(pos, def, owner)
        local meta = core.get_meta(pos)
        local placer_name = meta:get_string("owner2")

        if placer_name == "" then restore(pos, def); return end

        local igniter_name = owner:get_player_name()

        local player1 = nil
        local player2 = nil

        if placer_name == igniter_name then
            local nearest = nil
            local nearest_dist = math.huge

            local nearest = get_nearest_player(pos, igniter_name)
            if not nearest then restore(pos, def); return end

            player1 = owner
            player2 = nearest

        else
            local placer = core.get_player_by_name(placer_name)

            if not placer then restore(pos, def); return end

            player1 = owner
            player2 = placer
        end

        local pos1 = player1:get_pos()
        local pos2 = player2:get_pos()

        if pos1 and pos2 then
            player1:set_pos(pos2)
            player2:set_pos(pos1)
        end

        add_effects(pos, def.radius, owner)
        core.remove_node(pos)
        local sound = def.sound or "tnt_explode"
        core.sound_play(sound, {
            pos = pos,
            gain = 2.5,
            max_hear_distance = math.min(def.radius * 20, 128)
        }, true)
    end
})

_G[modname].register_tnt({
    name = modname..":chaos",
    description = S("Chaos TNT"),
    tiles = texture("[multiply:#ff4400", modname.."_title.png"),
    craft = {
        recipe = {
            {"tnt:tnt", "tnt:tnt", "tnt:tnt"},
            {"tnt:tnt", modname..":multiply", "tnt:tnt"},
            {"tnt:tnt", "tnt:tnt", "tnt:tnt"}
        }
    },
    boom = function(pos, def, owner)
        local owner_name = owner:get_player_name()
        local count = random(6, 10)
        for i = 1, count do
            core.after(i - 1, function()
                local launch_pos = {
                    x = pos.x,
                    y = pos.y + 1,
                    z = pos.z
                }

                if core.is_protected(launch_pos, owner_name) then return end

                core.set_node(launch_pos, {name = "tnt:tnt"})
                local meta = core.get_meta(launch_pos)
                meta:set_string("owner",  owner_name)
                meta:set_string("owner2", owner_name)

                core.swap_node(launch_pos, {name = "tnt:tnt_burning"})

                local _, obj = core.spawn_falling_node(launch_pos)

                if obj and obj:is_valid() then
                    local sign_x = (random(0, 1) == 0) and 1 or -1
                    local sign_z = (random(0, 1) == 0) and 1 or -1

                    local epos = table.copy(pos)
                    epos.y = epos.y + 1
                    add_effects(epos, def.radius, owner, false)
                    core.sound_play("tnt_explode", {pos = epos, gain = 2.5, max_hear_distance = math.min(def.radius * 20, 128)}, true)

                    obj:set_velocity({
                        x = sign_x * randomFloat(3, 6),
                        y = randomFloat(12, 20),
                        z = sign_z * randomFloat(3, 6)
                    })
                end

                if i == count then
                    core.after(1, function()
                        removetnt(pos, def.radius, owner)
                        tnt.boom(pos, def)
                    end)
                end
            end)
        end
    end
})

_G[modname].register_tnt({
	name = modname..":fake",
	description = S("Fake TNT"),
    tiles = texture("[multiply:#fc3838", modname.."_fake_side_overlay.png"),
    craft = {
        type = "shapeless",
        recipe = {
            "default:gold_ingot",
            "tnt:tnt",
            "default:steel_ingot",
            "default:diamondblock"
        }
    },
    boom = function(pos, def, owner)
        if not core.is_protected(pos, owner:get_player_name()) then
            core.remove_node(pos)
            add_effects(pos, def.radius, owner)
            core.sound_play("tnt_explode", {pos = pos, gain = 2.5, max_hear_distance = 128}, true)
            core.add_item(pos, modname..":fake")
        else
            core.remove_node(pos)
        end
    end
})

register_fakenode("meselamp")
register_fakenode("sandstonebrick")
register_fakenode("sandstone_block")

_G[modname].register_tnt({
    name = modname..":labyrinth",
    description = S("Labyrinth TNT"),
    tiles = texture("[multiply:#8f741d", modname.."_title.png"),
    craft = {
        recipe = {
            {"default:sandstonebrick", modname..":unstable_particle", "default:sandstonebrick"},
            {modname..":unstable_particle", "tnt:tnt", modname..":unstable_particle"},
            {"default:sandstonebrick", modname..":unstable_particle", "default:sandstonebrick"}
        }
    },
    boom = function(pos, def, owner)
        local owner_name = owner:get_player_name()
        local ppos = owner:get_pos()

        local SIZE = 19
        local WALL_H = 3
        local half = math.floor(SIZE / 2)

        local ox = math.floor(ppos.x) - half
        local oy = math.floor(ppos.y)
        local oz = math.floor(ppos.z) - half

        local grid = {}
        for i = 0, SIZE * SIZE - 1 do
            grid[i] = true
        end

        local function gidx(x, z)
            return math.floor(z) * SIZE + math.floor(x)
        end

        grid[gidx(1, 1)] = false
        local stack = {{1, 1}}

        while #stack > 0 do
            local top = stack[#stack]
            local cx, cz = top[1], top[2]
            local dirs = {{2,0},{-2,0},{0,2},{0,-2}}
            for i = 4, 2, -1 do
                local j = random(1, i)
                dirs[i], dirs[j] = dirs[j], dirs[i]
            end

            local found = false
            for _, d in ipairs(dirs) do
                local nx = cx + d[1]
                local nz = cz + d[2]
                if nx >= 1 and nx < SIZE and nz >= 1 and nz < SIZE
                   and grid[gidx(nx, nz)] then

                    grid[gidx((cx + nx) / 2, (cz + nz) / 2)] = false
                    grid[gidx(nx, nz)] = false

                    table.insert(stack, {nx, nz})
                    found = true
                    break
                end
            end

            if not found then
                table.remove(stack)
            end
        end

        local p1 = {x = ox, y = oy - 1, z = oz}
        local p2 = {x = ox + SIZE-1, y = oy + WALL_H - 1, z = oz + SIZE-1}

        local vm = VoxelManip()
        local minp, maxp = vm:read_from_map(p1, p2)
        local va = VoxelArea:new({MinEdge = minp, MaxEdge = maxp})
        local data = vm:get_data()

        local c_cobble = core.get_content_id(modname..":fake_sandstonebrick")
        local c_stone = core.get_content_id(modname..":fake_sandstone_block")
        local c_air = core.CONTENT_AIR
        local c_ignore = core.CONTENT_IGNORE

        for gz = 0, SIZE - 1 do
            for gx = 0, SIZE - 1 do
                local wx = ox + gx
                local wz = oz + gz
                local is_wall = grid[gidx(gx, gz)]

                local fi = va:index(wx, oy - 1, wz)
                if data[fi] ~= c_ignore then
                    data[fi] = c_stone
                end

                for h = 0, WALL_H - 1 do
                    local wi = va:index(wx, oy + h, wz)
                    if data[wi] ~= c_ignore then
                        data[wi] = is_wall and c_cobble or c_air
                    end
                end
            end
        end

        vm:set_data(data)
        vm:write_to_map()
        vm:update_liquids()
        if vm.close then vm:close() end

        for gz = 1, SIZE - 2, 2 do
            for gx = 1, SIZE - 2, 2 do
                if not grid[gidx(gx, gz)] and random(1, 4) == 1 then
                    local lpos = {x = ox + gx, y = oy + WALL_H - 1, z = oz + gz}
                    if not core.is_protected(lpos, owner_name) then
                        core.set_node(lpos, {name = modname..":fake_meselamp"})
                    end
                end
            end
        end

        owner:set_pos({
            x = ox + 1,
            y = oy,
            z = oz + 1
        })

        add_effects(pos, def.radius, owner)
        core.remove_node(pos)
        core.sound_play("tnt_explode", {
            pos = pos,
            gain = 2.5,
            max_hear_distance = math.min(def.radius * 20, 128)
        }, true)
    end
})

_G[modname].register_tnt({
    name = modname..":time",
    description = S("Long TNT"),
    tiles = texture("[multiply:#1d3d61", modname.."_time_side_overlay.png"),
    ignite_timer = 60,
    craft = {
        recipe = {
            {"ethereal:crystal_ingot", "basic_materials:ic", "ethereal:crystal_ingot"},
            {"basic_materials:plastic_sheet", "tnt:tnt", "basic_materials:plastic_sheet"},
            {"ethereal:crystal_ingot", "basic_materials:steel_wire", "ethereal:crystal_ingot"}
        }
    },
    boom = tnt.boom
})

register_fakenode("sandstone")

_G[modname].register_tnt({
    name = modname..":pyramid",
    description = S("Pyramid TNT"),
    tiles = texture("[multiply:#c8a020", modname.."_title.png"),
    craft = {
        recipe = {
            {"default:sandstone", "default:sandstone", "default:sandstone"},
            {"default:sandstone", "tnt:tnt", "default:sandstone"},
            {"default:sandstone", "default:sandstone", "default:sandstone"}
        }
    },
    boom = function(pos, def, owner)
        local owner_name = owner:get_player_name()

        local BASE = 9

        local half = math.floor(BASE / 2)
        local ox = math.floor(pos.x) - half
        local oy = math.floor(pos.y)
        local oz = math.floor(pos.z) - half

        local floors = math.ceil(BASE / 2)

        local p1 = {x = ox, y = oy - 1, z = oz}
        local p2 = {x = ox + BASE - 1, y = oy + floors, z = oz + BASE - 1}

        local vm = VoxelManip()
        local minp, maxp = vm:read_from_map(p1, p2)
        local va = VoxelArea:new({MinEdge = minp, MaxEdge = maxp})
        local data = vm:get_data()

        local c_block = core.get_content_id(modname..":fake_sandstone")
        local c_air = core.CONTENT_AIR
        local c_ignore = core.CONTENT_IGNORE

        for k = 0, floors - 1 do
            local side = BASE - k * 2
            if side <= 0 then break end

            local lox = ox + k
            local loz = oz + k
            local ly = oy + k
            local lox2 = lox + side - 1
            local loz2 = loz + side - 1

            local is_top = (side <= 3)
            for z = loz, loz2 do
                for x = lox, lox2 do
                    local on_edge = (x == lox or x == lox2 or z == loz or z == loz2)
                    if on_edge or is_top then
                        local vi = va:index(x, ly, z)
                        if data[vi] == c_air or data[vi] == c_ignore then
                            data[vi] = c_block
                        end
                    end
                end
            end
        end

        vm:set_data(data)
        vm:write_to_map()
        vm:update_liquids()
        if vm.close then vm:close() end

        local entrance = {
            x = ox + half + 0.5,
            y = oy,
            z = oz - 1
        }

        add_effects(pos, def.radius, owner)
        core.remove_node(pos)
        core.sound_play("tnt_explode", {
            pos = pos,
            gain = 2.5,
            max_hear_distance = math.min(def.radius * 20, 128)
        }, true)
    end
})

_G[modname].register_tnt({
    name = modname..":x_two",
    description = Stnt("TNT") .. " x4",
    tiles = texture("[multiply:#540000", modname.."_title.png"),
    radius = 6,
    craft = {
        recipe = {
            {"tnt:tnt", "tnt:tnt", "tnt:tnt"},
            {"tnt:tnt", "tnt:tnt", "tnt:tnt"},
            {"tnt:tnt", "tnt:tnt", "tnt:tnt"}
        }
    },
    boom = tnt.boom
})

_G[modname].register_tnt({
    name = modname..":x_sixteen",
    description = Stnt("TNT") .. " x16",
    tiles = texture("[multiply:#bd2d99", modname.."_title.png"),
    radius = 12,
    craft = {
        recipe = {
            {modname..":x_two", modname..":x_two", modname..":x_two"},
            {modname..":x_two", modname..":x_two", modname..":x_two"},
            {modname..":x_two", modname..":x_two", modname..":x_two"}
        }
    },
    boom = tnt.boom
})

_G[modname].register_tnt({
    name = modname..":x_fifty",
    description = Stnt("TNT") .. " x50",
    tiles = texture("[multiply:#2dbd8f", modname.."_title.png"),
    radius = 18,
    craft = {
        recipe = {
            {modname..":x_sixteen", modname..":x_sixteen", modname..":x_sixteen"},
            {modname..":x_sixteen", modname..":x_sixteen", modname..":x_sixteen"},
            {modname..":x_sixteen", modname..":x_sixteen", modname..":x_sixteen"}
        }
    },
    boom = tnt.boom
})

_G[modname].register_tnt({
    name = modname..":x_hundred",
    description = Stnt("TNT") .. " x100",
    tiles = texture("[multiply:#612e1d", modname.."_title.png"),
    radius = 24,
    craft = {
        recipe = {
            {modname..":x_fifty", modname..":x_fifty", modname..":x_fifty"},
            {modname..":x_fifty", modname..":x_fifty", modname..":x_fifty"},
            {modname..":x_fifty", modname..":x_fifty", modname..":x_fifty"}
        }
    },
    boom = tnt.boom
})

_G[modname].register_tnt({
    name = modname..":x_five_hundred",
    description = Stnt("TNT") .. " x500",
    tiles = texture("[multiply:#252616", modname.."_title.png"),
    radius = 32,
    craft = {
        recipe = {
            {modname..":x_hundred", modname..":x_hundred", modname..":x_hundred"},
            {modname..":x_hundred", modname..":x_hundred", modname..":x_hundred"},
            {modname..":x_hundred", modname..":x_hundred", modname..":x_hundred"}
        }
    },
    boom = tnt.boom
})

_G[modname].register_tnt({
    name = modname..":x_thousand",
    description = Stnt("TNT") .. " x1000",
    tiles = texture("[multiply:#10101a", modname.."_title.png"),
    radius = 40,
    craft = {
        recipe = {
            {modname..":x_five_hundred", modname..":x_five_hundred", modname..":x_five_hundred"},
            {modname..":x_five_hundred", modname..":x_five_hundred", modname..":x_five_hundred"},
            {modname..":x_five_hundred", modname..":x_five_hundred", modname..":x_five_hundred"}
        }
    },
    boom = tnt.boom
})

register_fakenode("stone")

_G[modname].register_tnt({
    name = modname..":trap",
    description = S("Trap TNT"),
    tiles = texture("[multiply:#a32607", modname.."_trap_side_overlay.png"),
    craft = {
        recipe = {
            {"default:stone", "mobs:lava_orb", "default:stone"},
            {"default:stone", "tnt:tnt", "default:stone"},
            {"default:stone", "bucket:bucket_lava", "default:stone"}
        }
    },
    boom = function(pos, def, owner)
        local owner_name = owner:get_player_name()

        local trapped = get_nearest_player(pos, owner_name)
        if not trapped then restore(pos, def); return end

        local DEPTH = 60
        local LAVA_FROM  = 58
        local PIT_RADIUS = 1
        local WALL_EXTRA = 1

        local p1 = {
            x = pos.x - PIT_RADIUS - WALL_EXTRA,
            y = pos.y - DEPTH,
            z = pos.z - PIT_RADIUS - WALL_EXTRA
        }
        local p2 = {
            x = pos.x + PIT_RADIUS + WALL_EXTRA,
            y = pos.y + 1,
            z = pos.z + PIT_RADIUS + WALL_EXTRA
        }

        local vm = VoxelManip()
        local minp, maxp = vm:read_from_map(p1, p2)
        local va = VoxelArea:new({MinEdge = minp, MaxEdge = maxp})
        local data = vm:get_data()

        local c_stone = core.get_content_id(modname..":fake_stone")
        local c_lava = core.get_content_id("default:lava_source")
        local c_air = core.CONTENT_AIR
        local c_ignore = core.CONTENT_IGNORE

        local pr = math.floor(PIT_RADIUS)
        local wr = math.floor(PIT_RADIUS + WALL_EXTRA)

        for dy = 0, DEPTH do
            local y = math.floor(pos.y) - dy
            for dz = -wr, wr do
                for dx = -wr, wr do
                    local x = math.floor(pos.x) + dx
                    local z = math.floor(pos.z) + dz
                    local vi = va:index(x, y, z)
                    if data[vi] == c_ignore then goto continue end

                    local in_pit = (dx >= -pr and dx <= pr and dz >= -pr and dz <= pr)
                    local is_wall = not in_pit

                    if is_wall then
                        if not core.is_protected({x=x,y=y,z=z}, owner_name) then
                            data[vi] = c_stone
                        end
                    else
                        if dy >= LAVA_FROM then
                            data[vi] = c_lava
                        else
                            data[vi] = c_air
                        end
                    end

                    ::continue::
                end
            end
        end

        vm:set_data(data)
        vm:write_to_map()
        vm:update_liquids()
        if vm.close then vm:close() end
        trapped:set_pos(pos)

        add_effects(pos, def.radius, owner)
        core.remove_node(pos)
        core.sound_play("tnt_explode", {
            pos = pos,
            gain = 2.5,
            max_hear_distance = math.min(def.radius * 20, 128)
        }, true)
    end
})

_G[modname].register_tnt({
    name = modname..":square",
    description = S("Cube TNT"),
    tiles = texture("[multiply:#a498f5", modname.."_title.png"),
    no_fire = true,
    craft = {
        recipe = {
            {"default:mese_crystal", "default:steel_ingot", "default:mese_crystal"},
            {"default:steelblock", "tnt:tnt", "default:steelblock"},
            {"default:mese_crystal", "default:steel_ingot", "default:mese_crystal"}
        }
    },
    boom = function(pos, def, owner)
        _G[modname].square_explode(pos, def.radius, nil, owner:get_player_name())

        add_effects(pos, def.radius, owner)
        core.sound_play("tnt_explode", {
            pos = pos,
            gain = 2.5,
            max_hear_distance = math.min(def.radius * 20, 128)
        }, true)
    end
})

_G[modname].register_tnt({
	name = modname..":water",
	description = S("Water TNT"),
	waving = 3,
    tiles = {
        top = {
            name = modname.."_water_top.png",
            animation = {
                type = "vertical_frames",
                aspect_w = 16,
                aspect_h = 16,
                length = 2,
            }
        },
        bottom = {
            name = "default_water_source_animated.png",
            animation = {
                type = "vertical_frames",
                aspect_w = 16,
                aspect_h = 16,
                length = 2,
            }
        },
        side = {
            name = modname.."_water_side.png",
            animation = {
                type = "vertical_frames",
                aspect_w = 16,
                aspect_h = 16,
                length = 2,
            }
        },
        burning = {
            name = modname.."_water_burning.png",
            animation = {
                type = "vertical_frames",
                aspect_w = 16,
                aspect_h = 16,
                length = 2,
            }
        }
    },
    craft = {
        recipe = {
            {"bucket:bucket_water", "bucket:bucket_water", "bucket:bucket_water"},
            {"bucket:bucket_water", "tnt:tnt", "bucket:bucket_water"},
            {"bucket:bucket_water", "bucket:bucket_water", "bucket:bucket_water"}
        }
    },
	post_effect_color = {a = 103, r = 30, g = 60, b = 90},
	is_ground_content = false,
	drawtype = "liquid",
	sounds = default.node_sound_water_defaults(),
	use_texture_alpha = "blend",
	paramtype = "light",
    radius = 2,
    boom = function(pos, def, owner)
        add_effects(pos, def.radius, owner)
        core.remove_node(pos)
        _G[modname].circular_explode(pos, def.radius, nil, "default:water_source", owner:get_player_name())
        local sound = def.sound or "tnt_explode"
        core.sound_play(sound, {pos = pos, gain = 2.5,
                max_hear_distance = math.min(def.radius * 20, 128)}, true)
    end
}, true)

_G[modname].register_tnt({
	name = modname..":wash",
	description = S("Wash TNT"),
    tiles = texture_top(modname.."_wash_background.png", modname.."_title.png", modname.."_wash_top_background.png"),
    craft = {
        recipe = {
            {"bucket:bucket_river", "bucket:bucket_river", "bucket:bucket_river"},
            {"bucket:bucket_river", "tnt:tnt", "bucket:bucket_river"},
            {"bucket:bucket_river", "bucket:bucket_river", "bucket:bucket_river"}
        }
    },
    boom = function(pos, def, owner)
        add_effects(pos, def.radius, owner)
        core.remove_node(pos)
        local sound = def.sound or "tnt_explode"
        _G[modname].circular_explode(pos, def.radius, nil, "default:river_water_source", owner:get_player_name())
        core.sound_play(sound, {pos = pos, gain = 2.5,
                max_hear_distance = math.min(def.radius * 20, 128)}, true)
    end
})

if core.get_modpath("xdecor") and
        core.get_modpath("stairs") and
        core.get_modpath("decor_api") and
        core.get_modpath("building_blocks") and
        core.get_modpath("homedecor_common") and
        core.get_modpath("laptop") and
        core.get_modpath("doors") then
    _G[modname].register_tnt({
        name = modname..":house",
        description = S("Super House TNT"),
        tiles = texture("default_diamond_block.png", modname.."_house_overlay.png"),
        craft = {
            recipe = {
                {modname..":super_diamondblock", modname..":super_diamondblock", modname..":super_diamondblock"},
                {modname..":super_diamondblock", modname..":brick", modname..":super_diamondblock"},
                {modname..":super_diamondblock", modname..":super_diamondblock", modname..":super_diamondblock"}
            }
        },
        boom = function(pos, def, owner)
            local name = "default:dirt_with_grass"

            local above_pos = table.copy(pos)
            above_pos.y = above_pos.y + 1

            local below_pos = table.copy(pos)
            below_pos.y = below_pos.y - 1
            local below_node = core.get_node(below_pos)

            local stone = nil
            if (below_node.name ~= name) and (string.find(below_node.name, ":dirt") or string.find(below_node.name, "_dirt")) or ((string.find(below_node.name, ":stone") or string.find(below_node.name, ":cobble")) and not string.find(below_node.name, ":stone_with_")) then
                name = below_node.name
                if string.find(below_node.name, "mossycobble") then
                    stone = "default:cobble"
                else
                    stone = below_node.name
                end
            end

            core.remove_node(pos)
            add_effects(pos, def.radius, owner)
            local sound = def.sound or "tnt_explode"
            core.sound_play(sound, {pos = pos, gain = 2.5,
                    max_hear_distance = math.min(def.radius * 20, 128)}, true)
            pos.y = pos.y - 7

            local house_path = modpath.."/schematics/supah_fuckass_house.mts"
            core.place_schematic(pos, house_path, "0", {}, true, {})

            local schematic = core.read_schematic(house_path, {})
            local size = schematic.size
            for x = 0, size.x - 1 do
                for y = 0, size.y - 1 do
                    for z = 0, size.z - 1 do
                        local npos = {
                            x = pos.x + x,
                            y = pos.y + y,
                            z = pos.z + z,
                        }
                        local node = core.get_node(npos)
                        local cnode = table.copy(node)
                        if stone and ((node.name == "default:dirt_with_grass" or node.name == "default:dirt") and cnode.name ~= stone) or
                                (node.name == "default:dirt_with_grass" and cnode.name ~= name) then
                            cnode.name = stone or name
                            core.set_node(npos, cnode)
                        end
                        if node and node.name ~= "air" and node.name ~= "ignore" then
                            local ndef = core.registered_nodes[node.name]
                            if ndef then
                                if ndef.on_construct then
                                    ndef.on_construct(npos)
                                end
                                if ndef.after_place_node and not string.find(node.name, "bed") then
                                    ndef.after_place_node(npos, owner, ItemStack(modname..":"..def.name), {type="node", under=below_pos, above=above_pos})
                                end
                            end
                        end
                    end
                end
            end
        end
    })
end

if core.get_modpath("mesecons") then
    _G[modname].register_tnt({
        name = modname..":piston_door",
        description = S("Piston Door TNT"),
        tiles = texture("jeija_microcontroller_sides.png", modname.."_title.png"),
        craft = {
            recipe = {
                {"mesecons_pistons:piston_sticky_off", "mesecons_walllever:wall_lever_off", "mesecons_pistons:piston_sticky_off"},
                {"mesecons_delayer:delayer_off_1", "tnt:tnt", "mesecons_delayer:delayer_off_1"},
                {"mesecons_pistons:piston_sticky_off", "mesecons:wire_00000000_off", "mesecons_pistons:piston_sticky_off"}
            }
        },
        boom = function(pos, def, owner)
            core.remove_node(pos)
            add_effects(pos, def.radius, owner)
            local sound = def.sound or "tnt_explode"
            core.sound_play(sound, {pos = pos, gain = 2.5,
                    max_hear_distance = math.min(def.radius * 20, 128)}, true)
            pos.y = pos.y - 2
            core.place_schematic(pos, modpath.."/schematics/2_by_2_piston_door.mts", "0", {}, true)
        end
    })

    core.register_craft({
        output = modname..":tnt_remote",
        recipe = {
            {"mesecons:wire_00000000_off", "mesecons:wire_00000000_off", "mesecons:wire_00000000_off"},
            {"mesecons:wire_00000000_off", "tnt:tnt", "mesecons:wire_00000000_off"},
            {"mesecons:wire_00000000_off", "mesecons:wire_00000000_off", "mesecons:wire_00000000_off"}
        }
    })

    if core.get_modpath("dye") then
        core.register_craft({
            type = "shapeless",
            output = modname..":remote",
            recipe = {
                "mesecons_fpga:programmer",
                "mesecons_button:button_off",
                "mesecons:wire_00000000_off",
                "mesecons:wire_00000000_off",
                "default:steel_ingot",
                "default:steel_ingot",
                "dye:red"
            }
        })
    end
end

local remote_tnt = texture("[multiply:#450e0e", modname.."_remote_side_overlay.png")
core.register_node(modname..":tnt_remote", {
    description = S("Remote TNT"),
    tiles = {remote_tnt.top, remote_tnt.bottom, remote_tnt.side},
    groups = {dig_immediate = 2, tnt = 1},
    sounds = default.node_sound_wood_defaults(),
    on_blast = function(pos)
        core.after(0.1, function()
            tnt.boom(pos)
        end)
    end
})

local remotemeta = modname.."_pos"

core.register_craftitem(modname..":remote", {
    description = S("Remote"),
    stack_max = 1,
    inventory_image = modname.."_remote.png",
    on_use = function(itemstack, user, pointed_thing)
        local pname = user:get_player_name()
        local meta = itemstack:get_meta()
        local pos = meta:get_string(remotemeta)

        local ppos = core.get_pointed_thing_position(pointed_thing)
        if ppos ~= nil then
            local pnode = core.get_node(ppos)
            if pnode.name == modname..":tnt_remote" then
                if pos ~= nil and pos ~= "" then
                    meta:set_string(remotemeta, "")
                    meta:set_string("description", S("Remote"))
                else
                    local str = vector.to_string(ppos)
                    meta:set_string(remotemeta, str)
                    meta:set_string("description", S("Remote").." "..str)
                end
                return itemstack
            end
        end

        if pos ~= nil and pos ~= "" then
            pos = vector.from_string(pos)
            if core.get_node(pos).name == modname..":tnt_remote" then
                local nmeta = core.get_meta(pos)
                nmeta:set_string("owner", pname)
                meta:set_string(remotemeta, "")
                meta:set_string("description", S("Remote"))
                core.sound_play(modname.."_spark", {to_player = pname})
                tnt.boom(pos, {radius = 4})
            end
        end

        return itemstack
    end
})

_G[modname].register_tnt({
    name = modname..":teleport",
    description = S("Teleport TNT"),
    tiles = texture("[multiply:#915966", modname.."_title.png"),
    craft = {
        recipe = {
            {"basic_materials:energy_crystal_simple", modname..":unstable_particle", "basic_materials:energy_crystal_simple"},
            {modname..":unstable_particle", "tnt:tnt", modname..":unstable_particle"},
            {"basic_materials:energy_crystal_simple", modname..":unstable_particle", "basic_materials:energy_crystal_simple"}
        }
    },
    boom = function(pos, def, owner)
        local owner_name = owner:get_player_name()

        local trapped = get_nearest_player(pos, owner_name)
        if not trapped then restore(pos, def); return end
        
        add_effects(pos, def.radius, owner)
        removetnt(pos, def.radius, owner)
        local sound = def.sound or "tnt_explode"
        core.sound_play(sound, {pos = pos, gain = 2.5,
                max_hear_distance = math.min(def.radius * 20, 128)}, true)
        
        local tp = table.copy(pos)
        tp.y = tp.y + 10000
        trapped:set_pos(tp)
    end
})

_G[modname].register_tnt({
    name = modname..":random_teleport",
    description = S("Random Teleport TNT"),
    tiles = texture("[multiply:#b595b8", modname.."_title.png"),
    craft = {
        recipe = {
            {"default:mese_crystal", modname..":unstable_particle", "default:mese_crystal"},
            {modname..":unstable_particle", "too_many_tnt:teleport", modname..":unstable_particle"},
            {"default:mese_crystal", modname..":unstable_particle", "default:mese_crystal"}
        }
    },
    boom = function(pos, def, owner)
        local owner_name = owner:get_player_name()

        local limit = core.get_mapgen_setting("mapgen_limit")
        local x = random(-30000, 30000)

        local trapped = get_nearest_player(pos, owner_name)
        if not trapped then restore(pos, def); return end
        
        add_effects(pos, def.radius, owner)
        removetnt(pos, def.radius, owner)
        local sound = def.sound or "tnt_explode"
        core.sound_play(sound, {pos = pos, gain = 2.5,
                max_hear_distance = math.min(def.radius * 20, 128)}, true)
        
        local tp = table.copy(pos)
        trapped:set_pos(tp)
    end
})

_G[modname].register_tnt({
    name = modname..":flip",
    description = S("Reverse TNT"),
    tiles = texture("[multiply:#4a9e6b", modname.."_title.png^[transformFY"),
    flip = true,
    craft = {
        recipe = {
            {"default:gravel", "default:diamond", "default:gravel"},
            {"default:mossycobble", "tnt:tnt", "default:mossycobble"},
            {"default:gravel", "default:diamond", "default:gravel"}
        }
    },
    radius = 5,
    boom = function(pos, def, owner)
        add_effects(pos, def.radius, owner)
        core.remove_node(pos)

        local sound = def.sound or "tnt_explode"
        core.sound_play(sound, {
            pos = pos, gain = 2.5,
            max_hear_distance = math.min(def.radius * 20, 128)
        }, true)

        local r = def.radius
        for dx = -r, r do
            for dz = -r, r do
                if dx*dx + dz*dz <= r*r then
                    local col = {}
                    local cx = pos.x + dx
                    local cz = pos.z + dz

                    for dy = -r, r do
                        local p = {x = cx, y = pos.y + dy, z = cz}
                        local node = core.get_node(p)
                        table.insert(col, node)
                    end

                    local len = #col
                    for dy = -r, r do
                        local p = {x = cx, y = pos.y + dy, z = cz}
                        local flipped = col[len - (dy + r)]
                        if flipped then
                            core.set_node(p, flipped)
                            core.check_for_falling(p)
                        end
                    end
                end
            end
        end
    end
})

_G[modname].register_tnt({
    name = modname..":fire",
    description = S("Fire TNT"),
    tiles = texture("[multiply:#ff8800", modname.."_title.png"),
    craft = {
        recipe = {
            {"fire:flint_and_steel", "fire:flint_and_steel", "fire:flint_and_steel"},
            {"fire:flint_and_steel", "tnt:tnt", "fire:flint_and_steel"},
            {"fire:flint_and_steel", "fire:flint_and_steel", "fire:flint_and_steel"}
        }
    },
    radius = 5,
    boom = function(pos, def, owner)
        core.remove_node(pos)
        add_effects(pos, def.radius, owner)
        _G[modname].circular_explode(pos, def.radius, nil, "fire:basic_flame", owner:get_player_name())
        local sound = def.sound or "tnt_explode"
        core.sound_play(sound, {pos = pos, gain = 2.5,
                max_hear_distance = math.min(def.radius * 20, 128)}, true)
    end
})

local disallowed_nodes = {
    "tnt",
    "grass",
    "mesecons",
    "stone_with_",
    "stair",
    "_cube",
    "_open",
    "micropanel",
    "farming",
    "leaves",
    "door",
    "decor_api",
    "modern",
    "_flowing",
    "mineral_",
    "multidecor"
}

local function check_node(name)
    for _, find in pairs(disallowed_nodes) do
        if string.find(name, find) then
            return false
        end
    end
    return true
end

local function nodes()
    local registered = {}
    for name, def in pairs(core.registered_nodes) do
        if def.groups["not_in_creative_inventory"] ~= 1 and not (def.drawtype == "airlike" or def.air_equivalent) and check_node(def.name) then
            def.name = name
            table.insert(registered, def)
        end
    end
    return registered
end

local function items()
    local registered = {}
    for name, d in pairs(core.registered_craftitems) do
        if d.groups["not_in_creative_inventory"] ~= 1 then
            table.insert(registered, name)
        end
    end
    return registered
end

if core.get_modpath("gloopblocks") then
    local nodes = nodes()
    if #nodes ~= 0 then
        _G[modname].register_tnt({
            name = modname..":random",
            description = S("Random TNT"),
            tiles = texture(modname.."_random_background.png", modname.."_title.png"),
            craft = {
                recipe = {
                    {modname..":glitch_block", "gloopblocks:rainbow_block_horizontal", modname..":glitch_block"},
                    {"gloopblocks:rainbow_block_horizontal", "tnt:tnt", "gloopblocks:rainbow_block_horizontal"},
                    {modname..":glitch_block", "gloopblocks:rainbow_block_horizontal", modname..":glitch_block"}
                }
            },
            radius = 2,
            boom = function(pos, def, owner)
                add_effects(pos, def.radius, owner)
                core.remove_node(pos)
                local sound = def.sound or "tnt_explode"
                core.sound_play(sound, {pos = pos, gain = 2.5,
                        max_hear_distance = math.min(def.radius * 20, 128)}, true)

                local above_pos = table.copy(pos)
                above_pos.y = above_pos.y + 1

                local below_pos = table.copy(pos)
                below_pos.y = below_pos.y - 1

                local pname = owner:get_player_name()
                local ndef = nodes[random(0, #nodes)]
                if ndef then
                    core.set_node(pos, {name = ndef.name})
                    local meta = core.get_meta(pos)
                    meta:set_string("owner", pname)
                    meta:set_string("owner2", pname)
                    if ndef.on_construct then
                        ndef.on_construct(pos)
                    end
                    if ndef.after_place_node then
                        ndef.after_place_node(pos, owner, ItemStack(modname..":"..def.name), {type="node", under=below_pos, above=above_pos})
                    end
                    core.check_for_falling(pos)
                end
            end
        })
    end

    local items = items()
    if #items ~= 0 then
        _G[modname].register_tnt({
            name = modname..":random_item",
            description = S("Random Item TNT"),
            tiles = texture(modname.."_random_item_background.png", modname.."_title.png"),
            craft = {
                recipe = {
                    {modname..":glitch_block", "gloopblocks:rainbow_block_horizontal", modname..":glitch_block"},
                    {"gloopblocks:rainbow_block_horizontal", modname..":random", "gloopblocks:rainbow_block_horizontal"},
                    {modname..":glitch_block", "gloopblocks:rainbow_block_horizontal", modname..":glitch_block"}
                }
            },
            radius = 2,
            boom = function(pos, def, owner)
                add_effects(pos, def.radius, owner)
                core.remove_node(pos)
                local sound = def.sound or "tnt_explode"
                core.sound_play(sound, {pos = pos, gain = 2.5,
                        max_hear_distance = math.min(def.radius * 20, 128)}, true)

                local above_pos = table.copy(pos)
                above_pos.y = above_pos.y + 1

                local below_pos = table.copy(pos)
                below_pos.y = below_pos.y - 1

                local pname = owner:get_player_name()
                local iname = items[random(0, #items)]
                core.add_item(pos, iname)
            end
        })
    end
end

_G[modname].register_tnt({
    name = modname..":shuffle",
    description = S("Shuffle TNT"),
    tiles = texture("[multiply:#7b4fa8", modname.."_title.png"),
    craft = {
        recipe = {
            {"default:diamondblock", "default:mese", "default:diamondblock"},
            {"default:mese", "tnt:tnt", "default:mese"},
            {"default:diamondblock", "default:mese", "default:diamondblock"}
        }
    },
    radius = 4,
    boom = function(pos, def, owner)
        add_effects(pos, def.radius, owner)
        core.remove_node(pos)

        local sound = def.sound or "tnt_explode"
        core.sound_play(sound, {
            pos = pos, gain = 2.5,
            max_hear_distance = math.min(def.radius * 20, 128)
        }, true)

        local r = def.radius

        local positions = {}
        local nodes = {}

        for dx = -r, r do
            for dy = -r, r do
                for dz = -r, r do
                    if dx*dx + dy*dy + dz*dz <= r*r then
                        local p = {
                            x = pos.x + dx,
                            y = pos.y + dy,
                            z = pos.z + dz
                        }
                        local node = core.get_node(p)
                        if node.name ~= "air" and node.name ~= "ignore" then
                            table.insert(positions, p)
                            table.insert(nodes, node)
                        end
                    end
                end
            end
        end

        local n = #nodes
        for i = n, 2, -1 do
            local j = math.random(1, i)
            nodes[i], nodes[j] = nodes[j], nodes[i]
        end

        for i = 1, #positions do
            local pos = positions[i]

            core.set_node(pos, nodes[i])
            local ndef = core.registered_nodes[nodes[i].name]
            if ndef.on_construct then
                ndef.on_construct(pos)
            end
            
            local above_pos = table.copy(pos)
            above_pos.y = above_pos.y + 1

            local below_pos = table.copy(pos)
            below_pos.y = below_pos.y - 1

            if ndef.after_place_node then
                ndef.after_place_node(pos, owner, ItemStack(modname..":"..def.name), {type="node", under=below_pos, above=above_pos})
            end

            core.check_for_falling(pos)
        end
    end
})

_G[modname].register_tnt({
	name = modname..":omega_nuke",
	description = S("Omega TNT"),
	radius = 96,
    tiles = texture("[multiply:#290000", modname.."_omega_side_overlay.png"),
    ignite_timer = 15,
    craft = {
        recipe = {
            {modname..":atomic_bomb", modname..":atomic_bomb", modname..":atomic_bomb"},
            {modname..":atomic_bomb", modname..":nuke", modname..":atomic_bomb"},
            {modname..":atomic_bomb", modname..":atomic_bomb", modname..":atomic_bomb"}
        }
    },
    boom = function(pos, def, owner)
        tnt.boom(pos, def)
        core.after(5, function()
            core.chat_send_all(core.colorize("#8a0000", S("OMEGA ATOMIC BOMB EXPLODED BY @1!", owner:get_player_name())))
            pos.y = pos.y
            scatter(pos, modname..":poison", 175, 480, owner:get_player_name())
        end)
    end
})

_G[modname].register_tnt({
    name = modname..":sponge",
    description = S("Sponge TNT"),
    tiles = texture(modname.."_sponge_background.png", modname.."_title.png"),
    craft = {
        recipe = {
            {"bucket:bucket_empty", "bucket:bucket_empty", "bucket:bucket_empty"},
            {"bucket:bucket_empty", "tnt:tnt", "bucket:bucket_empty"},
            {"bucket:bucket_empty", "bucket:bucket_empty", "bucket:bucket_empty"}
        }
    },
    radius = 6,
    boom = function(pos, def, owner)
        add_effects(pos, def.radius, owner)
        core.remove_node(pos, def.radius, owner)

        local sound = def.sound or "tnt_explode"
        core.sound_play(sound, {
            pos = pos, gain = 2.5,
            max_hear_distance = math.min(def.radius * 20, 128)
        }, true)

        local r = def.radius
        for dx = -r, r do
            for dy = -r, r do
                for dz = -r, r do
                    if dx*dx + dy*dy + dz*dz <= r*r then
                        local p = {
                            x = pos.x + dx,
                            y = pos.y + dy,
                            z = pos.z + dz
                        }
                        local name = core.get_node(p).name
                        if string.find(name, "_flowing") or string.find(name, "_source") then
                            core.remove_node(p)
                        end
                    end
                end
            end
        end
    end
})

local confetti_colors = {
    "#ff0000",
    "#00ff00",
    "#0000ff",
    "#00ffff",
    "#ff00ff",
    "#ffff00"
}

_G[modname].register_tnt({
	name = modname..":confetti",
	description = S("Confetti TNT"),
    tiles = texture("[multiply:#ffffff", modname.."_confetti_side_overlay.png"),
    craft = {
        recipe = {
            {"dye:red", "default:paper", "dye:blue"},
            {"default:paper", "tnt:tnt", "default:paper"},
            {"dye:green", "default:paper", "dye:yellow"}
        }
    },
    radius = 2,
    boom = function(pos, def, owner)
        core.remove_node(pos, def.radius, owner)
        core.sound_play(modname.."_confetti", {
            pos = pos,
            max_hear_distance = math.min(def.radius * 20, 128)
        }, true)

        for i = 0, random(12, 20) do
            core.add_particle({
                pos = pos,
                velocity = {x=randomFloat(-1.75, 1.75), y=3.5, z=randomFloat(-1.75, 1.75)},
                acceleration = {x=0, y=-3.5, z=0},
                expirationtime = 5,
                size = 3,
                collision_removal = true,
                collisiondetection = true,
                texture = modname.."_confetti_particle.png^[multiply:" .. confetti_colors[random(1, #confetti_colors)]
            })
        end
    end
})

if core.get_modpath("mobs_monster") then
    local challenge_entities = {
        "mobs_monster:mese_monster",
        "mobs_monster:oerkki",
        "mobs_monster:dungeon_master",
        "mobs_monster:lava_flan"
    }

    _G[modname].register_tnt({
        name = modname..":challenge",
        description = S("Challenge TNT"),
        tiles = texture("[multiply:#3d21cc", modname.."_title.png"),
        craft = {
            recipe = {
                {"mobs:protector2", "mobs:leather", "mobs:protector2"},
                {"mobs:leather", modname..":animal", "mobs:leather"},
                {"mobs:protector2", "mobs:leather", "mobs:protector2"}
            }
        },
        radius = 2,
        boom = function(pos, def, owner)
            add_effects(pos, def.radius, owner)
            core.remove_node(pos, def.radius, owner)
            core.sound_play(def.sound or "tnt_explode", {
                pos = pos,
                max_hear_distance = math.min(def.radius * 20, 128)
            }, true)

            local entity = challenge_entities[random(1, #challenge_entities)]
            for i = 1, random(5, 10) do
                local epos = table.copy(pos)
                epos.x = epos.x + random(-10, 10)
                epos.z = epos.z + random(-10, 10)
                epos = get_highest(epos)
                core.after(i, function()
                    core.add_entity(epos, entity)
                    core.sound_play(modname.."_pop", {pos = epos, gain = 2.0, max_hear_distance = 32})
                end)
            end
        end
    })
end

if core.get_modpath("fireworks") then
    local fireworks_entities = {
        "red",
        "orange",
        "violet",
        "green"
    }

    _G[modname].register_tnt({
        name = modname..":firework",
        description = S("Firework TNT"),
        tiles = texture("[multiply:#a82222", "firework_red.png"),
        craft = {
            recipe = {
                {"fireworks:red", "fireworks:green", "fireworks:violet"},
                {"fireworks:orange", "tnt:tnt", "fireworks:orange"},
                {"fireworks:violet", "fireworks:green", "fireworks:red"}
            }
        },
        radius = 2,
        boom = function(pos, def, owner)
            add_effects(pos, def.radius, owner)
            core.remove_node(pos, def.radius, owner)
            core.sound_play(def.sound or "tnt_explode", {
                pos = pos,
                max_hear_distance = math.min(def.radius * 20, 128)
            }, true)

            for i = 1, random(3, 6) do
                local epos = table.copy(pos)
                epos.x = epos.x + random(-4, 4)
                epos.z = epos.z + random(-4, 4)
                epos = get_highest(epos)
                core.after(i / 2, function()
                    fireworks_activate(epos, fireworks_entities[random(1, #fireworks_entities)])
                end)
            end
        end
    })
end

local function flowers()
    local registered = {}
    for name, def in pairs(core.registered_nodes) do
        if string.find(name, "flowers:") then
            def.name = name
            table.insert(registered, name)
        end
    end
    return registered
end

local flowers = flowers()
if core.get_modpath("flowers") and #flowers ~= 0 then
    _G[modname].register_tnt({
        name = modname..":flower",
        description = S("Flower TNT"),
        tiles = texture("[multiply:#eb8fd1", "flowers_rose.png"),
        craft = {
            recipe = {
                {"flowers:geranium", "flowers:viola", "flowers:chrysanthemum_green"},
                {"flowers:rose", "tnt:tnt", "flowers:dandelion_yellow"},
                {"flowers:tulip", "flowers:tulip_black", "flowers:dandelion_white"}
            }
        },
        radius = 2,
        boom = function(pos, def, owner)
            add_effects(pos, def.radius, owner)
            core.remove_node(pos, def.radius, owner)
            core.sound_play(def.sound or "tnt_explode", {
                pos = pos,
                max_hear_distance = math.min(def.radius * 20, 128)
            }, true)

            for i = 1, random(6, 8) do
                local epos = table.copy(pos)
                epos.x = epos.x + random(-5, 5)
                epos.z = epos.z + random(-5, 5)
                epos = get_highest(epos)
                core.after(i / 2, function()
                    core.set_node(epos, {name = flowers[random(1, #flowers)]})
                    core.sound_play(modname.."_pop", {pos = epos, gain = 2.0, max_hear_distance = 32})
                end)
            end
        end
    })
end

local trees = {
    core.get_modpath("default") .. "/schematics/aspen_tree.mts",
    core.get_modpath("default") .. "/schematics/apple_tree.mts",
    core.get_modpath("default") .. "/schematics/jungle_tree.mts",
    core.get_modpath("default") .. "/schematics/pine_tree.mts",
    core.get_modpath("default") .. "/schematics/acacia_tree.mts"
}

_G[modname].register_tnt({
    name = modname..":tree",
    description = S("Tree TNT"),
    tiles = texture("[multiply:#45270e", "too_many_tnt_tree_side_overlay.png"),
    craft = {
        recipe = {
            {"default:aspen_sapling", "default:tree", core.get_modpath("flowers") and "flowers:mushroom_red" or "default:large_cactus_seedling"},
            {"default:junglesapling", "tnt:tnt", "default:acacia_sappling"},
            {"default:pine_sapling", "default:sapling", "default:emergent_jungle_sappling"}
        }
    },
    radius = 2,
    boom = function(pos, def, owner)
        core.remove_node(pos)
        add_effects(pos, def.radius, owner)
        local sound = def.sound or "tnt_explode"
        core.sound_play(sound, {pos = pos, gain = 2.5,
                max_hear_distance = math.min(def.radius * 20, 128)}, true)
        core.place_schematic(pos, trees[random(1, #trees)], "random", {}, true, "place_center_x, place_center_z")
    end
})