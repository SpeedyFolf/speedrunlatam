SASS modifies both the alpha and dimension of elements.

If you have a map that modifies those in any way or form on a player or vehicle, please set the custom element data `sass.ignore` to `true .

Example:

```lua
setElementData(localPlayer, 'sass.ignore', 'true')

local myCoolVehicle = createVehicle(...)
setElementData(myCoolVehicle, 'sass.ignore', 'true')
```
