//
//  CloudSwitchModel.m
//  CloudSwitch
//
//  Created by Jasom Pi on 8/11/22.
//

#import "CloudSwitchModel.h"
#include "Particle-SDK.h"

static const NSUInteger kNumberOfSwitch = 5;

static NSString *const kCloudSwitchDeviceIDKey = @"CloudSwitchDeviceIDKey";
static NSString *const kCloudSwitchNamesKey = @"names";
static NSString *const kCloudSwitchCodesKey = @"codes";

static NSString *const kCloudSwitchFunctionName = @"sendtristate";
static NSString *const kCloudSwitchEventName = @"tristate-received";

static const NSTimeInterval kCloudSwitchReachableCheckPeriod = 60.0;

@interface ParticleDevice (CloudSwitch)<ParticleDevice>

@end

@interface CloudSwitchModel ()<ParticleDeviceDelegate> {
    NSMutableArray<NSString *> *_switchNames;
    NSMutableArray<NSString *> *_switchCodes;
    ParticleDevice *_cloudSwitchDevice;
    BOOL _cloudSwitchDeviceReachable;
}

@property (weak, nonatomic) id<CloudSwitchModelDelegate> delegate;
@property (copy, nonatomic) NSArray<ParticleDevice *> *availableDevices;
@property (strong, nonatomic) id eventSubscriberId;

@end

@implementation CloudSwitchModel

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
            [self.delegate onSwitchStateChanged];
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
        [self resetCloudSwitches];
    }
    return self;
}

- (void)resetCloudSwitches {
    NSString *emptyStrings[kNumberOfSwitch];
    for (NSUInteger i=0; i<kNumberOfSwitch; i++) {
        emptyStrings[i] = @"";
    }
    _switchNames = [NSMutableArray<NSString *> arrayWithObjects:emptyStrings count:kNumberOfSwitch];
    _switchCodes = [NSMutableArray<NSString *> arrayWithObjects:emptyStrings count:kNumberOfSwitch];
}

- (void)restoreCloudSwitches {
    if (!self.cloudSwitchDevice.id) {
        [self resetCloudSwitches];
        return;
    }
    NSDictionary<NSString *, NSArray<NSString *> *> *switchConfig = [[NSUserDefaults standardUserDefaults] objectForKey:self.cloudSwitchDevice.id];
    if (!switchConfig || switchConfig[kCloudSwitchNamesKey].count != kNumberOfSwitch || switchConfig[kCloudSwitchCodesKey].count != kNumberOfSwitch) {
        [self resetCloudSwitches];
        return;
    }
    _switchNames = [switchConfig[kCloudSwitchNamesKey] mutableCopy];
    _switchCodes = [switchConfig[kCloudSwitchCodesKey] mutableCopy];
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

- (void)seleteCloudSwitchDevice:(id<ParticleDevice>)cloudSwitchDevice {
    [self setCloudSwitchDevice:(ParticleDevice *)cloudSwitchDevice];
}

- (void)setCloudSwitchDevice:(ParticleDevice *)cloudSwitchDevice {
    if (_cloudSwitchDevice != cloudSwitchDevice) {
        [self stopListenForCode];
        _cloudSwitchDevice.delegate = nil;
        _cloudSwitchDevice = cloudSwitchDevice;
        _cloudSwitchDevice.delegate = self;
        [self restoreCloudSwitches];
        [[NSUserDefaults standardUserDefaults] setObject:_cloudSwitchDevice.id forKey:kCloudSwitchDeviceIDKey];
        self.cloudSwitchDeviceReachable = _cloudSwitchDevice.connected;
        [self.delegate onSwitchStateChanged];
    }
}

- (void)particleDevice:(ParticleDevice *)device didReceiveSystemEvent:(ParticleDeviceSystemEvent)event {
    if (event == ParticleDeviceSystemEventCameOnline || event == ParticleDeviceSystemEventWentOffline) {
        NSLog(@"%@ %@", device.name, device.connected ? @"came Online" : @"went Offline");
        self.cloudSwitchDeviceReachable = device.connected;
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
                // We will get notification when device came online. So only perfor check when device is alread online.
                [self performSelector:@selector(checkCloudSwitchDeviceReachable)
                               withObject:nil
                               afterDelay:kCloudSwitchReachableCheckPeriod];
            }
        }
    }];
}

- (void)updateSwitch:(NSUInteger)switchIndex withName:(NSString *)name tristateCode:(NSString *)tristateCode {
    _switchNames[switchIndex] = name;
    _switchCodes[switchIndex] = tristateCode;
    NSDictionary<NSString *, NSArray<NSString *>*> *switchConfig = @{kCloudSwitchNamesKey: _switchNames, kCloudSwitchCodesKey: _switchCodes};
    [[NSUserDefaults standardUserDefaults] setObject:switchConfig forKey:self.cloudSwitchDevice.id];
    [self.delegate onSwitchStateChanged];
}

- (void)startListenForCode {
    NSAssert(!self.eventSubscriberId, @"Already listening");
    NSLog(@"Start listening for code");
    self.eventSubscriberId = [_cloudSwitchDevice subscribeToEventsWithPrefix:kCloudSwitchEventName handler:^(ParticleEvent * _Nullable event, NSError * _Nullable error) {
        if (error) {
            NSLog(@"subscribe to events failed error: %@", error);
        } else if ([event.event isEqualToString:kCloudSwitchEventName]) {
            NSLog(@"received event: %@ with data: %@", event.event, event.data);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate onReceiveSwitchCode:event.data];
            });
        }
    }];
}

- (void)stopListenForCode {
    if (self.eventSubscriberId) {
        NSLog(@"Stop listening for code");
        [_cloudSwitchDevice unsubscribeFromEventWithID:self.eventSubscriberId];
        self.eventSubscriberId = nil;
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

- (void)loginWithUsername:(NSString *)username password:(NSString *)password completion:(void (^)(NSError * _Nullable))completion {
    [[ParticleCloud sharedInstance] loginWithUser:username password:password completion:^(NSError * _Nullable error) {
        if (error) {
            NSLog(@"Failed to login error: %@", error);
            completion(error);
        } else {
            [self.delegate onAuthenticationChanged];
            [self retrieveAllDevicesWithCompletion:completion];
        }
    }];
}

- (void)logout {
    if (self.isAuthenticated) {
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[NSBundle mainBundle].bundleIdentifier];
        self.cloudSwitchDevice = nil;
        [self resetCloudSwitches];
        [[ParticleCloud sharedInstance] logout];
        [self.delegate onAuthenticationChanged];
    }
}

- (BOOL)toggleSwitch:(NSUInteger)switchIndex completion:(void (^)(NSError * _Nullable))completion {
    NSAssert(switchIndex < kNumberOfSwitch, @"Invalid switchIndex: %lu", switchIndex);
    if (self.switchCodes[switchIndex].length) {
        NSLog(@"Switch %ld toggled", switchIndex);
        [_cloudSwitchDevice callFunction:kCloudSwitchFunctionName
                            withArguments:@[self.switchCodes[switchIndex]]
                               completion:^(NSNumber * _Nullable result, NSError * _Nullable error) {
            if (error) {
                NSLog(@"Failed to toggle switch %ld error: %@", switchIndex, error);
                [self checkCloudSwitchDeviceReachable];
            }
            completion(error);
        }];
        return YES;
    } else {
        NSLog(@"Switch %ld not assigned", switchIndex);
        return NO;
    }
}

@end
