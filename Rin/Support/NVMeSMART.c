#include "NVMeSMART.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/storage/nvme/NVMeSMARTLibExternal.h>
#include <string.h>

static int readService(io_service_t service, RinNVMeSMART *out) {
    CFTypeRef capable = IORegistryEntryCreateCFProperty(service, CFSTR("NVMe SMART Capable"), kCFAllocatorDefault, 0);
    int isCapable = capable && CFGetTypeID(capable) == CFBooleanGetTypeID() && CFBooleanGetValue(capable);
    if (capable) CFRelease(capable);
    if (!isCapable) return 0;

    IOCFPlugInInterface **plugin = NULL;
    SInt32 score = 0;
    if (IOCreatePlugInInterfaceForService(service, kIONVMeSMARTUserClientTypeID, kIOCFPlugInInterfaceID, &plugin, &score) != kIOReturnSuccess || !plugin) return 0;

    int ok = 0;
    IONVMeSMARTInterface **smart = NULL;
    if ((*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIONVMeSMARTInterfaceID), (LPVOID *)&smart) == S_OK && smart) {
        NVMeSMARTData data;
        memset(&data, 0, sizeof(data));
        if ((*smart)->SMARTReadData(smart, &data) == kIOReturnSuccess) {
            out->criticalWarning = data.CRITICAL_WARNING;
            out->percentageUsed = data.PERCENTAGE_USED;
            out->temperatureC = data.TEMPERATURE > 0 ? (double)data.TEMPERATURE - 273.15 : 0;
            // Data units are thousands of 512-byte blocks.
            out->bytesRead = data.DATA_UNITS_READ[0] * 512000ULL;
            out->bytesWritten = data.DATA_UNITS_WRITTEN[0] * 512000ULL;
            ok = 1;
        }
        (*smart)->Release(smart);
    }
    IODestroyPlugInInterface(plugin);
    return ok;
}

int RinReadNVMeSMART(RinNVMeSMART *out) {
    io_iterator_t iterator = 0;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IONVMeBlockStorageDevice"), &iterator) != KERN_SUCCESS) return 0;
    int ok = 0;
    io_service_t service;
    while (!ok && (service = IOIteratorNext(iterator))) {
        ok = readService(service, out);
        IOObjectRelease(service);
    }
    IOObjectRelease(iterator);
    return ok;
}
