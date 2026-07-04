#import <Foundation/Foundation.h>

#import "OBNPolycall.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *configPath = argc > 1
            ? [NSString stringWithUTF8String:argv[1]]
            : @"objc-polycallrc";
        NSError *error = nil;

        if (![OBNPolycall runConfigAtPath:configPath error:&error]) {
            NSLog(@"%@", error.localizedDescription);
            return (int)error.code;
        }

        NSLog(@"libpolycall completed '%@' successfully", configPath);
    }
    return 0;
}
