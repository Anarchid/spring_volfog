#Volumetric Clouds shader widget for SpringRTS

This is a widget for SpringRTS that draws volumetric clouds which scroll with the wind, faster when wind is faster and slower when wind is slower.

It is intended to be used as part of a map's ambience and is not a standalone widget. That is, the target user is mappers and not players.

The original intention is to emulate ground-attached clouds such as fog, dust clouds, or similar, but it should be possible to use it as sky clouds as well.

It requires GLSL compatible hardware and won't work without. Being a widget means that if it is included in a map and then annoys some people, they can turn it off easily and without restarting the game.

Conceptually, it's a bastard child of jK's glsl ground fog in Blueprint's dual_fog gadget, and [this](https://www.shadertoy.com/view/XslGRr).

To use it in your map, paste the entire thing into map's LuaUI/Widgets folder, and apply some config to your mapinfo's `custom` parameters table, like this:

```
custom = {
      clouds = {
         speed = 1, -- multiplier for speed of scrolling with wind
         color    = {0.46, 0.32, 0.2}, -- diffuse color of the fog
         -- all altitude values can be either absolute, in percent, or "auto"
         height   = "90%", -- opacity of fog above and at this altitude will be zero
         bottom = 0, -- no fog below this altitude
         fade_alt = "70%"; -- fog will linearly fade away between this and "height", should be between height and bottom
         scale = 255, -- how large will the clouds be
         opacity = 0.4, -- what it says
         clamp_to_map = true, -- whether fog volume is sliced to fit map, or spreads to horizon
         sun_penetration = 15, -- how much does the sun penetrate the fog
      },
}
```

