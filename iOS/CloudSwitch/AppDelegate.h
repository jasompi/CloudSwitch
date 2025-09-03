//
//  AppDelegate.h
//  CloudSwitch
//
//  Created by Jasom Pi on 8/10/22.
//

#import <UIKit/UIKit.h>

@class CloudSwitchModel;

@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (nonatomic, nonnull) CloudSwitchModel *cloudSwitchModel;

@property (class, nonatomic, nonnull) AppDelegate *shared;

@end

