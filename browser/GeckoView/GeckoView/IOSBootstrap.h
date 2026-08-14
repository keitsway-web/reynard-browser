#ifndef IOSBootstrap_h
#define IOSBootstrap_h

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <GeckoView/GeckoViewSwiftSupport.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void * xpc_connection_t;

@protocol GeckoProcessExtension <NSObject>
@end

void MainProcessInit(int32_t argc, char * _Nullable * _Nullable argv, id<SwiftGeckoViewRuntime> _Nonnull runtime);
void ChildProcessInit(xpc_connection_t _Nullable connection, id<GeckoProcessExtension> _Nullable process, id<SwiftGeckoViewRuntime> _Nonnull runtime);
void updateJetsamControl(int32_t pid);
id<GeckoViewWindow> _Nullable GeckoViewCreateWindow(void);

#ifdef __cplusplus
}
#endif

#endif /* IOSBootstrap_h */
