/*
 * fixed_time.c — LD_PRELOAD shim for deterministic clock control.
 *
 * Purpose: When MDL_FIXED_EPOCH is set in the environment, intercept the
 * C-library WALL-CLOCK calls and return a constant value derived from that
 * env var. Monotonic and CPU clocks are left untouched.
 * This freezes DSKDATE/GETTIMEDATE output so that the version-date line and
 * the RANDOM seed in Confusion/mdli runs are reproducible across machines and
 * across time.
 *
 * Usage:
 *   export MDL_FIXED_EPOCH=250776000   # 1977-12-12 12:00:00 UTC
 *   TZ=UTC LD_PRELOAD=/path/to/fixed_time.so mdli ...
 *
 * Build (boot_reference.py compiles it into the per-capture temp dir):
 *   gcc -shared -fPIC -O2 -o fixed_time.so fixed_time.c -ldl
 *
 * Functions intercepted (wall-clock sources only):
 *   - gettimeofday(2)   — primary time source in mdl_builtin_eval_gettimeofday
 *                         and mdl_builtin_eval_gettimedate (macros.cpp)
 *   - time(2)           — POSIX wall-clock time(); defensive
 *   - clock_gettime(2)  — ONLY for CLOCK_REALTIME and CLOCK_REALTIME_COARSE.
 *                         Every other clock (CLOCK_MONOTONIC*, CLOCK_BOOTTIME,
 *                         CLOCK_PROCESS_CPUTIME_ID, ...) falls through to libc
 *                         so timeouts, sleeps and CPU-time accounting keep
 *                         working normally.
 *
 * localtime_r is NOT intercepted: GETTIMEDATE calls localtime_r on the tv_sec
 * returned by gettimeofday. The capture tool sets TZ=UTC in the child
 * environment, so localtime_r is a deterministic function of the frozen
 * tv_sec. getrusage (MDL <TIME>, CPU seconds) is not a wall clock and is not
 * intercepted.
 *
 * If MDL_FIXED_EPOCH is unset or empty, all calls fall through to the real
 * libc implementations; this shim has zero effect when inactive.
 *
 * License: MIT-0 (compatible with the harness; Confusion itself is GPLv3).
 */

#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <sys/time.h>
#include <errno.h>

/* Lazily resolve the real libc symbol. */
#define REAL(sym, rettype, ...) \
    static rettype (*real_##sym)(__VA_ARGS__) = NULL; \
    if (!real_##sym) { \
        real_##sym = dlsym(RTLD_NEXT, #sym); \
        if (!real_##sym) { errno = ENOSYS; return -1; } \
    }

/* Return the MDL_FIXED_EPOCH value, or -1 if unset/empty/invalid. */
static time_t fixed_epoch(void)
{
    const char *env = getenv("MDL_FIXED_EPOCH");
    if (!env || !*env) return (time_t)-1;
    char *end;
    long long v = strtoll(env, &end, 10);
    if (*end != '\0') return (time_t)-1;
    return (time_t)v;
}

/* Intercept gettimeofday — primary clock for Confusion GETTIMEDATE/DSKDATE. */
int gettimeofday(struct timeval *tv, void *tz)
{
    REAL(gettimeofday, int, struct timeval *, void *);
    time_t epoch = fixed_epoch();
    if (epoch == (time_t)-1) return real_gettimeofday(tv, tz);
    if (tv) { tv->tv_sec = epoch; tv->tv_usec = 0; }
    return 0;
}

/* Intercept time() — occasionally called by libc internals. */
time_t time(time_t *tloc)
{
    REAL(time, time_t, time_t *);
    time_t epoch = fixed_epoch();
    if (epoch == (time_t)-1) return real_time(tloc);
    if (tloc) *tloc = epoch;
    return epoch;
}

/* Intercept clock_gettime() — wall-clock (CLOCK_REALTIME*) ids only. */
int clock_gettime(clockid_t clk_id, struct timespec *tp)
{
    REAL(clock_gettime, int, clockid_t, struct timespec *);
    time_t epoch = fixed_epoch();
    if (epoch == (time_t)-1) return real_clock_gettime(clk_id, tp);
    switch (clk_id) {
    case CLOCK_REALTIME:
#ifdef CLOCK_REALTIME_COARSE
    case CLOCK_REALTIME_COARSE:
#endif
        if (tp) { tp->tv_sec = epoch; tp->tv_nsec = 0; }
        return 0;
    default:
        /* CLOCK_MONOTONIC and all other clocks are deliberately NOT frozen. */
        return real_clock_gettime(clk_id, tp);
    }
}
