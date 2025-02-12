local LambdaIsValid = LambdaIsValid
local dev = GetConVar( "lambdaplayers_debug_path" )
local IsValid = IsValid
local math_max = math.max
local isvector = isvector
local Trace = util.TraceLine
local TraceHull = util.TraceHull
local debugoverlay = debugoverlay
local CurTime = CurTime
local tracetable = {}
local unstucktable = {}
local laddermovetable = { collisiongroup = COLLISION_GROUP_PLAYER }
local ents_FindByName = ents.FindByName
local GetGroundHeight = navmesh.GetGroundHeight
local navmesh_IsLoaded = navmesh.IsLoaded
local random = math.random
local ipairs = ipairs
local coroutine_yield = coroutine.yield

-- Finds "simple" ground height, treating the provided nav area as part of the floor
local function GetSimpleGroundHeightWithFloor( navArea, pos )
    local height, normal = GetGroundHeight( pos )
    if !height or !normal then return end
    if IsValid( navArea ) and navArea:IsOverlapping( pos ) then height = math_max( height, navArea:GetZ( pos ) ) end
    return height, normal
end

-- Start off simple
-- Pos arg can be a vector or a entity.
function ENT:MoveToPos( pos, options )
    pos = ( isvector( pos ) and pos or ( LambdaIsValid( pos ) and pos:GetPos() or nil ) )
    if !pos then return "failed" end

    -- If there is no nav mesh, try to go to the postion anyway
    if !navmesh_IsLoaded() or !IsValid( self.l_currentnavarea ) then 
        self:MoveToPosOFFNAV( pos, options ) 
        return "failed"
    end 

    options = options or {}

    local path = Path( "Follow" )
    path:SetGoalTolerance( options.tol or 20 )
    path:SetMinLookAheadDistance( self.l_LookAheadDistance )

    path:Compute( self, pos, self:PathGenerator() )
    if !IsValid( path ) then return "failed" end

    self.l_issmoving = true
    self.l_movepos = pos
    self.l_CurrentPath = path

    local timeout = options.timeout
    local update = options.update
    local callback = options.callback

    local autorun = options.autorun
    self:SetRun( !autorun and ( options.run or false ) or ( path:GetLength() > 1500 ) )

    local loco = self.loco
    local stepH = loco:GetStepHeight()
    local jumpCheckDist = 60
    local returnMsg = "ok"

    LambdaRunHook( "LambdaOnBeginMove", self, pos, true )

	while ( IsValid( path ) ) do
        if self:GetIsDead() then returnMsg = "invalid" break end
        if self.AbortMovement then 
            self.AbortMovement = false 
            returnMsg = "aborted"; break 
        end
        if timeout and path:GetAge() > timeout then returnMsg = "timeout" break end

        pos = ( isvector( self.l_movepos ) and self.l_movepos or ( LambdaIsValid( self.l_movepos ) and self.l_movepos:GetPos() or nil ) )
        if !pos then returnMsg = "invalid" break end

		if loco:IsStuck() then
            -- This prevents the stuck handling from running if we are right next to the entity we are going to            
            if isvector( pos ) or !self:IsInRange( pos, 100 ) then 
                local result = self:HandleStuck()
                if !result then returnMsg = "stuck" break end
            else
                loco:ClearStuck()
            end
		end

        local goal = path:GetCurrentGoal()

		if update then
            local updateTime = math_max( update, update * ( path:GetLength() / loco:GetDesiredSpeed() ) )
			if path:GetAge() > updateTime then path:Compute( self, pos, self:PathGenerator() ) end
		end

        if self.l_recomputepath then
            path:Compute( self, pos, self:PathGenerator() )
            self.l_recomputepath = nil
        end
        
        if !self:IsDisabled() and CurTime() > self.l_moveWaitTime then
            if callback and callback( pos, path, goal ) == false then returnMsg = "callback" break end 
            path:Update( self )

            self:ObstacleCheck()

            -- Close up jumping
            local selfPos = self:GetPos()
            local aheadNormal = ( goal.pos - selfPos ):GetNormalized(); aheadNormal.z = 0
            local grHeight = GetSimpleGroundHeightWithFloor( self.l_currentnavarea, selfPos + vector_up * stepH + aheadNormal * jumpCheckDist )
            if grHeight and ( grHeight - selfPos.z ) > stepH then self:LambdaJump() end
        end

        -- Checks if we need to climb ladder to traverse
        local moveType = goal.type
        if moveType == 4 or moveType == 5 then
            local ladder = goal.ladder
            if IsValid( ladder ) and self:IsInRange( ( moveType == 4 and ladder:GetBottom() or ladder:GetTop() ), 64 ) then
                self.l_ladderarea = ladder
                self:ClimbLadder( ladder, ( moveType == 5 ), goal.pos )
                self.l_ladderarea = NULL 
                
                pos = ( isvector( self.l_movepos ) and self.l_movepos or ( LambdaIsValid( self.l_movepos ) and self.l_movepos:GetPos() or nil ) )
                if pos then path:Compute( self, pos, self:PathGenerator() ) end
            end
        end

        if dev:GetBool() then path:Draw() end
        coroutine_yield()
	end

    self.l_issmoving = false 
    self.l_movepos = nil
    self.l_CurrentPath = nil

	return returnMsg
end

-- If the map we are on does not have a navmesh, the Lambda Players will default their movement to this so they can actually move
function ENT:MoveToPosOFFNAV( pos, options )
    pos = ( isvector( pos ) and pos or ( LambdaIsValid( pos ) and pos:GetPos() or nil ) )
    if !pos then return "failed" end

    self.l_issmoving = true
    self.l_movepos = pos
    self.l_CurrentPath = pos

	local options = options or {}
    local callback = options.callback
    local tolerance = options.tol or 20
    
    local timeout = options.timeout
    if timeout then timeout = CurTime() + timeout end

    local autorun = options.autorun
    self:SetRun( !autorun and ( options.run or false ) or ( !self:IsInRange( pos, 1500 ) ) )

    local returnMsg = "ok"
    local loco = self.loco

    LambdaRunHook( "LambdaOnBeginMove", self, pos, false )

    while IsValid( self ) do 
        if timeout and CurTime() > timeout then returnMsg = "timeout" break end
        if self:GetIsDead() then returnMsg = "dead" break end
        if self.AbortMovement then 
            self.AbortMovement = false 
            returnMsg = "aborted"; break
        end

        pos = ( isvector( self.l_movepos ) and self.l_movepos or ( LambdaIsValid( self.l_movepos ) and self.l_movepos:GetPos() or nil ) )
        if !pos then returnMsg = "invalid" break end

		if loco:IsStuck() then
            -- This prevents the stuck handling from running if we are right next to the entity we are going to            
            if isvector( pos ) or !self:IsInRange( pos, 100 ) then 
                local result = self:HandleStuck()
                if !result then returnMsg = "stuck" break end
            else
                loco:ClearStuck()
            end
		end

        local selfPos = self:GetPos()
        local posSelfZ = pos; posSelfZ.z = selfPos.z

        if self:IsInRange( posSelfZ, tolerance ) then
            break
        elseif !self:IsDisabled() and CurTime() > self.l_moveWaitTime then
            if callback and callback( pos ) == false then returnMsg = "callback" break end 

            loco:FaceTowards( pos )
            loco:Approach( pos, 1 )
            
            self:ObstacleCheck()
        end
        self.l_CurrentPath = pos

        if dev:GetBool() then debugoverlay.Line( selfPos, pos, 0.1, color_white, true ) end
        coroutine_yield()
    end

    self.l_issmoving = false
    self.l_movepos = nil 
    self.l_CurrentPath = nil

    return returnMsg
end

-- Start climbing the provided ladder
function ENT:ClimbLadder( ladder, isDown, movePos )
    if !IsValid( ladder ) then return end

    local startPos, goalPos, finishPos
    if isDown then
        startPos = ladder:GetTop()
        goalPos = ladder:GetBottom()
        finishPos = ladder:GetBottomArea():GetClosestPointOnArea( goalPos )
    else
        startPos = ladder:GetBottom()
        goalPos = ladder:GetTop()

        local possibleAreas = {}
        local ladderArea = ladder:GetTopForwardArea()
        if IsValid( ladderArea ) then possibleAreas[ #possibleAreas + 1 ] = ladderArea end
        ladderArea = ladder:GetTopBehindArea()
        if IsValid( ladderArea ) then possibleAreas[ #possibleAreas + 1 ] = ladderArea end
        ladderArea = ladder:GetTopLeftArea()
        if IsValid( ladderArea ) then possibleAreas[ #possibleAreas + 1 ] = ladderArea end
        ladderArea = ladder:GetTopRightArea()
        if IsValid( ladderArea ) then possibleAreas[ #possibleAreas + 1 ] = ladderArea end

        local lastDist = math.huge
        for _, v in ipairs( possibleAreas ) do
            local closePoint = v:GetClosestPointOnArea( goalPos )
            local closeDist = movePos:DistToSqr( closePoint )
            if closeDist >= lastDist then continue end

            lastDist = closeDist
            finishPos = closePoint
        end
    end

    local endDir = ( finishPos - goalPos ):GetNormalized(); endDir.z = 0
    laddermovetable.start = finishPos
    laddermovetable.endpos = ( finishPos + endDir * 48 )
    laddermovetable.filter = self
    laddermovetable.ignoreworld = false
    finishPos = Trace( laddermovetable ).HitPos

    local climbFract = 0
    local climbState = 1
    local nextSndTime = 0

    local climbStart = self:GetPos()
    local climbEnd = ( startPos + ( ladder:GetNormal() * 20 ) )
    local climbNormal = ( climbEnd - climbStart ):GetNormalized()
    local climbDist = climbStart:Distance( climbEnd )

    local mins, maxs = self:GetCollisionBounds()
    laddermovetable.mins = mins
    laddermovetable.maxs = maxs

    local stuckTime = CurTime() + 5

    while ( true ) do
        if !LambdaIsValid( self ) or self:IsInNoClip() then return end
        if CurTime() > stuckTime then 
            self:SetPos( finishPos )
            return 
        end
        
        local climbPos = ( climbStart + climbNormal * climbFract )
        self:SetPos( climbPos )
        self.loco:FaceTowards( self:GetPos() * climbNormal )

        laddermovetable.start = climbPos
        laddermovetable.endpos = ( climbPos + climbNormal * 20 )
        laddermovetable.filter = self
        laddermovetable.ignoreworld = true

        if !IsValid( TraceHull( laddermovetable ).Entity ) and ( !self:IsDisabled() and CurTime() > self.l_moveWaitTime or climbState != 2 ) then
            climbFract = climbFract + ( 200 * FrameTime() )
            stuckTime = CurTime() + 5

            if climbFract >= climbDist then
                if climbState == 1 then
                    climbEnd = goalPos + ( ladder:GetNormal() * 16 )
                elseif climbState == 2 then
                    climbEnd = finishPos
                else
                    return
                end

                climbStart = self:GetPos()
                climbNormal = ( climbEnd - climbStart ):GetNormalized()
                climbDist = climbStart:Distance( climbEnd ) - ( ( isDown and climbState == 2 ) and random( 0, 48 ) or 0 )

                climbFract = 0
                climbState = climbState + 1
            end

            if climbState == 2 and CurTime() > nextSndTime then
                self:EmitSound( "player/footsteps/ladder" .. random( 4 ) .. ".wav" )
                nextSndTime = CurTime() + 0.466
            end
        end
        
        coroutine_yield()
    end
end

-- If we are moving while this function is called, recompute our current path or change the goal position and recompute
function ENT:RecomputePath( pos )
    if self.l_issmoving then
        self.l_movepos = pos or self.l_movepos
        self.l_recomputepath = true
    end
end

-- Stops movement from :MoveToPos() and :MoveToPosOFFNAV()
function ENT:CancelMovement()
    self.AbortMovement = self.l_issmoving
end

-- Makes lambda wait and stop while moving for a given amount of time
function ENT:WaitWhileMoving( time )
    if !self.l_issmoving then return end
    self.l_moveWaitTime = CurTime() + time
end

-- This function will either return true or false
-- If this returns true, continue on our current path
-- Unless false, don't continue and stop
function ENT:HandleStuck()
    if self:GetIsDead() then -- Who knows just in case
        self.loco:ClearStuck() 
        return false 
    end

    self.l_stucktimes = self.l_stucktimes + 1
    self.l_stucktimereset = CurTime() + 10

    -- Allow external addons to control our stuck process. We assume whoever made that hook and returns "stop" or "continue" will handle the unstuck behaviour
    local result = LambdaRunHook( "LambdaOnStuck", self, self.l_stucktimes )
    if result == "stop" then 
        return false 
    elseif result == "continue" then 
        return true 
    end

    if self.l_stucktimes == 3 then 
        self.l_unstuck = true 
        return true 
    elseif self.l_stucktimes == 4 then 
        self.l_unstuck = true 
        return false 
    end

    local selfPos = self:GetPos()
    local mins, maxs = self:GetCollisionBounds()

    unstucktable.start = selfPos
    unstucktable.endpos = selfPos + vector_up * 4
    unstucktable.mins = mins
    unstucktable.maxs = maxs
    unstucktable.filter = self

    local istuckinsomething = TraceHull( unstucktable )
    if !istuckinsomething.Hit then -- If we didn't get stuck in any entity then try to jump
        self:LambdaJump()
        self.loco:ClearStuck()
    else -- We got stuck in something. Force our way out
        self.l_unstuck = true
    end

    return true
end


-- Returns a pathfinding function for the :Compute() function
function ENT:PathGenerator()
    local jumpPenalty = 10
    local isInNoClip = self:IsInNoClip()
    local stepHeight = self.loco:GetStepHeight()
    local jumpHeight = self.loco:GetJumpHeight()
    local deathHeight = -self.loco:GetDeathDropHeight()

    return function( area, fromArea, ladder, elevator, length )
        if !IsValid( fromArea ) then return 0 end
        if area:HasAttributes( NAV_MESH_AVOID ) then return -1 end

        local dist = 0
        if !isInNoClip and IsValid( ladder ) then
            dist = ladder:GetBottom():Distance( ladder:GetTop() )
        else
            dist = ( length > 0 and length or fromArea:GetCenter():Distance( area:GetCenter() ) )
        end
        local cost = ( fromArea:GetCostSoFar() + dist )

        if !isInNoClip and !IsValid( ladder ) then
            local deltaZ = fromArea:ComputeAdjacentConnectionHeightChange( area )
            if deltaZ > jumpHeight or deltaZ < deathHeight then return -1 end
            if deltaZ > stepHeight then cost = cost + ( dist * jumpPenalty ) end
        end

        return cost
    end
end

-- Approaches a position 
function ENT:Approach( pos, time )
    time = time and CurTime() + time or CurTime() + 1
    self:Hook( "Tick", "approachposition", function()
        if CurTime() > time then return "end" end
        self.loco:Approach( pos, 99 )
    end )
end

local doorClasses = {
    ["prop_door_rotating"] = true,
    ["func_door"] = true,
    ["func_door_rotating"] = true
}

-- Fires a trace in front of the player that will open doors if it hits a door and shoot at breakable obstacles
function ENT:ObstacleCheck()
    if CurTime() < self.l_nextobstaclecheck then return end

    local selfPos = ( self:GetPos() + vector_up * self.loco:GetStepHeight() )
    tracetable.start = selfPos
    tracetable.endpos = ( selfPos + self:GetForward() * 50 )
    tracetable.filter = self
    
    local ent = Trace( tracetable ).Entity
    if IsValid( ent ) then
        local class = ent:GetClass()
        if doorClasses[ class ] and ent.Fire then
            -- Back up when opening a door
            if ent:GetInternalVariable( "m_eDoorState" ) != 0 or ent:GetInternalVariable( "m_toggle_state" ) != 0 then
                self:Approach( self:GetPos() - self:GetForward() * 50, 0.8 )
                --self:WaitWhileMoving( 1.5 )
            end

            if class == "prop_door_rotating" then
                ent:Fire( "OpenAwayFrom", "!activator", 0, self )
                local keys = ent:GetKeyValues()
                local slaveDoor = ents_FindByName( keys.slavename )
                if IsValid( slaveDoor ) then slaveDoor:Fire( "OpenAwayFrom", "!activator", 0, self ) end
            else
                ent:Fire( "Open" )
            end
        elseif ent.Health and ent:Health() > 0 and !ent:IsPlayer() and !ent:IsNPC() and !ent:IsNextBot() then
            if !self:HasLethalWeapon() then self:SwitchToLethalWeapon() end
            self:LookTo( ent, 1.0 )
            self:UseWeapon( ent )
        end
    end

    self.l_nextobstaclecheck = CurTime() + 0.1
end

-- CNavArea --
local CNavAreaMeta            = FindMetaTable( "CNavArea" )
CNavArea_GetCenter            = CNavAreaMeta.GetCenter
CNavArea_GetAdjacentAreas     = CNavAreaMeta.GetAdjacentAreas
CNavArea_ClearSearchLists     = CNavAreaMeta.ClearSearchLists
CNavArea_AddToOpenList        = CNavAreaMeta.AddToOpenList
CNavArea_SetCostSoFar         = CNavAreaMeta.SetCostSoFar
CNavArea_SetTotalCost         = CNavAreaMeta.SetTotalCost
CNavArea_UpdateOnOpenList     = CNavAreaMeta.UpdateOnOpenList
CNavArea_IsOpenListEmpty      = CNavAreaMeta.IsOpenListEmpty
CNavArea_PopOpenList          = CNavAreaMeta.PopOpenList
CNavArea_AddToClosedList      = CNavAreaMeta.AddToClosedList
CNavArea_GetCostSoFar         = CNavAreaMeta.GetCostSoFar
CNavArea_IsOpen               = CNavAreaMeta.IsOpen
CNavArea_IsClosed             = CNavAreaMeta.IsClosed
CNavArea_RemoveFromClosedList = CNavAreaMeta.RemoveFromClosedList
--

-- Vector --
local VectorMeta              = FindMetaTable( "Vector" )
local GetDistToSqr            = VectorMeta.DistToSqr
--

local GetNavArea = navmesh.GetNavArea

-- Using the A* algorithm and navmesh, finds out if we can reach the given area
-- Was created because CLuaLocomotion's 'IsAreaTraversable' seems to be broken
-- Not recommended to use in loops with large tables
-- The area variable can be a vector or a nav area
function ENT:IsAreaTraversable( area, startArea, pathGenerator )
    if isvector( area ) then area = GetNavArea( area, 120 ) end 
    if !IsValid( area ) then return false end

    local myArea = startArea or self.l_currentnavarea
    if isvector( myArea ) then myArea = GetNavArea( myArea, 120 ) end 
    if !IsValid( myArea ) then return false end

    if area == myArea then return true end
    pathGenerator = pathGenerator or self:PathGenerator()

    CNavArea_ClearSearchLists( myArea )
    CNavArea_AddToOpenList( myArea )
    CNavArea_SetCostSoFar( myArea, 0 )

    local areaPos = CNavArea_GetCenter( area )
    CNavArea_SetTotalCost( myArea, GetDistToSqr( CNavArea_GetCenter( myArea ), areaPos ) )

    CNavArea_UpdateOnOpenList( myArea )

    while ( !CNavArea_IsOpenListEmpty( myArea ) ) do
        local curArea = CNavArea_PopOpenList( myArea )
        if curArea == area then return true end

        local adjAreas = CNavArea_GetAdjacentAreas( curArea )
        for i = 1, #adjAreas do
            local newArea = adjAreas[ i ]

            local newCostSoFar = pathGenerator( newArea, curArea, NULL, NULL, -1 )
            if !isnumber( newCostSoFar ) then newCostSoFar = 1e30 end
            if newCostSoFar < 0 then continue end

            if ( CNavArea_IsOpen( newArea ) or CNavArea_IsClosed( newArea ) ) and CNavArea_GetCostSoFar( newArea ) <= newCostSoFar then continue end
            CNavArea_SetCostSoFar( newArea, newCostSoFar )
            CNavArea_SetTotalCost( newArea, newCostSoFar + GetDistToSqr( CNavArea_GetCenter( newArea ), areaPos ) )

            if CNavArea_IsClosed( newArea ) then
                CNavArea_RemoveFromClosedList( newArea )
            end
            
            if CNavArea_IsOpen( newArea ) then
                CNavArea_UpdateOnOpenList( newArea )
            else
                CNavArea_AddToOpenList( newArea )
            end
        end

        CNavArea_AddToClosedList( curArea )
    end

    return false
end