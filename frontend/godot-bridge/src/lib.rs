mod catalog;

use godot::classes::Node;
use godot::prelude::*;

struct RetroLifeExtension;

#[gdextension]
unsafe impl ExtensionLibrary for RetroLifeExtension {}

#[derive(GodotClass)]
#[class(init, base=Node)]
struct RetroLifeBackend {
    base: Base<Node>,
}

#[godot_api]
impl RetroLifeBackend {
    #[func]
    fn ping(&self) -> GString {
        let message = format!(
            "RetroLife Rust bridge connected to core {}",
            retrolife_core::version()
        );
        GString::from(message.as_str())
    }

    #[func]
    fn core_version(&self) -> GString {
        GString::from(retrolife_core::version())
    }

    #[func]
    fn default_display_settings_json(&self) -> GString {
        let json = retrolife_core::default_display_settings_json();
        GString::from(json.as_str())
    }

    #[func]
    fn catalog_status_json(&self) -> GString {
        let json = catalog::catalog_status_json();
        GString::from(json.as_str())
    }

    #[func]
    fn reset_reference_catalog_json(&self) -> GString {
        let json = catalog::reset_reference_catalog_json();
        GString::from(json.as_str())
    }

    #[func]
    fn load_server_catalog_snapshot_json(&self, snapshot_json: GString) -> GString {
        let json = catalog::load_server_catalog_snapshot_json(&snapshot_json.to_string());
        GString::from(json.as_str())
    }

    #[func]
    fn catalog_view_json(
        &self,
        system_id: GString,
        search: GString,
        offset: i64,
        limit: i64,
    ) -> GString {
        let json =
            catalog::library_view_json(&system_id.to_string(), &search.to_string(), offset, limit);
        GString::from(json.as_str())
    }

    #[func]
    fn game_details_json(&self, game_id: GString) -> GString {
        let json = catalog::game_details_json(&game_id.to_string());
        GString::from(json.as_str())
    }
}
