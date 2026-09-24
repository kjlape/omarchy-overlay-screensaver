# rigrekt Shader Visual Issues

## Problem
The `rigrekt` shader port renders with:
1. Upside-down display
2. Jittery noisy mess around the edges of the view

## Status
- Shader compiles and loads correctly
- Shader appears in `omarchy-overlay-screensaver shaders` listing
- Shader can be activated without errors
- No GL compilation or runtime errors in journal

## Technical Notes
- Shader works with the standard porting recipe (uniform block, coordinate conversion, iMouse replacement)
- The issue appears to be in coordinate system handling or rendering pipeline interaction
- Original shader uses `vec3 p = iResolution; u = (u+u-p.xy)/p.y;` for coordinate conversion
- May be related to Qt's texture coordinate system handling or the specific rendering algorithm

## Investigation Needed
1. Compare coordinate conversion in `rigrekt.frag` vs working shaders (`universeball`, `hexplasma`)
2. Verify the exact coordinate mapping used in the original shadertoy version
3. Test with different coordinate handling approaches
4. Check if this is a Qt 6 ShaderEffect specific rendering issue

## Files to Check
- `shaders/rigrekt.frag` - coordinate conversion logic
- `shaders/rigrekt.vert` - vertex shader
- Compare with working shaders for coordinate handling patterns