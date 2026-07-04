#import <Foundation/Foundation.h>

#import "OBNPolycall.h"

int main(void) {
    @autoreleasepool {
        int32_t status = [OBNPolycall rawStatusForConfigAtPath:@"objc-polycallrc"];
        NSCAssert(status == 0, @"expected success status");

        NSError *error = nil;
        BOOL succeeded = [OBNPolycall runConfigAtPath:@"__status_37__"
                                                 error:&error];
        NSCAssert(!succeeded, @"expected failure");
        NSCAssert(error != nil, @"expected NSError");
        NSCAssert(error.code == 37, @"expected status 37");
        NSCAssert([error.domain isEqualToString:OBNPolycallErrorDomain],
                  @"unexpected error domain");

        NSLog(@"objc-polycall Objective-C smoke test: PASS");
    }
    return 0;
}
