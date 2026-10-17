// Private system interfaces Hum reads hardware data from.
// IOHIDEventSystemClient: Apple Silicon temperature sensors (same approach as Stats).
// IOReport: per-block energy and GPU frequency residency (same approach as powermetrics / macmon).

#ifndef Hum_Bridging_Header_h
#define Hum_Bridging_Header_h

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/ps/IOPowerSources.h>
#include <IOKit/ps/IOPSKeys.h>
#include <libproc.h>
#include <sys/sysctl.h>
#include <mach/mach.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <net/if_dl.h>

CF_IMPLICIT_BRIDGING_ENABLED
CF_ASSUME_NONNULL_BEGIN

typedef struct CF_BRIDGED_TYPE(id) __IOHIDEvent *IOHIDEventRef;
typedef struct CF_BRIDGED_TYPE(id) __IOHIDServiceClient *IOHIDServiceClientRef;
typedef struct CF_BRIDGED_TYPE(id) __IOHIDEventSystemClient *IOHIDEventSystemClientRef;

IOHIDEventSystemClientRef _Nullable IOHIDEventSystemClientCreate(CFAllocatorRef _Nullable allocator) CF_RETURNS_RETAINED;
int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef match);
CFArrayRef _Nullable IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef client) CF_RETURNS_RETAINED;
CFTypeRef _Nullable IOHIDServiceClientCopyProperty(IOHIDServiceClientRef service, CFStringRef property) CF_RETURNS_RETAINED;
IOHIDEventRef _Nullable IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service, int64_t type, int32_t options, int64_t timestamp) CF_RETURNS_RETAINED;
double IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);

typedef struct CF_BRIDGED_TYPE(id) IOReportSubscription *IOReportSubscriptionRef;

CFDictionaryRef _Nullable IOReportCopyChannelsInGroup(CFStringRef _Nullable group, CFStringRef _Nullable subgroup, uint64_t a, uint64_t b, uint64_t c) CF_RETURNS_RETAINED;
void IOReportMergeChannels(CFMutableDictionaryRef a, CFDictionaryRef b, CFTypeRef _Nullable unused);
IOReportSubscriptionRef _Nullable IOReportCreateSubscription(void * _Nullable a, CFMutableDictionaryRef channels, CFMutableDictionaryRef _Nullable * _Nonnull subscribed, uint64_t channelID, CFTypeRef _Nullable b) CF_RETURNS_RETAINED;
CFDictionaryRef _Nullable IOReportCreateSamples(IOReportSubscriptionRef subscription, CFMutableDictionaryRef channels, CFTypeRef _Nullable unused) CF_RETURNS_RETAINED;
CFDictionaryRef _Nullable IOReportCreateSamplesDelta(CFDictionaryRef previous, CFDictionaryRef current, CFTypeRef _Nullable unused) CF_RETURNS_RETAINED;
CFStringRef _Nullable IOReportChannelGetGroup(CFDictionaryRef channel);
CFStringRef _Nullable IOReportChannelGetSubGroup(CFDictionaryRef channel);
CFStringRef _Nullable IOReportChannelGetChannelName(CFDictionaryRef channel);
CFStringRef _Nullable IOReportChannelGetUnitLabel(CFDictionaryRef channel);
int64_t IOReportSimpleGetIntegerValue(CFDictionaryRef channel, int32_t index);
int32_t IOReportStateGetCount(CFDictionaryRef channel);
CFStringRef _Nullable IOReportStateGetNameForIndex(CFDictionaryRef channel, int32_t index);
int64_t IOReportStateGetResidency(CFDictionaryRef channel, int32_t index);

CF_ASSUME_NONNULL_END
CF_IMPLICIT_BRIDGING_DISABLED

#endif
