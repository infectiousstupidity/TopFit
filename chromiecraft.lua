-- ChromieCraft baseline data.
--
-- The fork previously bundled presets, talent-rating adjustments, gem candidates, and proc
-- metadata that were either unused or tailored to a different private realm. Keep those inputs
-- empty until they are rebuilt from verified WotLK 3.3.5a / ChromieCraft data.
--
-- Item scanning still reads the gems and enchants that are actually present on an item. Empty
-- socket optimization is intentionally disabled for now because the legacy candidate database
-- did not model profession restrictions, meta activation, or off-color socketing correctly.

TopFit.gemIDs = {}
TopFit.talentRatingBonuses = {}

function TopFit.GetPresets()
    return {}
end
