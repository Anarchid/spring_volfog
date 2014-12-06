--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--

function widget:GetInfo()
  return {
    name      = "Volumetric Clouds",
    version   = 3,
    desc      = "Clouds! Wohoo!",
    author    = "Anarchid",
    date      = "november 2014",
    license   = "GNU GPL, v2 or later",
    layer     = -1000,
    enabled   = true
  }
end

local enabled = true;

local GroundFogDefs = {
	color    = {0.26, 0.30, 0.41},
	height   = "50%", --// allows either absolute sizes or in percent of map's MaxHeight
	fogatten = 0.003,
};

local gnd_min, gnd_max = Spring.GetGroundExtremes()

if (GroundFogDefs.height == "auto") then
	GroundFogDefs.height = gnd_max
elseif (GroundFogDefs.height:match("(%d+)%%")) then
	local percent = GroundFogDefs.height:match("(%d+)%%")
	GroundFogDefs.height = gnd_max * (percent / 100)
end

local fogHeight    = GroundFogDefs.height
local fogColor     = GroundFogDefs.color
local fogAtten     = GroundFogDefs.fogatten
local fr,fg,fb     = unpack(fogColor)
local sunDir = {0,0,0}
local sunCol = {1,0,0}

assert(type(fogHeight) == "number")
assert(type(fr) == "number")
assert(type(fg) == "number")
assert(type(fb) == "number")
assert(type(fogAtten) == "number")

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- Automatically generated local definitions

local GL_MODELVIEW           = GL.MODELVIEW
local GL_NEAREST             = GL.NEAREST
local GL_ONE                 = GL.ONE
local GL_ONE_MINUS_SRC_ALPHA = GL.ONE_MINUS_SRC_ALPHA
local GL_PROJECTION          = GL.PROJECTION
local GL_QUADS               = GL.QUADS
local GL_SRC_ALPHA           = GL.SRC_ALPHA
local glBeginEnd             = gl.BeginEnd
local glBlending             = gl.Blending
local glCallList             = gl.CallList
local glColor                = gl.Color
local glColorMask            = gl.ColorMask
local glCopyToTexture        = gl.CopyToTexture
local glCreateList           = gl.CreateList
local glCreateShader         = gl.CreateShader
local glCreateTexture        = gl.CreateTexture
local glDeleteShader         = gl.DeleteShader
local glDeleteTexture        = gl.DeleteTexture
local glDepthMask            = gl.DepthMask
local glDepthTest            = gl.DepthTest
local glGetMatrixData        = gl.GetMatrixData
local glGetShaderLog         = gl.GetShaderLog
local glGetUniformLocation   = gl.GetUniformLocation
local glGetViewSizes         = gl.GetViewSizes
local glLoadIdentity         = gl.LoadIdentity
local glLoadMatrix           = gl.LoadMatrix
local glMatrixMode           = gl.MatrixMode
local glMultiTexCoord        = gl.MultiTexCoord
local glPopMatrix            = gl.PopMatrix
local glPushMatrix           = gl.PushMatrix
local glResetMatrices        = gl.ResetMatrices
local glTexCoord             = gl.TexCoord
local glTexture              = gl.Texture
local glRect                 = gl.Rect
local glUniform              = gl.Uniform
local glUniformMatrix        = gl.UniformMatrix
local glUseShader            = gl.UseShader
local glVertex               = gl.Vertex
local glTranslate            = gl.Translate
local spGetCameraPosition    = Spring.GetCameraPosition
local spGetCameraVectors     = Spring.GetCameraVectors
local spGetWind              = Spring.GetWind
local time                   = Spring.GetGameSeconds
local spGetDrawFrame         = Spring.GetDrawFrame

local function spEcho(words)
	Spring.Echo('<Volumetric Clouds> '..words)
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--
--  Extra GL constants
--

local GL_DEPTH_BITS = 0x0D56

local GL_DEPTH_COMPONENT   = 0x1902
local GL_DEPTH_COMPONENT16 = 0x81A5
local GL_DEPTH_COMPONENT24 = 0x81A6
local GL_DEPTH_COMPONENT32 = 0x81A7
local GL_RGBA32F_ARB       = 0x8814


--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local debugGfx  = false --or true

local GLSLRenderer = true
local forceNonGLSL = false -- force using the non-GLSL renderer
local post83 = true

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

if (gnd_min < 0) then gnd_min = 0 end
if (gnd_max < 0) then gnd_max = 0 end
local vsx, vsy
local mx = Game.mapSizeX
local mz = Game.mapSizeZ
local fog
local CurrentCameraY
local timeNow, timeThen = 0,0

local depthShader
local depthTexture
local fogTexture

local uniformEyePos
local uniformViewPrjInv
local uniformOffset
local uniformSunColor

local offsetX = 0;
local offsetY = 0;
local offsetZ = 0;

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
----a simple plane, very complete, would look good with shadows, reflex and stuff.

local function DrawPlaneModel()
  local layers = (fogHeight - (gnd_min+50)) / 50

  glColor(fr,fg,fb,50*fogAtten)
  glDepthTest(true)
  glBlending(true)

  glBeginEnd(GL_QUADS,function()
    for h = gnd_min+50,fogHeight,50 do
      local l = -mx*4
      local r = mx + mx*4
      local t = -mz*4
      local b = mz + mz*4
      glVertex(l, h, t)
      glVertex(r, h, t)
      glVertex(r, h, b)
      glVertex(l, h, b)
    end
  end)

  glDepthTest(false)
  glBlending(false)
  glColor(1,1,1,1)
end


--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
-- fog rendering

local function FogSlices()
	local h = 8*(math.sin(time()/1.2)) + 30*(math.sin(time()/7.3)) - 30
	glPushMatrix()
		glTranslate(0,h,0)
			glCallList(fog)
	glPopMatrix()
end

local function FogFullscreen()
	local camY = select(2, spGetCameraPosition())
	local inFogH = fogHeight - camY

	if (inFogH > fogHeight * 0.1) then
		glColor(fr,fg,fb, math.min(0.8, inFogH * fogAtten))
		glRect(0,0,vsx,vsy)
		glColor(1,1,1,1)
	end
end


--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function widget:ViewResize()
	vsx, vsy = gl.GetViewSizes()
	if (Spring.GetMiniMapDualScreen()=='left') then
		vsx=vsx/2;
	end
	if (Spring.GetMiniMapDualScreen()=='right') then
		vsx=vsx/2
	end

	if (depthTexture) then
		glDeleteTexture(depthTexture)
	end
	
	if (fogTexture) then
		glDeleteTexture(fogTexture)
	end

	depthTexture = glCreateTexture(vsx, vsy, {
		format = GL_DEPTH_COMPONENT24,
		min_filter = GL_NEAREST,
		mag_filter = GL_NEAREST,
	});
	
	fogTexture = glCreateTexture(vsx/2, vsy/2, {
		min_filter = GL.LINEAR, 
		mag_filter = GL.LINEAR,
		format = GL_RGB16F_ARB, 
		wrap_s = GL.CLAMP, 
		wrap_t = GL.CLAMP,
		fbo = true,
	});

	if (depthTexture == nil) then
		spEcho("Removing fog widget, bad depth texture")
		widgetHandler:RemoveWidget();
	end
end

widget:ViewResize()


--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local vertSrc = [[

  void main(void)
  {
    gl_TexCoord[0] = gl_MultiTexCoord0;
    gl_Position    = gl_Vertex;
  }
]]

local fragSrc = VFS.LoadFile("LuaUI/Widgets/Shaders/fog_frag.glsl"); 

fragSrc = fragSrc:format(fogAtten, fogHeight, fogColor[1], fogColor[2], fogColor[3], mx, mz, gnd_min);


if (post83) then
  fragSrc = '#define USE_INVERSEMATRIX\n' .. fragSrc
end

if (debugGfx) then
  fragSrc = '#define DEBUG_GFX\n' .. fragSrc
end


--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--
--  Vector Math
--

local function cross(a, b)
  return {
    (a[2] * b[3]) - (a[3] * b[2]),
    (a[3] * b[1]) - (a[1] * b[3]),
    (a[1] * b[2]) - (a[2] * b[1])
  }
end

local function add(a, b)
  return {
    a[1] * b[1],
    a[2] * b[2],
    a[3] * b[3]
  }
end

local function dot(a, b)
  return (a[1] * b[1]) + (a[2] * b[2]) + (a[3] * b[3])
end


local function normalize(a)
  local len = math.sqrt((a[1] * a[1]) + (a[2] * a[2]) + (a[3] * a[3]))
  if (len == 0.0) then
    return a
  end
  a[1] = a[1] / len
  a[2] = a[2] / len
  a[3] = a[3] / len
  return { a[1], a[2], a[3] }
end


local function scale(a, s)
  a[1] = a[1] * s
  a[2] = a[2] * s
  a[3] = a[3] * s
  return { a[1], a[2], a[3] }
end



local function fract(x)
	return select(2, math.modf(x,1))
end


--------------------------------------------------------------------------------
--------------------------------------------------------------------------------


--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function widget:Initialize()
	if (enabled) then
		if ((not forceNonGLSL) and Spring.GetMiniMapDualScreen()~='left') then --FIXME dualscreen
			if (not glCreateShader) then
				spEcho("Shaders not found, reverting to non-GLSL widget")
				GLSLRenderer = false
			else
				depthShader = glCreateShader({
					vertex = vertSrc,
					fragment = fragSrc,
					uniformInt = {
						tex0 = 0,
						tex1 = 1,
					},
				});
				
				local sunx, suny, sunz = gl.GetSun('pos');
				local sunr, sung, sunb = gl.GetSun('specular');
				sunDir = normalize({sunx, suny, sunz});
				sunCol = {sunr, sung, sunb};
				
				spEcho(glGetShaderLog())
				if (not depthShader) then	
					spEcho("Bad shader, reverting to non-GLSL widget.")
					GLSLRenderer = false
				else
					uniformEyePos       = glGetUniformLocation(depthShader, 'eyePos')
					uniformViewPrjInv   = glGetUniformLocation(depthShader, 'viewProjectionInv')
					uniformOffset       = glGetUniformLocation(depthShader, 'offset')
					uniformSundir       = glGetUniformLocation(depthShader, 'sundir')
					uniformSunColor     = glGetUniformLocation(depthShader, 'suncolor')
				end
			end
		else
			GLSLRenderer = false
		end
		if (not GLSLRenderer) then
			fog = glCreateList(DrawPlaneModel)
		end
	else
		widgetHandler:RemoveWidget();
	end
end


function widget:Shutdown()
  if (GLSLRenderer) then
    glDeleteTexture(depthTexture)
    if (glDeleteShader) then
      glDeleteShader(depthShader)
    end
  end
end


local dl

local function renderToTextureFunc()
	if (not dl) then
		dl = gl.CreateList(function()
			-- render a full screen quad
			gl.Clear( GL.COLOR_BUFFER_BIT,0,0,0,0);
			glTexture(0, depthTexture)
			glTexture(0, false)
			glTexture(1,"LuaUI/Widgets/Images/rgbnoise.png");
			glTexture(1, false)

			gl.TexRect(-1, -1, 1, 1, 0, 0, 1, 1)

			--// finished
			glUseShader(0)
		end)
	end

	glCallList(dl)
end

local function DrawFogNew()
	--//FIXME handle dualscreen correctly!

	-- copy the depth buffer
	glCopyToTexture(depthTexture, 0, 0, 0, 0, vsx, vsy) --FIXME scale down?

	-- setup the shader and its uniform values
	glUseShader(depthShader)

	-- set uniforms
	local cpx, cpy, cpz = spGetCameraPosition()
	glUniform(uniformEyePos, cpx, cpy, cpz)
	glUniform(uniformOffset, offsetX, offsetY, offsetZ);
	
	glUniform(uniformSundir, sunDir[1], sunDir[2], sunDir[3]);
	glUniform(uniformSunColor, sunCol[1], sunCol[2], sunCol[3]);

	glUniformMatrix(uniformViewPrjInv,  "viewprojectioninverse")

	-- TODO: completely reset the texture before applying shader
	-- TODO: figure out why it disappears in some places
	-- maybe add a switch to make it high-res direct-render
	gl.RenderToTexture(fogTexture, renderToTextureFunc);
end


--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function widget:GameFrame()
	local dx,dy,dz = spGetWind();
	offsetX = offsetX-dx*0.5;
	offsetY = offsetY-0.25-dy*0.25;
	offsetZ = offsetZ-dz*0.5;
	
	local sunx, suny, sunz = gl.GetSun('pos');
	local sunr, sung, sunb = gl.GetSun('diffuse');
	sunDir = normalize({sunx, suny, sunz});
	sunCol = {sunr, sung, sunb};
end

function widget:DrawScreenEffects()
	glBlending(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
	glTexture(fogTexture);
	gl.TexRect(0,0,vsx,vsy,0,0,1,1);
end

function widget:DrawWorld()
	if (debugGfx) then glBlending(GL_SRC_ALPHA, GL_ONE) end
	DrawFogNew()
	if (debugGfx) then glBlending(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA) end
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
