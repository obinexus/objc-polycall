#import "OBNPolycall.h"

#include "objc_polycall.h"

NSString * const OBNPolycallErrorDomain = @"org.obinexus.polycall";

@implementation OBNPolycall

+ (int32_t)rawStatusForConfigAtPath:(NSString *)configPath {
    if (configPath == nil) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"configPath must not be nil"
                                     userInfo:nil];
    }

    const char *utf8Path = [configPath UTF8String];
    if (utf8Path == NULL) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"configPath could not be encoded as UTF-8"
                                     userInfo:nil];
    }

    return objc_polycall_run_config(utf8Path);
}

+ (BOOL)runConfigAtPath:(NSString *)configPath
                   error:(NSError * _Nullable * _Nullable)error {
    int32_t status = [self rawStatusForConfigAtPath:configPath];
    if (status == 0) {
        return YES;
    }

    if (error != NULL) {
        NSString *description = [NSString stringWithFormat:
            @"libpolycall failed with status %d for config '%@'",
            status,
            configPath];
        *error = [NSError errorWithDomain:OBNPolycallErrorDomain
                                     code:(NSInteger)status
                                 userInfo:@{
                                     NSLocalizedDescriptionKey: description,
                                     @"configPath": configPath
                                 }];
    }
    return NO;
}

@end
