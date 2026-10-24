/* Original deterministic libretro fixture. Contains no commercial game data. */
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

typedef bool (*environment_fn)(unsigned, void *);
typedef void (*video_fn)(const void *, unsigned, unsigned, size_t);
typedef void (*audio_fn)(int16_t, int16_t);
typedef size_t (*audio_batch_fn)(const int16_t *, size_t);
typedef void (*input_poll_fn)(void);
typedef int16_t (*input_state_fn)(unsigned, unsigned, unsigned, unsigned);
struct system_info { const char *name, *version, *extensions; bool fullpath, extract; };
struct geometry { unsigned width, height, max_width, max_height; float aspect; };
struct timing { double fps, sample_rate; };
struct av_info { struct geometry geometry; struct timing timing; };
struct game_info { const char *path; const void *data; size_t size; const char *meta; };
struct saved_state { uint32_t magic, counter; uint8_t battery[16]; };
static environment_fn environment;
static video_fn video;
static audio_batch_fn audio;
static input_poll_fn poll;
static input_state_fn input;
static struct saved_state state;
static uint8_t ram[128 * 1024];
static bool reject_old, reject_all;
unsigned retro_api_version(void) { return 1; }
void retro_set_environment(environment_fn fn) { environment = fn; }
void retro_set_video_refresh(video_fn fn) { video = fn; }
void retro_set_audio_sample(audio_fn fn) { (void)fn; }
void retro_set_audio_sample_batch(audio_batch_fn fn) { audio = fn; }
void retro_set_input_poll(input_poll_fn fn) { poll = fn; }
void retro_set_input_state(input_state_fn fn) { input = fn; }
void retro_set_controller_port_device(unsigned port, unsigned device) { (void)port; (void)device; }
void retro_init(void) { unsigned format = 1; environment(10, &format); }
void retro_deinit(void) {}
void retro_get_system_info(struct system_info *info) { *info = (struct system_info){"Checkpoint fixture", "1", "sfc", false, false}; }
void retro_get_system_av_info(struct av_info *info) { *info = (struct av_info){{2, 2, 2, 2, 1.0f}, {60.0, 44100.0}}; }
void retro_reset(void) { state.counter = 0; }
bool retro_load_game(const struct game_info *info) {
    if (!info || !info->size) return false;
    memset(&state, 0, sizeof(state)); state.magic = 0x12345678;
    memset(ram, 0, sizeof(ram)); reject_old = false; reject_all = false; return true;
}
void retro_unload_game(void) {}
void retro_run(void) {
    poll();
    if (input(0, 1, 0, 10)) reject_old = true;
    if (input(0, 1, 0, 11)) reject_all = true;
    ++state.counter; state.battery[0] = state.counter; ram[0] = state.counter;
    uint32_t color = ((state.counter & 255) << 16) | 0x1234;
    uint32_t pixels[4] = {color, color, color, color};
    int16_t samples[4] = {100, -100, 100, -100};
    video(pixels, 2, 2, sizeof(uint32_t) * 2); audio(samples, 2);
}
void *retro_get_memory_data(unsigned id) { return id == 0 ? (void *)state.battery : id == 2 ? (void *)ram : NULL; }
size_t retro_get_memory_size(unsigned id) { return id == 0 ? sizeof(state.battery) : id == 2 ? sizeof(ram) : 0; }
#ifndef NO_STATES
size_t retro_serialize_size(void) { return sizeof(state); }
bool retro_serialize(void *bytes, size_t size) { if (size != sizeof(state)) return false; memcpy(bytes, &state, size); return true; }
bool retro_unserialize(const void *bytes, size_t size) {
    state.counter = 999; state.battery[0] = 0xee; /* Deliberately mutate before failure. */
    if (size != sizeof(state)) return false;
    const struct saved_state *incoming = bytes;
    if (incoming->magic != 0x12345678 || reject_all || (reject_old && incoming->counter < 20)) return false;
    memcpy(&state, incoming, size); ram[0] = state.counter; return true;
}
#endif
