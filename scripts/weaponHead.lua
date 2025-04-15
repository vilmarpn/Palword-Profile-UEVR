local api = uevr.api
local vr = uevr.params.vr

local game_engine_class = api:find_uobject("Class /Script/Engine.GameEngine")
local hitresult_c = api:find_uobject("ScriptStruct /Script/Engine.HitResult")
local kismet_system_library = api:find_uobject("Class /Script/Engine.KismetSystemLibrary")
local kismet_math_library = api:find_uobject("Class /Script/Engine.KismetMathLibrary")
local kismet_input_library = api:find_uobject("Class /Script/Engine.KismetInputLibrary")
local color_c = api:find_uobject("ScriptStruct /Script/CoreUObject.LinearColor")
local FLinearColor = api:find_uobject("ScriptStruct /Script/CoreUObject.LinearColor")
local rotator_c = api:find_uobject("ScriptStruct /Script/CoreUObject.Rotator")
local fkey_class = api:find_uobject("ScriptStruct /Script/InputCore.Key")
local ksl = kismet_system_library:get_class_default_object()
local kml = kismet_math_library:get_class_default_object()
local kil = kismet_input_library:get_class_default_object()

-- Weapon offset configuration
local weapon_location_offset = Vector3f.new(1.9078741073608398, -2.1786863803863525, 11.48326301574707)
local weapon_rotation_offset = Vector3f.new(0.0, -0.04, 0.0)

local last_pawn = nil

local RIGHT_GRIP = 0x0200  -- XINPUT_GAMEPAD_RIGHT_SHOULDER
local was_pressed = false
local press_time = 0
local hold_threshold = 0.2  -- segundos para considerar como "segurando"
local is_holding = false

local function hide_Mesh(name)
    if name then
        name:SetRenderInMainPass(false)
        name:SetRenderInDepthPass(false)
        name:SetRenderCustomDepth(false)
    end
end

local function show_Mesh(name)
    if name then
        name:SetRenderInMainPass(true)
        name:SetRenderInDepthPass(true)
        name:SetRenderCustomDepth(true)
    end
end

-- Applies motion controller state to the weapon
local function update_weapon_motion_controller()
    local pawn = api:get_local_pawn(0)
    if not pawn or not pawn.Children then return end
    local Glider_vec3 = Vector3d.new(0, 0, 70)
    local empty_hitresult = StructObject.new(hitresult_c)

    for _, component in ipairs(pawn.Children) do
        
        if component and UEVR_UObjectHook.exists(component) and (string.find(component:get_full_name(), "ThrowPalWeapon")) then
            --hide Sphere
            --print("aqui",component.SK_Weapon_PalSphere_001)   
            hide_Mesh(component.SK_Weapon_PalSphere_001)    
        elseif component and UEVR_UObjectHook.exists(component) and (not string.find(component:get_full_name(), "Glider")) and (not string.find(component:get_full_name(), "Lamp"))then
            local state = UEVR_UObjectHook.get_or_add_motion_controller_state(component.RootComponent)
            if state then
                state:set_hand(1)  -- Right hand
                state:set_permanent(true)
                state:set_location_offset(weapon_location_offset)
                state:set_rotation_offset(weapon_rotation_offset)
            end        
        end
    end
end

-- Handles weapon aiming and firing trace
local function update_weapon_aim_and_trace()
    local pawn = api:get_local_pawn(0)
    if not pawn or not pawn.Children then return end

    local zero_color = StructObject.new(color_c)
    local reusable_hit_result = StructObject.new(hitresult_c)
    local game_engine = UEVR_UObjectHook.get_first_object_by_class(game_engine_class)
    local world = game_engine and game_engine.GameViewport and game_engine.GameViewport.World
    if not world then return end

    local ignore_actors = {pawn}

    for _, weapon in ipairs(pawn.Children) do
        if weapon and weapon.BlueprintCreatedComponents then
            local mesh = nil
            for _, comp in ipairs(weapon.BlueprintCreatedComponents) do
                if string.find(comp:get_full_name(), "SkeletalMeshComponent") then
                    mesh = comp
                    break
                end
            end

            if mesh and mesh:DoesSocketExist("Muzzle") then
                -- Fire the trace starting from the muzzle socket, following the weapon's forward direction
                local muzzle_pos = mesh:GetSocketLocation("Muzzle")
                local muzzle_rot = mesh:GetSocketRotation("Muzzle")
                local forward_vector = kml:GetForwardVector(muzzle_rot)

                local trace_end = Vector3f.new(
                    muzzle_pos.X + forward_vector.X * 8192.0,
                    muzzle_pos.Y + forward_vector.Y * 8192.0,
                    muzzle_pos.Z + forward_vector.Z * 8192.0
                )

                local corrected_muzzle_pos = muzzle_pos -- Optional aiming offset could be added here
                table.insert(ignore_actors, weapon)
                table.insert(ignore_actors, mesh)
                --print("pos ",corrected_muzzle_pos.X,corrected_muzzle_pos.Y,corrected_muzzle_pos.Z,trace_end.X,trace_end.y,trace_end.Z)
                -- Line trace
                local hit = ksl:LineTraceSingle(
                    world,
                    corrected_muzzle_pos,
                    trace_end,
                    3,                  -- ECC_Visibility
                    true,               -- trace complex
                    ignore_actors,
                    2,                  -- no debug trace type
                    reusable_hit_result,
                    true,               -- ignore self
                    zero_color,
                    zero_color,
                    1.0
                )

                -- Debug line (red color)
                local red_color = StructObject.new(FLinearColor)
                red_color.R = 179.0 / 255.0
                red_color.G = 45.0 / 255.0
                red_color.B = 54.0 / 255.0
                red_color.A = 1.0

                ksl:DrawDebugLine(world, corrected_muzzle_pos, trace_end, red_color, 5.0, 2.0)

                -- If hit, handle impact (optional: apply damage, effects, etc.)
                if hit and reusable_hit_result then
                    local impact_location = reusable_hit_result.ImpactPoint
                    -- print("Hit at:", impact_location.X, impact_location.Y, impact_location.Z)
                end
            end
        end
    end
end

-- Disables camera effects that may cause issues
local function disable_camera_effects(pawn)
    local camera_component = pawn:GetComponentByClass(api:find_uobject("Class /Script/Engine.CameraComponent"))
    local attach_parent = camera_component and camera_component.AttachParent

    if attach_parent then
        attach_parent.bEnableCameraRotationLag = false
        attach_parent.bEnableCameraLag = false

        local attach_parent_parent = attach_parent.AttachParent
        if attach_parent_parent and attach_parent_parent.ResetLookOperation then
            attach_parent_parent:ResetLookOperation(nil) -- Reseta ajustes automáticos da câmera
        end
    end
end

-- Gets the correct head position from the Mesh
local function get_head_position(pawn)
    if not pawn or not pawn.Mesh then
        print("Error: Mesh not found!")
        return pawn:K2_GetActorLocation() -- Returns the default position if the Mesh is not found
    end

    -- If the head socket exists, retrieves its correct position
    if pawn.Mesh:DoesSocketExist("Head") then
        return pawn.Mesh:GetSocketLocation("Head")
    else
        -- Otherwise, uses the Mesh position and applies a manual fine adjustment
        local head_pos = pawn.Mesh:K2_GetComponentLocation()
        head_pos.Z = head_pos.Z + 80 -- Fine adjustment
        return head_pos
    end
end

-- Smooths the transition of the camera position (prevents jitter)
local function lerp_position(from, to, alpha)
    return Vector3f.new(
        from.X + (to.X - from.X) * alpha,
        from.Y + (to.Y - from.Y) * alpha,
        from.Z + (to.Z - from.Z) * alpha
    )
end

-- Keeps the body rotation only on the Yaw axis
local function update_character_rotation(pawn, rotation)
    local character_rotation = pawn:K2_GetActorRotation()
    character_rotation.Yaw = rotation.Yaw -- Keeps only the horizontal rotation
    pawn:K2_SetActorRotation(character_rotation, false)
end

local function hide_player_mesh(pawn)
    -- Checks if pawn is the player character (adjust base name if necessary)
    local pawn_name = pawn:get_full_name()
    if string.find(pawn_name, "BP_Player_Female_C") then
        -- Hides only the character mesh
        hide_Mesh(pawn.Mesh)
        hide_Mesh(pawn.HeadMesh)
        hide_Mesh(pawn.HairMesh)
        hide_Mesh(pawn.HairAttachAccessory)
    end
end


local delta = 10.0

uevr.sdk.callbacks.on_early_calculate_stereo_view_offset(function(device, view_index, world_to_meters, position, rotation, is_double)
    local pawn = api:get_local_pawn(0)
    if not pawn then return end

    hide_player_mesh(pawn)

    -- Disables unwanted camera effects
    disable_camera_effects(pawn)

    -- Gets the head position
    local head_pos = get_head_position(pawn)
    position.x, position.y, position.z = head_pos.X, head_pos.Y, head_pos.Z

    -- Smooths the camera transition to prevent jitter
    local new_position = lerp_position(position, head_pos, 0.1)
    position.x, position.y, position.z = new_position.X, new_position.Y, new_position.Z

    -- Keeps body rotation only on the horizontal axis
    update_character_rotation(pawn, rotation)

    -- Safely finds the camera
    local camera_component = pawn:GetComponentByClass(api:find_uobject("Class /Script/Engine.CameraComponent"))

    if camera_component then
        local empty_hitresult = StructObject.new(hitresult_c)
        camera_component:K2_SetWorldLocation(Vector3f.new(position.x, position.y, position.z), false, empty_hitresult, true)
    else
        -- Alternative: Adjusts the camera in the PlayerCameraManager
        local player_controller = api:get_player_controller(0)
        local camera_manager = player_controller and player_controller.PlayerCameraManager
        if camera_manager then
            camera_manager:SetCameraLocation(position)
            camera_manager:SetCameraRotation(rotation)
        end
    end

    update_weapon_aim_and_trace()

    --[[ -- Gets the rotation of the player's HMD (to avoid body sway)
    local player_controller = api:get_player_controller(0)
    local camera_manager = player_controller and player_controller.PlayerCameraManager
    local target_raw = rotation  -- Usa a rotação do HMD diretamente

    -- Get the current rotation
    local current_raw = pawn:K2_GetActorRotation()

    local current_rot = StructObject.new(rotator_c)
    current_rot.Pitch = current_raw.Pitch
    current_rot.Yaw = current_raw.Yaw
    current_rot.Roll = current_raw.Roll

    local target_rot = StructObject.new(rotator_c)
    target_rot.Pitch = target_raw.Pitch
    target_rot.Yaw = target_raw.Yaw
    target_rot.Roll = target_raw.Roll
   
    if not current_rot or not target_rot then return end

    local alpha = tonumber(delta * 20.0) -- Aumenta a suavidade
    
    local smooth_rot = kml:RLerp(current_rot, target_rot, alpha, true)
    
    if smooth_rot then
        pawn:K2_SetActorRotation(smooth_rot, false)
    else
        print("Error: RLerp returned nil!")
    end ]]
end) 

uevr.sdk.callbacks.on_xinput_get_state(function(retval, user_index, state)
    local now = os.clock()
    local buttons = state.Gamepad.wButtons
    local is_pressed = (buttons & RIGHT_GRIP) ~= 0


    -- Quando o botão é pressionado
    if is_pressed and not was_pressed then
        press_time = now
        was_pressed = true
        is_holding = false  -- Ainda não sabemos se é clique ou segurar

    -- Enquanto o botão está pressionado
    elseif is_pressed and was_pressed then
        local duration = now - press_time
        if duration >= hold_threshold and not is_holding then
            print("Começou a SEGURAR o botão")
            is_holding = true
        elseif is_holding then
            -- Aqui você pode fazer alguma ação contínua enquanto segura
            print("Ainda segurando...")
            local pawn = api:get_local_pawn(0)
            if not pawn or not pawn.Children then return end

            for _, component in ipairs(pawn.Children) do
                
                if component and UEVR_UObjectHook.exists(component) and (string.find(component:get_full_name(), "ThrowPalWeapon")) then
                    --hide Sphere
                    --print("aqui",component.SK_Weapon_PalSphere_001)   
                    show_Mesh(component.SK_Weapon_PalSphere_001)  
                end  
            end
        end

    -- Quando o botão é solto
    elseif not is_pressed and was_pressed then
        local duration = now - press_time
        if duration < hold_threshold then
            print("CLIQUE curto detectado")
        elseif is_holding then
            print("Parou de SEGURAR após " .. duration .. "s")
        end

        -- Resetando estados
        was_pressed = false
        is_holding = false
    end
end)

-- Main loop for updating weapon controller and firing logic
uevr.sdk.callbacks.on_pre_engine_tick(function(engine, delta)
    
    if vr.is_hmd_active() then
        update_weapon_motion_controller()
    end
    
end)
