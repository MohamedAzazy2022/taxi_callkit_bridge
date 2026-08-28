#import <Foundation/Foundation.h>
#include <stdint.h>

extern intptr_t Iris_InitDartApiDL(void *data);

__attribute__((used))
static intptr_t (*volatile TaxiAgoraRetainedIrisInitDartApiDL)(void *) =
    Iris_InitDartApiDL;

@interface TaxiAgoraIrisSymbolRetainer : NSObject
@end

@implementation TaxiAgoraIrisSymbolRetainer

+ (void)load {
  (void)TaxiAgoraRetainedIrisInitDartApiDL;
}

@end