#ifndef GeckoViewSwiftSupport_h
#define GeckoViewSwiftSupport_h

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@protocol EventCallback <NSObject>
- (void)sendSuccess:(id _Nullable)result;
- (void)sendError:(id _Nullable)error;
@end

@protocol GeckoEventDispatcher <NSObject>
- (void)dispatch:(NSString * _Nonnull)type message:(id _Nullable)message;
@end

@protocol SwiftEventDispatcher <NSObject>
@end

@protocol SwiftGeckoViewRuntime <NSObject>
- (id<SwiftEventDispatcher> _Nonnull)runtimeDispatcher;
- (id<SwiftEventDispatcher> _Nonnull)dispatcherByName:(const char * _Nonnull)name;
- (void)childProcessDidStartWithPID:(int32_t)pid processType:(NSString * _Nonnull)processType;
@end

@protocol GeckoViewInputResultDelegate <NSObject>
@end

@protocol GeckoViewWindow <NSObject>
- (UIView * _Nullable)view;
- (void)setInputResultDelegate:(id<GeckoViewInputResultDelegate> _Nullable)delegate;
- (void)close;
@end

#endif /* GeckoViewSwiftSupport_h */
