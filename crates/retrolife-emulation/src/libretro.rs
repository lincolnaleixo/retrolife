use crate::persistence::atomic_write;
use crate::transport::{
    AtomicInputs, AudioRing, INPUT_PORTS, MAX_AUDIO_BUFFER_FRAMES, MAX_VIDEO_BYTES,
    MAX_VIDEO_HEIGHT, MAX_VIDEO_WIDTH, PixelFormat, VideoSlot,
};
use crate::{EmulationError, SessionInfo, StartRequest};
use libloading::Library;
use std::collections::HashMap;
use std::ffi::{CStr, CString, c_char, c_void};
use std::fs::{self, File};
use std::io::Read;
use std::path::{Path, PathBuf};
use std::ptr;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{SystemTime, UNIX_EPOCH};

const RETRO_API_VERSION: u32 = 1;
const RETRO_DEVICE_JOYPAD: u32 = 1;
const RETRO_MEMORY_SAVE_RAM: u32 = 0;
const MAX_CONTENT_BYTES: u64 = 128 * 1024 * 1024;
const MAX_BATTERY_BYTES: usize = 16 * 1024 * 1024;

// Environment commands from libretro.h. The loader intentionally implements
// only frontend responsibilities needed by a local SNES session.
const ENV_GET_OVERSCAN: u32 = 2;
const ENV_GET_CAN_DUPE: u32 = 3;
const ENV_SET_MESSAGE: u32 = 6;
const ENV_SHUTDOWN: u32 = 7;
const ENV_GET_SYSTEM_DIRECTORY: u32 = 9;
const ENV_SET_PIXEL_FORMAT: u32 = 10;
const ENV_GET_VARIABLE: u32 = 15;
const ENV_SET_VARIABLES: u32 = 16;
const ENV_GET_VARIABLE_UPDATE: u32 = 17;
const ENV_SET_SUPPORT_NO_GAME: u32 = 18;
const ENV_GET_CONTENT_DIRECTORY: u32 = 30;
const ENV_GET_SAVE_DIRECTORY: u32 = 31;
const ENV_SET_SYSTEM_AV_INFO: u32 = 32;
const ENV_GET_LOG_INTERFACE: u32 = 27;
const ENV_SET_MEMORY_MAPS: u32 = 36;
const ENV_SET_GEOMETRY: u32 = 37;
const ENV_GET_LANGUAGE: u32 = 39;
const ENV_SET_SUPPORT_ACHIEVEMENTS: u32 = 42;
const ENV_GET_AUDIO_VIDEO_ENABLE: u32 = 47;
const ENV_GET_FASTFORWARDING: u32 = 49;
const ENV_GET_TARGET_REFRESH_RATE: u32 = 50;
const ENV_GET_INPUT_BITMASKS: u32 = 51;
const ENV_GET_CORE_OPTIONS_VERSION: u32 = 52;
const ENV_GET_MESSAGE_INTERFACE_VERSION: u32 = 59;
const ENV_GET_INPUT_MAX_USERS: u32 = 61;
const ENV_SET_CORE_OPTIONS_DISPLAY: u32 = 55;
const ENV_SET_PERFORMANCE_LEVEL: u32 = 8;
const ENV_SET_VARIABLE: u32 = 70;

#[repr(C)]
struct RetroSystemInfo {
    library_name: *const c_char,
    library_version: *const c_char,
    valid_extensions: *const c_char,
    need_fullpath: bool,
    block_extract: bool,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
struct RetroGameGeometry {
    base_width: u32,
    base_height: u32,
    max_width: u32,
    max_height: u32,
    aspect_ratio: f32,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
struct RetroSystemTiming {
    fps: f64,
    sample_rate: f64,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
struct RetroSystemAvInfo {
    geometry: RetroGameGeometry,
    timing: RetroSystemTiming,
}

#[repr(C)]
struct RetroGameInfo {
    path: *const c_char,
    data: *const c_void,
    size: usize,
    meta: *const c_char,
}

#[repr(C)]
struct RetroVariable {
    key: *const c_char,
    value: *const c_char,
}

type EnvironmentCallback = unsafe extern "C" fn(u32, *mut c_void) -> bool;
type VideoCallback = unsafe extern "C" fn(*const c_void, u32, u32, usize);
type AudioSampleCallback = unsafe extern "C" fn(i16, i16);
type AudioBatchCallback = unsafe extern "C" fn(*const i16, usize) -> usize;
type InputPollCallback = unsafe extern "C" fn();
type InputStateCallback = unsafe extern "C" fn(u32, u32, u32, u32) -> i16;
type RetroLogPrintf = unsafe extern "C" fn(i32, *const c_char, ...);

#[repr(C)]
struct RetroLogCallback {
    log: Option<RetroLogPrintf>,
}

unsafe extern "C" {
    fn retrolife_fill_log_callback(callback: *mut RetroLogCallback);
}

type RetroApiVersion = unsafe extern "C" fn() -> u32;
type RetroSetEnvironment = unsafe extern "C" fn(EnvironmentCallback);
type RetroSetVideoRefresh = unsafe extern "C" fn(VideoCallback);
type RetroSetAudioSample = unsafe extern "C" fn(AudioSampleCallback);
type RetroSetAudioSampleBatch = unsafe extern "C" fn(AudioBatchCallback);
type RetroSetInputPoll = unsafe extern "C" fn(InputPollCallback);
type RetroSetInputState = unsafe extern "C" fn(InputStateCallback);
type RetroInit = unsafe extern "C" fn();
type RetroDeinit = unsafe extern "C" fn();
type RetroGetSystemInfo = unsafe extern "C" fn(*mut RetroSystemInfo);
type RetroGetSystemAvInfo = unsafe extern "C" fn(*mut RetroSystemAvInfo);
type RetroSetControllerPortDevice = unsafe extern "C" fn(u32, u32);
type RetroReset = unsafe extern "C" fn();
type RetroRun = unsafe extern "C" fn();
type RetroLoadGame = unsafe extern "C" fn(*const RetroGameInfo) -> bool;
type RetroUnloadGame = unsafe extern "C" fn();
type RetroGetMemoryData = unsafe extern "C" fn(u32) -> *mut c_void;
type RetroGetMemorySize = unsafe extern "C" fn(u32) -> usize;

#[derive(Clone, Copy)]
struct Functions {
    set_environment: RetroSetEnvironment,
    set_video_refresh: RetroSetVideoRefresh,
    set_audio_sample: RetroSetAudioSample,
    set_audio_sample_batch: RetroSetAudioSampleBatch,
    set_input_poll: RetroSetInputPoll,
    set_input_state: RetroSetInputState,
    init: RetroInit,
    deinit: RetroDeinit,
    get_system_info: RetroGetSystemInfo,
    get_system_av_info: RetroGetSystemAvInfo,
    set_controller_port_device: Option<RetroSetControllerPortDevice>,
    reset: RetroReset,
    run: RetroRun,
    load_game: RetroLoadGame,
    unload_game: RetroUnloadGame,
    get_memory_data: Option<RetroGetMemoryData>,
    get_memory_size: Option<RetroGetMemorySize>,
}

struct CallbackState {
    pixel_format: Mutex<PixelFormat>,
    video: Arc<Mutex<VideoSlot>>,
    audio: Arc<Mutex<AudioRing>>,
    inputs: Arc<AtomicInputs>,
    variables: Mutex<HashMap<String, CString>>,
    system_directory: CString,
    save_directory: CString,
    content_directory: CString,
    shutdown_requested: AtomicBool,
    fps: Mutex<f64>,
    sample_rate: Mutex<f64>,
}

impl CallbackState {
    fn new(
        request: &StartRequest,
        save_directory: &Path,
        video: Arc<Mutex<VideoSlot>>,
        audio: Arc<Mutex<AudioRing>>,
        inputs: Arc<AtomicInputs>,
    ) -> Result<Self, EmulationError> {
        let content_directory = request
            .content_path
            .parent()
            .unwrap_or_else(|| Path::new("."));
        let mut variables = HashMap::new();
        for (key, value) in &request.core_options {
            let key = CString::new(key.as_str())
                .map_err(|_| EmulationError::InvalidRequest("core option contains NUL".into()))?;
            let value = CString::new(value.as_str()).map_err(|_| {
                EmulationError::InvalidRequest("core option value contains NUL".into())
            })?;
            variables.insert(key.to_string_lossy().into_owned(), value);
        }

        Ok(Self {
            pixel_format: Mutex::new(PixelFormat::ZeroRgb1555),
            video,
            audio,
            inputs,
            variables: Mutex::new(variables),
            system_directory: path_cstring(request.save_root.as_path(), "system directory")?,
            save_directory: path_cstring(save_directory, "save directory")?,
            content_directory: path_cstring(content_directory, "content directory")?,
            shutdown_requested: AtomicBool::new(false),
            fps: Mutex::new(60.0),
            sample_rate: Mutex::new(48_000.0),
        })
    }
}

static ACTIVE_CALLBACKS: OnceLock<Mutex<Option<Arc<CallbackState>>>> = OnceLock::new();

fn active_callbacks() -> &'static Mutex<Option<Arc<CallbackState>>> {
    ACTIVE_CALLBACKS.get_or_init(|| Mutex::new(None))
}

fn current_callbacks() -> Option<Arc<CallbackState>> {
    active_callbacks().lock().ok()?.clone()
}

fn install_callbacks(state: Arc<CallbackState>) -> Result<(), EmulationError> {
    let mut current = active_callbacks()
        .lock()
        .map_err(|_| EmulationError::Core("callback registry is unavailable".into()))?;
    if current.is_some() {
        return Err(EmulationError::Core(
            "another libretro session is already active".into(),
        ));
    }
    *current = Some(state);
    Ok(())
}

fn clear_callbacks(target: &Arc<CallbackState>) {
    if let Ok(mut current) = active_callbacks().lock()
        && current
            .as_ref()
            .is_some_and(|active| Arc::ptr_eq(active, target))
    {
        *current = None;
    }
}

pub(crate) struct CoreSession {
    functions: Functions,
    _library: Library,
    _rom_data: Vec<u8>,
    _rom_path: CString,
    callback: Arc<CallbackState>,
    battery_path: PathBuf,
    initialized: bool,
    loaded: bool,
}

impl CoreSession {
    pub(crate) fn start(
        request: StartRequest,
        video: Arc<Mutex<VideoSlot>>,
        audio: Arc<Mutex<AudioRing>>,
        inputs: Arc<AtomicInputs>,
    ) -> Result<(Self, SessionInfo), EmulationError> {
        request.validate()?;
        let save_directory = request.save_directory();
        fs::create_dir_all(&save_directory)?;

        let content_bytes = read_bounded_file(&request.content_path, MAX_CONTENT_BYTES)?;

        let callback = Arc::new(CallbackState::new(
            &request,
            &save_directory,
            video,
            audio,
            inputs,
        )?);
        install_callbacks(callback.clone())?;

        let library = match unsafe { Library::new(&request.core_path) } {
            Ok(library) => library,
            Err(error) => {
                clear_callbacks(&callback);
                return Err(EmulationError::Core(format!(
                    "cannot load emulator core: {error}"
                )));
            }
        };
        let functions = match unsafe { load_functions(&library) } {
            Ok(functions) => functions,
            Err(error) => {
                clear_callbacks(&callback);
                return Err(error);
            }
        };
        let api_version = match unsafe { load_api_version(&library) } {
            Ok(version) => version,
            Err(error) => {
                clear_callbacks(&callback);
                return Err(error);
            }
        };
        if api_version != RETRO_API_VERSION {
            clear_callbacks(&callback);
            return Err(EmulationError::Core(format!(
                "unsupported libretro API version {api_version}"
            )));
        }

        let mut lifecycle = CoreLifecycle {
            functions,
            callback: callback.clone(),
            initialized: false,
            loaded: false,
            callback_installed: true,
        };

        unsafe {
            (functions.set_environment)(environment_callback);
            (functions.set_video_refresh)(video_callback);
            (functions.set_audio_sample)(audio_sample_callback);
            (functions.set_audio_sample_batch)(audio_batch_callback);
            (functions.set_input_poll)(input_poll_callback);
            (functions.set_input_state)(input_state_callback);
            (functions.init)();
        }
        lifecycle.initialized = true;

        let mut system_info = RetroSystemInfo {
            library_name: ptr::null(),
            library_version: ptr::null(),
            valid_extensions: ptr::null(),
            need_fullpath: false,
            block_extract: false,
        };
        unsafe { (functions.get_system_info)(&mut system_info) };
        let core_name = c_string_lossy(system_info.library_name, "Unknown Core");
        let core_version = c_string_lossy(system_info.library_version, "Unknown Version");
        validate_content_mode(&system_info)?;
        let rom_path = path_cstring(&request.content_path, "content path")?;
        let rom_data = content_bytes;
        let game_info = RetroGameInfo {
            path: rom_path.as_ptr(),
            data: if rom_data.is_empty() {
                ptr::null()
            } else {
                rom_data.as_ptr().cast()
            },
            size: rom_data.len(),
            meta: ptr::null(),
        };

        if !unsafe { (functions.load_game)(&game_info) } {
            return Err(EmulationError::Core(format!(
                "{core_name} could not load this content"
            )));
        }
        lifecycle.loaded = true;

        if let Some(set_controller) = functions.set_controller_port_device {
            for port in 0..4 {
                unsafe { set_controller(port, RETRO_DEVICE_JOYPAD) };
            }
        }

        let mut av_info = RetroSystemAvInfo::default();
        unsafe { (functions.get_system_av_info)(&mut av_info) };
        validate_geometry(av_info.geometry)?;
        if av_info.timing.fps.is_finite()
            && av_info.timing.fps > 0.0
            && let Ok(mut fps) = callback.fps.lock()
        {
            *fps = av_info.timing.fps;
        }
        if av_info.timing.sample_rate.is_finite()
            && av_info.timing.sample_rate > 0.0
            && let Ok(mut sample_rate) = callback.sample_rate.lock()
        {
            *sample_rate = av_info.timing.sample_rate;
        }

        let battery_path = save_directory.join("battery.srm");
        load_battery(&functions, &battery_path)?;
        let has_battery_ram = memory_size(&functions, RETRO_MEMORY_SAVE_RAM)
            .map(|size| size > 0)
            .unwrap_or(false);
        let pixel_format = callback
            .pixel_format
            .lock()
            .map(|format| format.name())
            .unwrap_or("0rgb1555");
        let info = SessionInfo {
            core_name,
            core_version,
            width: av_info.geometry.base_width,
            height: av_info.geometry.base_height,
            max_width: av_info.geometry.max_width.max(av_info.geometry.base_width),
            max_height: av_info
                .geometry
                .max_height
                .max(av_info.geometry.base_height),
            aspect_ratio: av_info.geometry.aspect_ratio,
            fps: av_info.timing.fps,
            sample_rate: av_info.timing.sample_rate,
            pixel_format,
            has_battery_ram,
        };

        lifecycle.disarm();
        Ok((
            Self {
                functions,
                _library: library,
                _rom_data: rom_data,
                _rom_path: rom_path,
                callback,
                battery_path,
                initialized: true,
                loaded: true,
            },
            info,
        ))
    }

    pub(crate) fn run_frame(&self) -> Result<(), EmulationError> {
        unsafe { (self.functions.run)() };
        if self.callback.shutdown_requested.load(Ordering::Acquire) {
            return Err(EmulationError::Core(
                "the emulator core requested shutdown".into(),
            ));
        }
        Ok(())
    }

    pub(crate) fn reset(&self) {
        unsafe { (self.functions.reset)() };
    }

    pub(crate) fn stop(&mut self) -> Result<usize, EmulationError> {
        // Keep the core loaded when persistence fails. The caller can repair
        // the save destination and retry without losing the in-memory RAM.
        let battery_bytes = self.persist_battery()?;
        self.release_core();
        Ok(battery_bytes)
    }

    fn persist_battery(&self) -> Result<usize, EmulationError> {
        let Some(size) = memory_size(&self.functions, RETRO_MEMORY_SAVE_RAM) else {
            return Ok(0);
        };
        if size == 0 {
            return Ok(0);
        }
        if size > MAX_BATTERY_BYTES {
            return Err(EmulationError::Core(
                "battery RAM exceeds the session safety limit".into(),
            ));
        }
        let Some(pointer) = memory_data(&self.functions, RETRO_MEMORY_SAVE_RAM) else {
            return Err(EmulationError::Core(
                "the core reported invalid battery RAM".into(),
            ));
        };
        if pointer.is_null() {
            return Err(EmulationError::Core(
                "the core reported a null battery RAM pointer".into(),
            ));
        }
        let bytes = unsafe { std::slice::from_raw_parts(pointer.cast::<u8>(), size) };
        atomic_write(&self.battery_path, bytes)?;
        Ok(size)
    }

    fn release_core(&mut self) {
        unsafe {
            if self.loaded {
                (self.functions.unload_game)();
                self.loaded = false;
            }
            if self.initialized {
                (self.functions.deinit)();
                self.initialized = false;
            }
        }
        clear_callbacks(&self.callback);
    }
}

fn validate_content_mode(system_info: &RetroSystemInfo) -> Result<(), EmulationError> {
    if system_info.need_fullpath {
        return Err(EmulationError::Core(
            "core requires full-path content loading; memory-backed content is required".into(),
        ));
    }
    Ok(())
}

impl Drop for CoreSession {
    fn drop(&mut self) {
        // Battery memory belongs to a loaded core. `stop` releases the core
        // before this destructor runs, so never call a memory callback after
        // unload/deinit.
        if self.loaded {
            let _ = self.persist_battery();
        }
        self.release_core();
    }
}

struct CoreLifecycle {
    functions: Functions,
    callback: Arc<CallbackState>,
    initialized: bool,
    loaded: bool,
    callback_installed: bool,
}

impl CoreLifecycle {
    fn disarm(&mut self) {
        self.initialized = false;
        self.loaded = false;
        self.callback_installed = false;
    }
}

impl Drop for CoreLifecycle {
    fn drop(&mut self) {
        unsafe {
            if self.loaded {
                (self.functions.unload_game)();
            }
            if self.initialized {
                (self.functions.deinit)();
            }
        }
        if self.callback_installed {
            clear_callbacks(&self.callback);
        }
    }
}

unsafe fn load_api_version(library: &Library) -> Result<u32, EmulationError> {
    let symbol =
        unsafe { library.get::<RetroApiVersion>(b"retro_api_version\0") }.map_err(|error| {
            EmulationError::Core(format!("core is missing retro_api_version: {error}"))
        })?;
    Ok(unsafe { (*symbol)() })
}

unsafe fn load_functions(library: &Library) -> Result<Functions, EmulationError> {
    macro_rules! required {
        ($name:literal, $type:ty) => {{
            let symbol = unsafe { library.get::<$type>(concat!($name, "\0").as_bytes()) }.map_err(
                |error| EmulationError::Core(format!("core is missing {}: {error}", $name)),
            )?;
            *symbol
        }};
    }
    fn optional<T: Copy>(library: &Library, name: &str) -> Option<T> {
        unsafe {
            library
                .get::<T>(format!("{name}\0").as_bytes())
                .ok()
                .map(|symbol| *symbol)
        }
    }

    Ok(Functions {
        set_environment: required!("retro_set_environment", RetroSetEnvironment),
        set_video_refresh: required!("retro_set_video_refresh", RetroSetVideoRefresh),
        set_audio_sample: required!("retro_set_audio_sample", RetroSetAudioSample),
        set_audio_sample_batch: required!("retro_set_audio_sample_batch", RetroSetAudioSampleBatch),
        set_input_poll: required!("retro_set_input_poll", RetroSetInputPoll),
        set_input_state: required!("retro_set_input_state", RetroSetInputState),
        init: required!("retro_init", RetroInit),
        deinit: required!("retro_deinit", RetroDeinit),
        get_system_info: required!("retro_get_system_info", RetroGetSystemInfo),
        get_system_av_info: required!("retro_get_system_av_info", RetroGetSystemAvInfo),
        set_controller_port_device: optional(library, "retro_set_controller_port_device"),
        reset: required!("retro_reset", RetroReset),
        run: required!("retro_run", RetroRun),
        load_game: required!("retro_load_game", RetroLoadGame),
        unload_game: required!("retro_unload_game", RetroUnloadGame),
        get_memory_data: optional(library, "retro_get_memory_data"),
        get_memory_size: optional(library, "retro_get_memory_size"),
    })
}

fn memory_size(functions: &Functions, id: u32) -> Option<usize> {
    let get_size = functions.get_memory_size?;
    Some(unsafe { get_size(id) })
}

fn memory_data(functions: &Functions, id: u32) -> Option<*mut c_void> {
    let get_data = functions.get_memory_data?;
    Some(unsafe { get_data(id) })
}

fn load_battery(functions: &Functions, path: &Path) -> Result<usize, EmulationError> {
    let Some(size) = memory_size(functions, RETRO_MEMORY_SAVE_RAM) else {
        return Ok(0);
    };
    if size == 0 {
        return Ok(0);
    }
    if size > MAX_BATTERY_BYTES {
        return Err(EmulationError::Core(
            "battery RAM exceeds the session safety limit".into(),
        ));
    }
    let Some(pointer) = memory_data(functions, RETRO_MEMORY_SAVE_RAM) else {
        return Ok(0);
    };
    if pointer.is_null() {
        return Ok(0);
    }
    let bytes = read_optional_bounded_file(path, size as u64)?;
    let count = bytes.len().min(size);
    unsafe {
        ptr::write_bytes(pointer, 0, size);
        ptr::copy_nonoverlapping(bytes.as_ptr(), pointer.cast::<u8>(), count);
    }
    Ok(count)
}

fn read_bounded_file(path: &Path, maximum: u64) -> Result<Vec<u8>, EmulationError> {
    read_bounded_file_inner(path, maximum, false)
}

fn read_optional_bounded_file(path: &Path, maximum: u64) -> Result<Vec<u8>, EmulationError> {
    read_bounded_file_inner(path, maximum, true)
}

fn read_bounded_file_inner(
    path: &Path,
    maximum: u64,
    missing_is_empty: bool,
) -> Result<Vec<u8>, EmulationError> {
    let file = match File::open(path) {
        Ok(file) => file,
        Err(error) if missing_is_empty && error.kind() == std::io::ErrorKind::NotFound => {
            return Ok(Vec::new());
        }
        Err(error) => return Err(error.into()),
    };
    let metadata = file.metadata()?;
    if !metadata.is_file() {
        return Err(EmulationError::InvalidRequest(
            "file path is not a regular file".into(),
        ));
    }
    let maximum = usize::try_from(maximum).map_err(|_| {
        EmulationError::InvalidRequest("file safety limit is unsupported on this platform".into())
    })?;
    let read_limit = maximum.saturating_add(1);
    let capacity = usize::try_from(metadata.len())
        .unwrap_or(maximum)
        .min(maximum);
    let mut bytes = Vec::with_capacity(capacity);
    let mut limited = file.take(read_limit as u64);
    limited.read_to_end(&mut bytes)?;
    if bytes.len() > maximum {
        return Err(EmulationError::InvalidRequest(
            "file exceeds the emulation safety limit".into(),
        ));
    }
    Ok(bytes)
}

fn validate_geometry(geometry: RetroGameGeometry) -> Result<(), EmulationError> {
    if geometry.base_width == 0
        || geometry.base_height == 0
        || geometry.base_width > MAX_VIDEO_WIDTH
        || geometry.base_height > MAX_VIDEO_HEIGHT
    {
        return Err(EmulationError::Core(
            "core reported an unsupported video geometry".into(),
        ));
    }
    Ok(())
}

const RETRO_PIXEL_FORMAT_0RGB1555: u32 = 0;
const RETRO_PIXEL_FORMAT_XRGB8888: u32 = 1;
const RETRO_PIXEL_FORMAT_RGB565: u32 = 2;
const RETRO_DEVICE_ID_JOYPAD_B: u32 = 0;
const RETRO_DEVICE_ID_JOYPAD_R: u32 = 11;

unsafe extern "C" fn environment_callback(command: u32, data: *mut c_void) -> bool {
    let Some(state) = current_callbacks() else {
        return false;
    };

    match command {
        ENV_GET_OVERSCAN => set_bool(data, false),
        ENV_GET_CAN_DUPE => set_bool(data, true),
        ENV_SET_MESSAGE
        | ENV_SET_SUPPORT_NO_GAME
        | ENV_SET_MEMORY_MAPS
        | ENV_SET_SUPPORT_ACHIEVEMENTS
        | ENV_SET_CORE_OPTIONS_DISPLAY
        | ENV_SET_PERFORMANCE_LEVEL => true,
        ENV_SHUTDOWN => {
            state.shutdown_requested.store(true, Ordering::Release);
            true
        }
        ENV_GET_LOG_INTERFACE => fill_log_interface(data),
        ENV_GET_SYSTEM_DIRECTORY => set_pointer(data, state.system_directory.as_ptr()),
        ENV_GET_SAVE_DIRECTORY => set_pointer(data, state.save_directory.as_ptr()),
        ENV_GET_CONTENT_DIRECTORY => set_pointer(data, state.content_directory.as_ptr()),
        ENV_SET_PIXEL_FORMAT => {
            if data.is_null() {
                return false;
            }
            let format = unsafe { *(data.cast::<u32>()) };
            let format = match format {
                RETRO_PIXEL_FORMAT_0RGB1555 => PixelFormat::ZeroRgb1555,
                RETRO_PIXEL_FORMAT_XRGB8888 => PixelFormat::Xrgb8888,
                RETRO_PIXEL_FORMAT_RGB565 => PixelFormat::Rgb565,
                _ => return false,
            };
            if let Ok(mut current) = state.pixel_format.lock() {
                *current = format;
                true
            } else {
                false
            }
        }
        ENV_GET_VARIABLE => get_variable(&state, data),
        ENV_SET_VARIABLES => set_variables(&state, data),
        ENV_GET_VARIABLE_UPDATE => set_bool(data, false),
        ENV_SET_VARIABLE => set_variable(&state, data),
        ENV_SET_SYSTEM_AV_INFO => set_system_av_info(&state, data),
        ENV_SET_GEOMETRY => true,
        ENV_GET_LANGUAGE => set_u32(data, 0),
        ENV_GET_AUDIO_VIDEO_ENABLE => set_u32(data, 3),
        ENV_GET_FASTFORWARDING => set_bool(data, false),
        ENV_GET_TARGET_REFRESH_RATE => set_f32(
            data,
            state.fps.lock().map(|fps| *fps as f32).unwrap_or(60.0),
        ),
        ENV_GET_INPUT_BITMASKS => false,
        ENV_GET_CORE_OPTIONS_VERSION => set_u32(data, 0),
        ENV_GET_MESSAGE_INTERFACE_VERSION => set_u32(data, 0),
        ENV_GET_INPUT_MAX_USERS => set_u32(data, INPUT_PORTS as u32),
        _ => false,
    }
}

fn set_bool(data: *mut c_void, value: bool) -> bool {
    if data.is_null() {
        return false;
    }
    unsafe { *(data.cast::<bool>()) = value };
    true
}

fn set_u32(data: *mut c_void, value: u32) -> bool {
    if data.is_null() {
        return false;
    }
    unsafe { *(data.cast::<u32>()) = value };
    true
}

fn set_f32(data: *mut c_void, value: f32) -> bool {
    if data.is_null() {
        return false;
    }
    unsafe { *(data.cast::<f32>()) = value };
    true
}

fn set_pointer(data: *mut c_void, value: *const c_char) -> bool {
    if data.is_null() {
        return false;
    }
    unsafe { *(data.cast::<*const c_char>()) = value };
    true
}

fn fill_log_interface(data: *mut c_void) -> bool {
    if data.is_null() {
        return false;
    }
    unsafe { retrolife_fill_log_callback(data.cast()) };
    true
}

fn get_variable(state: &CallbackState, data: *mut c_void) -> bool {
    if data.is_null() {
        return false;
    }
    let variable = unsafe { &mut *(data.cast::<RetroVariable>()) };
    let Some(key) = c_str(variable.key) else {
        return false;
    };
    let key = key.to_string_lossy();
    let Ok(variables) = state.variables.lock() else {
        return false;
    };
    let Some(value) = variables.get(key.as_ref()) else {
        variable.value = ptr::null();
        return false;
    };
    variable.value = value.as_ptr();
    true
}

fn set_variables(state: &CallbackState, data: *mut c_void) -> bool {
    if data.is_null() {
        return true;
    }
    let mut cursor = data.cast::<RetroVariable>();
    let Ok(mut variables) = state.variables.lock() else {
        return false;
    };
    loop {
        let variable = unsafe { &*cursor };
        if variable.key.is_null() {
            break;
        }
        let Some(key) = c_str(variable.key) else {
            break;
        };
        let key = key.to_string_lossy().into_owned();
        if let std::collections::hash_map::Entry::Vacant(entry) = variables.entry(key) {
            let default = c_str(variable.value)
                .map(|value| selected_default(value.to_string_lossy().as_ref()))
                .unwrap_or_default();
            if let Ok(default) = CString::new(default) {
                entry.insert(default);
            }
        }
        cursor = unsafe { cursor.add(1) };
    }
    true
}

fn set_variable(state: &CallbackState, data: *mut c_void) -> bool {
    if data.is_null() {
        return false;
    }
    let variable = unsafe { &*(data.cast::<RetroVariable>()) };
    let Some(key) = c_str(variable.key) else {
        return false;
    };
    let Some(value) = c_str(variable.value) else {
        return false;
    };
    let Ok(mut variables) = state.variables.lock() else {
        return false;
    };
    let Ok(value) = CString::new(value.to_bytes()) else {
        return false;
    };
    variables.insert(key.to_string_lossy().into_owned(), value);
    true
}

fn selected_default(declaration: &str) -> String {
    let options = declaration
        .split_once(';')
        .map(|(_, options)| options)
        .unwrap_or(declaration);
    options
        .split('|')
        .next()
        .unwrap_or_default()
        .trim()
        .to_owned()
}

fn set_system_av_info(state: &CallbackState, data: *mut c_void) -> bool {
    if data.is_null() {
        return false;
    }
    let info = unsafe { &*(data.cast::<RetroSystemAvInfo>()) };
    if info.timing.fps.is_finite()
        && info.timing.fps > 0.0
        && let Ok(mut fps) = state.fps.lock()
    {
        *fps = info.timing.fps;
    }
    if info.timing.sample_rate.is_finite()
        && info.timing.sample_rate > 0.0
        && let Ok(mut sample_rate) = state.sample_rate.lock()
    {
        *sample_rate = info.timing.sample_rate;
    }
    true
}

unsafe extern "C" fn video_callback(data: *const c_void, width: u32, height: u32, pitch: usize) {
    let Some(state) = current_callbacks() else {
        return;
    };
    let Ok(format) = state.pixel_format.lock().map(|format| *format) else {
        return;
    };
    if data.is_null() {
        if let Ok(mut video) = state.video.lock() {
            video.publish_duplicate(now_ns());
        }
        return;
    }
    if width == 0 || height == 0 || width > MAX_VIDEO_WIDTH || height > MAX_VIDEO_HEIGHT {
        return;
    }
    let Some(row_bytes) = (width as usize).checked_mul(format.bytes_per_pixel()) else {
        return;
    };
    if pitch < row_bytes {
        return;
    }
    let Some(source_bytes) = pitch
        .checked_mul(height.saturating_sub(1) as usize)
        .and_then(|bytes| bytes.checked_add(row_bytes))
    else {
        return;
    };
    if source_bytes > MAX_VIDEO_BYTES {
        return;
    }
    let Some(output_bytes) = (width as usize)
        .checked_mul(height as usize)
        .and_then(|pixels| pixels.checked_mul(4))
    else {
        return;
    };
    if output_bytes > MAX_VIDEO_BYTES {
        return;
    }
    let mut rgba = vec![0_u8; output_bytes];
    let source = data.cast::<u8>();
    for y in 0..height as usize {
        let source_row = unsafe { std::slice::from_raw_parts(source.add(y * pitch), row_bytes) };
        let output_start = y * width as usize * 4;
        let output_row = &mut rgba[output_start..output_start + width as usize * 4];
        convert_row(source_row, output_row, format);
    }
    if let Ok(mut video) = state.video.lock() {
        video.publish(rgba, width, height, format.name(), now_ns(), false);
    }
}

fn convert_row(source: &[u8], output: &mut [u8], format: PixelFormat) {
    let pixels = output.len() / 4;
    for index in 0..pixels {
        let (red, green, blue) = match format {
            PixelFormat::ZeroRgb1555 => {
                let offset = index * 2;
                let value = u16::from_ne_bytes([source[offset], source[offset + 1]]);
                (
                    expand_5(((value >> 10) & 0x1f) as u8),
                    expand_5(((value >> 5) & 0x1f) as u8),
                    expand_5((value & 0x1f) as u8),
                )
            }
            PixelFormat::Xrgb8888 => {
                let offset = index * 4;
                let value = u32::from_ne_bytes([
                    source[offset],
                    source[offset + 1],
                    source[offset + 2],
                    source[offset + 3],
                ]);
                ((value >> 16) as u8, (value >> 8) as u8, value as u8)
            }
            PixelFormat::Rgb565 => {
                let offset = index * 2;
                let value = u16::from_ne_bytes([source[offset], source[offset + 1]]);
                (
                    expand_5(((value >> 11) & 0x1f) as u8),
                    expand_6(((value >> 5) & 0x3f) as u8),
                    expand_5((value & 0x1f) as u8),
                )
            }
        };
        let offset = index * 4;
        output[offset..offset + 4].copy_from_slice(&[red, green, blue, 255]);
    }
}

const fn expand_5(value: u8) -> u8 {
    (value << 3) | (value >> 2)
}

const fn expand_6(value: u8) -> u8 {
    (value << 2) | (value >> 4)
}

unsafe extern "C" fn audio_sample_callback(left: i16, right: i16) {
    let Some(state) = current_callbacks() else {
        return;
    };
    if let Ok(mut audio) = state.audio.lock() {
        audio.push_interleaved_stereo(&[left, right]);
    }
}

unsafe extern "C" fn audio_batch_callback(data: *const i16, frames: usize) -> usize {
    if data.is_null() || frames == 0 {
        return 0;
    }
    let Some(state) = current_callbacks() else {
        return 0;
    };
    let readable_frames = frames.min(MAX_AUDIO_BUFFER_FRAMES.saturating_mul(2));
    let Some(sample_count) = readable_frames.checked_mul(2) else {
        return 0;
    };
    let samples = unsafe { std::slice::from_raw_parts(data, sample_count) };
    if let Ok(mut audio) = state.audio.lock() {
        audio.push_interleaved_stereo(samples);
    }
    frames
}

unsafe extern "C" fn input_poll_callback() {}

unsafe extern "C" fn input_state_callback(port: u32, device: u32, _index: u32, id: u32) -> i16 {
    if device != RETRO_DEVICE_JOYPAD
        || !(RETRO_DEVICE_ID_JOYPAD_B..=RETRO_DEVICE_ID_JOYPAD_R).contains(&id)
    {
        return 0;
    }
    let Some(state) = current_callbacks() else {
        return 0;
    };
    let bit = 1_u16 << id;
    if state.inputs.get(port as usize) & bit != 0 {
        1
    } else {
        0
    }
}

fn c_str(pointer: *const c_char) -> Option<&'static CStr> {
    if pointer.is_null() {
        None
    } else {
        Some(unsafe { CStr::from_ptr(pointer) })
    }
}

fn now_ns() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos()
        .min(u64::MAX as u128) as u64
}

fn path_cstring(path: &Path, label: &str) -> Result<CString, EmulationError> {
    CString::new(path.to_string_lossy().as_bytes()).map_err(|_| {
        EmulationError::InvalidRequest(format!("{label} contains an unsupported NUL byte"))
    })
}

fn c_string_lossy(pointer: *const c_char, fallback: &str) -> String {
    if pointer.is_null() {
        fallback.to_owned()
    } else {
        unsafe { CStr::from_ptr(pointer) }
            .to_string_lossy()
            .into_owned()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn system_info(need_fullpath: bool) -> RetroSystemInfo {
        RetroSystemInfo {
            library_name: ptr::null(),
            library_version: ptr::null(),
            valid_extensions: ptr::null(),
            need_fullpath,
            block_extract: false,
        }
    }

    #[test]
    fn rejects_full_path_core_mode() {
        let error = validate_content_mode(&system_info(true)).expect_err("full path accepted");
        assert!(matches!(
            error,
            EmulationError::Core(message) if message.contains("memory-backed content is required")
        ));
    }

    #[test]
    fn accepts_memory_backed_core_mode() {
        validate_content_mode(&system_info(false)).expect("memory-backed content rejected");
    }
}
