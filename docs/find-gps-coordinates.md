# How To Find GPS Coordinates

This guide helps you find the values you need for the approved `ALLOW` location.

You need three things:

- latitude
- longitude
- radius

## The Easiest Way

Use Apple Maps or Google Maps on your Mac.

## Option 1: Apple Maps

1. Open Apple Maps
2. Search for your approved place
3. Zoom in until you are centered on the building or location you want
4. Right-click the exact spot
5. Look for the location details
6. Copy the latitude and longitude

## Option 2: Google Maps

1. Open Google Maps in your browser
2. Search for your approved place
3. Right-click the exact spot
4. Google Maps will show the coordinates
5. Copy them

## Where To Put Them

Open:

- `~/.hammerspoon/config/default.lua`

Find:

```lua
lab_geofence = {
    latitude = 0,
    longitude = 0,
    radius = 0,
}
```

Replace those values with your own.

## Choosing A Radius

Radius is measured in meters.

Simple advice:

- small building: start around `50`
- medium building area: start around `75`
- larger area: start around `100`

If the system switches too often near the edge, the radius may be too small.

## Best First Choice

For most users, a medium-sized radius is safer than a tiny one.

Start with a radius that is forgiving, then make it smaller later if needed.

## How To Test

1. save the settings
2. reload Hammerspoon
3. stand clearly inside the approved place
4. stand clearly outside the approved place
5. check whether the mode changes correctly

## Common Mistakes

- copying the wrong spot from the map
- using too small a radius
- testing too close to the edge
- forgetting to enable Location Services for Hammerspoon
