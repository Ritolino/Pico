#include "CShim.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <math.h>
#include <dlfcn.h>
#include <pthread.h>
#include <time.h>
#include <sys/sysctl.h>
#include <libproc.h>
#include <sys/proc_info.h>
#include <mach/mach.h>
#include <mach/processor_info.h>
#include <mach/mach_host.h>
#include <IOKit/IOKitLib.h>
#include <CoreFoundation/CoreFoundation.h>

static io_service_t g_gpu_service = IO_OBJECT_NULL;
static char g_gpu_class_name[64] = {0};
static uint64_t g_cached_memsize = 0;

static io_service_t g_smc_service = IO_OBJECT_NULL;
static io_connect_t g_smc_conn = IO_OBJECT_NULL;

typedef struct {
    char major; char minor; char build; char reserved; uint16_t release;
} SMCVersion;

typedef struct {
    uint16_t version; uint16_t length; uint32_t cpuPLimit; uint32_t gpuPLimit; uint32_t memPLimit;
} SMCPLimitData;

typedef struct {
    uint32_t dataSize; uint32_t dataType; uint8_t dataAttributes;
} SMCKeyInfoData;

typedef struct {
    uint32_t key;
    SMCVersion vers;
    SMCPLimitData pLimitData;
    SMCKeyInfoData keyInfo;
    uint8_t result;
    uint8_t status;
    uint8_t data8;
    uint32_t data32;
    uint8_t bytes[32];
} SMCParamStruct;

#define SMC_CMD_READ_KEYINFO 9
#define SMC_CMD_READ_BYTES   5
#define SMC_CMD_READ_INDEX   8
#define KERNEL_INDEX_SMC     2

#define PICO_MAX_SMC_THERMAL_KEYS 64

int pico_read_hw_topology(pico_hw_topology_t *out) {
    if (!out) {
        return -1;
    }
    memset(out, 0, sizeof(*out));

    size_t brand_size = sizeof(out->brand) - 1;
    if (sysctlbyname("machdep.cpu.brand_string", out->brand, &brand_size, NULL, 0) != 0) {
        strncpy(out->brand, "Apple Silicon", sizeof(out->brand) - 1);
    }

    size_t int_size = sizeof(int32_t);
    sysctlbyname("hw.ncpu", &out->total_cores, &int_size, NULL, 0);

    int_size = sizeof(int32_t);
    sysctlbyname("hw.perflevel0.physicalcpu", &out->perflevel0_cores, &int_size, NULL, 0);

    int_size = sizeof(int32_t);
    sysctlbyname("hw.perflevel1.physicalcpu", &out->perflevel1_cores, &int_size, NULL, 0);

    size_t name_size = sizeof(out->perflevel0_name) - 1;
    if (sysctlbyname("hw.perflevel0.name", out->perflevel0_name, &name_size, NULL, 0) != 0 || out->perflevel0_name[0] == '\0') {
        strncpy(out->perflevel0_name, "Performance", sizeof(out->perflevel0_name) - 1);
    }

    name_size = sizeof(out->perflevel1_name) - 1;
    if (sysctlbyname("hw.perflevel1.name", out->perflevel1_name, &name_size, NULL, 0) != 0 || out->perflevel1_name[0] == '\0') {
        strncpy(out->perflevel1_name, "Efficiency", sizeof(out->perflevel1_name) - 1);
    }

    size_t mem_size = sizeof(out->memsize_bytes);
    sysctlbyname("hw.memsize", &out->memsize_bytes, &mem_size, NULL, 0);
    g_cached_memsize = out->memsize_bytes;

    return 0;
}

int pico_cshim_hw_summary(char *buffer, size_t buffer_len) {
    if (!buffer || buffer_len == 0) {
        return -1;
    }

    pico_hw_topology_t topo;
    if (pico_read_hw_topology(&topo) != 0) {
        return -1;
    }

    unsigned long mem_gb = (unsigned long)(topo.memsize_bytes / (1024ULL * 1024ULL * 1024ULL));
    snprintf(
        buffer,
        buffer_len,
        "%s | %d core (%d %s + %d %s) | %lu GB RAM",
        topo.brand,
        topo.total_cores,
        topo.perflevel0_cores,
        topo.perflevel0_name,
        topo.perflevel1_cores,
        topo.perflevel1_name,
        mem_gb
    );

    return 0;
}

int pico_read_cpu_ticks(pico_cpu_ticks_t *out) {
    if (!out) {
        return -1;
    }
    memset(out, 0, sizeof(*out));

    natural_t cpu_count = 0;
    processor_info_array_t info_array = NULL;
    mach_msg_type_number_t info_count = 0;

    kern_return_t kr = host_processor_info(
        mach_host_self(),
        PROCESSOR_CPU_LOAD_INFO,
        &cpu_count,
        &info_array,
        &info_count
    );

    if (kr != KERN_SUCCESS || !info_array) {
        return -1;
    }

    uint32_t limit = (cpu_count < PICO_MAX_CORES) ? (uint32_t)cpu_count : PICO_MAX_CORES;
    out->count = limit;

    processor_cpu_load_info_t cpu_load = (processor_cpu_load_info_t)info_array;
    for (uint32_t i = 0; i < limit; i++) {
        out->user[i]   = (uint64_t)cpu_load[i].cpu_ticks[CPU_STATE_USER];
        out->system[i] = (uint64_t)cpu_load[i].cpu_ticks[CPU_STATE_SYSTEM];
        out->nice[i]   = (uint64_t)cpu_load[i].cpu_ticks[CPU_STATE_NICE];
        out->idle[i]   = (uint64_t)cpu_load[i].cpu_ticks[CPU_STATE_IDLE];
    }

    vm_deallocate(
        mach_task_self(),
        (vm_address_t)info_array,
        (vm_size_t)(info_count * sizeof(integer_t))
    );

    return 0;
}

static int32_t clamp_percent(double val) {
    int32_t r = (int32_t)lround(val);
    if (r < 0) return 0;
    if (r > 100) return 100;
    return r;
}

int pico_compute_cpu_delta(
    const pico_cpu_ticks_t *prev,
    const pico_cpu_ticks_t *curr,
    uint32_t first_group_cores,
    pico_cpu_usage_t *out
) {
    if (!prev || !curr || !out || curr->count == 0 || prev->count != curr->count) {
        return -1;
    }
    memset(out, 0, sizeof(*out));
    out->count = curr->count;

    uint64_t total_active = 0;
    uint64_t total_all = 0;
    uint64_t g0_active = 0;
    uint64_t g0_all = 0;
    uint64_t g1_active = 0;
    uint64_t g1_all = 0;

    for (uint32_t i = 0; i < curr->count; i++) {
        uint64_t d_user = curr->user[i] - prev->user[i];
        uint64_t d_sys  = curr->system[i] - prev->system[i];
        uint64_t d_nice = curr->nice[i] - prev->nice[i];
        uint64_t d_idle = curr->idle[i] - prev->idle[i];

        uint64_t active = d_user + d_sys + d_nice;
        uint64_t total  = active + d_idle;

        if (total > 0) {
            out->core_percent[i] = clamp_percent(((double)active / (double)total) * 100.0);
        }

        total_active += active;
        total_all += total;

        if (i < first_group_cores) {
            g0_active += active;
            g0_all += total;
        } else {
            g1_active += active;
            g1_all += total;
        }
    }

    if (total_all == 0) {
        return -1;
    }

    out->total_exact = ((double)total_active / (double)total_all) * 100.0;
    out->total_percent = clamp_percent(out->total_exact);
    out->first_group_percent = (g0_all > 0) ? clamp_percent(((double)g0_active / (double)g0_all) * 100.0) : 0;
    out->second_group_percent = (g1_all > 0) ? clamp_percent(((double)g1_active / (double)g1_all) * 100.0) : 0;

    return 0;
}

static bool pico_extract_cfnumber_int32(CFDictionaryRef dict, CFStringRef key, int32_t *out_val) {
    CFTypeRef val = CFDictionaryGetValue(dict, key);
    if (val && CFGetTypeID(val) == CFNumberGetTypeID()) {
        return CFNumberGetValue((CFNumberRef)val, kCFNumberSInt32Type, out_val);
    }
    return false;
}

static bool pico_extract_cfnumber_int64(CFDictionaryRef dict, CFStringRef key, uint64_t *out_val) {
    CFTypeRef val = CFDictionaryGetValue(dict, key);
    if (val && CFGetTypeID(val) == CFNumberGetTypeID()) {
        int64_t signed_val = 0;
        if (CFNumberGetValue((CFNumberRef)val, kCFNumberSInt64Type, &signed_val)) {
            *out_val = (signed_val >= 0) ? (uint64_t)signed_val : 0;
            return true;
        }
    }
    return false;
}

static io_service_t pico_find_gpu_service(void) {
    CFMutableDictionaryRef matching = IOServiceMatching("IOAccelerator");
    if (!matching) {
        return IO_OBJECT_NULL;
    }

    io_iterator_t iterator = IO_OBJECT_NULL;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) != KERN_SUCCESS) {
        return IO_OBJECT_NULL;
    }

    io_service_t service = IOIteratorNext(iterator);
    IOObjectRelease(iterator);

    if (service != IO_OBJECT_NULL) {
        io_name_t class_name = {0};
        if (IOObjectGetClass(service, class_name) == KERN_SUCCESS) {
            strncpy(g_gpu_class_name, class_name, sizeof(g_gpu_class_name) - 1);
        } else {
            strncpy(g_gpu_class_name, "IOAccelerator", sizeof(g_gpu_class_name) - 1);
        }
    }
    return service;
}

typedef CFDictionaryRef (*PicoIRCopyChannelsFunc)(CFStringRef, CFStringRef, uint64_t, uint64_t, uint64_t);
typedef void* (*PicoIRCreateSubFunc)(void*, CFMutableDictionaryRef, CFMutableDictionaryRef*, uint64_t, CFTypeRef);
typedef CFDictionaryRef (*PicoIRCreateSamplesFunc)(void*, CFMutableDictionaryRef, CFTypeRef);
typedef CFDictionaryRef (*PicoIRCreateDeltaFunc)(CFDictionaryRef, CFDictionaryRef, CFTypeRef);
typedef void (*PicoIRIterateFunc)(CFDictionaryRef, int (^)(CFDictionaryRef));
typedef CFStringRef (*PicoIRGetNameFunc)(CFDictionaryRef);
typedef int32_t (*PicoIRStateCountFunc)(CFDictionaryRef);
typedef CFStringRef (*PicoIRStateNameFunc)(CFDictionaryRef, int32_t);
typedef int64_t (*PicoIRStateResFunc)(CFDictionaryRef, int32_t);

static PicoIRCopyChannelsFunc g_ir_copy_channels = NULL;
static PicoIRCreateSubFunc g_ir_create_sub = NULL;
static PicoIRCreateSamplesFunc g_ir_create_samples = NULL;
static PicoIRCreateDeltaFunc g_ir_create_delta = NULL;
static PicoIRIterateFunc g_ir_iterate = NULL;
static PicoIRGetNameFunc g_ir_get_chan_name = NULL;
static PicoIRStateCountFunc g_ir_state_count = NULL;
static PicoIRStateNameFunc g_ir_state_name = NULL;
static PicoIRStateResFunc g_ir_state_res = NULL;
static pthread_once_t g_ir_gpu_once = PTHREAD_ONCE_INIT;

static void *g_gpu_ir_sub = NULL;
static CFMutableDictionaryRef g_gpu_ir_sub_dict = NULL;
static CFDictionaryRef g_gpu_prev_sample = NULL;
static uint64_t g_gpu_prev_ns = 0;
static int32_t g_gpu_last_pct = 0;
static bool g_gpu_has_last_pct = false;

static void pico_init_ioreport_gpu_symbols(void) {
    void *h = dlopen("/usr/lib/libIOReport.dylib", RTLD_LAZY);
    if (!h) return;
    g_ir_copy_channels = (PicoIRCopyChannelsFunc)dlsym(h, "IOReportCopyChannelsInGroup");
    g_ir_create_sub = (PicoIRCreateSubFunc)dlsym(h, "IOReportCreateSubscription");
    g_ir_create_samples = (PicoIRCreateSamplesFunc)dlsym(h, "IOReportCreateSamples");
    g_ir_create_delta = (PicoIRCreateDeltaFunc)dlsym(h, "IOReportCreateSamplesDelta");
    g_ir_iterate = (PicoIRIterateFunc)dlsym(h, "IOReportIterate");
    g_ir_get_chan_name = (PicoIRGetNameFunc)dlsym(h, "IOReportChannelGetChannelName");
    g_ir_state_count = (PicoIRStateCountFunc)dlsym(h, "IOReportStateGetCount");
    g_ir_state_name = (PicoIRStateNameFunc)dlsym(h, "IOReportStateGetNameForIndex");
    g_ir_state_res = (PicoIRStateResFunc)dlsym(h, "IOReportStateGetResidency");
}

static bool pico_ensure_gpu_ioreport(void) {
    if (g_gpu_ir_sub && g_gpu_ir_sub_dict) {
        return true;
    }
    pthread_once(&g_ir_gpu_once, pico_init_ioreport_gpu_symbols);
    if (!g_ir_copy_channels || !g_ir_create_sub || !g_ir_create_samples ||
        !g_ir_create_delta || !g_ir_iterate || !g_ir_get_chan_name ||
        !g_ir_state_count || !g_ir_state_name || !g_ir_state_res) {
        return false;
    }

    CFDictionaryRef channels = g_ir_copy_channels(CFSTR("GPU Stats"), CFSTR("GPU Performance States"), 0, 0, 0);
    if (!channels) {
        return false;
    }
    CFMutableDictionaryRef mut = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, channels);
    CFRelease(channels);
    if (!mut) {
        return false;
    }

    CFMutableDictionaryRef sub_dict = NULL;
    void *sub = g_ir_create_sub(NULL, mut, &sub_dict, 0, NULL);
    CFRelease(mut);
    if (!sub || !sub_dict) {
        if (sub_dict) CFRelease(sub_dict);
        if (sub) CFRelease(sub);
        return false;
    }

    g_gpu_ir_sub = sub;
    g_gpu_ir_sub_dict = sub_dict;
    return true;
}

static void pico_release_gpu_ioreport(void) {
    if (g_gpu_prev_sample) {
        CFRelease(g_gpu_prev_sample);
        g_gpu_prev_sample = NULL;
    }
    if (g_gpu_ir_sub_dict) {
        CFRelease(g_gpu_ir_sub_dict);
        g_gpu_ir_sub_dict = NULL;
    }
    if (g_gpu_ir_sub) {
        CFRelease(g_gpu_ir_sub);
        g_gpu_ir_sub = NULL;
    }
    g_gpu_prev_ns = 0;
    g_gpu_last_pct = 0;
    g_gpu_has_last_pct = false;
}

void pico_prime_gpu_baseline(void) {
    if (!pico_ensure_gpu_ioreport() || g_gpu_prev_sample) {
        return;
    }
    g_gpu_prev_sample = g_ir_create_samples(g_gpu_ir_sub, g_gpu_ir_sub_dict, NULL);
    if (g_gpu_prev_sample) {
        g_gpu_prev_ns = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    }
}

static bool pico_read_gpu_ioreport_pct(int32_t *out_pct) {
    if (!pico_ensure_gpu_ioreport()) {
        return false;
    }

    uint64_t now_ns = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
    if (!g_gpu_prev_sample) {
        g_gpu_prev_sample = g_ir_create_samples(g_gpu_ir_sub, g_gpu_ir_sub_dict, NULL);
        if (g_gpu_prev_sample) {
            g_gpu_prev_ns = now_ns;
        }
        return false;
    }

    // Finestra minima 150ms per preservare il delta medio su letture ravvicinate (es. click dopo tick barra)
    if (now_ns >= g_gpu_prev_ns && (now_ns - g_gpu_prev_ns) < 150000000ULL) {
        if (g_gpu_has_last_pct) {
            *out_pct = g_gpu_last_pct;
            return true;
        }
        return false;
    }

    CFDictionaryRef curr = g_ir_create_samples(g_gpu_ir_sub, g_gpu_ir_sub_dict, NULL);
    if (!curr) {
        pico_release_gpu_ioreport();
        return false;
    }

    CFDictionaryRef delta = g_ir_create_delta(g_gpu_prev_sample, curr, NULL);
    if (!delta) {
        CFRelease(curr);
        pico_release_gpu_ioreport();
        return false;
    }

    __block int32_t computed_pct = -1;
    g_ir_iterate(delta, ^int(CFDictionaryRef sample) {
        CFStringRef cn = g_ir_get_chan_name(sample);
        if (!cn || CFStringCompare(cn, CFSTR("GPUPH"), 0) != kCFCompareEqualTo) {
            return 0;
        }
        int32_t sc = g_ir_state_count(sample);
        int64_t off_ticks = 0;
        int64_t total_ticks = 0;
        bool has_off_state = false;
        for (int32_t i = 0; i < sc; i++) {
            int64_t res = g_ir_state_res(sample, i);
            if (res < 0) continue;
            total_ticks += res;
            CFStringRef sn = g_ir_state_name(sample, i);
            if (sn && (CFStringCompare(sn, CFSTR("OFF"), kCFCompareCaseInsensitive) == kCFCompareEqualTo ||
                       CFStringCompare(sn, CFSTR("IDLE"), kCFCompareCaseInsensitive) == kCFCompareEqualTo ||
                       CFStringCompare(sn, CFSTR("DOWN"), kCFCompareCaseInsensitive) == kCFCompareEqualTo)) {
                off_ticks += res;
                has_off_state = true;
            }
        }
        if (has_off_state && total_ticks > 0) {
            double active_pct = ((double)(total_ticks - off_ticks) / (double)total_ticks) * 100.0;
            computed_pct = clamp_percent(active_pct);
        }
        return 1;
    });

    CFRelease(delta);

    if (computed_pct >= 0) {
        CFRelease(g_gpu_prev_sample);
        g_gpu_prev_sample = curr;
        g_gpu_prev_ns = now_ns;
        g_gpu_last_pct = computed_pct;
        g_gpu_has_last_pct = true;
        *out_pct = computed_pct;
        return true;
    }

    CFRelease(curr);
    return false;
}

void pico_release_gpu_service(void) {
    if (g_gpu_service != IO_OBJECT_NULL) {
        IOObjectRelease(g_gpu_service);
        g_gpu_service = IO_OBJECT_NULL;
    }
    pico_release_gpu_ioreport();
}

static bool pico_read_gpu_perfstats(pico_gpu_raw_t *out, bool include_details) {
    if (!out) {
        return false;
    }

    if (g_gpu_service == IO_OBJECT_NULL) {
        g_gpu_service = pico_find_gpu_service();
        if (g_gpu_service == IO_OBJECT_NULL) {
            return false;
        }
    }

    CFTypeRef prop = IORegistryEntryCreateCFProperty(
        g_gpu_service,
        CFSTR("PerformanceStatistics"),
        kCFAllocatorDefault,
        0
    );

    if (!prop) {
        // Rilascia solo l'handle IOKit scaduto; preserva l'eventuale baseline IOReport
        IOObjectRelease(g_gpu_service);
        g_gpu_service = pico_find_gpu_service();
        if (g_gpu_service != IO_OBJECT_NULL) {
            prop = IORegistryEntryCreateCFProperty(
                g_gpu_service,
                CFSTR("PerformanceStatistics"),
                kCFAllocatorDefault,
                0
            );
        }
    }

    if (!prop) {
        return false;
    }

    if (CFGetTypeID(prop) != CFDictionaryGetTypeID()) {
        CFRelease(prop);
        return false;
    }

    CFDictionaryRef stats = (CFDictionaryRef)prop;
    strncpy(out->service_class, g_gpu_class_name, sizeof(out->service_class) - 1);

    int32_t dev_util = -1;
    if (pico_extract_cfnumber_int32(stats, CFSTR("Device Utilization %"), &dev_util)) {
        if (dev_util < 0) dev_util = 0;
        if (dev_util > 100) dev_util = 100;
        out->device_utilization = dev_util;
        out->available = true;
    }

    if (include_details) {
        int32_t rend_util = -1;
        if (pico_extract_cfnumber_int32(stats, CFSTR("Renderer Utilization %"), &rend_util)) {
            out->renderer_utilization = rend_util;
        }

        int32_t tiler_util = -1;
        if (pico_extract_cfnumber_int32(stats, CFSTR("Tiler Utilization %"), &tiler_util)) {
            out->tiler_utilization = tiler_util;
        }

        pico_extract_cfnumber_int64(stats, CFSTR("In use system memory"), &out->in_use_system_memory);
        pico_extract_cfnumber_int64(stats, CFSTR("Alloc system memory"), &out->alloc_system_memory);
    }

    CFRelease(prop);
    return out->available;
}

int pico_read_gpu_bar_percent(int32_t *out_pct) {
    if (!out_pct) {
        return -1;
    }
    int32_t ir_util = -1;
    if (pico_read_gpu_ioreport_pct(&ir_util)) {
        *out_pct = ir_util;
        return 0;
    }
    pico_gpu_raw_t fallback;
    memset(&fallback, 0, sizeof(fallback));
    fallback.device_utilization = -1;
    fallback.renderer_utilization = -1;
    fallback.tiler_utilization = -1;
    if (pico_read_gpu_perfstats(&fallback, false) && fallback.available) {
        *out_pct = fallback.device_utilization;
        return 0;
    }
    return -1;
}

int pico_read_gpu_raw(pico_gpu_raw_t *out) {
    if (!out) {
        return -1;
    }
    memset(out, 0, sizeof(*out));
    out->device_utilization = -1;
    out->renderer_utilization = -1;
    out->tiler_utilization = -1;

    (void)pico_read_gpu_perfstats(out, true);

    int32_t ir_util = -1;
    if (pico_read_gpu_ioreport_pct(&ir_util)) {
        out->device_utilization = ir_util;
        out->available = true;
    }

    return out->available ? 0 : -1;
}

int pico_read_ram_raw(pico_ram_raw_t *out) {
    if (!out) {
        return -1;
    }
    memset(out, 0, sizeof(*out));

    if (g_cached_memsize == 0) {
        size_t mem_size = sizeof(g_cached_memsize);
        sysctlbyname("hw.memsize", &g_cached_memsize, &mem_size, NULL, 0);
    }

    vm_statistics64_data_t vm_stat;
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    kern_return_t kr = host_statistics64(
        mach_host_self(),
        HOST_VM_INFO64,
        (host_info64_t)&vm_stat,
        &count
    );

    if (kr != KERN_SUCCESS) {
        return -1;
    }

    out->available = true;
    out->total_bytes = g_cached_memsize;
    out->page_size = (uint64_t)vm_kernel_page_size;
    out->free_pages = (uint64_t)vm_stat.free_count;
    out->active_pages = (uint64_t)vm_stat.active_count;
    out->inactive_pages = (uint64_t)vm_stat.inactive_count;
    out->speculative_pages = (uint64_t)vm_stat.speculative_count;
    out->wire_pages = (uint64_t)vm_stat.wire_count;
    out->purgeable_pages = (uint64_t)vm_stat.purgeable_count;
    out->internal_pages = (uint64_t)vm_stat.internal_page_count;
    out->external_pages = (uint64_t)vm_stat.external_page_count;
    out->compressor_pages = (uint64_t)vm_stat.compressor_page_count;

    struct xsw_usage swap;
    size_t swap_len = sizeof(swap);
    if (sysctlbyname("vm.swapusage", &swap, &swap_len, NULL, 0) == 0) {
        out->swap_used_bytes = (uint64_t)swap.xsu_used;
        out->swap_total_bytes = (uint64_t)swap.xsu_total;
    }

    return 0;
}

/* ========================================================================= */
/* AppleSMC: Temperature e Potenza in Watt (On-Demand a Menu Aperto)          */
/* ========================================================================= */

static io_connect_t pico_get_smc_conn(void) {
    if (g_smc_conn != IO_OBJECT_NULL) {
        return g_smc_conn;
    }
    if (g_smc_service == IO_OBJECT_NULL) {
        g_smc_service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
        if (!g_smc_service) return IO_OBJECT_NULL;
    }
    kern_return_t kr = IOServiceOpen(g_smc_service, mach_task_self(), 0, &g_smc_conn);
    if (kr != KERN_SUCCESS) {
        g_smc_conn = IO_OBJECT_NULL;
    }
    return g_smc_conn;
}

void pico_release_smc(void) {
    if (g_smc_conn != IO_OBJECT_NULL) {
        IOServiceClose(g_smc_conn);
        g_smc_conn = IO_OBJECT_NULL;
    }
    if (g_smc_service != IO_OBJECT_NULL) {
        IOObjectRelease(g_smc_service);
        g_smc_service = IO_OBJECT_NULL;
    }
}

static float pico_smc_read_float(io_connect_t conn, const char *key_str) {
    uint32_t key = ((uint32_t)key_str[0] << 24) | ((uint32_t)key_str[1] << 16) |
                   ((uint32_t)key_str[2] << 8)  | (uint32_t)key_str[3];

    SMCParamStruct in, out;
    memset(&in, 0, sizeof(in));
    in.key = key;
    in.data8 = SMC_CMD_READ_KEYINFO;
    size_t in_size = sizeof(SMCParamStruct);
    size_t out_size = sizeof(SMCParamStruct);

    if (IOConnectCallStructMethod(conn, KERNEL_INDEX_SMC, &in, in_size, &out, &out_size) != KERN_SUCCESS || out.result != 0) {
        return -1.0f;
    }

    uint32_t data_size = out.keyInfo.dataSize;
    uint32_t data_type = out.keyInfo.dataType;
    bool is_flt = (data_type == (((uint32_t)'f'<<24)|((uint32_t)'l'<<16)|((uint32_t)'t'<<8)|(uint32_t)' ') && data_size == 4);
    bool is_sp78 = (data_type == (((uint32_t)'s'<<24)|((uint32_t)'p'<<16)|((uint32_t)'7'<<8)|(uint32_t)'8') && data_size == 2);
    if (!is_flt && !is_sp78) {
        return -1.0f;
    }

    in.data8 = SMC_CMD_READ_BYTES;
    in.keyInfo = out.keyInfo;
    out_size = sizeof(SMCParamStruct);
    if (IOConnectCallStructMethod(conn, KERNEL_INDEX_SMC, &in, in_size, &out, &out_size) != KERN_SUCCESS || out.result != 0) {
        return -1.0f;
    }

    float val = -1.0f;
    if (is_flt) {
        memcpy(&val, out.bytes, 4);
    } else if (is_sp78) {
        int16_t raw = (int16_t)(((uint16_t)out.bytes[0] << 8) | (uint16_t)out.bytes[1]);
        val = (float)raw / 256.0f;
    }
    return isfinite(val) ? val : -1.0f;
}

static char g_cpu_smc_keys[PICO_MAX_SMC_THERMAL_KEYS][5];
static int g_cpu_smc_count = 0;
static char g_gpu_smc_keys[PICO_MAX_SMC_THERMAL_KEYS][5];
static int g_gpu_smc_count = 0;
static bool g_smc_keys_scanned = false;

static const char *k_cpu_fallback_keys[] = {
    "TVC0", "TCXC", "TC0P",
    "Te04", "Te05", "Te08", "Te0C", "Te0R",
    "Ta00", "Ta04", "Ta08", "Ta0K", "Ta0O", "Ta0R",
    "Tc0a", "Tc0b", "Tc0x",
    "Tp00", "Tp01", "Tp04", "Tp05", "Tp09", "Tp0C", "Tp0D", "Tp0G", "Tp0H", "Tp0L",
    "Tp0O", "Tp0P", "Tp0R", "Tp0T", "Tp0X", "Tp0a", "Tp0b", "Tp0f", "Tp0j", "Tp0p", "Tp0u", "Tp0y",
    "Tp12", "Tp16", "Tp1E"
};

static const char *k_gpu_fallback_keys[] = {
    "TVG0", "Tg04", "Tg05", "Tg0C", "Tg0D", "Tg0G", "Tg0K", "Tg0L", "Tg0O", "Tg0R", "Tg0U", "Tg0X",
    "Tg0a", "Tg0b", "Tg0d", "Tg0f", "Tg0g", "Tg0j", "Tg0m", "Tg0p",
    "Tg12", "Tg16", "Tg1A", "Tg1I", "Tg1M", "Tg1Y", "Tg1a", "Tg1c", "Tg1g", "Tg1o", "Tg1s"
};

static bool pico_is_digit(char c) {
    return (c >= '0' && c <= '9');
}

static bool pico_is_cpu_smc_key(const char *ks) {
    if (strcmp(ks, "TVC0") == 0 || strcmp(ks, "TCXC") == 0 || strcmp(ks, "TC0P") == 0) {
        return true;
    }
    if (ks[0] == 'T' && (ks[1] == 'p' || ks[1] == 'e' || ks[1] == 'a' || ks[1] == 'c') && pico_is_digit(ks[2])) {
        return true;
    }
    return false;
}

static bool pico_is_gpu_smc_key(const char *ks) {
    if (strcmp(ks, "TVG0") == 0) {
        return true;
    }
    if (ks[0] == 'T' && ks[1] == 'g' && pico_is_digit(ks[2])) {
        return true;
    }
    return false;
}

/// Scansiona l'indice SMC una sola volta (zero allocazioni heap, array statici BSS)
/// per scoprire automaticamente tutte le chiavi termiche die CPU/GPU su Apple Silicon (M1..M5+).
static void pico_discover_smc_thermal_keys(io_connect_t conn) {
    if (g_smc_keys_scanned) {
        return;
    }
    g_smc_keys_scanned = true;
    g_cpu_smc_count = 0;
    g_gpu_smc_count = 0;

    SMCParamStruct in, out;
    size_t sz = sizeof(SMCParamStruct);
    memset(&in, 0, sz);
    in.key = ((uint32_t)'#'<<24)|((uint32_t)'K'<<16)|((uint32_t)'E'<<8)|(uint32_t)'Y';
    in.data8 = SMC_CMD_READ_KEYINFO;

    uint32_t total = 0;
    if (IOConnectCallStructMethod(conn, KERNEL_INDEX_SMC, &in, sz, &out, &sz) == KERN_SUCCESS && out.result == 0 && out.keyInfo.dataSize == 4) {
        in.data8 = SMC_CMD_READ_BYTES;
        in.keyInfo = out.keyInfo;
        sz = sizeof(SMCParamStruct);
        if (IOConnectCallStructMethod(conn, KERNEL_INDEX_SMC, &in, sz, &out, &sz) == KERN_SUCCESS && out.result == 0) {
            total = ((uint32_t)out.bytes[0] << 24) | ((uint32_t)out.bytes[1] << 16) |
                    ((uint32_t)out.bytes[2] << 8)  | (uint32_t)out.bytes[3];
        }
    }

    if (total > 0 && total < 20000) {
        for (uint32_t i = 0; i < total; i++) {
            memset(&in, 0, sizeof(in));
            in.data8 = SMC_CMD_READ_INDEX;
            in.data32 = i;
            sz = sizeof(SMCParamStruct);
            if (IOConnectCallStructMethod(conn, KERNEL_INDEX_SMC, &in, sz, &out, &sz) != KERN_SUCCESS || out.result != 0) {
                continue;
            }
            char ks[5];
            ks[0] = (char)((out.key >> 24) & 0xff);
            ks[1] = (char)((out.key >> 16) & 0xff);
            ks[2] = (char)((out.key >> 8) & 0xff);
            ks[3] = (char)(out.key & 0xff);
            ks[4] = '\0';

            if (ks[0] != 'T') continue;

            if (pico_is_cpu_smc_key(ks) && g_cpu_smc_count < PICO_MAX_SMC_THERMAL_KEYS) {
                memcpy(g_cpu_smc_keys[g_cpu_smc_count++], ks, 5);
            } else if (pico_is_gpu_smc_key(ks) && g_gpu_smc_count < PICO_MAX_SMC_THERMAL_KEYS) {
                memcpy(g_gpu_smc_keys[g_gpu_smc_count++], ks, 5);
            }
        }
    }

    if (g_cpu_smc_count == 0) {
        size_t n = sizeof(k_cpu_fallback_keys) / sizeof(k_cpu_fallback_keys[0]);
        for (size_t i = 0; i < n && g_cpu_smc_count < PICO_MAX_SMC_THERMAL_KEYS; i++) {
            strncpy(g_cpu_smc_keys[g_cpu_smc_count], k_cpu_fallback_keys[i], 4);
            g_cpu_smc_keys[g_cpu_smc_count][4] = '\0';
            g_cpu_smc_count++;
        }
    }
    if (g_gpu_smc_count == 0) {
        size_t n = sizeof(k_gpu_fallback_keys) / sizeof(k_gpu_fallback_keys[0]);
        for (size_t i = 0; i < n && g_gpu_smc_count < PICO_MAX_SMC_THERMAL_KEYS; i++) {
            strncpy(g_gpu_smc_keys[g_gpu_smc_count], k_gpu_fallback_keys[i], 4);
            g_gpu_smc_keys[g_gpu_smc_count][4] = '\0';
            g_gpu_smc_count++;
        }
    }
}

/* Fallback IOHIDEventSystemClient (caricamento dinamico senza link statico) */
typedef void* (*PicoIOHIDCreateClientFunc)(CFAllocatorRef);
typedef void (*PicoIOHIDSetMatchingFunc)(void*, CFDictionaryRef);
typedef CFArrayRef (*PicoIOHIDCopyServicesFunc)(void*);
typedef CFTypeRef (*PicoIOHIDCopyPropFunc)(void*, CFStringRef);
typedef void* (*PicoIOHIDCopyEventFunc)(void*, int64_t, int32_t, int64_t);
typedef double (*PicoIOHIDGetFloatFunc)(void*, uint32_t);

static PicoIOHIDCreateClientFunc g_hid_create = NULL;
static PicoIOHIDSetMatchingFunc g_hid_set_match = NULL;
static PicoIOHIDCopyServicesFunc g_hid_copy_services = NULL;
static PicoIOHIDCopyPropFunc g_hid_copy_prop = NULL;
static PicoIOHIDCopyEventFunc g_hid_copy_event = NULL;
static PicoIOHIDGetFloatFunc g_hid_get_float = NULL;
static pthread_once_t g_hid_init_once = PTHREAD_ONCE_INIT;

static void pico_init_hid_symbols(void) {
    void *h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);
    if (!h) return;
    g_hid_create = (PicoIOHIDCreateClientFunc)dlsym(h, "IOHIDEventSystemClientCreate");
    g_hid_set_match = (PicoIOHIDSetMatchingFunc)dlsym(h, "IOHIDEventSystemClientSetMatching");
    g_hid_copy_services = (PicoIOHIDCopyServicesFunc)dlsym(h, "IOHIDEventSystemClientCopyServices");
    g_hid_copy_prop = (PicoIOHIDCopyPropFunc)dlsym(h, "IOHIDServiceClientCopyProperty");
    g_hid_copy_event = (PicoIOHIDCopyEventFunc)dlsym(h, "IOHIDServiceClientCopyEvent");
    g_hid_get_float = (PicoIOHIDGetFloatFunc)dlsym(h, "IOHIDEventGetFloatValue");
}

static bool pico_hid_name_matches(const char *name, bool is_cpu) {
    if (strcasestr(name, "battery") || strcasestr(name, "NAND") ||
        strcasestr(name, "als") || strcasestr(name, "tdev") || strcasestr(name, "tcal")) {
        return false;
    }
    if (is_cpu) {
        return (strcasestr(name, "pACC") != NULL ||
                strcasestr(name, "eACC") != NULL ||
                strcasestr(name, "PMU tdie") != NULL ||
                strcasestr(name, "SOC MTR") != NULL ||
                strcasestr(name, "CPU") != NULL);
    } else {
        return (strcasestr(name, "GPU") != NULL);
    }
}

static int pico_read_hid_thermal(bool is_cpu, pico_thermal_t *out) {
    pthread_once(&g_hid_init_once, pico_init_hid_symbols);
    if (!g_hid_create || !g_hid_set_match || !g_hid_copy_services ||
        !g_hid_copy_prop || !g_hid_copy_event || !g_hid_get_float) {
        return -1;
    }

    void *client = g_hid_create(kCFAllocatorDefault);
    if (!client) return -1;

    int page = 0xff00, usage = 5;
    CFNumberRef p = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &page);
    CFNumberRef u = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &usage);
    if (p && u) {
        const void *keys[] = { CFSTR("PrimaryUsagePage"), CFSTR("PrimaryUsage") };
        const void *vals[] = { p, u };
        CFDictionaryRef dict = CFDictionaryCreate(
            kCFAllocatorDefault, keys, vals, 2,
            &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks
        );
        if (dict) {
            g_hid_set_match(client, dict);
            CFRelease(dict);
        }
    }
    if (p) CFRelease(p);
    if (u) CFRelease(u);

    CFArrayRef services = g_hid_copy_services(client);
    if (!services) {
        CFRelease(client);
        return -1;
    }

    double sum = 0.0;
    int count = 0;
    double hotspot = -1.0;

    CFIndex n = CFArrayGetCount(services);
    for (CFIndex i = 0; i < n; i++) {
        void *s = (void *)CFArrayGetValueAtIndex(services, i);
        CFTypeRef prod = g_hid_copy_prop(s, CFSTR("Product"));
        char name[128] = {0};
        if (prod) {
            if (CFGetTypeID(prod) == CFStringGetTypeID()) {
                CFStringGetCString((CFStringRef)prod, name, sizeof(name), kCFStringEncodingUTF8);
            }
            CFRelease(prod);
        }
        if (name[0] == '\0' || !pico_hid_name_matches(name, is_cpu)) {
            continue;
        }
        void *ev = g_hid_copy_event(s, 15, 0, 0);
        if (ev) {
            double t = g_hid_get_float(ev, 15 << 16);
            CFRelease(ev);
            if (isfinite(t) && t > 1.0 && t < 125.0) {
                sum += t;
                count++;
                if (t > hotspot) hotspot = t;
            }
        }
    }

    CFRelease(services);
    CFRelease(client);

    if (count > 0 && hotspot > 1.0) {
        out->avg_temp_c = (float)(sum / (double)count);
        out->hotspot_temp_c = (float)hotspot;
        out->available = true;
        return 0;
    }
    return -1;
}

int pico_read_cpu_thermal(pico_thermal_t *out) {
    if (!out) return -1;
    memset(out, 0, sizeof(*out));

    io_connect_t conn = pico_get_smc_conn();
    if (conn != IO_OBJECT_NULL) {
        pico_discover_smc_thermal_keys(conn);

        float sum = 0.0f;
        int count = 0;
        float hotspot = -1.0f;
        float preferred_avg = -1.0f;

        for (int i = 0; i < g_cpu_smc_count; i++) {
            float t = pico_smc_read_float(conn, g_cpu_smc_keys[i]);
            if (t > 1.0f && t < 125.0f) {
                sum += t;
                count++;
                if (t > hotspot) hotspot = t;
                if (strcmp(g_cpu_smc_keys[i], "TVC0") == 0 ||
                    (preferred_avg <= 1.0f && (strcmp(g_cpu_smc_keys[i], "TCXC") == 0 || strcmp(g_cpu_smc_keys[i], "TC0P") == 0))) {
                    preferred_avg = t;
                }
            }
        }

        if (count > 0 && hotspot > 1.0f) {
            out->avg_temp_c = (preferred_avg > 1.0f && preferred_avg < 125.0f) ? preferred_avg : (sum / (float)count);
            out->hotspot_temp_c = hotspot;
            out->available = true;
            return 0;
        }
    }

    return pico_read_hid_thermal(true, out);
}

int pico_read_gpu_thermal(pico_thermal_t *out) {
    if (!out) return -1;
    memset(out, 0, sizeof(*out));

    io_connect_t conn = pico_get_smc_conn();
    if (conn != IO_OBJECT_NULL) {
        pico_discover_smc_thermal_keys(conn);

        float sum = 0.0f;
        int count = 0;
        float hotspot = -1.0f;
        float preferred_avg = -1.0f;

        for (int i = 0; i < g_gpu_smc_count; i++) {
            float t = pico_smc_read_float(conn, g_gpu_smc_keys[i]);
            if (t > 1.0f && t < 125.0f) {
                sum += t;
                count++;
                if (t > hotspot) hotspot = t;
                if (strcmp(g_gpu_smc_keys[i], "TVG0") == 0) {
                    preferred_avg = t;
                }
            }
        }

        if (count > 0 && hotspot > 1.0f) {
            out->avg_temp_c = (preferred_avg > 1.0f && preferred_avg < 125.0f) ? preferred_avg : (sum / (float)count);
            out->hotspot_temp_c = hotspot;
            out->available = true;
            return 0;
        }
    }

    return pico_read_hid_thermal(false, out);
}

int pico_read_system_power(pico_power_t *out) {
    if (!out) return -1;
    memset(out, 0, sizeof(*out));
    io_connect_t conn = pico_get_smc_conn();
    if (conn == IO_OBJECT_NULL) return -1;

    static const char *k_power_keys[] = { "PSTR", "PPBR", "PDTR" };
    for (size_t i = 0; i < sizeof(k_power_keys) / sizeof(k_power_keys[0]); i++) {
        float w = pico_smc_read_float(conn, k_power_keys[i]);
        if (w > 0.0f && w < 500.0f) {
            out->system_watts = w;
            out->available = true;
            return 0;
        }
    }
    return -1;
}

/* ========================================================================= */
/* Top 5 Processi per Physical Footprint via libproc                         */
/* ========================================================================= */

#define PICO_PID_BUFFER_STATIC_COUNT 2048
static pid_t g_pid_static_buffer[PICO_PID_BUFFER_STATIC_COUNT];

int pico_read_top_processes(pico_top_processes_t *out) {
    if (!out) return -1;
    memset(out, 0, sizeof(*out));

    int bytes_needed = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    if (bytes_needed <= 0) {
        return -1;
    }

    pid_t *pids = g_pid_static_buffer;
    bool heap_allocated = false;

    if ((size_t)bytes_needed > sizeof(g_pid_static_buffer)) {
        pids = (pid_t *)malloc((size_t)bytes_needed);
        if (!pids) return -1;
        heap_allocated = true;
    }

    int actual_bytes = proc_listpids(PROC_ALL_PIDS, 0, pids, bytes_needed);
    int count = (actual_bytes > 0) ? (int)(actual_bytes / sizeof(pid_t)) : 0;

    pico_top_process_t top[5];
    memset(top, 0, sizeof(top));

    for (int i = 0; i < count; i++) {
        pid_t pid = pids[i];
        if (pid <= 0) continue;

        struct rusage_info_v4 rusage;
        if (proc_pid_rusage(pid, RUSAGE_INFO_V4, (rusage_info_t *)&rusage) == 0) {
            uint64_t fp = rusage.ri_phys_footprint;
            if (fp > top[4].phys_footprint_bytes) {
                int pos = 4;
                while (pos > 0 && fp > top[pos - 1].phys_footprint_bytes) {
                    pos--;
                }
                for (int j = 4; j > pos; j--) {
                    top[j] = top[j - 1];
                }
                top[pos].pid = pid;
                top[pos].phys_footprint_bytes = fp;
                top[pos].name[0] = '\0';
            }
        }
    }

    if (heap_allocated) {
        free(pids);
    }

    int valid_count = 0;
    for (int i = 0; i < 5; i++) {
        if (top[i].pid > 0 && top[i].phys_footprint_bytes > 0) {
            memset(top[i].name, 0, sizeof(top[i].name));
            proc_name(top[i].pid, top[i].name, (int)(sizeof(top[i].name) - 1));
            top[i].name[sizeof(top[i].name) - 1] = '\0';
            if (top[i].name[0] == '\0') {
                snprintf(top[i].name, sizeof(top[i].name), "PID %d", top[i].pid);
            }
            out->processes[valid_count] = top[i];
            valid_count++;
        }
    }
    out->count = valid_count;
    return 0;
}

int32_t pico_get_top_process_pid(const pico_top_processes_t *procs, int index) {
    if (!procs || index < 0 || index >= procs->count || index >= 5) return -1;
    return procs->processes[index].pid;
}

uint64_t pico_get_top_process_footprint(const pico_top_processes_t *procs, int index) {
    if (!procs || index < 0 || index >= procs->count || index >= 5) return 0;
    return procs->processes[index].phys_footprint_bytes;
}

const char *pico_get_top_process_name(const pico_top_processes_t *procs, int index) {
    if (!procs || index < 0 || index >= procs->count || index >= 5) return NULL;
    return procs->processes[index].name;
}
