//
//  KeychainShim.c
//  SceneBox
//
//  Created by SpontaneousArray on 20.09.26.
//

#include <TargetConditionals.h>

#if TARGET_OS_OSX || TARGET_OS_MACCATALYST

#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>
#include <dispatch/dispatch.h>
#include <os/lock.h>
#include <limits.h>
#include <stdbool.h>
#include <stdio.h>
#include <sys/stat.h>
#include <unistd.h>

#define INTERPOSE(replacement, original) \
    __attribute__((used)) static const struct { const void *replacement; const void *original; } \
    interpose_##original __attribute__((section("__DATA,__interpose"))) = \
    { (const void *)&replacement, (const void *)&original }

static CFStringRef const kItemService = CFSTR("service");
static CFStringRef const kItemAccount = CFSTR("account");
static CFStringRef const kItemData = CFSTR("data");

static os_unfair_lock storeLock = OS_UNFAIR_LOCK_INIT;
static CFMutableArrayRef storeItems;
static char storePath[PATH_MAX];

static bool dataProtectionKeychainUnavailable(void) {
    static bool unavailable;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        const void *keys[] = { kSecClass, kSecAttrService, kSecAttrAccount, kSecUseDataProtectionKeychain };
        const void *values[] = { kSecClassGenericPassword, CFSTR("app.scenebox.keychain-probe"),
                                 CFSTR("probe"), kCFBooleanTrue };
        CFDictionaryRef probe = CFDictionaryCreate(NULL, keys, values, 4,
                                                   &kCFTypeDictionaryKeyCallBacks,
                                                   &kCFTypeDictionaryValueCallBacks);
        OSStatus status = SecItemDelete(probe);
        CFRelease(probe);
        unavailable = status == errSecMissingEntitlement;
    });
    return unavailable;
}

static void storeLoad(void) {
    if (storeItems) return;
    storeItems = CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);

    CFURLRef home = CFCopyHomeDirectoryURL();
    CFStringRef bundleID = CFBundleGetIdentifier(CFBundleGetMainBundle()) ?: CFSTR("KeychainShim");
    CFStringRef relative = CFStringCreateWithFormat(NULL, NULL, CFSTR("Library/Application Support/%@"), bundleID);
    CFURLRef dir = CFURLCreateCopyAppendingPathComponent(NULL, home, relative, true);
    CFURLRef file = CFURLCreateCopyAppendingPathComponent(NULL, dir, CFSTR("keychain-items.plist"), false);

    char dirPath[PATH_MAX];
    if (CFURLGetFileSystemRepresentation(dir, true, (UInt8 *)dirPath, sizeof dirPath)) {
        char *slash = strrchr(dirPath, '/');
        if (slash) { *slash = 0; mkdir(dirPath, 0700); *slash = '/'; }
        mkdir(dirPath, 0700);
    }
    CFURLGetFileSystemRepresentation(file, true, (UInt8 *)storePath, sizeof storePath);
    CFRelease(home); CFRelease(relative); CFRelease(dir); CFRelease(file);

    FILE *f = fopen(storePath, "rb");
    if (!f) return;
    CFMutableDataRef raw = CFDataCreateMutable(NULL, 0);
    UInt8 buffer[4096];
    size_t n;
    while ((n = fread(buffer, 1, sizeof buffer, f)) > 0) CFDataAppendBytes(raw, buffer, (CFIndex)n);
    fclose(f);
    CFPropertyListRef plist = CFPropertyListCreateWithData(NULL, raw, kCFPropertyListMutableContainers, NULL, NULL);
    CFRelease(raw);
    if (!plist) return;
    if (CFGetTypeID(plist) == CFArrayGetTypeID()) {
        CFArrayRef items = plist;
        for (CFIndex i = 0; i < CFArrayGetCount(items); i++) {
            CFTypeRef item = CFArrayGetValueAtIndex(items, i);
            if (CFGetTypeID(item) == CFDictionaryGetTypeID()) CFArrayAppendValue(storeItems, item);
        }
    }
    CFRelease(plist);
}

static void storeSave(void) {
    CFDataRef data = CFPropertyListCreateData(NULL, storeItems, kCFPropertyListBinaryFormat_v1_0, 0, NULL);
    if (!data) return;
    char tmpPath[PATH_MAX];
    snprintf(tmpPath, sizeof tmpPath, "%s.tmp", storePath);
    FILE *f = fopen(tmpPath, "wb");
    if (f) {
        fwrite(CFDataGetBytePtr(data), 1, (size_t)CFDataGetLength(data), f);
        fclose(f);
        chmod(tmpPath, 0600);
        rename(tmpPath, storePath);
    }
    CFRelease(data);
}

static bool valueMatches(CFDictionaryRef query, CFStringRef queryKey, CFDictionaryRef item, CFStringRef itemKey) {
    CFTypeRef wanted = CFDictionaryGetValue(query, queryKey);
    if (!wanted) return true;
    CFTypeRef actual = CFDictionaryGetValue(item, itemKey);
    return actual && CFEqual(wanted, actual);
}

static bool itemMatches(CFDictionaryRef item, CFDictionaryRef query) {
    return valueMatches(query, kSecAttrService, item, kItemService)
        && valueMatches(query, kSecAttrAccount, item, kItemAccount);
}

static bool boolValue(CFDictionaryRef dict, CFStringRef key) {
    CFTypeRef value = CFDictionaryGetValue(dict, key);
    return value && CFGetTypeID(value) == CFBooleanGetTypeID() && CFBooleanGetValue(value);
}

static CFTypeRef copyResult(CFDictionaryRef item, bool wantData, bool wantAttributes) {
    CFTypeRef data = CFDictionaryGetValue(item, kItemData);
    if (wantData && !wantAttributes) return data ? CFRetain(data) : NULL;
    CFMutableDictionaryRef result = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks,
                                                              &kCFTypeDictionaryValueCallBacks);
    CFDictionarySetValue(result, kSecClass, kSecClassGenericPassword);
    CFTypeRef service = CFDictionaryGetValue(item, kItemService);
    CFTypeRef account = CFDictionaryGetValue(item, kItemAccount);
    if (service) CFDictionarySetValue(result, kSecAttrService, service);
    if (account) CFDictionarySetValue(result, kSecAttrAccount, account);
    if (wantData && data) CFDictionarySetValue(result, kSecValueData, data);
    return result;
}

static OSStatus storeCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    os_unfair_lock_lock(&storeLock);
    storeLoad();
    bool wantData = boolValue(query, kSecReturnData);
    bool wantAttributes = boolValue(query, kSecReturnAttributes);
    CFIndex limit = 1;
    CFTypeRef limitValue = CFDictionaryGetValue(query, kSecMatchLimit);
    if (limitValue) {
        if (CFEqual(limitValue, kSecMatchLimitAll)) limit = LONG_MAX;
        else if (CFGetTypeID(limitValue) == CFNumberGetTypeID()) CFNumberGetValue(limitValue, kCFNumberCFIndexType, &limit);
    }
    CFMutableArrayRef matches = CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);
    for (CFIndex i = 0; i < CFArrayGetCount(storeItems) && CFArrayGetCount(matches) < limit; i++) {
        CFDictionaryRef item = CFArrayGetValueAtIndex(storeItems, i);
        if (!itemMatches(item, query)) continue;
        CFTypeRef entry = copyResult(item, wantData, wantAttributes);
        if (entry) { CFArrayAppendValue(matches, entry); CFRelease(entry); }
    }
    os_unfair_lock_unlock(&storeLock);

    OSStatus status = CFArrayGetCount(matches) ? errSecSuccess : errSecItemNotFound;
    if (result) {
        if (status != errSecSuccess) *result = NULL;
        else if (limit > 1) *result = CFRetain(matches);
        else *result = CFRetain(CFArrayGetValueAtIndex(matches, 0));
    }
    CFRelease(matches);
    return status;
}

static OSStatus storeAdd(CFDictionaryRef attributes, CFTypeRef *result) {
    if (result) *result = NULL;
    CFTypeRef account = CFDictionaryGetValue(attributes, kSecAttrAccount);
    CFTypeRef data = CFDictionaryGetValue(attributes, kSecValueData);
    if (!account || !data) return errSecParam;

    os_unfair_lock_lock(&storeLock);
    storeLoad();
    OSStatus status = errSecSuccess;
    for (CFIndex i = 0; i < CFArrayGetCount(storeItems); i++) {
        if (itemMatches(CFArrayGetValueAtIndex(storeItems, i), attributes)) { status = errSecDuplicateItem; break; }
    }
    if (status == errSecSuccess) {
        CFMutableDictionaryRef item = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks,
                                                                &kCFTypeDictionaryValueCallBacks);
        CFTypeRef service = CFDictionaryGetValue(attributes, kSecAttrService);
        if (service) CFDictionarySetValue(item, kItemService, service);
        CFDictionarySetValue(item, kItemAccount, account);
        CFDictionarySetValue(item, kItemData, data);
        CFArrayAppendValue(storeItems, item);
        CFRelease(item);
        storeSave();
    }
    os_unfair_lock_unlock(&storeLock);
    return status;
}

static OSStatus storeUpdate(CFDictionaryRef query, CFDictionaryRef attributesToUpdate) {
    os_unfair_lock_lock(&storeLock);
    storeLoad();
    CFIndex updated = 0;
    for (CFIndex i = 0; i < CFArrayGetCount(storeItems); i++) {
        CFMutableDictionaryRef item = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(storeItems, i);
        if (!itemMatches(item, query)) continue;
        CFTypeRef data = CFDictionaryGetValue(attributesToUpdate, kSecValueData);
        CFTypeRef service = CFDictionaryGetValue(attributesToUpdate, kSecAttrService);
        CFTypeRef account = CFDictionaryGetValue(attributesToUpdate, kSecAttrAccount);
        if (data) CFDictionarySetValue(item, kItemData, data);
        if (service) CFDictionarySetValue(item, kItemService, service);
        if (account) CFDictionarySetValue(item, kItemAccount, account);
        updated++;
    }
    if (updated) storeSave();
    os_unfair_lock_unlock(&storeLock);
    return updated ? errSecSuccess : errSecItemNotFound;
}

static OSStatus storeDelete(CFDictionaryRef query) {
    os_unfair_lock_lock(&storeLock);
    storeLoad();
    CFIndex removed = 0;
    for (CFIndex i = CFArrayGetCount(storeItems) - 1; i >= 0; i--) {
        if (!itemMatches(CFArrayGetValueAtIndex(storeItems, i), query)) continue;
        CFArrayRemoveValueAtIndex(storeItems, i);
        removed++;
    }
    if (removed) storeSave();
    os_unfair_lock_unlock(&storeLock);
    return removed ? errSecSuccess : errSecItemNotFound;
}

static OSStatus shimSecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    if (query && dataProtectionKeychainUnavailable()) return storeCopyMatching(query, result);
    return SecItemCopyMatching(query, result);
}

static OSStatus shimSecItemAdd(CFDictionaryRef attributes, CFTypeRef *result) {
    if (attributes && dataProtectionKeychainUnavailable()) return storeAdd(attributes, result);
    return SecItemAdd(attributes, result);
}

static OSStatus shimSecItemUpdate(CFDictionaryRef query, CFDictionaryRef attributesToUpdate) {
    if (query && attributesToUpdate && dataProtectionKeychainUnavailable()) return storeUpdate(query, attributesToUpdate);
    return SecItemUpdate(query, attributesToUpdate);
}

static OSStatus shimSecItemDelete(CFDictionaryRef query) {
    if (query && dataProtectionKeychainUnavailable()) return storeDelete(query);
    return SecItemDelete(query);
}

INTERPOSE(shimSecItemCopyMatching, SecItemCopyMatching);
INTERPOSE(shimSecItemAdd, SecItemAdd);
INTERPOSE(shimSecItemUpdate, SecItemUpdate);
INTERPOSE(shimSecItemDelete, SecItemDelete);

#endif
