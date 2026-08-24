extends SceneTree

const ExtensionLoader = preload("res://scripts/extension_loader.gd")
const CatalogClient = preload("res://scripts/catalog_client.gd")


func _initialize() -> void:
    var extension_error := ExtensionLoader.ensure_loaded()
    if not extension_error.is_empty():
        _fail(extension_error)
        return

    var backend := ClassDB.instantiate("RetroLifeBackend") as Node
    if backend == null:
        _fail("RetroLifeBackend could not be instantiated.")
        return
    root.add_child(backend)

    var core_version := str(backend.call("core_version"))
    if core_version.is_empty():
        _fail("The Rust bridge returned an empty core version.")
        return
    if not str(backend.call("ping")).contains(core_version):
        _fail("The Rust bridge ping did not include the active core version.")
        return

    var catalog := CatalogClient.new(backend)
    var reset: Dictionary = catalog.reset_reference()
    if not bool(reset.get("ok", false)):
        _fail(str(reset.get("error", "Reference catalog reset failed.")))
        return

    var view: Dictionary = catalog.view("", "", 0, 500)
    if not _expect_ok(view, "reference catalog view"):
        return
    var data: Dictionary = view.get("data", {})
    if int(data.get("totalGames", -1)) != 5:
        _fail("Expected 5 reference games: %s" % data)
        return
    if int((data.get("systems", []) as Array).size()) != 3:
        _fail("Expected 3 reference systems: %s" % data)
        return

    var snes: Dictionary = catalog.view("snes", "", 0, 500)
    if not _expect_ok(snes, "SNES filter"):
        return
    if int((snes.get("data", {}) as Dictionary).get("filteredGames", -1)) != 2:
        _fail("SNES filter did not return two games.")
        return

    var alias_search: Dictionary = catalog.view("", "bare knuckle", 0, 500)
    if not _expect_ok(alias_search, "alias search"):
        return
    var alias_games: Array = (alias_search.get("data", {}) as Dictionary).get("games", [])
    if alias_games.size() != 1 \
        or str((alias_games[0] as Dictionary).get("id", "")) != "streets-of-rage-2":
        _fail("The Rust core did not own alternate-title search.")
        return

    var details: Dictionary = catalog.details("ridge-racer")
    if not _expect_ok(details, "game details"):
        return
    if bool((details.get("data", {}) as Dictionary).get("playable", true)):
        _fail("Ridge Racer should be presentation-only in the reference catalog.")
        return

    var snapshot := _server_snapshot_json()
    var loaded: Dictionary = catalog.load_server_snapshot_text(snapshot)
    if not _expect_ok(loaded, "server snapshot load"):
        return
    var server_view: Dictionary = catalog.view("", "remote alias", 0, 500)
    if not _expect_ok(server_view, "server snapshot search"):
        return
    var server_data: Dictionary = server_view.get("data", {})
    if int(server_data.get("totalGames", -1)) != 1 \
        or str(server_data.get("source", "")) != "serverSnapshot":
        _fail("The server snapshot did not replace the in-process catalog.")
        return

    var rejected: Dictionary = catalog.load_server_snapshot_text(
        '{"games":[],"nextCursor":"more"}'
    )
    if bool(rejected.get("ok", true)):
        _fail("An incomplete server snapshot was accepted.")
        return
    var rollback: Dictionary = catalog.status()
    if not _expect_ok(rollback, "catalog rollback status"):
        return
    if int((rollback.get("data", {}) as Dictionary).get("totalGames", -1)) != 1:
        _fail("An invalid snapshot changed the active catalog.")
        return

    catalog.reset_reference()
    backend.queue_free()
    print(
        "RETROLIFE_CATALOG_SMOKE_OK core=%s games=5 systems=3 snapshot=true rollback=true"
        % core_version
    )
    quit(0)


func _expect_ok(response: Dictionary, context: String) -> bool:
    if bool(response.get("ok", false)):
        return true
    _fail("%s failed: %s" % [context, response.get("error", "unknown error")])
    return false


func _server_snapshot_json() -> String:
    return JSON.stringify({
        "games": [{
            "sha256": "a".repeat(64),
            "system": "snes",
            "title": "Remote Game",
            "aliases": ["Remote Alias"],
            "developer": "Remote Studio",
            "publisher": "Remote Publisher",
            "genres": ["Adventure"],
            "region": "World",
            "languages": ["en"],
            "players": 2,
            "summary": "Loaded from a server-shaped file snapshot.",
            "releaseYear": 1996,
            "media": {"boxFront": "b".repeat(64)},
        }],
        "nextCursor": null,
    })


func _fail(message: String) -> void:
    push_error("RETROLIFE_CATALOG_SMOKE_FAILED: %s" % message)
    quit(1)
