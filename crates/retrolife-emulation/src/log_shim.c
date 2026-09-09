/*
 * Stable C variadic callback bridge for RETRO_ENVIRONMENT_GET_LOG_INTERFACE.
 *
 * Rust can describe a foreign variadic function pointer, but stable Rust cannot
 * define one. The libretro core expects this exact ABI and may call it during
 * startup, so the shim supplies a deliberately silent callback. Suppressing
 * core logs also keeps local paths out of frontend logs.
 */

typedef void (*retrolife_log_printf_t)(int level, const char *format, ...);

struct retrolife_log_callback {
    retrolife_log_printf_t log;
};

static void retrolife_log_printf(int level, const char *format, ...)
{
    (void)level;
    (void)format;
}

void retrolife_fill_log_callback(void *callback)
{
    struct retrolife_log_callback *log = (struct retrolife_log_callback *)callback;
    log->log = retrolife_log_printf;
}
