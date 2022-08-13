//
//  CloudSwitchModel.h
//  CloudSwitch
//
//  Created by Jasom Pi on 8/11/22.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol CloudSwitchModelDelegate <NSObject>

- (void)onAuthenticationChanged;
- (void)onSwitchStateChanged;
- (void)onReceiveSwitchCode:(NSString *)tristateCode;

@end

@protocol ParticleDevice <NSObject>

@property (nonatomic, readonly) NSString* id;
@property (nonatomic, readonly, nullable) NSString* name;

@end

@interface CloudSwitchModel : NSObject

@property (nonatomic, readonly) BOOL isAuthenticated;
@property (nonatomic, readonly) BOOL cloudSwitchDeviceReachable;
@property (nonatomic, readonly) NSArray<id<ParticleDevice>> *availableDevices;
@property (nonatomic, readonly) id<ParticleDevice> cloudSwitchDevice;
@property (nonatomic, readonly) NSUInteger numberOfSwitches;
@property (strong, nonatomic, readonly) NSArray<NSString *> *switchNames;
@property (strong, nonatomic, readonly) NSArray<NSString *> *switchCodes;

- (instancetype)initWithDelegate:(id<CloudSwitchModelDelegate>)delegate;
- (void)restoreCloudSwitchDevice;

- (void)loginWithUsername:(NSString *)username
                 password:(NSString *)password
               completion:(void (^)(NSError * _Nullable error))completion;
- (void)seleteCloudSwitchDevice:(id<ParticleDevice>)cloudSwitchDevice;
- (void)logout;

- (BOOL)toggleSwitch:(NSUInteger)switchIndex completion:(void (^)(NSError * _Nullable))completion;
- (void)updateSwitch:(NSUInteger)switchIndex withName:(NSString *)name tristateCode:(NSString *)tristateCode;

- (void)startListenForCode;
- (void)stopListenForCode;

@end

NS_ASSUME_NONNULL_END
