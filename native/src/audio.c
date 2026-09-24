/* Jupiter ACE beeper sound, copyright (C) 2026 Edward Patel.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * The emulator thread turns each frame's speaker level changes into samples
 * (audio_render_frame) and writes them to a single-producer/single-consumer ring.
 * The audio device thread reads them (ace_audio_read). Each sample is the average
 * speaker level over its time slice (a box filter against aliasing), passed through
 * a DC-blocking high-pass filter like the ACE's AC-coupled speaker.
 */

#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "ace_internal.h"
#include "ace_miniaudio.h"

#define SAMPLES_PER_FRAME (ACE_AUDIO_SAMPLE_RATE / 50)
#define PRIME_SAMPLES (ACE_AUDIO_SAMPLE_RATE * 40 / 1000)  /* start playing at 40 ms buffered */
#define MAX_SAMPLES (ACE_AUDIO_SAMPLE_RATE * 150 / 1000)   /* drop audio beyond 150 ms */
#define HIGH_PASS 0.995f                                   /* about 35 Hz at 44.1 kHz */
#define OUTPUT_GAIN 0.5f

struct ace_audio_device {
    ma_context context;
    ma_device device;
};

static size_t ring_fill(const ace_machine *m)
{
    return atomic_load_explicit(&m->audio_write, memory_order_acquire) -
           atomic_load_explicit(&m->audio_read, memory_order_acquire);
}

void audio_reset(ace_machine *m)
{
    atomic_store(&m->audio_write, 0);
    atomic_store(&m->audio_read, 0);
    m->audio_hp_x = 0.0f;
    m->audio_hp_y = 0.0f;
    m->audio_primed = 0;
    m->audio_last = 0.0f;
}

void audio_render_frame(ace_machine *m)
{
    const uint32_t *events = m->beeper_events;
    const size_t count = m->beeper_count;
    const float volume = atomic_load_explicit(&m->audio_volume, memory_order_relaxed);
    size_t e = 0;
    int level = m->beeper_frame_start_level;

    size_t write = atomic_load_explicit(&m->audio_write, memory_order_relaxed);
    size_t room = ACE_AUDIO_RING - ring_fill(m);
    int keep = room >= SAMPLES_PER_FRAME; /* if the reader is gone, drop this frame */

    for (unsigned long i = 0; i < SAMPLES_PER_FRAME; i++) {
        unsigned long t0 = i * ACE_TSTATES_PER_FRAME / SAMPLES_PER_FRAME;
        unsigned long t1 = (i + 1) * ACE_TSTATES_PER_FRAME / SAMPLES_PER_FRAME;
        unsigned long t = t0, high = 0;
        while (e < count && (events[e] >> 1) < t1) {
            unsigned long at = events[e] >> 1;
            if (at > t) {
                if (level)
                    high += at - t;
                t = at;
            }
            level = (int)(events[e] & 1);
            e++;
        }
        if (level)
            high += t1 - t;

        float x = (float)high / (float)(t1 - t0);
        float y = HIGH_PASS * (m->audio_hp_y + x - m->audio_hp_x);
        m->audio_hp_x = x;
        m->audio_hp_y = y;
        if (keep)
            m->audio_ring[(write + i) % ACE_AUDIO_RING] = y * OUTPUT_GAIN * volume;
    }
    for (; e < count; e++)
        level = (int)(events[e] & 1);
    m->beeper_frame_start_level = level;

    if (keep)
        atomic_store_explicit(&m->audio_write, write + SAMPLES_PER_FRAME, memory_order_release);
}

size_t ace_audio_read(ace_machine *m, float *out, size_t frames)
{
    if (!m || !out)
        return 0;
    size_t read = atomic_load_explicit(&m->audio_read, memory_order_relaxed);
    size_t fill = ring_fill(m);

    if (fill > MAX_SAMPLES) { /* running behind: skip ahead to the prime level */
        read += fill - PRIME_SAMPLES;
        fill = PRIME_SAMPLES;
    }
    if (!m->audio_primed && fill >= PRIME_SAMPLES)
        m->audio_primed = 1;

    size_t n = 0;
    if (m->audio_primed) {
        for (; n < frames && n < fill; n++)
            out[n] = m->audio_ring[(read + n) % ACE_AUDIO_RING];
        if (n)
            m->audio_last = out[n - 1];
        if (n < frames)
            m->audio_primed = 0; /* ran dry: wait until buffered again */
    }
    /* Fade the last sample instead of jumping to silence, to avoid a click. */
    for (size_t k = n; k < frames; k++) {
        m->audio_last *= 0.995f;
        out[k] = m->audio_last;
    }
    atomic_store_explicit(&m->audio_read, read + n, memory_order_release);
    return n;
}

void ace_audio_set_volume(ace_machine *m, float volume)
{
    if (!m)
        return;
    if (!(volume >= 0.0f))
        volume = 0.0f;
    if (volume > 1.0f)
        volume = 1.0f;
    atomic_store_explicit(&m->audio_volume, volume, memory_order_relaxed);
}

static void data_callback(ma_device *device, void *output, const void *input, ma_uint32 frames)
{
    (void)input;
    ace_audio_read((ace_machine *)device->pUserData, (float *)output, frames);
}

int ace_audio_start(ace_machine *m)
{
    if (!m)
        return 0;
    if (m->audio_device)
        return 1;

    struct ace_audio_device *audio = calloc(1, sizeof(*audio));
    if (!audio)
        return 0;

    ma_device_config config = ma_device_config_init(ma_device_type_playback);
    config.playback.format = ma_format_f32;
    config.playback.channels = 1;
    config.sampleRate = ACE_AUDIO_SAMPLE_RATE;
    config.periodSizeInMilliseconds = 10;
    config.dataCallback = data_callback;
    config.pUserData = m;

    /* iOS: play even with the silent switch on (as iACE 1.x did) but mix with other apps'
     * audio. The default category would be PlayAndRecord, which asks for the microphone. */
    ma_context_config context_config = ma_context_config_init();
    context_config.coreaudio.sessionCategory = ma_ios_session_category_playback;
    context_config.coreaudio.sessionCategoryOptions = ma_ios_session_category_option_mix_with_others;

    audio_reset(m);
    if (ma_context_init(NULL, 0, &context_config, &audio->context) != MA_SUCCESS) {
        free(audio);
        return 0;
    }
    if (ma_device_init(&audio->context, &config, &audio->device) != MA_SUCCESS) {
        ma_context_uninit(&audio->context);
        free(audio);
        return 0;
    }
    if (ma_device_start(&audio->device) != MA_SUCCESS) {
        ma_device_uninit(&audio->device);
        ma_context_uninit(&audio->context);
        free(audio);
        return 0;
    }
    m->audio_device = audio;
    return 1;
}

void ace_audio_stop(ace_machine *m)
{
    if (!m || !m->audio_device)
        return;
    ma_device_uninit(&m->audio_device->device);
    ma_context_uninit(&m->audio_device->context);
    free(m->audio_device);
    m->audio_device = NULL;
    audio_reset(m);
}
