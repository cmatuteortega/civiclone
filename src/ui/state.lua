-- What the parts of the screen share: the game and its picture, the camera,
-- the canvases, the pointer, what is selected, and what is moving.

local S = {
    mode = "title",     -- title, loading, play
    zoomStep = 0,       -- the board's zoom, in whole steps from the window's own
    camx = 0, camy = 0, -- the board picture's pixel at the canvas's top left
    mouse = { x = 0, y = 0, wx = 0, wy = 0 },
    buttons = {},       -- the HUD's buttons this frame, for the pointer
    panels = {},        -- the HUD's panels this frame: clicks on them stop there
    anim = {},          -- per unit id: where it is drawn and how it moves
    effects = {},       -- floating numbers, flashes, the dying
    grid = true,
    touch = false,      -- a touch screen: the HUD adds buttons for what keys do
    phone = false,      -- a phone or tablet: the HUD is drawn bigger, for fingers
    clock = 0,
}

-- Board pixels the window's short edge should be, about: the zoom is the
-- whole number that gives nearest this.
S.SHORT = 250
-- The HUD's pixels, likewise; fewer, so bigger, on a phone.
S.UI_SHORT = 250
S.UI_SHORT_PHONE = 180

return S
