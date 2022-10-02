//
//  ViewController.m
//  CloudSwitch
//
//  Created by Jasom Pi on 8/10/22.
//

#import "ViewController.h"
#include "CloudSwitchModel.h"

static const NSUInteger kNumberOfSwitch = 5;
static const NSTimeInterval kLongPressHoldTime = 1.0;

@interface ViewController ()<CloudSwitchModelDelegate, UITextFieldDelegate>

@property (weak, nonatomic) IBOutlet UIButton *loginButton;
@property (weak, nonatomic) IBOutlet UILabel *deviceStatusLabel;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView *busyIndicator;

@property (weak, nonatomic) UITextField *switchNameTextField;
@property (weak, nonatomic) UITextField *switchCodeTextField;
@property (weak, nonatomic) UIAlertAction *assignSwitchAction;

@property (strong, nonatomic) CloudSwitchModel *cloudSwitchModel;
@property (strong, nonatomic) dispatch_block_t buttonLongPressedBlock;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    self.cloudSwitchModel = [[CloudSwitchModel alloc] initWithDelegate:self];
    [self.cloudSwitchModel restoreCloudSwitchDevice];
    [self.deviceStatusLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(deviceStatusLabelTapped:)]];
}

- (void)deviceStatusLabelTapped:(id)senser {
    if (self.cloudSwitchModel.availableDevices > 0) {
        [self showDeviceSelectionAlert];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    self.busyIndicator.hidden = YES;
    [self updateDeviceStatus];
}

- (void)onAuthenticationChanged {
    [self.loginButton setTitle:self.cloudSwitchModel.isAuthenticated ? @"Logout" : @"Login"
                      forState:UIControlStateNormal];
}

- (void)onSwitchConfigChanged {
    [self updateDeviceStatus];
}

- (void)onSwitchStateChanged:(NSUInteger)switchIndex isOn:(BOOL)isOn {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIButton *switchButton = (UIButton *)[self.view viewWithTag:switchIndex + 1];
        [switchButton setSelected:isOn];
    });
}

- (void)onReceiveSwitchCode:(NSString *)tristateCode {
    self.switchCodeTextField.text = tristateCode;
    [self learnSwitchAlertTextFieldChanged:self];
}

- (void)updateDeviceStatus {
    NSString *deviceName = self.cloudSwitchModel.cloudSwitchDevice.name;
    BOOL deviceConnected = self.cloudSwitchModel.cloudSwitchDeviceReachable;
    if (deviceName) {
        NSMutableAttributedString *attrStr = [[NSMutableAttributedString alloc] initWithString:deviceName attributes:@{NSUnderlineStyleAttributeName : @(NSUnderlineStyleSingle) }];
        [attrStr appendAttributedString:[[NSAttributedString alloc] initWithString:deviceConnected ? @" is online." : @" is not reachable."]];
        [attrStr addAttributes:@{NSForegroundColorAttributeName: deviceConnected ? UIColor.greenColor : UIColor.redColor} range:NSMakeRange(0, attrStr.length)];
        self.deviceStatusLabel.attributedText = attrStr;
    } else {
        self.deviceStatusLabel.text = @"Device not selected";
    }
    for (NSInteger i = 0; i < kNumberOfSwitch; i++) {
        UIButton *switchButton = (UIButton *)[self.view viewWithTag:i + 1];
        BOOL buttonAssigned = self.cloudSwitchModel.switchCodes[i].length > 0;
        NSString *switchName = self.cloudSwitchModel.switchNames[i];
        [switchButton setTitle:buttonAssigned ? switchName : @"<Not Assigned>"
                      forState:UIControlStateNormal];
        [switchButton setTitle:[@"💡" stringByAppendingString:buttonAssigned ? switchName : @"<Not Assigned>"]
                      forState:UIControlStateSelected];
        switchButton.enabled = deviceConnected;
        switchButton.hidden = deviceName == nil;
    }
}

- (NSUInteger)switchIndex:(id)sender {
    NSInteger switchButtonTag = ((UIButton *)sender).tag;
    NSAssert(switchButtonTag > 0 && switchButtonTag <= kNumberOfSwitch, @"Invalid switch button tag: %ld", switchButtonTag);
    return switchButtonTag - 1;
}

- (IBAction)switchButtonTouchDown:(id)sender {
    NSUInteger switchIndex = [self switchIndex:sender];
    NSLog(@"Switch %lu down", switchIndex);
    if (self.buttonLongPressedBlock) {
        dispatch_block_cancel(self.buttonLongPressedBlock);
        self.buttonLongPressedBlock = nil;
    }
    self.buttonLongPressedBlock = dispatch_block_create(DISPATCH_BLOCK_ASSIGN_CURRENT, ^{
        NSLog(@"Switch %lu long pressed", switchIndex);
        [self showLearnSwitchAlert:switchIndex];
        self.buttonLongPressedBlock = nil;
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, kLongPressHoldTime * NSEC_PER_SEC) , dispatch_get_main_queue(), self.buttonLongPressedBlock);
}

- (IBAction)switchButtonTouchUpInside:(id)sender {
    NSUInteger switchIndex = [self switchIndex:sender];
    UIButton *switchButton = (UIButton *)sender;
    if (self.buttonLongPressedBlock) {
        dispatch_block_cancel(self.buttonLongPressedBlock);
        self.buttonLongPressedBlock = nil;
        if ([self.cloudSwitchModel toggleSwitch:switchIndex completion:^(NSError * _Nullable error) {
            switchButton.enabled = YES;
        }]) {
            switchButton.enabled = NO;
        } else {
            [self showLearnSwitchAlert:switchIndex];
        }
    }
}

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField {
    if (textField == self.switchCodeTextField) {
        return NO;
    }
    return YES;
}

- (void)learnSwitchAlertTextFieldChanged:(id)sender {
    self.assignSwitchAction.enabled = self.switchNameTextField.text.length && self.switchCodeTextField.text.length;
}

- (void)showLearnSwitchAlert:(NSUInteger)switchIndex {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Learn switch code" message:@"Press the button on the remote control to learn the code for the switch." preferredStyle:UIAlertControllerStyleAlert];
    [alertController addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"Switch Name";
        textField.autocapitalizationType = UITextAutocapitalizationTypeWords;
        NSString *switchName = self.cloudSwitchModel.switchNames[switchIndex];
        textField.text = switchName.length > 0 ? switchName : [NSString stringWithFormat:@"Switch %lu", switchIndex + 1];
        self.switchNameTextField = textField;
        [textField addTarget:self action:@selector(learnSwitchAlertTextFieldChanged:) forControlEvents:UIControlEventEditingChanged];
    }];
    [alertController addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"Switch tristate code";
        NSString *switchCode = self.cloudSwitchModel.switchCodes[switchIndex];
        if (switchCode.length > 0) {
            textField.text = switchCode;
        }
        textField.delegate = self;
        self.switchCodeTextField = textField;
    }];
    UIAlertAction *assignSwitchAction = [UIAlertAction actionWithTitle:@"Assign"
                                                                 style:UIAlertActionStyleDefault
                                                               handler:^(UIAlertAction * _Nonnull action) {
        NSString *switchName = [alertController textFields][0].text;
        NSString *switchCode = [alertController textFields][1].text;
        NSAssert(switchName.length && switchCode.length, @"Switch name or code not set");
        [self.cloudSwitchModel updateSwitch:switchIndex withName:switchName tristateCode:switchCode];
        [self.cloudSwitchModel stopListenForCode];
    }];
    [alertController addAction:assignSwitchAction];
    self.assignSwitchAction = assignSwitchAction;
    [self learnSwitchAlertTextFieldChanged:self];
    if (assignSwitchAction.isEnabled) {
        bool isOn = [self.cloudSwitchModel switchState:switchIndex];
        UIAlertAction *changeStateAction = [UIAlertAction actionWithTitle:isOn ? @"Set state to OFF" : @"Set state to ON"
                                                                    style:UIAlertActionStyleDefault
                                                                  handler:^(UIAlertAction * _Nonnull action) {
            [self.cloudSwitchModel setSwitchState:switchIndex isOn:!isOn];
            [self.cloudSwitchModel stopListenForCode];
        }];
        [alertController addAction:changeStateAction];
        
        UIAlertAction *unassignAction = [UIAlertAction actionWithTitle:@"Unassign"
                                                                 style:UIAlertActionStyleDestructive
                                                               handler:^(UIAlertAction * _Nonnull action) {
            [self.cloudSwitchModel updateSwitch:switchIndex withName:@"" tristateCode:@""];
            [self.cloudSwitchModel stopListenForCode];
        }];
        [alertController addAction:unassignAction];
    }

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        NSLog(@"Canelled");
        [self.cloudSwitchModel stopListenForCode];
    }];
    [alertController addAction:cancelAction];
    [self presentViewController:alertController animated:YES completion:nil];
    [self.cloudSwitchModel startListenForCode];
}

- (IBAction)loginButtonClicked:(id)sender {
    if (self.cloudSwitchModel.isAuthenticated) {
        [self showLogoutAlert];
    } else {
        [self showLoginAlert];
    }
}

- (void)showLogoutAlert {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Sign out" message:@"Are you sure?" preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"Sign out" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [self.cloudSwitchModel logout];
    }];
    [alertController addAction:confirmAction];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        NSLog(@"Canelled");
    }];
    [alertController addAction:cancelAction];
    [self presentViewController:alertController animated:YES completion:nil];
}

- (void)showLoginAlert {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Sign In" message:@"Sign in with particle account:" preferredStyle:UIAlertControllerStyleAlert];
    [alertController addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"Email";
        textField.keyboardType = UIKeyboardTypeEmailAddress;
    }];
    [alertController addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = @"Password";
        textField.secureTextEntry = YES;
    }];
    UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSString *username = [alertController textFields][0].text;
        NSString *password = [alertController textFields][1].text;
        [self loginWithUsername:username passowrd:password];
    }];
    [alertController addAction:confirmAction];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        NSLog(@"Canelled");
    }];
    [alertController addAction:cancelAction];
    [self presentViewController:alertController animated:YES completion:nil];
}

- (void)loginWithUsername:(NSString *)username passowrd:(NSString *)password {
    self.loginButton.enabled = NO;
    self.busyIndicator.hidden = NO;
    [self.cloudSwitchModel loginWithUsername:username password:password completion:^(NSError * _Nullable error) {
        self.busyIndicator.hidden = YES;
        self.loginButton.enabled = YES;
        if (error) {
            NSLog(@"Failed to login %@", error);
            NSString *message = [NSString stringWithFormat:@"Failed to login.\n%@", [error localizedDescription]];
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Login Failed"
                                                                           message:message
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK"
                                                               style:UIAlertActionStyleDefault
                                                             handler:nil];

            [alert addAction:okAction];
            [self presentViewController:alert animated: YES completion:nil];
        } else {
            [self showDeviceSelectionAlert];
        }
    }];
}

- (void)showDeviceSelectionAlert {
    if (self.cloudSwitchModel.availableDevices.count == 1) {
        [self.cloudSwitchModel seleteCloudSwitchDevice:self.cloudSwitchModel.availableDevices[0]];
    } else {
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Select Device" message:@"Choose the particle device you want to control." preferredStyle:UIAlertControllerStyleActionSheet];
        for (id<ParticleDevice> device in self.cloudSwitchModel.availableDevices) {
            UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:device.name style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                [self.cloudSwitchModel seleteCloudSwitchDevice:device];
            }];
            [alertController addAction:confirmAction];
        }
        [self presentViewController:alertController animated:YES completion:nil];
    }
}

@end
