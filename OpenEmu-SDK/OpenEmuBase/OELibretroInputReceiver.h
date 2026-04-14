#import <Foundation/Foundation.h>
@protocol OELibretroInputReceiver <NSObject>
- (void)receiveLibretroButton:(uint8_t)buttonID forPort:(NSUInteger)port pressed:(BOOL)pressed;
- (void)receiveLibretroAnalogIndex:(uint8_t)index axis:(uint8_t)axis value:(int16_t)value forPort:(NSUInteger)port;
@end
