-- Shared physical dimensions for first-person traversal and model audits.
-- Island/model units are metres; the chibi explorer is deliberately 1.2 m.
return {
    HEIGHT = 1.20,
    EYE_HEIGHT = 1.08,
    RADIUS = 0.14,
    STEP_HEIGHT = 0.52,
    -- Detect a raised surface as soon as the capsule reaches its edge. A
    -- smaller value creates an impossible strip between surface snapping and
    -- the same block's expanded collision volume.
    SURFACE_PADDING = 0.14,
}
