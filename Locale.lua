-- Light Council – Sprachen
--
-- Alle sichtbaren Texte stehen im Code auf Deutsch und werden über L["…"] übersetzt.
-- Fehlt eine Übersetzung, erscheint der deutsche Text. Übersetzungen: Locales\*.lua
--   L["Text"]            -> übersetzter Text
--   L("Text %d", wert)   -> übersetzter Text mit string.format
local _, LC = ...

-- Auswahl in den Einstellungen (Reihenfolge = Anzeige)
LC.LANGUAGES = {
    { key = "auto", label = "Auto" },
    { key = "deDE", label = "Deutsch" },
    { key = "enUS", label = "English" },
    { key = "frFR", label = "Français" },
    { key = "esES", label = "Español" },
    { key = "ruRU", label = "Русский" },
}

local tables = {}      -- [Sprache] = { [deutscher Text] = Übersetzung }
local current          -- aktive Tabelle (nil = Deutsch)
local resolved = false

function LC:RegisterLocale(lang, t)
    tables[lang] = t
end

local ALIASES = { enGB = "enUS", esMX = "esES" }

-- "auto" = Sprache des Spielclients; nicht unterstützte Sprachen bekommen Englisch
function LC:ResolveLanguage(choice)
    local lang = choice
    if not lang or lang == "auto" then
        lang = GetLocale and GetLocale() or "enUS"
        lang = ALIASES[lang] or lang
    end
    if lang == "deDE" or tables[lang] then return lang end
    return "enUS"
end

function LC:SetLanguage(choice)
    self.lang = self:ResolveLanguage(choice)
    current = tables[self.lang]
    resolved = true
end

local function Lookup(key)
    if not resolved then
        LC:SetLanguage(LC.db and LC.db.config and LC.db.config.language or "auto")
    end
    local v = current and current[key]
    if v == nil then return key end
    return v
end

LC.L = setmetatable({}, {
    __index = function(_, key) return Lookup(key) end,
    __call = function(_, key, ...) return string.format(Lookup(key), ...) end,
})
