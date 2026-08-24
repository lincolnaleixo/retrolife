use retrolife_core::{Catalog, CatalogSource, Game, SystemSummary};
use serde::Serialize;
use std::sync::{OnceLock, RwLock};

const DTO_SCHEMA_VERSION: u32 = 1;
const MAX_PAGE_SIZE: usize = 500;
const MAX_SEARCH_BYTES: usize = 256;

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CatalogStatusDto {
    schema_version: u32,
    source: &'static str,
    source_label: String,
    revision: u64,
    total_games: usize,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LibraryViewDto {
    schema_version: u32,
    source: &'static str,
    source_label: String,
    revision: u64,
    total_games: usize,
    filtered_games: usize,
    offset: usize,
    limit: usize,
    has_more: bool,
    selected_system_id: Option<String>,
    query: String,
    systems: Vec<SystemDto>,
    games: Vec<GameCardDto>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SystemDto {
    id: String,
    name: String,
    game_count: usize,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GameCardDto {
    id: String,
    title: String,
    system_id: String,
    system_name: String,
    release_year: Option<u16>,
    artwork_ref: Option<String>,
    artwork_kind: Option<&'static str>,
    accent_primary: String,
    accent_secondary: String,
    favorite: bool,
    playable: bool,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GameDetailsDto {
    schema_version: u32,
    id: String,
    title: String,
    system_id: String,
    system_name: String,
    aliases: Vec<String>,
    release_year: Option<u16>,
    region: Option<String>,
    developer: Option<String>,
    publisher: Option<String>,
    genres: Vec<String>,
    languages: Vec<String>,
    players: Option<String>,
    description: Option<String>,
    artwork_ref: Option<String>,
    artwork_kind: Option<&'static str>,
    accent_primary: String,
    accent_secondary: String,
    favorite: bool,
    playable: bool,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct BridgeResponse<T: Serialize> {
    schema_version: u32,
    ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    data: Option<T>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
}

pub fn catalog_status_json() -> String {
    encode_response(with_catalog(|catalog| Ok(catalog_status(catalog))))
}

pub fn reset_reference_catalog_json() -> String {
    let result = (|| {
        let mut catalog = catalog_store()
            .write()
            .map_err(|_| "The catalog store is unavailable".to_owned())?;
        *catalog = retrolife_core::reference_catalog().clone();
        Ok(catalog_status(&catalog))
    })();
    encode_response(result)
}

pub fn load_server_catalog_snapshot_json(json: &str) -> String {
    let result = (|| {
        let replacement = retrolife_core::catalog_from_server_library_json(json)?;
        let mut catalog = catalog_store()
            .write()
            .map_err(|_| "The catalog store is unavailable".to_owned())?;
        *catalog = replacement;
        Ok(catalog_status(&catalog))
    })();
    encode_response(result)
}

pub fn library_view_json(system_id: &str, search: &str, offset: i64, limit: i64) -> String {
    encode_response(with_catalog(|catalog| {
        library_view(catalog, system_id, search, offset, limit)
    }))
}

pub fn game_details_json(game_id: &str) -> String {
    encode_response(with_catalog(|catalog| game_details(catalog, game_id)))
}

fn catalog_store() -> &'static RwLock<Catalog> {
    static STORE: OnceLock<RwLock<Catalog>> = OnceLock::new();
    STORE.get_or_init(|| RwLock::new(retrolife_core::reference_catalog().clone()))
}

fn with_catalog<T>(operation: impl FnOnce(&Catalog) -> Result<T, String>) -> Result<T, String> {
    let catalog = catalog_store()
        .read()
        .map_err(|_| "The catalog store is unavailable".to_owned())?;
    operation(&catalog)
}

fn catalog_status(catalog: &Catalog) -> CatalogStatusDto {
    CatalogStatusDto {
        schema_version: DTO_SCHEMA_VERSION,
        source: source_name(catalog.source),
        source_label: catalog.source_label.clone(),
        revision: catalog.revision,
        total_games: catalog.games.len(),
    }
}

fn library_view(
    catalog: &Catalog,
    system_id: &str,
    search: &str,
    offset: i64,
    limit: i64,
) -> Result<LibraryViewDto, String> {
    let offset = usize::try_from(offset).map_err(|_| "offset cannot be negative".to_owned())?;
    let limit = usize::try_from(limit).map_err(|_| "limit cannot be negative".to_owned())?;
    if !(1..=MAX_PAGE_SIZE).contains(&limit) {
        return Err(format!("limit must be between 1 and {MAX_PAGE_SIZE}"));
    }
    if search.len() > MAX_SEARCH_BYTES {
        return Err(format!("search exceeds {MAX_SEARCH_BYTES} bytes"));
    }
    if search.chars().any(char::is_control) {
        return Err("search contains a control character".to_owned());
    }

    let selected_system = system_id.trim();
    if !selected_system.is_empty()
        && !catalog
            .systems()
            .iter()
            .any(|system| system.id == selected_system)
    {
        return Err(format!("Unknown system filter {selected_system}"));
    }

    let matches = catalog.query(
        (!selected_system.is_empty()).then_some(selected_system),
        (!search.trim().is_empty()).then_some(search),
    );
    let filtered_games = matches.len();
    let games = matches
        .into_iter()
        .skip(offset)
        .take(limit)
        .map(GameCardDto::from)
        .collect::<Vec<_>>();
    let has_more = offset.saturating_add(games.len()) < filtered_games;

    Ok(LibraryViewDto {
        schema_version: DTO_SCHEMA_VERSION,
        source: source_name(catalog.source),
        source_label: catalog.source_label.clone(),
        revision: catalog.revision,
        total_games: catalog.games.len(),
        filtered_games,
        offset,
        limit,
        has_more,
        selected_system_id: (!selected_system.is_empty()).then(|| selected_system.to_owned()),
        query: search.trim().to_owned(),
        systems: catalog.systems().into_iter().map(SystemDto::from).collect(),
        games,
    })
}

fn game_details(catalog: &Catalog, game_id: &str) -> Result<GameDetailsDto, String> {
    let game_id = game_id.trim();
    if game_id.is_empty() {
        return Err("gameId cannot be empty".to_owned());
    }
    let game = catalog
        .game(game_id)
        .ok_or_else(|| format!("Unknown game {game_id}"))?;
    Ok(GameDetailsDto::from(game))
}

fn encode_response<T: Serialize>(result: Result<T, String>) -> String {
    let response = match result {
        Ok(data) => BridgeResponse {
            schema_version: DTO_SCHEMA_VERSION,
            ok: true,
            data: Some(data),
            error: None,
        },
        Err(error) => BridgeResponse {
            schema_version: DTO_SCHEMA_VERSION,
            ok: false,
            data: None,
            error: Some(error),
        },
    };
    serde_json::to_string(&response).expect("bridge responses must always serialize")
}

fn source_name(source: CatalogSource) -> &'static str {
    match source {
        CatalogSource::Reference => "reference",
        CatalogSource::ServerSnapshot => "serverSnapshot",
    }
}

fn artwork_kind(game: &Game) -> Option<&'static str> {
    game.artwork.as_ref().map(|artwork| match artwork.kind {
        retrolife_core::ArtworkKind::FrontCover => "frontCover",
        retrolife_core::ArtworkKind::Screenshot => "screenshot",
    })
}

impl From<SystemSummary> for SystemDto {
    fn from(value: SystemSummary) -> Self {
        Self {
            id: value.id,
            name: value.name,
            game_count: value.game_count,
        }
    }
}

impl From<&Game> for GameCardDto {
    fn from(game: &Game) -> Self {
        Self {
            id: game.id.clone(),
            title: game.title.clone(),
            system_id: game.system_id.clone(),
            system_name: game.system_name.clone(),
            release_year: game.release_year,
            artwork_ref: game.artwork.as_ref().map(|artwork| artwork.key.clone()),
            artwork_kind: artwork_kind(game),
            accent_primary: game.accent.primary.clone(),
            accent_secondary: game.accent.secondary.clone(),
            favorite: game.favorite,
            playable: game.playable,
        }
    }
}

impl From<&Game> for GameDetailsDto {
    fn from(game: &Game) -> Self {
        Self {
            schema_version: DTO_SCHEMA_VERSION,
            id: game.id.clone(),
            title: game.title.clone(),
            system_id: game.system_id.clone(),
            system_name: game.system_name.clone(),
            aliases: game.aliases.clone(),
            release_year: game.release_year,
            region: game.region.clone(),
            developer: game.developer.clone(),
            publisher: game.publisher.clone(),
            genres: game.genres.clone(),
            languages: game.languages.clone(),
            players: game.players.clone(),
            description: game.description.clone(),
            artwork_ref: game.artwork.as_ref().map(|artwork| artwork.key.clone()),
            artwork_kind: artwork_kind(game),
            accent_primary: game.accent.primary.clone(),
            accent_secondary: game.accent.secondary.clone(),
            favorite: game.favorite,
            playable: game.playable,
        }
    }
}
