local IsValid = IsValid
local table_insert = table.insert

ENT.l_ToolgunTools = {}

-- Adds a tool function to the list of tools
-- See the functions below for examples on making tools
function AddToolFunctionToLambdaTools( toolname, func )
    local convar = CreateLambdaConvar( "lambdaplayers_tool_allow" .. toolname, 1, true, false, false, "If lambda players can use the " .. toolname .. " tool", 0, 1, { type = "Bool", name = "Allow " .. toolname .. " Tool", category = "Limits and Tool Permissions" } )
    table_insert( ENT.l_ToolgunTools, { toolname, convar, func } )
end


local function UseColorTool( self, target )
    if !IsValid( target ) then return end -- Returning nothing is basically the same as returning false

    self:LookTo( target, 2 )

    coroutine.wait( 1 )
    if !IsValid( target ) then return end -- Because we wait 1 second we must make sure the target is valid

    self:UseWeapon( target:WorldSpaceCenter() ) -- Use the toolgun on the target to fake using a tool
    target:SetColor( ColorRand( false ) )

    return true -- Return true to let the for loop in Chance_Tool know we actually got to use the tool so it can break. All tools must do this
end
AddToolFunctionToLambdaTools( "Color", UseColorTool )


-- Called when all default tools are loaded
-- This hook can be used to add custom tool functions by using AddToolFunctionToLambdaTools()
hook.Run( "LambdaOnToolsLoaded" )
