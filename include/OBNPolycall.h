#import <Foundation/Foundation.h>

#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const OBNPolycallErrorDomain;

@interface OBNPolycall : NSObject

+ (int32_t)rawStatusForConfigAtPath:(NSString *)configPath;

+ (BOOL)runConfigAtPath:(NSString *)configPath
                   error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
