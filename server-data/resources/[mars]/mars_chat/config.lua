ChatConfig = {
    OpenKey = 'T',
    FadeSeconds = 10,        -- messages fade out this long after arriving (chat closed)
    MaxMessages = 100,       -- history kept in the window
    MaxLength = 250,         -- longest message
    SpamSeconds = 0.6,       -- minimum time between two messages per player

    -- plain text without a command goes to people nearby
    LocalRadius = 20.0,

    Commands = {
        -- name      radius (nil = everyone)   label shown before the name   colour
        ooc = { radius = nil,  label = 'OOC',     color = { 170, 170, 170 }, ooc = true,  help = 'Out of character chat (everyone)' },
        f   = { radius = 50.0, label = 'Shout',   color = { 255, 120, 80 },  help = 'Shout (large range)' },
        w   = { radius = 3.0,  label = 'Whisper',   color = { 150, 200, 255 }, help = 'Whisper (very close only)' },
        me  = { radius = 20.0, label = '*',       color = { 200, 130, 255 }, action = true, help = 'Describe an action (e.g. /me opens the door)' },
        ['do'] = { radius = 20.0, label = '**',   color = { 120, 220, 160 }, action = true, help = 'Describe the scene (e.g. /do the door is locked)' },
    },
}
