--[[
	An API framework for mounting objects.

	Copyright (C) 2016 blert2112 and contributors
	Copyright (C) 2019-2023 David Leal (halfpacho@gmail.com) and contributors

    This library is free software; you can redistribute it and/or
    modify it under the terms of the GNU Lesser General Public
    License as published by the Free Software Foundation; either
    version 2.1 of the License, or (at your option) any later version.

    This library is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
    Lesser General Public License for more details.

    You should have received a copy of the GNU Lesser General Public
    License along with this library; if not, write to the Free Software
    Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301
	  USA
--]]

lib_mount = {
	passengers = { }
}

local crash_threshold = 6.5		-- ignored if enable_crash is disabled

------------------------------------------------------------------------------

local mobs_redo = false
if minetest.get_modpath("mobs") then
	if mobs.mod and mobs.mod == "redo" then
		mobs_redo = true
	end
end

--
-- Helper functions
--

--local function is_group(pos, group)
--	local nn = minetest.get_node(pos).name
--	return minetest.get_item_group(nn, group) ~= 0
--end

local function node_is(pos)
	local node = minetest.get_node(pos)
	if node.name == "air" then
		return "air"
	end
	if minetest.get_item_group(node.name, "liquid") ~= 0 then
		return "liquid"
	end
	if minetest.get_item_group(node.name, "walkable") ~= 0 then
		return "walkable"
	end
	return "other"
end

local function get_sign(i)
	i = i or 0
	if i == 0 then
		return 0
	else
		return i / math.abs(i)
	end
end

local function get_velocity(v, yaw, y)
	local x = -math.sin(yaw) * v
	local z =  math.cos(yaw) * v
	return vector.new(x, y, z)
end

local function get_v(v)
	return math.sqrt(v.x ^ 2 + v.z ^ 2)
end

local function ensure_passengers_exists(entity)
	if entity.passengers ~= nil then
		return
	end
	entity.passengers = {}
	if entity.passenger ~= nil or
		entity.passenger_attach_at ~= nil or
		entity.passenger_eye_offset ~= nil then
		table.insert(entity.passengers,{
			player=entity.passenger,
			attach_at=entity.passenger_attach_at,
			eye_offset=entity.passenger_eye_offset
		})
	else
		return
	end
	if entity.passenger2 ~= nil or
		entity.passenger2_attach_at ~= nil or
		entity.passenger2_eye_offset ~= nil then
		table.insert(entity.passengers,{
			player=entity.passenger2,
			attach_at=entity.passenger2_attach_at,
			eye_offset=entity.passenger2_eye_offset
		})
	else
		return
	end
	if entity.passenger3 ~= nil or
		entity.passenger3_attach_at ~= nil or
		entity.passenger3_eye_offset ~= nil then
		table.insert(entity.passengers,{
			player=entity.passenger3,
			attach_at=entity.passenger3_attach_at,
			eye_offset=entity.passenger3_eye_offset
		})
	end
end
-- Copies the specified passenger to the older api. Note that this is one-directional.
-- If something changed in the old api before this is called it is lost.
-- In code you control be sure to always use the newer API and to call this function on every change.
-- If you would like to improove preformance (memory & CPU) by not updating the old API, set
--  entity.new_api to true. This will return from the funciton instead of doing anything.
local function old_copy_passenger(entity,index,player,attach,eye)
	if entity.new_api then
		return
	end
	ensure_passengers_exists(entity)
	if index==1 then  -- Don't forget! Lua indexes start at 1
		if player then
			entity.passenger = entity.passengers[index].player
		end
		if attach then
			entity.passenger_attach_at = entity.passengers[index].attach_at
		end
		if eye then
			entity.passenger_eye_offset = entity.passengers[index].eye_offset
		end
	elseif index==2 then
		if player then
			entity.passenger2 = entity.passengers[index].player
		end
		if attach then
			entity.passenger2_attach_at = entity.passengers[index].attach_at
		end
		if eye then
			entity.passenger2_eye_offset = entity.passengers[index].eye_offset
		end
	elseif index==3 then
		if player then
			entity.passenger3 = entity.passengers[index].player
		end
		if attach then
			entity.passenger3_attach_at = entity.passengers[index].attach_at
		end
		if eye then
			entity.passenger3_eye_offset = entity.passengers[index].eye_offset
		end
	end
end

local function force_detach(player)
	local attached_to = player:get_attach()
	if attached_to then
		local entity = attached_to:get_luaentity()
		if entity.driver and entity.driver == player then
			entity.driver = nil
		else
			ensure_passengers_exists(entity)
			for i,passenger in ipairs(entity.passengers) do
				if passenger.player == player then -- If it's nil it won't match
					entity.passengers[i].player = nil -- This maintains the behavior where you could have passenger 1 leave but passenger 2 is still there, and they don't move
					lib_mount.passengers[player] = nil

					-- Legacy support
					old_copy_passenger(entity,i,true,false,false)

					break -- No need to continue looping. We found them.
				end
			end
		end
		player:set_detach()
		player_api.player_attached[player:get_player_name()] = false
		player:set_eye_offset(vector.new(0,0,0), vector.new(0,0,0))
	end
end

-------------------------------------------------------------------------------

minetest.register_on_leaveplayer(function(player)
	force_detach(player)
end)

minetest.register_on_shutdown(function()
    local players = minetest.get_connected_players()
	for i = 1,#players do
		force_detach(players[i])
	end
end)

minetest.register_on_dieplayer(function(player)
	force_detach(player)
	return true
end)

-------------------------------------------------------------------------------

function lib_mount.attach(entity, player, is_passenger, passenger_number)
	local attach_at, eye_offset = {}, {}

	if not is_passenger then
		passenger_number = nil
	end

	if not entity.player_rotation then
		entity.player_rotation = vector.new(0,0,0)
	end

	if is_passenger == true then
		-- Legacy support
		ensure_passengers_exists(entity)

		local attach_updated=false
		if not entity.passengers[passenger_number].attach_at then
			entity.passengers[passenger_number].attach_at = vector.new(0,0,0)
			attach_updated=true
		end
		local eye_updated=false
		if not entity.passengers[passenger_number].eye_offset then
			entity.passengers[passenger_number].eye_offset = vector.new(0,0,0)
			eye_updated=true
		end

		attach_at = entity.passengers[passenger_number].attach_at
		eye_offset = entity.passengers[passenger_number].eye_offset

		entity.passengers[passenger_number].player = player
		lib_mount.passengers[player] = player

		-- Legacy support
		old_copy_passenger(entity,passenger_number,true,attach_updated,eye_updated)
	else
		if not entity.driver_attach_at then
			entity.driver_attach_at = vector.new(0,0,0)
		end
		if not entity.driver_eye_offset then
			entity.driver_eye_offset = vector.new(0,0,0)
		end
		attach_at = entity.driver_attach_at
		eye_offset = entity.driver_eye_offset
		entity.driver = player
	end

	force_detach(player)

	player:set_attach(entity.object, "", attach_at, entity.player_rotation)
	player_api.player_attached[player:get_player_name()] = true
	player:set_eye_offset(eye_offset, vector.new(0,0,0))
	minetest.after(0.2, function()
		player_api.set_animation(player, "sit", 30)
	end)
	player:set_look_horizontal(entity.object:get_yaw() - math.rad(entity.player_rotation.y or 90))
end

function lib_mount.detach(player, offset)
	force_detach(player)
	player_api.set_animation(player, "stand", 30)
	local pos = player:get_pos()
	pos = {x = pos.x + offset.x, y = pos.y + 0.2 + offset.y, z = pos.z + offset.z}
	minetest.after(0.1, function()
		player:set_pos(pos)
	end)
end

local aux_timer = 0

function lib_mount.drive(entity, dtime, is_mob, moving_anim, stand_anim, jump_height, can_fly, can_go_down, can_go_up, enable_crash, moveresult)
	-- Sanity checks
	if entity.driver and not entity.driver:get_attach() then entity.driver = nil end

	-- Legacy support
	ensure_passengers_exists(entity)
	for i,passenger in ipairs(entity.passengers) do
		if passenger.player and not passenger.player:get_attach() then
			entity.passengers[i].player = nil
			-- Legacy support
			old_copy_passenger(entity,i,true,false,false)
		end
	end

	aux_timer = aux_timer + dtime

	if can_fly and can_fly == true then
		jump_height = 0
	end

	local rot_steer, rot_view = math.pi/2, 0 -- luacheck: ignore
	if entity.player_rotation.y == 90 then
		rot_steer, rot_view = 0, math.pi/2 -- luacheck: ignore
	end

	local acce_y = 0

	local velo = entity.object:get_velocity()
	entity.v = get_v(velo) * get_sign(entity.v)

	-- process controls
	if entity.driver then
		local ctrl = entity.driver:get_player_control()
		if ctrl.aux1 then
			if aux_timer >= 0.2 then
				entity.mouselook = not entity.mouselook
				aux_timer = 0
			end
		end
		if ctrl.up then
			if get_sign(entity.v) >= 0 then
				entity.v = entity.v + entity.accel/10
			else
				entity.v = entity.v + entity.braking/10
			end
		elseif ctrl.down then
			if entity.max_speed_reverse == 0 and entity.v == 0 then return end
			if get_sign(entity.v) < 0 then
				entity.v = entity.v - entity.accel/10
			else
				entity.v = entity.v - entity.braking/10
			end
		end
		if entity.mouselook then
			if ctrl.left then
				entity.object:set_yaw(entity.object:get_yaw()+get_sign(entity.v)*math.rad(1+dtime)*entity.turn_spd)
			elseif ctrl.right then
				entity.object:set_yaw(entity.object:get_yaw()-get_sign(entity.v)*math.rad(1+dtime)*entity.turn_spd)
			end
		else
			if minetest.settings:get_bool("lib_mount.limited_turn_speed") then
				-- WIP and may contain bugs.
				local yaw = entity.object:get_yaw()
				local yaw_delta = entity.driver:get_look_horizontal() - yaw + math.rad(entity.player_rotation.y or 90)
				if yaw_delta > math.pi then
					yaw_delta = yaw_delta - math.pi * 2
				elseif yaw_delta < - math.pi then
					yaw_delta = yaw_delta + math.pi * 2
				end

				local yaw_sign = get_sign(yaw_delta)
				if yaw_sign == 0 then
					yaw_sign = 1
				end

				yaw_delta = math.abs(yaw_delta)
				if yaw_delta > math.pi / 2 then
					yaw_delta = math.pi / 2
				end

				local yaw_speed = yaw_delta * entity.turn_spd
				yaw_speed = yaw_speed * dtime

				entity.object:set_yaw(yaw + yaw_sign*yaw_speed)
			else
				entity.object:set_yaw(entity.driver:get_look_horizontal() + math.rad(entity.player_rotation.y or 90))
			end
		end
		if ctrl.jump then
			if jump_height > 0 and velo.y == 0 then
				velo.y = velo.y + (jump_height * 3) + 1
				acce_y = acce_y + (acce_y * 3) + 1
			end
			if can_go_up and can_fly and can_fly == true then
				velo.y = velo.y + 1
				acce_y = acce_y + 1
			end
		end
		if ctrl.sneak then
			if can_go_down and can_fly and can_fly == true then
				velo.y = velo.y - 1
				acce_y = acce_y - 1
			end
		end
	end

	-- if not moving then set animation and return
	if entity.v == 0 and velo.x == 0 and velo.y == 0 and velo.z == 0 then
		if is_mob and mobs_redo == true then
			if stand_anim and stand_anim ~= nil then
				set_animation(entity, stand_anim)
			end
		end
		return
	end

	-- set animation
	if is_mob and mobs_redo == true then
		if moving_anim and moving_anim ~= nil then
			set_animation(entity, moving_anim)
		end
	end

	-- Stop!
	local s = get_sign(entity.v)
	entity.v = entity.v - 0.02 * s
	if s ~= get_sign(entity.v) then
		entity.object:set_velocity(vector.new(0,0,0))
		entity.v = 0
		return
	end

	-- Stop! (upwards and downwards; applies only if `can_fly` is enabled)
	if can_fly == true then
		local s2 = get_sign(velo.y)
		local s3 = get_sign(acce_y)
		velo.y = velo.y - 0.02 * s2
		acce_y = acce_y - 0.02 * s3
		if s2 ~= get_sign(velo.y) then
			entity.object:set_velocity(vector.new(0,0,0))
			velo.y = 0
			return
		end
		if s3 ~= get_sign(acce_y) then
			entity.object:set_velocity(vector.new(0,0,0))
			acce_y = 0 -- luacheck: ignore
			return
		end
	end

	-- enforce speed limit forward and reverse
	local max_spd = entity.max_speed_reverse
	if get_sign(entity.v) >= 0 then
		max_spd = entity.max_speed_forward
	end
	if math.abs(entity.v) > max_spd then
		entity.v = entity.v - get_sign(entity.v)
	end

	-- Enforce speed limit when going upwards or downwards (applies only if `can_fly` is enabled)
	if can_fly == true then
		local max_spd_flying = entity.max_speed_downwards
		if get_sign(velo.y) >= 0 or get_sign(acce_y) >= 0 then
			max_spd_flying = entity.max_speed_upwards
		end

		if math.abs(velo.y) > max_spd_flying then
			velo.y = velo.y - get_sign(velo.y)
		end
		if velo.y > max_spd_flying then -- This check is to prevent exceeding the maximum speed; but the above check also prevents that.
			velo.y = velo.y - get_sign(velo.y)
		end

		if math.abs(acce_y) > max_spd_flying then
			acce_y = acce_y - get_sign(acce_y)
		end
	end

	-- Set position, velocity and acceleration
	local p = entity.object:get_pos()
	local new_velo = vector.new(0,0,0)
	local new_acce = vector.new(0,-9.8,0)

	p.y = p.y - 0.5
	local ni = node_is(p)
	local v = entity.v
	if ni == "air" then
		if can_fly == true then
			new_acce.y = 0
			acce_y = acce_y - get_sign(acce_y) -- When going down, this will prevent from exceeding the maximum speed.
		end
	elseif ni == "liquid" then
		if entity.terrain_type == 2 or entity.terrain_type == 3 then
			new_acce.y = 0
			p.y = p.y + 1
			if node_is(p) == "liquid" then
				if velo.y >= 5 then
					velo.y = 5
				elseif velo.y < 0 then
					new_acce.y = 20
				else
					new_acce.y = 5
				end
			else
				if math.abs(velo.y) < 1 then
					local pos = entity.object:get_pos()
					pos.y = math.floor(pos.y) + 0.5
					entity.object:set_pos(pos)
					velo.y = 0
				end
			end
		else
			v = v*0.25
		end
--	elseif ni == "walkable" then
--		v = 0
--		new_acce.y = 1
	end

	new_velo = get_velocity(v, entity.object:get_yaw() - rot_view, velo.y)
	new_acce.y = new_acce.y + acce_y

	entity.object:set_velocity(new_velo)
	entity.object:set_acceleration(new_acce)

	-- CRASH!
	if enable_crash then
		local intensity = entity.v2 - v
		if intensity >= crash_threshold then
			if is_mob then
				entity.object:set_hp(entity.object:get_hp() - intensity)
			else
				if entity.driver then
					local drvr = entity.driver
					lib_mount.detach(drvr, vector.new(0,0,0))
					drvr:set_velocity(new_velo)
					drvr:set_hp(drvr:get_hp() - intensity)
				end
				ensure_passengers_exists(entity)-- Legacy support
				for _,passenger in ipairs(entity.passengers) do
					if passenger.player then
						local pass = passenger.player
						lib_mount.detach(pass, vector.new(0,0,0))  -- This function already copies to old API
						pass:set_velocity(new_velo)
						pass:set_hp(pass:get_hp() - intensity)
					end
				end
				local pos = entity.object:get_pos()

				------------------
				-- Handle drops --
				------------------

				-- `entity.drop_on_destory` is table which stores all the items that will be dropped on destroy.
				-- It will drop one of those items, from `1` to the length, or the end of the table.

				local i = math.random(1, #entity.drop_on_destroy)
				local j = math.random(2, #entity.drop_on_destroy)

				minetest.add_item(pos, entity.drop_on_destroy[i])
				if i ~= j then
					minetest.add_item(pos, entity.drop_on_destroy[j])
				end

				entity.removed = true
				-- delay remove to ensure player is detached
				minetest.after(0.1, function()
					entity.object:remove()
				end)
			end
		end
	end

	entity.v2 = v
end

-- Print after the mod was loaded successfully
local load_message = "[MOD] Library Mount loaded!"
if minetest.log then
	minetest.log("info", load_message) -- Aims at state of the MT software art
else
	print(load_message)  -- Aims at legacy MT software used in the field
end
