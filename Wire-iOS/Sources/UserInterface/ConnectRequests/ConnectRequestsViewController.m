// 
// Wire
// Copyright (C) 2016 Wire Swiss GmbH
// 
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
// 
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License
// along with this program. If not, see http://www.gnu.org/licenses/.
// 


#import "ConnectRequestsViewController.h"
#import "SessionObjectCache.h"

// ui
#import "IncomingConnectRequestView.h"
#import "TextView.h"
#import "ConnectRequestCell.h"
#import "ProfileViewController.h"
#import "UIView+PopoverBorder.h"
#import "ProfilePresenter.h"
#import "IncomingConnectRequestView.h"
#import "UserImageView.h"
#import "UIColor+WR_ColorScheme.h"
#import "Wire-Swift.h"

// model
#import "zmessaging+iOS.h"

// helpers
#import <PureLayout/PureLayout.h>


@class ZMConversation;

static NSString *ConnectionRequestCellIdentifier = @"ConnectionRequestCell";


@interface ConnectRequestsViewController () <ZMConversationListObserver, ZMUserObserver, UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) NSArray *connectionRequests;
@property (nonatomic) id <ZMUserObserverOpaqueToken> userObserverToken;
@property (nonatomic) id <ZMConversationListObserverOpaqueToken> pendingConnectionsListObserverToken;

@property (nonatomic) UITableView *tableView;
@end



@implementation ConnectRequestsViewController

- (void)dealloc
{
    [[[SessionObjectCache sharedCache] pendingConnectionRequests] removeConversationListObserverForToken:self.pendingConnectionsListObserverToken];
    [ZMUser removeUserObserverForToken:self.userObserverToken];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)loadView
{
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero];
    self.view = self.tableView;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self.tableView registerClass:[ConnectRequestCell class] forCellReuseIdentifier:ConnectionRequestCellIdentifier];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    
    ZMConversationList *pendingConnectionsList = [[SessionObjectCache sharedCache] pendingConnectionRequests];
    self.pendingConnectionsListObserverToken = [pendingConnectionsList addConversationListObserver:self];
    
    self.userObserverToken = [ZMUser addUserObserver:self forUsers:@[[ZMUser selfUser]] inUserSession:[ZMUserSession sharedSession]];
    self.connectionRequests = [SessionObjectCache sharedCache].pendingConnectionRequests;
    
    [self conversationListDidChange:nil];
    
    self.tableView.backgroundColor = [UIColor wr_colorFromColorScheme:ColorSchemeColorBackground];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    self.tableView.separatorColor = [UIColor wr_colorFromColorScheme:ColorSchemeColorSeparator];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [[UIApplication sharedApplication] wr_updateStatusBarForCurrentControllerAnimated:YES];
}

- (BOOL)prefersStatusBarHidden
{
    return YES;
}

- (void)viewDidLayoutSubviews
{
    CGFloat xPos = MAX(self.tableView.bounds.size.height - self.tableView.contentSize.height, 0);
    [self.tableView setContentInset:UIEdgeInsetsMake(xPos, 0, 0, 0)];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        [self.tableView reloadData];
    } completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
    }];
    
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.connectionRequests.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    ConnectRequestCell *cell = [tableView dequeueReusableCellWithIdentifier:ConnectionRequestCellIdentifier];
    [self configureCell:cell forIndexPath:indexPath];
    
    return cell;
}

#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    ConnectRequestCell *cell = [tableView dequeueReusableCellWithIdentifier:ConnectionRequestCellIdentifier];
    [self configureCell:cell forIndexPath:indexPath];
    [cell setNeedsLayout];
    [cell layoutIfNeeded];
    CGSize size = [cell.contentView systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
    return size.height;
}

#pragma mark - Helpers

- (void)configureCell:(ConnectRequestCell *)cell forIndexPath:(NSIndexPath *)indexPath
{
    ZMConversation *request = self.connectionRequests[(self.connectionRequests.count - 1) - indexPath.row];
    
    ZMUser *user = request.connectedUser;
    cell.user = user;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.separatorInset = UIEdgeInsetsZero;
    cell.preservesSuperviewLayoutMargins = NO;
    cell.layoutMargins = UIEdgeInsetsZero;
    @weakify(self);
    
    cell.acceptBlock = ^{
        @strongify(self);
        
        BOOL lastConnectionRequest = (self.connectionRequests.count == 1);
        [[ZMUserSession sharedSession] enqueueChanges:^{
                                        [user accept];
                                    }
                                    completionHandler:^{
                                        if (lastConnectionRequest) {
                                            [[ZClientViewController sharedZClientViewController] hideIncomingContactRequestsWithCompletion:^{
                                                [[ZClientViewController sharedZClientViewController] selectConversation:user.oneToOneConversation
                                                                                                            focusOnView:YES
                                                                                                               animated:YES];
                                            }];
                                        }
                                    }];
    };
    
    cell.ignoreBlock = ^{
        BOOL lastConnectionRequest = (self.connectionRequests.count == 1);

        [[ZMUserSession sharedSession] enqueueChanges:^{
            [user ignore];
        } completionHandler:^{
            if (lastConnectionRequest) {
                [[ZClientViewController sharedZClientViewController] hideIncomingContactRequestsWithCompletion:nil];
            }
        }];
    };
    
}

#pragma mark - ZMUserObserver

- (void)userDidChange:(UserChangeInfo *)change
{
    [self.tableView reloadData]; //may need a slightly different approach, like enumerating through table cells of type FirstTimeTableViewCell and setting their bgColor property
}

#pragma mark - ZMConversationsObserver

- (void)conversationListDidChange:(ConversationListChangeInfo *)change
{
    [self.tableView reloadData];
    
    if (self.connectionRequests.count != 0) {
        // Scroll to bottom of inbox
        [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:self.connectionRequests.count - 1 inSection:0]
                              atScrollPosition:UITableViewScrollPositionBottom
                                      animated:YES];
    }
}

@end
