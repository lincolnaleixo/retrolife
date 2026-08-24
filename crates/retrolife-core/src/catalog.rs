use crate::contracts::{
    SCHEMA_VERSION, canonical_json, parse_versioned, validate_identifier, validate_sha256,
    validate_text,
};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{
    cmp::Ordering,
    collections::{HashMap, HashSet},
    sync::OnceLock,
};

pub const MAX_CATALOG_GAMES: usize = 100_000;
const MAX_ALIASES: usize = 64;
const MAX_GENRES: usize = 32;
const MAX_LANGUAGES: usize = 32;

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum CatalogSource {
    Reference,
    ServerSnapshot,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum ArtworkKind {
    FrontCover,
    Screenshot,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ArtworkReference {
    pub key: String,
    pub kind: ArtworkKind,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct GameAccent {
    pub primary: String,
    pub secondary: String,
}

impl Default for GameAccent {
    fn default() -> Self {
        Self {
            primary: "#5865F2".to_owned(),
            secondary: "#232946".to_owned(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct Game {
    pub id: String,
    pub title: String,
    pub system_id: String,
    pub system_name: String,
    #[serde(default)]
    pub aliases: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub release_year: Option<u16>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub region: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub developer: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub publisher: Option<String>,
    #[serde(default)]
    pub genres: Vec<String>,
    #[serde(default)]
    pub languages: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub players: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub description: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub artwork: Option<ArtworkReference>,
    #[serde(default)]
    pub accent: GameAccent,
    #[serde(default)]
    pub favorite: bool,
    #[serde(default = "default_playable")]
    pub playable: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct SystemSummary {
    pub id: String,
    pub name: String,
    pub game_count: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct Catalog {
    pub schema_version: u32,
    pub source: CatalogSource,
    pub source_label: String,
    pub revision: u64,
    pub games: Vec<Game>,
}

impl Catalog {
    pub fn validate(&self) -> Result<(), String> {
        if self.schema_version != SCHEMA_VERSION {
            return Err(format!(
                "Unsupported catalog schemaVersion {}; expected {SCHEMA_VERSION}",
                self.schema_version
            ));
        }
        validate_text("catalog sourceLabel", &self.source_label, 256)?;
        if self.games.len() > MAX_CATALOG_GAMES {
            return Err(format!(
                "catalog contains {} games; maximum is {MAX_CATALOG_GAMES}",
                self.games.len()
            ));
        }

        let mut game_ids = HashSet::with_capacity(self.games.len());
        let mut systems: HashMap<&str, &str> = HashMap::new();
        for game in &self.games {
            game.validate()?;
            if !game_ids.insert(game.id.as_str()) {
                return Err(format!("catalog game id {} is duplicated", game.id));
            }
            if let Some(existing) = systems.insert(&game.system_id, &game.system_name)
                && existing != game.system_name
            {
                return Err(format!(
                    "system id {} has conflicting names {} and {}",
                    game.system_id, existing, game.system_name
                ));
            }
        }
        Ok(())
    }

    pub fn normalize(mut self) -> Result<Self, String> {
        self.source_label = self.source_label.trim().to_owned();
        for game in &mut self.games {
            game.normalize()?;
        }
        self.games.sort_by(compare_games);
        self.validate()?;
        Ok(self)
    }

    pub fn game(&self, game_id: &str) -> Option<&Game> {
        self.games.iter().find(|game| game.id == game_id)
    }

    pub fn systems(&self) -> Vec<SystemSummary> {
        let mut systems: HashMap<&str, (&str, usize)> = HashMap::new();
        for game in &self.games {
            let entry = systems
                .entry(game.system_id.as_str())
                .or_insert((game.system_name.as_str(), 0));
            entry.1 += 1;
        }

        let mut summaries: Vec<SystemSummary> = systems
            .into_iter()
            .map(|(id, (name, game_count))| SystemSummary {
                id: id.to_owned(),
                name: name.to_owned(),
                game_count,
            })
            .collect();
        summaries.sort_by(|left, right| {
            compare_text(&left.name, &right.name).then_with(|| left.id.cmp(&right.id))
        });
        summaries
    }

    pub fn query<'a>(&'a self, system_id: Option<&str>, search: Option<&str>) -> Vec<&'a Game> {
        let selected_system = system_id.map(str::trim).filter(|value| !value.is_empty());
        let search = search.map(str::trim).filter(|value| !value.is_empty());

        self.games
            .iter()
            .filter(|game| {
                selected_system
                    .map(|system_id| game.system_id.eq_ignore_ascii_case(system_id))
                    .unwrap_or(true)
                    && search.map(|query| game.matches(query)).unwrap_or(true)
            })
            .collect()
    }
}

impl Game {
    pub fn validate(&self) -> Result<(), String> {
        validate_identifier("game id", &self.id, 128)?;
        validate_text("game title", &self.title, 512)?;
        validate_identifier("game systemId", &self.system_id, 64)?;
        validate_text("game systemName", &self.system_name, 128)?;
        validate_text_list("game aliases", &self.aliases, MAX_ALIASES, 512)?;
        validate_optional_text("game region", self.region.as_deref(), 64)?;
        validate_optional_text("game developer", self.developer.as_deref(), 256)?;
        validate_optional_text("game publisher", self.publisher.as_deref(), 256)?;
        validate_text_list("game genres", &self.genres, MAX_GENRES, 128)?;
        validate_text_list("game languages", &self.languages, MAX_LANGUAGES, 32)?;
        validate_optional_text("game players", self.players.as_deref(), 64)?;
        validate_optional_text("game description", self.description.as_deref(), 16_384)?;
        validate_color("game accent primary", &self.accent.primary)?;
        validate_color("game accent secondary", &self.accent.secondary)?;
        if let Some(artwork) = &self.artwork {
            validate_identifier("game artwork key", &artwork.key, 192)?;
        }
        Ok(())
    }

    fn normalize(&mut self) -> Result<(), String> {
        self.id = self.id.trim().to_owned();
        self.title = self.title.trim().to_owned();
        self.system_id = self.system_id.trim().to_owned();
        self.system_name = self.system_name.trim().to_owned();
        trim_optional(&mut self.region);
        trim_optional(&mut self.developer);
        trim_optional(&mut self.publisher);
        trim_optional(&mut self.players);
        trim_optional(&mut self.description);
        normalize_text_list(&mut self.aliases);
        normalize_text_list(&mut self.genres);
        normalize_text_list(&mut self.languages);
        if let Some(artwork) = &mut self.artwork {
            artwork.key = artwork.key.trim().to_owned();
        }
        self.accent.primary = self.accent.primary.trim().to_ascii_uppercase();
        self.accent.secondary = self.accent.secondary.trim().to_ascii_uppercase();
        self.validate()
    }

    fn matches(&self, query: &str) -> bool {
        let query = query.to_lowercase();
        self.title.to_lowercase().contains(&query)
            || self.system_id.to_lowercase().contains(&query)
            || self.system_name.to_lowercase().contains(&query)
            || self
                .developer
                .as_deref()
                .map(|value| value.to_lowercase().contains(&query))
                .unwrap_or(false)
            || self
                .publisher
                .as_deref()
                .map(|value| value.to_lowercase().contains(&query))
                .unwrap_or(false)
            || self
                .aliases
                .iter()
                .chain(self.genres.iter())
                .chain(self.languages.iter())
                .any(|value| value.to_lowercase().contains(&query))
    }
}

pub fn decode(json: &str) -> Result<Catalog, String> {
    let catalog: Catalog = parse_versioned(json, "catalog")?;
    catalog.normalize()
}

pub fn normalize_json(json: &str) -> Result<String, String> {
    canonical_json(&decode(json)?, "catalog")
}

pub fn reference_catalog() -> &'static Catalog {
    static REFERENCE: OnceLock<Catalog> = OnceLock::new();
    REFERENCE.get_or_init(|| {
        decode(include_str!("../fixtures/reference-catalog.json"))
            .expect("the bundled reference catalog must always be valid")
    })
}

pub fn reference_catalog_json() -> String {
    canonical_json(reference_catalog(), "catalog")
        .expect("the bundled reference catalog must always serialize")
}

pub fn from_server_library_json(json: &str) -> Result<Catalog, String> {
    let value: Value = serde_json::from_str(json)
        .map_err(|error| format!("Cannot decode server library snapshot JSON: {error}"))?;
    let page = if value.is_array() {
        ServerLibraryPage {
            games: serde_json::from_value(value)
                .map_err(|error| format!("Cannot decode server library games: {error}"))?,
            next_cursor: None,
        }
    } else {
        serde_json::from_value::<ServerLibraryPage>(value)
            .map_err(|error| format!("Cannot decode server library page: {error}"))?
    };

    if page
        .next_cursor
        .as_deref()
        .map(str::trim)
        .is_some_and(|cursor| !cursor.is_empty())
    {
        return Err(
            "Server library snapshot is incomplete because nextCursor is present; export every page before loading it"
                .to_owned(),
        );
    }
    if page.games.len() > MAX_CATALOG_GAMES {
        return Err(format!(
            "server library snapshot contains {} games; maximum is {MAX_CATALOG_GAMES}",
            page.games.len()
        ));
    }

    let mut games = Vec::with_capacity(page.games.len());
    for source in page.games {
        validate_sha256("server game sha256", &source.sha256)?;
        let artwork = source
            .media
            .box_front
            .or(source.media.screenshot)
            .map(|hash| ArtworkReference {
                key: format!("server-media:{hash}"),
                kind: ArtworkKind::FrontCover,
            });
        let players = source.players.map(|count| match count {
            1 => "1 player".to_owned(),
            _ => format!("{count} players"),
        });
        let accent = accent_from_identity(&source.sha256);
        games.push(Game {
            id: source.sha256,
            title: source.title,
            system_name: system_display_name(&source.system),
            system_id: source.system,
            aliases: source.aliases,
            release_year: source.release_year,
            region: source.region,
            developer: source.developer,
            publisher: source.publisher,
            genres: source.genres,
            languages: source.languages,
            players,
            description: source.summary,
            artwork,
            accent,
            favorite: false,
            playable: true,
        });
    }

    Catalog {
        schema_version: SCHEMA_VERSION,
        source: CatalogSource::ServerSnapshot,
        source_label: "RetroLife Server library snapshot".to_owned(),
        revision: 1,
        games,
    }
    .normalize()
}

fn compare_games(left: &Game, right: &Game) -> Ordering {
    compare_text(&left.title, &right.title)
        .then_with(|| compare_text(&left.system_name, &right.system_name))
        .then_with(|| left.system_id.cmp(&right.system_id))
        .then_with(|| left.id.cmp(&right.id))
}

fn compare_text(left: &str, right: &str) -> Ordering {
    left.to_lowercase()
        .cmp(&right.to_lowercase())
        .then_with(|| left.cmp(right))
}

fn default_playable() -> bool {
    true
}

fn trim_optional(value: &mut Option<String>) {
    if let Some(text) = value {
        *text = text.trim().to_owned();
        if text.is_empty() {
            *value = None;
        }
    }
}

fn normalize_text_list(values: &mut Vec<String>) {
    for value in values.iter_mut() {
        *value = value.trim().to_owned();
    }
    values.retain(|value| !value.is_empty());
    values.sort_by(|left, right| compare_text(left, right));
    values.dedup_by(|left, right| left.eq_ignore_ascii_case(right));
}

fn validate_optional_text(label: &str, value: Option<&str>, maximum: usize) -> Result<(), String> {
    match value {
        Some(value) => validate_text(label, value, maximum),
        None => Ok(()),
    }
}

fn validate_text_list(
    label: &str,
    values: &[String],
    maximum_count: usize,
    maximum_length: usize,
) -> Result<(), String> {
    if values.len() > maximum_count {
        return Err(format!("{label} exceeds {maximum_count} entries"));
    }
    for value in values {
        validate_text(label, value, maximum_length)?;
    }
    Ok(())
}

fn validate_color(label: &str, value: &str) -> Result<(), String> {
    if value.len() != 7
        || !value.starts_with('#')
        || !value[1..].bytes().all(|byte| byte.is_ascii_hexdigit())
    {
        return Err(format!("{label} must use #RRGGBB"));
    }
    Ok(())
}

fn system_display_name(system_id: &str) -> String {
    match system_id.to_ascii_lowercase().as_str() {
        "snes" => "Super Nintendo".to_owned(),
        "nes" => "Nintendo Entertainment System".to_owned(),
        "megadrive" | "genesis" => "Mega Drive".to_owned(),
        "playstation" | "psx" => "PlayStation".to_owned(),
        "n64" => "Nintendo 64".to_owned(),
        "gb" => "Game Boy".to_owned(),
        "gbc" => "Game Boy Color".to_owned(),
        "gba" => "Game Boy Advance".to_owned(),
        "mastersystem" => "Master System".to_owned(),
        "arcade" => "Arcade".to_owned(),
        _ => humanize_identifier(system_id),
    }
}

fn humanize_identifier(value: &str) -> String {
    value
        .split(|character: char| matches!(character, '-' | '_' | '.'))
        .filter(|part| !part.is_empty())
        .map(|part| {
            let mut characters = part.chars();
            match characters.next() {
                Some(first) => first.to_uppercase().collect::<String>() + characters.as_str(),
                None => String::new(),
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

fn accent_from_identity(identity: &str) -> GameAccent {
    let mut hash = 2_166_136_261_u32;
    for byte in identity.bytes() {
        hash ^= u32::from(byte);
        hash = hash.wrapping_mul(16_777_619);
    }
    let primary = (
        80 + (hash & 0x7f) as u8,
        80 + ((hash >> 8) & 0x7f) as u8,
        80 + ((hash >> 16) & 0x7f) as u8,
    );
    let secondary = (
        28 + ((hash >> 4) & 0x3f) as u8,
        28 + ((hash >> 12) & 0x3f) as u8,
        28 + ((hash >> 20) & 0x3f) as u8,
    );
    GameAccent {
        primary: format!("#{:02X}{:02X}{:02X}", primary.0, primary.1, primary.2),
        secondary: format!("#{:02X}{:02X}{:02X}", secondary.0, secondary.1, secondary.2),
    }
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ServerLibraryPage {
    games: Vec<ServerCatalogGame>,
    #[serde(default)]
    next_cursor: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ServerCatalogGame {
    sha256: String,
    #[serde(default)]
    system: String,
    title: String,
    #[serde(default)]
    aliases: Vec<String>,
    #[serde(default)]
    developer: Option<String>,
    #[serde(default)]
    publisher: Option<String>,
    #[serde(default)]
    genres: Vec<String>,
    #[serde(default)]
    region: Option<String>,
    #[serde(default)]
    languages: Vec<String>,
    #[serde(default)]
    players: Option<u16>,
    #[serde(default)]
    summary: Option<String>,
    #[serde(default)]
    release_year: Option<u16>,
    #[serde(default)]
    media: ServerMediaManifest,
}

#[derive(Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ServerMediaManifest {
    #[serde(default)]
    box_front: Option<String>,
    #[serde(default)]
    screenshot: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn game(id: &str, title: &str, system_id: &str, system_name: &str) -> Game {
        Game {
            id: id.to_owned(),
            title: title.to_owned(),
            system_id: system_id.to_owned(),
            system_name: system_name.to_owned(),
            aliases: Vec::new(),
            release_year: Some(1994),
            region: Some("World".to_owned()),
            developer: None,
            publisher: None,
            genres: Vec::new(),
            languages: vec!["en".to_owned()],
            players: Some("1 player".to_owned()),
            description: None,
            artwork: None,
            accent: GameAccent::default(),
            favorite: false,
            playable: true,
        }
    }

    #[test]
    fn reference_catalog_is_valid_normalized_and_realistic() {
        let catalog = reference_catalog();
        assert_eq!(catalog.games.len(), 5);
        assert_eq!(catalog.games[0].id, "chrono-trigger");
        assert_eq!(catalog.games[4].id, "super-metroid");
        assert_eq!(catalog.systems().len(), 3);
        assert!(
            catalog
                .game("ridge-racer")
                .is_some_and(|game| !game.playable)
        );
        assert_eq!(decode(&reference_catalog_json()).unwrap(), *catalog);
    }

    #[test]
    fn duplicate_games_and_conflicting_system_names_are_rejected() {
        let duplicate = Catalog {
            schema_version: SCHEMA_VERSION,
            source: CatalogSource::Reference,
            source_label: "test".to_owned(),
            revision: 1,
            games: vec![
                game("same", "Alpha", "snes", "Super Nintendo"),
                game("same", "Beta", "snes", "Super Nintendo"),
            ],
        };
        assert!(duplicate.normalize().unwrap_err().contains("duplicated"));

        let conflict = Catalog {
            schema_version: SCHEMA_VERSION,
            source: CatalogSource::Reference,
            source_label: "test".to_owned(),
            revision: 1,
            games: vec![
                game("alpha", "Alpha", "snes", "Super Nintendo"),
                game("beta", "Beta", "snes", "SNES"),
            ],
        };
        assert!(conflict.normalize().unwrap_err().contains("conflicting"));
    }

    #[test]
    fn query_is_case_insensitive_and_owned_by_the_core() {
        let catalog = reference_catalog();
        assert_eq!(catalog.query(Some("snes"), None).len(), 2);
        assert_eq!(catalog.query(None, Some("bare knuckle")).len(), 1);
        assert_eq!(catalog.query(None, Some("role-playing")).len(), 1);
        assert_eq!(catalog.query(Some("playstation"), Some("ridge")).len(), 1);
        assert!(catalog.query(Some("snes"), Some("ridge")).is_empty());
    }

    #[test]
    fn server_snapshot_maps_the_existing_contract_and_rejects_partial_pages() {
        let hash = "a".repeat(64);
        let media_hash = "b".repeat(64);
        let snapshot = json!({
            "games": [{
                "sha256": hash,
                "md5": "ignored",
                "system": "snes",
                "title": "Server Game",
                "aliases": ["Remote Alias"],
                "developer": "Studio",
                "publisher": "Publisher",
                "genres": ["Adventure"],
                "region": "World",
                "languages": ["en"],
                "players": 2,
                "summary": "Server-backed catalog details.",
                "releaseYear": 1995,
                "fileName": "Server Game.sfc",
                "size": 1024,
                "media": {"boxFront": media_hash}
            }],
            "nextCursor": null
        });
        let catalog = from_server_library_json(&snapshot.to_string()).unwrap();
        assert_eq!(catalog.source, CatalogSource::ServerSnapshot);
        assert_eq!(catalog.games[0].system_name, "Super Nintendo");
        assert_eq!(catalog.games[0].players.as_deref(), Some("2 players"));
        assert_eq!(
            catalog.games[0].artwork.as_ref().unwrap().key,
            format!("server-media:{media_hash}")
        );

        let partial = json!({"games": [], "nextCursor": "more"});
        assert!(
            from_server_library_json(&partial.to_string())
                .unwrap_err()
                .contains("incomplete")
        );
    }

    #[test]
    fn ten_thousand_game_catalog_remains_deterministic_without_external_io() {
        let mut games = Vec::with_capacity(10_000);
        for index in (0..10_000).rev() {
            let system_id = if index % 2 == 0 { "snes" } else { "megadrive" };
            let system_name = if index % 2 == 0 {
                "Super Nintendo"
            } else {
                "Mega Drive"
            };
            games.push(game(
                &format!("fixture-{index:05}"),
                &format!("Game {index:05}"),
                system_id,
                system_name,
            ));
        }
        let catalog = Catalog {
            schema_version: SCHEMA_VERSION,
            source: CatalogSource::Reference,
            source_label: "large deterministic fixture".to_owned(),
            revision: 1,
            games,
        }
        .normalize()
        .unwrap();

        assert_eq!(catalog.games.len(), 10_000);
        assert_eq!(catalog.games[0].id, "fixture-00000");
        assert_eq!(catalog.games[9_999].id, "fixture-09999");
        assert_eq!(catalog.query(None, Some("Game 09999")).len(), 1);
        assert_eq!(catalog.query(Some("snes"), None).len(), 5_000);
    }
}
