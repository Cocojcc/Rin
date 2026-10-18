// Reads the internal SSD's NVMe S.M.A.R.T. log through IOKit's public NVMeSMARTLib plug-in.

#ifndef NVMeSMART_h
#define NVMeSMART_h

#include <stdint.h>

typedef struct {
    uint8_t criticalWarning;
    uint8_t percentageUsed;     // 0...100 (can exceed 100 past rated endurance)
    double temperatureC;
    uint64_t bytesRead;
    uint64_t bytesWritten;
} HumNVMeSMART;

/// Returns 1 and fills `out` for the first SMART-capable NVMe drive, 0 when none answers.
int HumReadNVMeSMART(HumNVMeSMART *out);

#endif
