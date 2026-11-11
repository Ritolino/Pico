#ifndef PICO_CSHIM_H
#define PICO_CSHIM_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

#define PICO_MAX_CORES 32

typedef struct {
    int32_t total_cores;
    int32_t perflevel0_cores;
    int32_t perflevel1_cores;
    char perflevel0_name[32];
    char perflevel1_name[32];
    char brand[64];
    uint64_t memsize_bytes;
} pico_hw_topology_t;

typedef struct {
    uint32_t count;
    uint64_t user[PICO_MAX_CORES];
    uint64_t system[PICO_MAX_CORES];
    uint64_t nice[PICO_MAX_CORES];
    uint64_t idle[PICO_MAX_CORES];
} pico_cpu_ticks_t;

typedef struct {
    uint32_t count;
    double total_exact;
    int32_t total_percent;
    int32_t first_group_percent;
    int32_t second_group_percent;
    int32_t core_percent[PICO_MAX_CORES];
} pico_cpu_usage_t;

typedef struct {
    bool available;
    int32_t device_utilization;
    int32_t renderer_utilization;
    int32_t tiler_utilization;
    uint64_t in_use_system_memory;
    uint64_t alloc_system_memory;
    char service_class[64];
} pico_gpu_raw_t;

typedef struct {
    bool available;
    uint64_t total_bytes;
    uint64_t page_size;
    uint64_t free_pages;
    uint64_t active_pages;
    uint64_t inactive_pages;
    uint64_t speculative_pages;
    uint64_t wire_pages;
    uint64_t purgeable_pages;
    uint64_t internal_pages;
    uint64_t external_pages;
    uint64_t compressor_pages;
    uint64_t swap_used_bytes;
    uint64_t swap_total_bytes;
} pico_ram_raw_t;

typedef struct {
    bool available;
    float avg_temp_c;
    float hotspot_temp_c;
} pico_thermal_t;

typedef struct {
    bool available;
    float system_watts;
} pico_power_t;

typedef struct {
    int32_t pid;
    uint64_t phys_footprint_bytes;
    char name[64];
} pico_top_process_t;

typedef struct {
    int count;
    pico_top_process_t processes[5];
} pico_top_processes_t;

/// Popola una breve descrizione dell'hardware letta via sysctl in-process.
int pico_cshim_hw_summary(char *buffer, size_t buffer_len);

/// Legge la topologia statica del SoC (core totali, cluster 0/1, nomi e RAM totale).
int pico_read_hw_topology(pico_hw_topology_t *out);

/// Legge i contatori cumulativi di tick per tutti i core via host_processor_info
/// e rilascia immediatamente il buffer Mach con vm_deallocate.
int pico_read_cpu_ticks(pico_cpu_ticks_t *out);

/// Calcola i delta di utilizzo CPU tra due letture di tick senza allocazioni heap.
int pico_compute_cpu_delta(
    const pico_cpu_ticks_t *prev,
    const pico_cpu_ticks_t *curr,
    uint32_t first_group_cores,
    pico_cpu_usage_t *out
);

/// Legge le statistiche istantanee della GPU da IOKit (IOAccelerator / PerformanceStatistics).
/// Mantiene in cache il servizio IOKit e rilascia il dizionario CF a ogni chiamata.
int pico_read_gpu_raw(pico_gpu_raw_t *out);

/// Rilascia esplicitamente l'handle IOKit della GPU se in cache.
void pico_release_gpu_service(void);

/// Legge i contatori VM a 64 bit del kernel tramite host_statistics64(HOST_VM_INFO64).
int pico_read_ram_raw(pico_ram_raw_t *out);

/// Legge temperatura media e hotspot CPU via AppleSMC.
int pico_read_cpu_thermal(pico_thermal_t *out);

/// Legge temperatura media e hotspot GPU via AppleSMC.
int pico_read_gpu_thermal(pico_thermal_t *out);

/// Legge la potenza totale del sistema in Watt (chiave PSTR di AppleSMC).
int pico_read_system_power(pico_power_t *out);

/// Rilascia la connessione AppleSMC se aperta.
void pico_release_smc(void);

/// Scansiona in-process i processi attivi via libproc e popola i primi 5 per physical footprint.
int pico_read_top_processes(pico_top_processes_t *out);

/// Getters sicuri per i campi dei top 5 processi (zero allocazioni o buffer intermedi).
int32_t pico_get_top_process_pid(const pico_top_processes_t *procs, int index);
uint64_t pico_get_top_process_footprint(const pico_top_processes_t *procs, int index);
const char *pico_get_top_process_name(const pico_top_processes_t *procs, int index);

#ifdef __cplusplus
}
#endif

#endif /* PICO_CSHIM_H */
