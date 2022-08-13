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
static NSString *const kCloudSwitchNameKey = @"CloudSwitchNameKey";
static NSString *const kCloudSwitchCodeKey = @"CloudSwitchCodeKey";

static NSString *const kCloudSwitchFunctionName = @"sendtristate";
static NSString *const kCloudSwitchEventName = @"tristate-received";

@interface ParticleDevice (CloudSwitch)<ParticleDevice>

@end

@interface CloudSwitchModel ()<ParticleDeviceDelegate> {
    NSMutableArray<NSString *> *_switchNames;
    NSMutableArray<NSString *> *_switchCodes;
    ParticleDevice *_cloudSwitchDevice;
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
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    for (NSUInteger i=0; i<kNumberOfSwitch; i++) {
        _switchNames[i] = [userDefaults stringForKey:[kCloudSwitchNameKey stringByAppendingFormat:@"%lu", i]] ?: @"";
        _switchCodes[i] = [userDefaults stringForKey:[kCloudSwitchCodeKey stringByAppendingFormat:@"%lu", i]] ?: @"";
    }
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
        [self.delegate onSwitchStateChanged];
    }
}

- (void)particleDevice:(ParticleDevice *)device didReceiveSystemEvent:(ParticleDeviceSystemEvent)event {
    if (event == ParticleDeviceSystemEventCameOnline || event == ParticleDeviceSystemEventWentOffline)
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate onSwitchStateChanged];
    });
}

- (void)updateSwitch:(NSUInteger)switchIndex withName:(NSString *)name tristateCode:(NSString *)tristateCode {
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults setObject:name forKey:[kCloudSwitchNameKey stringByAppendingFormat:@"%lu", switchIndex]];
    [userDefaults setObject:tristateCode forKey:[kCloudSwitchCodeKey stringByAppendingFormat:@"%lu", switchIndex]];
    _switchNames[switchIndex] = name;
    _switchCodes[switchIndex] = tristateCode;
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
                        [self.delegate onSwitchStateChanged];
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

- (BOOL)toggleSwitch:(NSUInteger)switchIndex {
    NSAssert(switchIndex < kNumberOfSwitch, @"Invalid switchIndex: %lu", switchIndex);
    if (self.switchCodes[switchIndex].length) {
        NSLog(@"Switch %ld toggled", switchIndex);
        [_cloudSwitchDevice callFunction:kCloudSwitchFunctionName
                            withArguments:@[self.switchCodes[switchIndex]]
                               completion:^(NSNumber * _Nullable result, NSError * _Nullable error) {
            if (error) {
                NSLog(@"Failed to toggle switch %ld error: %@", switchIndex, error);
            }
        }];
        return YES;
    } else {
        NSLog(@"Switch %ld not assigned", switchIndex);
        return NO;
    }
}

@end
