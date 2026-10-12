#import <Foundation/Foundation.h>
#import <Security/Security.h>
#include "bridge.h"
#include <string.h>
#include <stdlib.h>
// Keychain contains credentials, the local outbox key and small queue indexes only.
static NSDictionary *secretQuery(){return @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,(__bridge id)kSecAttrService:@"chat.clawkit.shared-clipboard",(__bridge id)kSecAttrAccount:@"session"};}
extern "C" char *native_secret_load(){@autoreleasepool{
 NSMutableDictionary *q=[secretQuery()mutableCopy];q[(__bridge id)kSecReturnData]=@YES;
 CFTypeRef value=nullptr;OSStatus status=SecItemCopyMatching((__bridge CFDictionaryRef)q,&value);
 if(status!=errSecSuccess)return strdup("");
 NSData *data=CFBridgingRelease(value);return strdup(([[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding]?:@"").UTF8String);
}}
extern "C" int native_secret_save(const char *text){@autoreleasepool{
 NSData *data=[@(text)dataUsingEncoding:NSUTF8StringEncoding];
 OSStatus status=SecItemUpdate((__bridge CFDictionaryRef)secretQuery(),(__bridge CFDictionaryRef)@{(__bridge id)kSecValueData:data});
 if(status==errSecItemNotFound){NSMutableDictionary *q=[secretQuery()mutableCopy];q[(__bridge id)kSecValueData]=data;q[(__bridge id)kSecAttrAccessible]=(__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;status=SecItemAdd((__bridge CFDictionaryRef)q,nullptr);}
 return status==errSecSuccess;
}}

extern "C" char *native_data_dir(){@autoreleasepool{
 NSURL *root=[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
 NSURL *dir=[root URLByAppendingPathComponent:@"chat.clawkit.shared-clipboard" isDirectory:YES];
 if(![NSFileManager.defaultManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil])return strdup("");
 return strdup(dir.path.UTF8String);
}}
