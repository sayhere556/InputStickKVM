#import "KVMTransport.h"
#import "InputStickManager.h"
#import "InputStickKeyboardHandler.h"
#import "InputStickMouseHandler.h"
#import "InputStickManagerDelegate.h"
#import "InputStickConnectionManager.h"
#import "InputStickPeripheralInfo.h"
#import "InputStickHIDBuffersManager.h"
#import "InputStickHIDReport.h"
#import "InputStickDeviceDB.h"
#import "InputStickDeviceData.h"

@interface KVMTransport () <InputStickManagerDelegate, InputStickConnectionNotificationObserver, InputStickPeripheralScanNotificationObserver>
@property(nonatomic, strong) InputStickManager *manager;
@property(nonatomic, readwrite) BOOL scanning;
@end

@implementation KVMTransport
- (void)start {
    if (_manager) return;
    _manager = [[InputStickManager alloc] init];
    _manager.delegate = self;
    [NSNotificationCenter.defaultCenter registerForInputStickConnectionNotificationsWithObserver:self];
    [NSNotificationCenter.defaultCenter registerForInputStickPeripheralScanNotificationsWithObserver:self];
    [self changed];
}
- (void)dealloc {
    [NSNotificationCenter.defaultCenter unregisterFromInputStickConnectionNotificationsWithObserver:self];
    [NSNotificationCenter.defaultCenter unregisterFromInputStickPeripheralScanNotificationsWithObserver:self];
}
- (BOOL)started { return _manager != nil; }
- (BOOL)ready { return _manager.inputStickReady; }
- (BOOL)mouseCanAccept { return self.ready && _manager.buffersManager.mouseLocalBufferEmpty; }
- (BOOL)keyboardCanAccept { return self.ready && _manager.buffersManager.keyboardLocalBufferEmpty; }
- (BOOL)keyboardIdle { return self.ready && _manager.buffersManager.keyboardBufferEmpty; }
- (NSDictionary *)lastDevice {
    NSString *identifier = [_manager.deviceDB getMostRecentlyUsedDeviceIdentifier];
    if (!identifier) return nil;
    InputStickDeviceData *device = [_manager.deviceDB getDataForDeviceWithIdentifier:identifier];
    return @{@"id":identifier, @"name":device.name ?: @"InputStick"};
}
- (NSInteger)bluetoothState { return _manager ? _manager.connectionManager.bluetoothCentralManager.state : 0; }
- (NSInteger)connectionState { return _manager.connectionState; }
- (NSArray *)devices {
    NSMutableArray *result = [NSMutableArray array];
    for (InputStickPeripheralInfo *device in _manager.connectionManager.foundPeripherals) {
        [result addObject:@{@"id":device.identifier, @"name":device.name ?: @"InputStick", @"rssi":@(device.rssi)}];
    }
    return result;
}
- (void)changed { if (self.onChange) self.onChange(); }
- (void)message:(NSString *)message { if (self.onMessage) self.onMessage(message); }
- (void)scan { if (self.bluetoothState == CBManagerStatePoweredOn) [_manager startBluetoothPeripheralScanWithTimeout:YES]; }
- (void)stopScan { [_manager stopBluetoothPeripheralScan]; }
- (void)connect:(NSString *)identifier {
    if (self.bluetoothState != CBManagerStatePoweredOn) return;
    [self stopScan];
    [_manager connectToInputStickWithIdentifier:identifier];
}
- (void)disconnect {
    [self releaseInputs];
    [self stopScan];
    // Allow queued neutral reports a short opportunity to leave before closing BLE.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 150 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        [self.manager disconnectFromInputStick];
    });
}
- (void)typeHello { if (self.ready) [_manager.keyboardHandler typeText:@"hello"]; }
- (void)typeText:(NSString *)text { if (self.ready) [_manager.keyboardHandler typeText:text]; }
- (void)sendKeyboard:(NSData *)report {
    if (!self.ready || report.length != 8) return;
    Byte bytes[8];
    [report getBytes:bytes length:8];
    [_manager.buffersManager addKeyboardHIDReport:[InputStickHIDReport keyboardReportWithBytes:bytes] flush:YES];
}
- (void)sendMouse:(uint8_t)buttons x:(int8_t)x y:(int8_t)y wheel:(int8_t)wheel {
    if (self.ready) [_manager.mouseHandler sendCustomReportWithButtons:buttons x:x y:y scroll:wheel flush:YES];
}
- (void)releaseInputs {
    if (!_manager) return;
    [_manager.buffersManager clearHIDBuffers];
    if (self.ready) {
        [_manager.keyboardHandler sendCustomReportWithModifiers:0 key:0 flush:YES];
        [_manager.mouseHandler sendCustomReportWithButtons:0 x:0 y:0 scroll:0 flush:YES];
    }
}
- (void)didUpdateInputStickConnectionState:(NSNotification *)notification {
    // Never restore a held key/button after reconnecting or USB resume.
    if (self.ready) [self releaseInputs];
    [self changed];
}
- (void)didUpdateInputStickPeripheralsList:(NSNotification *)notification { [self changed]; }
- (void)didStartInputStickPeripheralScan { self.scanning = YES; [self changed]; }
- (void)didFinishInputStickPeripheralScan { self.scanning = NO; [self changed]; }
- (void)didTimeoutInputStickPeripheralScan { self.scanning = NO; [self changed]; }
- (void)inputStickManager:(InputStickManager *)manager presentErrorDialog:(NSError *)error {
    [self message:[NSString stringWithFormat:@"%@ (code %ld)", error.localizedDescription, (long)error.code]];
}
- (BOOL)inputStickManager:(InputStickManager *)manager presentEncryptionKeyDialog:(InputStickDeviceData *)data request:(InputStickKeyRequest)request {
    [self message:@"This prototype has no password-entry screen yet. A protected device will disconnect; its protection is not changed."];
    return NO;
}
- (void)inputStickManager:(InputStickManager *)manager presentFirmwareUpdateDialog:(InputStickDeviceData *)data {
    [self message:@"The SDK recommends a firmware update through InputStickUtility. No firmware changes were made."];
}
- (void)inputStickManager:(InputStickManager *)manager presentUSBResumeDialog:(InputStickDeviceData *)data {
    [self message:@"The receiving computer is asleep. Wake it, then reconnect if needed."];
}
@end
