#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
/// All methods and callbacks run on the main thread. Bluetooth starts only on start().
@interface KVMTransport : NSObject
@property(nonatomic, copy, nullable) void (^onChange)(void);
@property(nonatomic, copy, nullable) void (^onMessage)(NSString *message);
@property(nonatomic, readonly) BOOL started;
@property(nonatomic, readonly) BOOL ready;
@property(nonatomic, readonly) BOOL scanning;
@property(nonatomic, readonly) BOOL mouseCanAccept;
@property(nonatomic, readonly) BOOL keyboardCanAccept;
@property(nonatomic, readonly) BOOL keyboardIdle;
@property(nonatomic, readonly, nullable) NSDictionary<NSString *, NSString *> *lastDevice;
@property(nonatomic, readonly) NSInteger bluetoothState;
@property(nonatomic, readonly) NSInteger connectionState;
@property(nonatomic, readonly) NSArray<NSDictionary<NSString *, id> *> *devices;
- (void)start;
- (void)scan;
- (void)stopScan;
- (void)connect:(NSString *)identifier;
- (void)disconnect;
- (void)typeHello;
- (void)typeText:(NSString *)text;
- (void)sendKeyboard:(NSData *)report;
- (void)sendMouse:(uint8_t)buttons x:(int8_t)x y:(int8_t)y wheel:(int8_t)wheel;
- (void)releaseInputs;
@end
NS_ASSUME_NONNULL_END
