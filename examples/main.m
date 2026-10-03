#import <Foundation/Foundation.h>

#import "OBNPolycall.h"

#include <stdio.h>

/* @autoreleasepool under ARC; NSAutoreleasePool under manual reference counting (GCC). */
#if defined(__has_feature)
#  if __has_feature(objc_arc)
#    define EX_ARC 1
#  endif
#endif
#ifdef EX_ARC
#  define EX_POOL_BEGIN @autoreleasepool {
#  define EX_POOL_END }
#else
#  define EX_POOL_BEGIN { NSAutoreleasePool *ex_pool_ = [[NSAutoreleasePool alloc] init];
#  define EX_POOL_END [ex_pool_ drain]; }
#endif

/*
 *   objc-polycall-example [config-path]   validate (strict) a *-polycallrc
 *   objc-polycall-example --version       library version and ABI check
 *
 * Exit status 0 on success, 1 on a Polycall error (printed to stderr).
 */
int main(int argc, const char *argv[]) {
    int rc = 0;
    EX_POOL_BEGIN
    NSError *error = nil;
    NSString *arg = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"objc-polycallrc";

    if ([arg isEqualToString:@"--version"]) {
        if ([OBNPolycall checkABIVersion:&error]) {
            printf("libpolycall %s (binding ABI %d) from %s\n", [[OBNPolycall libraryVersion] UTF8String],
                   [OBNPolycall abiVersion], [[OBNPolycall libraryPath] UTF8String]);
        } else {
            fprintf(stderr, "objc-polycall-example: %s\n", [[error localizedDescription] UTF8String]);
            rc = 1;
        }
    } else if ([OBNPolycall runConfigAtPath:arg error:&error]) {
        NSLog(@"libpolycall validated '%@' successfully", arg);
    } else {
        fprintf(stderr, "objc-polycall-example: %s\n", [[error localizedDescription] UTF8String]);
        rc = 1;
    }
    EX_POOL_END
    return rc;
}
