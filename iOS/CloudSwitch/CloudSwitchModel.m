//
//  CloudSwitchModel.m
//  CloudSwitch
//
//  Created by Jasom Pi on 8/11/22.
//

#import "CloudSwitchModel.h"
#import "Particle-SDK.h"

#import <UIKit/UIKit.h>

static const NSUInteger kNumberOfSwitch = 5;

static NSString *const kCloudSwitchAccessTokenKey = @"CloudSwitchAccessTokenKey";
static NSString *const kCloudSwitchDeviceIDKey = @"CloudSwitchDeviceIDKey";
static NSString *const kCloudSwitchConfigNamesKey = @"names";
static NSString *const kCloudSwitchConfigCodesKey = @"codes";
static NSString *const kCloudSwitchConfigTimestampKey = @"timestamp";

static NSString *const kCloudSwitchFunctionName = @"sendtristate";
static NSString *const kCloudSwitchTristateReceivedEvent = @"tristate-received";
static NSString *const kCloudSwitchSetConfigFunctionName = @"setSwitchConfig";
static NSString *const kCloudSwitchGetConfigVariableName = @"switchConfig";
static NSString *const kCloudSwitchConfigChangedEvent = @"switchConfigChanged";
static NSString *const kCloudSwitchToggleSwitchFunction = @"toggleSwitch";
static NSString *const kCloudSwitchSetSwitchStateFunction = @"setSwitchState";
static NSString *const kCloudSwitchSwitchStateVariableName = @"switchState";
static NSString *const kCloudSwitchSwitchStateChangedEvent = @"switchStateChanged";

static const NSTimeInterval kCloudSwitchReachableCheckPeriod = 60.0;

@interface ParticleDevice (CloudSwitch)<ParticleDevice>

@end

@interface CloudSwitchModel ()<ParticleDeviceDelegate> {
    NSMutableArray<NSString *> *_switchNames;
    NSMutableArray<NSString *> *_switchCodes;
    BOOL _switchStates[kNumberOfSwitch];
    int64_t _timestamp;
    ParticleDevice *_cloudSwitchDevice;
    BOOL _cloudSwitchDeviceReachable;
}

@property (weak, nonatomic) id<CloudSwitchModelDelegate> delegate;
@property (copy, nonatomic) NSArray<ParticleDevice *> *availableDevices;
@property (strong, nonatomic) id tristateReceivedEventSubscriberId;
@property (strong, nonatomic) id switchConfigChangedEventSubscriberId;
@property (strong, nonatomic) id switchStateChangedEventSubscriberId;
@property (strong, nonatomic) NSDictionary<NSString *, id> *switchConfig;

@end

@implementation CloudSwitchModel

@dynamic switchConfig;

- (NSUInteger)numberOfSwitches {
    return kNumberOfSwitch;
}

- (BOOL)isAuthenticated {
    return [ParticleCloud sharedInstance].isAuthenticated;
}

- (BOOL)cloudSwitchDeviceReachable {
    dispatch_assert_queue(dispatch_get_main_queue());
    return _cloudSwitchDeviceReachable;
}

- (void)setCloudSwitchDeviceReachable:(BOOL)reachable {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_cloudSwitchDeviceReachable != reachable) {
            self->_cloudSwitchDeviceReachable = reachable;
            if (reachable) {
                [self performSelector:@selector(checkCloudSwitchDeviceReachable)
                               withObject:nil
                               afterDelay:kCloudSwitchReachableCheckPeriod];
            }
            [self.delegate onSwitchConfigChanged];
        }
    });
}

- (NSArray<NSString *> *)switchNames {
    return [_switchNames copy];
}

- (NSArray<NSString *> *)switchCodes {
    return [_switchCodes copy];
}

- (id<ParticleDevice>)cloudSwitchDevice {
    return _cloudSwitchDevice;
}

- (instancetype)initWithDelegate:(id<CloudSwitchModelDelegate>)delegate {
    self = [super init];
    if (self) {
        _delegate = delegate;
        [self loadSwitchConfig];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidBecomeActive)
                                                     name:UIApplicationDidBecomeActiveNotification
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidEnterBackground)
                                                     name:UIApplicationDidEnterBackgroundNotification
                                                   object:nil];
    }
    return self;
}

- (void)applicationDidBecomeActive {
    if (_cloudSwitchDevice != nil) {
        [self syncSwitchState];
        [self startListenForSwichStateChanged];
        [self startListenForSwichConfigChanged];
    }
}

- (void)applicationDidEnterBackground {
    if (_cloudSwitchDevice != nil) {
        [self stopListenForSwichStateChanged];
        [self stopListenForSwichConfigChanged];
    }
}

- (NSDictionary<NSString *, id> *)defaultSwitchConfig {
    NSString *emptyStrings[kNumberOfSwitch];
    for (NSUInteger i=0; i<kNumberOfSwitch; i++) {
        emptyStrings[i] = @"";
    }
    return @{
        kCloudSwitchConfigNamesKey: [NSArray<NSString *> arrayWithObjects:emptyStrings count:kNumberOfSwitch],
        kCloudSwitchConfigCodesKey: [NSArray<NSString *> arrayWithObjects:emptyStrings count:kNumberOfSwitch],
        kCloudSwitchConfigTimestampKey: @(0),
    };
}

- (NSDictionary<NSString *, id> *)switchConfig {
    return @{kCloudSwitchConfigNamesKey: _switchNames, kCloudSwitchConfigCodesKey: _switchCodes, kCloudSwitchConfigTimestampKey: @(_timestamp)};
}

- (void)setSwitchConfig:(NSDictionary<NSString *,id> *)switchConfig {
    NSAssert([CloudSwitchModel isValidSwitchConfig:switchConfig], @"Invalid switch config: %@", switchConfig);
    _switchNames = [switchConfig[kCloudSwitchConfigNamesKey] mutableCopy];
    _switchCodes = [switchConfig[kCloudSwitchConfigCodesKey] mutableCopy];
    _timestamp = [switchConfig[kCloudSwitchConfigTimestampKey] longLongValue];
}

- (void)sendSwitchConfig {
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:self.switchConfig
                                                       options:0
                                                         error:&error];

    if (!jsonData) {
        NSLog(@"Coud not serialize config to json error: %@", error);
    } else {
        NSString *jsonConfig = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        NSLog(@"Send switch config to '%@': %@", self.cloudSwitchDevice.name, jsonConfig);
        [_cloudSwitchDevice callFunction:kCloudSwitchSetConfigFunctionName
                           withArguments:@[jsonConfig]
                              completion:^(NSNumber * _Nullable result, NSError * _Nullable error) {
            if (error) {
                NSLog(@"Failed to send switch config to '%@' error: %@", self.cloudSwitchDevice.name, error);
                [self checkCloudSwitchDeviceReachable];
            }
            
        }];
    }
}

+ (BOOL)isValidSwitchConfig:(NSDictionary<NSString *, id> *)switchConfig {
    if (!switchConfig) return NO;
    if (![switchConfig[kCloudSwitchConfigNamesKey] isKindOfClass:[NSArray class]]) return NO;
    if (![switchConfig[kCloudSwitchConfigCodesKey] isKindOfClass:[NSArray class]]) return NO;
    if (![switchConfig[kCloudSwitchConfigTimestampKey] isKindOfClass:[NSNumber class]]) return NO;
    return [switchConfig[kCloudSwitchConfigNamesKey] count] == kNumberOfSwitch && [switchConfig[kCloudSwitchConfigCodesKey] count] == kNumberOfSwitch;
}

- (void)saveSwitchConfig {
    [[NSUserDefaults standardUserDefaults] setObject:self.switchConfig forKey:self.cloudSwitchDevice.id];
}

- (void)loadSwitchConfig {
    NSDictionary<NSString *, id> *switchConfig = [self defaultSwitchConfig];
    if (self.cloudSwitchDevice.id) {
        NSDictionary<NSString *, id> *switchConfigFromUserDefaults = [[NSUserDefaults standardUserDefaults] objectForKey:self.cloudSwitchDevice.id];
        if ([CloudSwitchModel isValidSwitchConfig:switchConfigFromUserDefaults]) {
            switchConfig = switchConfigFromUserDefaults;
        }
    }
    self.switchConfig = switchConfig;
}

- (void)syncSwitchConfig {
    [_cloudSwitchDevice getVariable:kCloudSwitchGetConfigVariableName completion:^(id  _Nullable result, NSError * _Nullable error) {
        if (error) {
            NSLog(@"Failed to get config variable error: %@", error);
            [self checkCloudSwitchDeviceReachable];
        } else {
            if ([result isKindOfClass:[NSString class]]) {
                NSString *jsonString = (NSString *)result;
                NSData *jsonData = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
                NSError *jsonError = nil;
                NSDictionary<NSString *, id> *switchConfig = [NSJSONSerialization JSONObjectWithData:jsonData
                                                                                             options:0
                                                                                               error:&jsonError];
                if (jsonError) {
                    NSLog(@"Failed to parse switchConfig from: %@", jsonString);
                } else if ([CloudSwitchModel isValidSwitchConfig:switchConfig]) {
                    uint64_t timestamp = [switchConfig[kCloudSwitchConfigTimestampKey] longLongValue];
                    if (timestamp == self->_timestamp) {
                        NSLog(@"Switch config is same.");
                        return;
                    } else if (timestamp > self->_timestamp) {
                        NSLog(@"Local switch config is older.");
                        self.switchConfig = switchConfig;
                        [self saveSwitchConfig];
                        [self.delegate onSwitchConfigChanged];
                        return;
                    } else {
                        NSLog(@"Local switch config is newer.");
                    }
                }
                // Device switch config is invalid or older, send local switch config to device.
                [self sendSwitchConfig];
            }
        }
    }];
}

- (BOOL)switchState:(NSUInteger)switchIndex {
    return _switchStates[switchIndex];
}

- (void)setSwitchState:(NSUInteger)switchIndex isOn:(BOOL)isOn {
    if (_switchStates[switchIndex] != isOn) {
        [_cloudSwitchDevice callFunction:kCloudSwitchSetSwitchStateFunction
                           withArguments:@[[NSString stringWithFormat:@"%lu %d", switchIndex, isOn]]
                              completion:^(NSNumber * _Nullable result, NSError * _Nullable error) {
            if (error) {
                NSLog(@"Failed to set switch state error: %@", error);
                [self checkCloudSwitchDeviceReachable];
            } else {
                int state = result.intValue;
                if (state >= 0) {
                    [self updateSwitch:switchIndex withState:state];
                }
            }
        }];
    }
}

- (void)updateSwitch:(NSUInteger)switchIndex withState:(BOOL)isOn {
    if (_switchStates[switchIndex] != isOn) {
        _switchStates[switchIndex] = isOn;
        [self.delegate onSwitchStateChanged:switchIndex isOn:isOn];
    }
}

- (void)syncSwitchState {
    [_cloudSwitchDevice getVariable:kCloudSwitchSwitchStateVariableName completion:^(id  _Nullable result, NSError * _Nullable error) {
        if (error) {
            NSLog(@"Failed to get config variable error: %@", error);
            [self checkCloudSwitchDeviceReachable];
        } else {
            if ([result isKindOfClass:[NSString class]]) {
                NSString *stateString = (NSString *)result;
                NSArray<NSString *> *states = [stateString componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
                [states enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                    [self updateSwitch:idx withState:obj.boolValue];
                }];
            }
        }
    }];
}

- (void)restoreCloudSwitchDevice {
    if ([ParticleCloud sharedInstance].isAuthenticated && !self.availableDevices) {
        [self retrieveAllDevicesWithCompletion:^(NSError * _Nullable error) {
            if (error) {
                NSLog(@"Failed to retrieveAllDevices error: %@", error);
            }
        }];
    }
    [self.delegate onAuthenticationChanged];
}

- (void)startListenForSwichConfigChanged {
    NSAssert(!self.switchConfigChangedEventSubscriberId, @"Already listening for switchConfigChanged");
    NSLog(@"Start listening for switchConfigChanged");
    self.switchConfigChangedEventSubscriberId =
        [_cloudSwitchDevice subscribeToEventsWithPrefix:kCloudSwitchConfigChangedEvent
                                                handler:^(ParticleEvent * _Nullable event, NSError * _Nullable error) {
        if (error) {
            NSLog(@"Failed to subscribe to switchConfigChanged event error: %@", error);
        } else if ([event.event isEqualToString:kCloudSwitchConfigChangedEvent]) {
            NSLog(@"Received event: %@ with data: %@", event.event, event.data);
            int64_t timestamp = 0;
            if ([event.data isKindOfClass:[NSString class]]) {
                timestamp = [event.data longLongValue];
            }
            if (timestamp == self->_timestamp) {
                NSLog(@"Switch config is same.");
                return;
            } else if (timestamp > self->_timestamp) {
                NSLog(@"Local switch config is older.");
                [self syncSwitchConfig];
                return;
            } else {
                NSLog(@"Local switch config is newer.");
                [self sendSwitchConfig];
            }
        }
    }];
}

- (void)stopListenForSwichConfigChanged {
    if (self.switchConfigChangedEventSubscriberId) {
        NSLog(@"Stop listening for switchConfigChanged event");
        [_cloudSwitchDevice unsubscribeFromEventWithID:self.switchConfigChangedEventSubscriberId];
        self.switchConfigChangedEventSubscriberId = nil;
    }
}

- (void)startListenForSwichStateChanged {
    NSAssert(!self.switchStateChangedEventSubscriberId, @"Already listening for switchStateChanged");
    NSLog(@"Start listening for switchStateChanged");
    self.switchStateChangedEventSubscriberId =
        [_cloudSwitchDevice subscribeToEventsWithPrefix:kCloudSwitchSwitchStateChangedEvent
                                                handler:^(ParticleEvent * _Nullable event, NSError * _Nullable error) {
        if (error) {
            NSLog(@"Failed to subscribe to switchStateChanged event error: %@", error);
        } else if ([event.event isEqualToString:kCloudSwitchSwitchStateChangedEvent]) {
            NSLog(@"Received event: %@ with data: %@", event.event, event.data);
            NSArray<NSString *> *valueStr = [event.data componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            if (valueStr.count != 2) {
                NSLog(@"Inavlid data in switchStateChanged event");
                return;
            }
            NSInteger switchIndex = valueStr[0].integerValue;
            BOOL switchState = valueStr[1].boolValue;
            if (switchIndex < 0 || switchIndex >= kNumberOfSwitch) {
                NSLog(@"Inavlid switchIndex in switchStateChanged event");
                return;
            }
            [self updateSwitch:switchIndex withState:switchState];
        }
    }];
}

- (void)stopListenForSwichStateChanged {
    if (self.switchStateChangedEventSubscriberId) {
        NSLog(@"Stop listening for switchStateChanged event");
        [_cloudSwitchDevice unsubscribeFromEventWithID:self.switchStateChangedEventSubscriberId];
        self.switchStateChangedEventSubscriberId = nil;
    }
}

- (void)seleteCloudSwitchDevice:(id<ParticleDevice>)cloudSwitchDevice {
    [self setCloudSwitchDevice:(ParticleDevice *)cloudSwitchDevice];
}

- (void)setCloudSwitchDevice:(ParticleDevice *)cloudSwitchDevice {
    if (_cloudSwitchDevice != cloudSwitchDevice) {
        [self stopListenForCode];
        [self stopListenForSwichStateChanged];
        [self stopListenForSwichConfigChanged];
        _cloudSwitchDevice.delegate = nil;
        _cloudSwitchDevice = cloudSwitchDevice;
        _cloudSwitchDevice.delegate = self;
        [self loadSwitchConfig];
        [[NSUserDefaults standardUserDefaults] setObject:_cloudSwitchDevice.id forKey:kCloudSwitchDeviceIDKey];
        self.cloudSwitchDeviceReachable = _cloudSwitchDevice.connected;
        if (_cloudSwitchDevice.connected) {
            [self syncSwitchConfig];
            [self syncSwitchState];
        }
        [self startListenForSwichConfigChanged];
        [self startListenForSwichStateChanged];
        [self.delegate onSwitchConfigChanged];
    }
}

- (void)particleDevice:(ParticleDevice *)device didReceiveSystemEvent:(ParticleDeviceSystemEvent)event {
    if (event == ParticleDeviceSystemEventCameOnline || event == ParticleDeviceSystemEventWentOffline) {
        NSLog(@"%@ %@", device.name, device.connected ? @"came Online" : @"went Offline");
        self.cloudSwitchDeviceReachable = device.connected;
        if (_cloudSwitchDevice.connected) {
            [self syncSwitchConfig];
        }
    }
}

- (void)checkCloudSwitchDeviceReachable {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(checkCloudSwitchDeviceReachable) object:nil];
    NSLog(@"Check clould switch device reachable");
    [_cloudSwitchDevice ping:^(BOOL result, NSError * _Nullable error) {
        if (error) {
            NSLog(@"ping cloud device failed error: %@", error);
            self.cloudSwitchDeviceReachable = NO;
            // TODO: change to use rechablility to trigger the check.
            [self performSelector:@selector(checkCloudSwitchDeviceReachable)
                           withObject:nil
                           afterDelay:kCloudSwitchReachableCheckPeriod];
        } else {
            NSLog(@"Cloud switch device is%@ reachable.", result ? @"" : @" NOT");
            self.cloudSwitchDeviceReachable = result;
            if (result) {
                [self performSelector:@selector(checkCloudSwitchDeviceReachable)
                               withObject:nil
                               afterDelay:kCloudSwitchReachableCheckPeriod];
            } else {
                // We will usually get notification when device came online. But in case the notification lost
                // we can do period check at a lower frequency.
                [self performSelector:@selector(checkCloudSwitchDeviceReachable)
                               withObject:nil
                               afterDelay:kCloudSwitchReachableCheckPeriod * 5];
            }
        }

    }];
}

- (void)updateSwitch:(NSUInteger)switchIndex withName:(NSString *)name tristateCode:(NSString *)tristateCode {
    _switchNames[switchIndex] = name;
    _switchCodes[switchIndex] = tristateCode;
    _timestamp = (int64_t)[NSDate now].timeIntervalSince1970;
    [[NSUserDefaults standardUserDefaults] setObject:self.switchConfig forKey:self.cloudSwitchDevice.id];
    [self sendSwitchConfig];
    [self.delegate onSwitchConfigChanged];
}

- (void)startListenForCode {
    NSAssert(!self.tristateReceivedEventSubscriberId, @"Already listening");
    NSLog(@"Start listening for tristate code");
    self.tristateReceivedEventSubscriberId = [_cloudSwitchDevice subscribeToEventsWithPrefix:kCloudSwitchTristateReceivedEvent handler:^(ParticleEvent * _Nullable event, NSError * _Nullable error) {
        if (error) {
            NSLog(@"Failed to subscribe to tristate-received event error: %@", error);
        } else if ([event.event isEqualToString:kCloudSwitchTristateReceivedEvent]) {
            NSLog(@"Received event: %@ with data: %@", event.event, event.data);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate onReceiveSwitchCode:event.data];
            });
        }
    }];
}

- (void)stopListenForCode {
    if (self.tristateReceivedEventSubscriberId) {
        NSLog(@"Stop listening for tristate code");
        [_cloudSwitchDevice unsubscribeFromEventWithID:self.tristateReceivedEventSubscriberId];
        self.tristateReceivedEventSubscriberId = nil;
    }
}

- (void)retrieveAllDevicesWithCompletion:(void (^)(NSError * _Nullable))completion {
    NSString *cloudSwitchDeviceID = [[NSUserDefaults standardUserDefaults] stringForKey:kCloudSwitchDeviceIDKey];
    [[ParticleCloud sharedInstance] getDevices:^(NSArray<ParticleDevice *> * _Nullable particleDevices, NSError * _Nullable error) {
        if (error) {
            NSLog(@"Failed to retrieve devices error: %@", error);
            completion(error);
        } else {
            NSMutableArray<ParticleDevice *> *availableDevices = [NSMutableArray<ParticleDevice *> array];
            for (ParticleDevice *device in particleDevices) {
                if ([device.functions containsObject:kCloudSwitchFunctionName]) {
                    [availableDevices addObject:device];
                    if ([device.id isEqualToString:cloudSwitchDeviceID]) {
                        self.cloudSwitchDevice = device;
                    }
                }
            }
            if (!availableDevices.count) {
                NSLog(@"No device in the account");
                completion([NSError errorWithDomain:@"CloudSwitchError" code:1001 userInfo:@{NSLocalizedDescriptionKey: @"No device in account"}]);
            } else {
                self.availableDevices = availableDevices;
                completion(nil);
            }
        }
    }];
}

- (bool)tryLogin {
    NSString *accessToken = [[NSUserDefaults standardUserDefaults] stringForKey:kCloudSwitchAccessTokenKey];
    if (!accessToken) return NO;
    return [[ParticleCloud sharedInstance] injectSessionAccessToken:accessToken];
}

- (void)loginWithUsername:(NSString *)username password:(NSString *)password completion:(void (^)(NSError * _Nullable))completion {
    [[ParticleCloud sharedInstance] loginWithUser:username password:password completion:^(NSError * _Nullable error) {
        if (error) {
            NSLog(@"Failed to login error: %@", error);
            completion(error);
        } else {
            [self.delegate onAuthenticationChanged];
            [self retrieveAllDevicesWithCompletion:completion];
            [[NSUserDefaults standardUserDefaults] setObject:[ParticleCloud sharedInstance].accessToken forKey:kCloudSwitchAccessTokenKey];
        }
    }];
}

- (void)logout {
    if (self.isAuthenticated) {
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[NSBundle mainBundle].bundleIdentifier];
        self.cloudSwitchDevice = nil;
        [[ParticleCloud sharedInstance] logout];
        [self.delegate onAuthenticationChanged];
    }
}

- (BOOL)toggleSwitch:(NSUInteger)switchIndex completion:(void (^)(NSError * _Nullable))completion {
    NSAssert(switchIndex < kNumberOfSwitch, @"Invalid switchIndex: %lu", switchIndex);
    if (self.switchCodes[switchIndex].length) {
        NSLog(@"Switch %ld toggled", switchIndex);
        [_cloudSwitchDevice callFunction:kCloudSwitchToggleSwitchFunction
                            withArguments:@[@(switchIndex)]
                               completion:^(NSNumber * _Nullable result, NSError * _Nullable error) {
            if (error) {
                NSLog(@"Failed to toggle switch %ld error: %@", switchIndex, error);
                [self checkCloudSwitchDeviceReachable];
            } else {
                int state = result.intValue;
                if (state >= 0) {
                    [self updateSwitch:switchIndex withState:state];
                }
            }
            completion(error);
        }];
        return YES;
    } else {
        NSLog(@"Switch %ld not assigned", switchIndex);
        return NO;
    }
}

- (void)toggleSwitch:(NSUInteger)switchIndex withCompletion:(void (^)(NSError * _Nullable))completion {
    if (![self toggleSwitch:switchIndex completion:completion]) {
        completion([NSError errorWithDomain:@"com.jpimobile.cloudswitch.error" code:-1 userInfo:nil]);
    }
}

@end
