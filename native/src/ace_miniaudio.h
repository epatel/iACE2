/* miniaudio configuration for the Jupiter ACE core: playback only, low-level API,
 * and only the backends the app runs on. Include this instead of miniaudio.h. */

#ifndef ACE_MINIAUDIO_H
#define ACE_MINIAUDIO_H

#define MA_NO_DECODING
#define MA_NO_ENCODING
#define MA_NO_GENERATION
#define MA_NO_RESOURCE_MANAGER
#define MA_NO_NODE_GRAPH
#define MA_NO_ENGINE
#define MA_ENABLE_ONLY_SPECIFIC_BACKENDS
#define MA_ENABLE_COREAUDIO
#define MA_ENABLE_AAUDIO
#define MA_ENABLE_OPENSL
#define MA_ENABLE_NULL

#if defined(__APPLE__)
/* Link CoreAudio/AudioToolbox directly instead of loading them at run time. */
#define MA_NO_RUNTIME_LINKING
#endif

#include "../third_party/miniaudio.h"

#endif
