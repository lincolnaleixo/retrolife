use retrolife_library::{Entry, Library};
use serde::Serialize;
use std::path::Path;

const DTO_SCHEMA_VERSION: u32 = 1;
const MAX_PAGE_SIZE: usize = 500;
const MAX_SEARCH_BYTES: usize = 256;
const SYSTEM_ID: &str = "snes";
const SYSTEM_NAME: &str = "Super Nintendo Entertainment System";
const ACCENT_PRIMARY: &str = "#F1C75B";
const ACCENT_SECONDARY: &str = "#252A35";
const SOURCE: &str = "managed-local-library";
const SOURCE_LABEL: &str = "Local library";

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CatalogStatusDto {
    schema_version: u32,
    source: &'static str,
    source_label: &'static str,
    revision: u64,
    total_games: usize,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LibraryViewDto {
    schema_version: u32,
    source: &'static str,
    source_label: &'static str,
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
    id: &'static str,
    name: &'static str,
    game_count: usize,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GameCardDto {
    id: String,
    title: String,
    system_id: &'static str,
    system_name: &'static str,
    release_year: Option<u16>,
    artwork_ref: Option<String>,
    artwork_kind: Option<&'static str>,
    accent_primary: &'static str,
    accent_secondary: &'static str,
    favorite: bool,
    playable: bool,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GameDetailsDto {
    schema_version: u32,
    id: String,
    title: String,
    system_id: &'static str,
    system_name: &'static str,
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
    accent_primary: &'static str,
    accent_secondary: &'static str,
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

pub fn status_json(root: &Path) -> String {
    encode_response(open_library(root).and_then(|library| {
        let entries = library.list().map_err(|error| error.to_string())?;
        Ok(status(&entries))
    }))
}

pub fn view_json(root: &Path, system_id: &str, search: &str, offset: i64, limit: i64) -> String {
    encode_response(open_library(root).and_then(|library| {
        let entries = library.list().map_err(|error| error.to_string())?;
        view(&entries, system_id, search, offset, limit)
    }))
}

pub fn details_json(root: &Path, game_id: &str) -> String {
    encode_response(open_library(root).and_then(|library| {
        let entries = library.list().map_err(|error| error.to_string())?;
        details(&entries, game_id)
    }))
}

pub fn import_json(root: &Path, source: &Path) -> String {
    encode_response(
        open_library(root)
            .and_then(|library| library.import(source).map_err(|error| error.to_string()))
            .map(|entry| ImportDto {
                id: entry.id,
                title: entry.title,
            }),
    )
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct ImportDto {
    id: String,
    title: String,
}

pub fn entry(root: &Path, game_id: &str) -> Result<(Entry, std::path::PathBuf), String> {
    let library = open_library(root)?;
    let entries = library.list().map_err(|error| error.to_string())?;
    let entry = entries
        .into_iter()
        .find(|entry| entry.id == game_id.trim())
        .ok_or_else(|| "The selected game is not in the local library.".to_owned())?;
    let path = library.resolve(&entry).map_err(|error| error.to_string())?;
    Ok((entry, path))
}

fn open_library(root: &Path) -> Result<Library, String> {
    Library::open(root).map_err(|error| error.to_string())
}

fn status(entries: &[Entry]) -> CatalogStatusDto {
    CatalogStatusDto {
        schema_version: DTO_SCHEMA_VERSION,
        source: SOURCE,
        source_label: SOURCE_LABEL,
        revision: revision(entries),
        total_games: entries.len(),
    }
}

fn view(
    entries: &[Entry],
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
    if !selected_system.is_empty() && selected_system != SYSTEM_ID {
        return Err(format!("Unknown system filter {selected_system}"));
    }
    let query = search.trim();
    let query_lower = query.to_lowercase();
    let matches = entries
        .iter()
        .filter(|entry| query.is_empty() || entry.title.to_lowercase().contains(&query_lower))
        .collect::<Vec<_>>();
    let filtered_games = matches.len();
    let games = matches
        .into_iter()
        .skip(offset)
        .take(limit)
        .map(GameCardDto::from)
        .collect::<Vec<_>>();

    Ok(LibraryViewDto {
        schema_version: DTO_SCHEMA_VERSION,
        source: SOURCE,
        source_label: SOURCE_LABEL,
        revision: revision(entries),
        total_games: entries.len(),
        filtered_games,
        offset,
        limit,
        has_more: offset.saturating_add(games.len()) < filtered_games,
        selected_system_id: (!selected_system.is_empty()).then(|| SYSTEM_ID.to_owned()),
        query: query.to_owned(),
        systems: vec![SystemDto {
            id: SYSTEM_ID,
            name: SYSTEM_NAME,
            game_count: entries.len(),
        }],
        games,
    })
}

fn details(entries: &[Entry], game_id: &str) -> Result<GameDetailsDto, String> {
    let game_id = game_id.trim();
    if game_id.is_empty() {
        return Err("gameId cannot be empty".to_owned());
    }
    entries
        .iter()
        .find(|entry| entry.id == game_id)
        .map(GameDetailsDto::from)
        .ok_or_else(|| "The selected game is not in the local library.".to_owned())
}

fn revision(entries: &[Entry]) -> u64 {
    entries.iter().fold(0_u64, |revision, entry| {
        entry.id.as_bytes().iter().fold(revision, |value, byte| {
            value.wrapping_mul(33).wrapping_add(u64::from(*byte))
        })
    })
}

impl From<&Entry> for GameCardDto {
    fn from(entry: &Entry) -> Self {
        Self {
            id: entry.id.clone(),
            title: entry.title.clone(),
            system_id: SYSTEM_ID,
            system_name: SYSTEM_NAME,
            release_year: None,
            artwork_ref: None,
            artwork_kind: None,
            accent_primary: ACCENT_PRIMARY,
            accent_secondary: ACCENT_SECONDARY,
            favorite: false,
            playable: true,
        }
    }
}

impl From<&Entry> for GameDetailsDto {
    fn from(entry: &Entry) -> Self {
        Self {
            schema_version: DTO_SCHEMA_VERSION,
            id: entry.id.clone(),
            title: entry.title.clone(),
            system_id: SYSTEM_ID,
            system_name: SYSTEM_NAME,
            aliases: Vec::new(),
            release_year: None,
            region: None,
            developer: None,
            publisher: None,
            genres: vec!["SNES".to_owned()],
            languages: Vec::new(),
            players: None,
            description: Some("Imported from the local library.".to_owned()),
            artwork_ref: None,
            artwork_kind: None,
            accent_primary: ACCENT_PRIMARY,
            accent_secondary: ACCENT_SECONDARY,
            favorite: false,
            playable: true,
        }
    }
}

fn encode_response<T: Serialize>(result: Result<T, String>) -> String {
    let response = match result {
        Ok(data) => BridgeResponse {
            schema_version: DTO_SCHEMA_VERSION,
            ok: true,
            data: Some(data),
            error: None,
        },
        Err(error) => BridgeResponse::<T> {
            schema_version: DTO_SCHEMA_VERSION,
            ok: false,
            data: None,
            error: Some(error),
        },
    };
    serde_json::to_string(&response).unwrap_or_else(|_| {
        r#"{"schemaVersion":1,"ok":false,"error":"The bridge could not encode its response."}"#
            .to_owned()
    })
}
