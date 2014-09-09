//
//  BVReorderTableView.m
//
//  Copyright (c) 2013 Ben Vogelzang.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

#import "BVReorderTableView.h"
#import <QuartzCore/QuartzCore.h>


@interface BVReorderTableView () <UIGestureRecognizerDelegate>

@property (nonatomic, strong) UILongPressGestureRecognizer *longPress;
@property (nonatomic, strong) NSTimer *scrollingTimer;
@property (nonatomic, assign) CGFloat scrollRate;
@property (nonatomic, strong) NSIndexPath *currentLocationIndexPath;
@property (nonatomic, strong) NSIndexPath *initialIndexPath;
@property (nonatomic, strong) UIImageView *draggingView;
@property (nonatomic, retain) id savedObject;

@property (nonatomic, assign) CGPoint previousSuperviewLocation;

- (void)initialize;
- (void)longPress:(UILongPressGestureRecognizer *)gesture;
- (void)updateCurrentLocation:(UILongPressGestureRecognizer *)gesture;
- (void)scrollTableWithCell:(NSTimer *)timer;
- (void)cancelGesture;

@end



@implementation BVReorderTableView

- (id)init {
    return [self initWithFrame:CGRectZero];
}

- (id)initWithFrame:(CGRect)frame {
    return [self initWithFrame:frame style:UITableViewStylePlain];
}

- (id)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self initialize];
    }
    return self;
}

- (id)initWithFrame:(CGRect)frame style:(UITableViewStyle)style {
    self = [super initWithFrame:frame style:style];
    if (self) {
        [self initialize];
    }
    return self;
}


- (void)initialize {
    self.longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPress:)];
    self.longPress.delegate = self;
    [self addGestureRecognizer:self.longPress];
    
    self.canReorderRows = YES;
}


- (void)setCanReorderRows:(BOOL)canReorderRows {
    _canReorderRows = canReorderRows;
    self.longPress.enabled = canReorderRows;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    BOOL shouldBegin = YES;
    if (gestureRecognizer == self.longPress)
    {
        CGPoint location = [gestureRecognizer locationInView:self];
        NSIndexPath *indexPath = [self indexPathForRowAtPoint:location];

        shouldBegin = self.canReorderRows;
        if ([self.delegate respondsToSelector:@selector(tableView:canReorderRowAtIndexPath:)])
        {
            shouldBegin = shouldBegin && [self.delegate tableView:self canReorderRowAtIndexPath:indexPath];
        }
    }
    return shouldBegin;
}

- (CGPoint)locationWithinBounds:(CGPoint)location
{
    location = [self convertPoint:location fromView:self.superview];
    if (location.y < self.draggingView.bounds.size.height / 2)
    {
        location.y = self.draggingView.bounds.size.height / 2;
    }
    else if (location.y > self.contentSize.height - self.draggingView.bounds.size.height / 2)
    {
        location.y = self.contentSize.height - self.draggingView.bounds.size.height / 2;
    }
    location = [self convertPoint:location toView:self.superview];
    return location;
}

- (void)longPress:(UILongPressGestureRecognizer *)gesture {
    CGPoint location = [gesture locationInView:self];
    CGPoint superviewLocation = [gesture locationInView:self.superview];
    CGPoint locationDelta = CGPointMake(superviewLocation.x - self.previousSuperviewLocation.x,
                                        superviewLocation.y - self.previousSuperviewLocation.y);
    self.previousSuperviewLocation = superviewLocation;
    
    NSIndexPath *indexPath = [self indexPathForRowAtPoint:location];
    
    NSInteger sections = [self numberOfSections];
    NSInteger rows = 0;
    for(NSInteger i = 0; i < sections; i++) {
        rows += [self numberOfRowsInSection:i];
    }
    
    // get out of here if the long press was not on a valid row or our table is empty
    if (rows == 0 || (gesture.state == UIGestureRecognizerStateBegan && indexPath == nil) ||
        (gesture.state == UIGestureRecognizerStateEnded && self.currentLocationIndexPath == nil)) {
        [self cancelGesture];
        return;
    }
    
    // started
    if (gesture.state == UIGestureRecognizerStateBegan) {
        
        UITableViewCell *cell = [self cellForRowAtIndexPath:indexPath];
        self.draggingRowHeight = cell.frame.size.height;
        [cell setSelected:NO animated:NO];
        [cell setHighlighted:NO animated:NO];
        
        
        // make an image from the pressed tableview cell
        UIGraphicsBeginImageContextWithOptions(cell.bounds.size, NO, 0);
        cell.highlighted = YES;
        [cell.layer renderInContext:UIGraphicsGetCurrentContext()];
        UIImage *cellImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        
        // create and image view that we will drag around the screen
        if (!self.draggingView) {
            self.draggingView = [[UIImageView alloc] initWithImage:cellImage];
            [self.superview addSubview:self.draggingView];
            CGRect rect = [self rectForRowAtIndexPath:indexPath];
            rect = [self convertRect:rect toView:self.superview];
            self.draggingView.frame = rect;
            
            // add drop shadow to image and lower opacity
            self.draggingView.layer.masksToBounds = NO;
            self.draggingView.layer.shadowColor = [[UIColor blackColor] CGColor];
            self.draggingView.layer.shadowOffset = CGSizeMake(0, 0);
            self.draggingView.layer.shadowRadius = 6.0;
            self.draggingView.layer.shadowOpacity = 0.6;
            self.draggingView.layer.shadowPath = [UIBezierPath bezierPathWithRect:self.draggingView.bounds].CGPath;
            
            // zoom image towards user
            [UIView beginAnimations:@"zoom" context:nil];
            self.draggingView.transform = CGAffineTransformMakeScale(1.1, 1.1);
            self.draggingView.center = CGPointMake(self.center.x, self.draggingView.center.y);
            [UIView commitAnimations];
        }
        
        [self beginUpdates];
        [self deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationNone];
        [self insertRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationNone];
        self.savedObject = [self.delegate tableView:self willMoveRowAtIndexPath:indexPath];
        self.currentLocationIndexPath = indexPath;
        self.initialIndexPath = indexPath;
        [self endUpdates];
        
        // enable scrolling for cell
        NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:gesture forKey:@"gesture"];
        self.scrollingTimer = [NSTimer timerWithTimeInterval:1/8
                                                      target:self
                                                    selector:@selector(scrollTableWithCell:)
                                                    userInfo:userInfo
                                                     repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:self.scrollingTimer forMode:NSDefaultRunLoopMode];
    }
    // dragging
    else if (gesture.state == UIGestureRecognizerStateChanged) {
        CGPoint newLocation = self.draggingView.center;
        newLocation.y += locationDelta.y;
        // update position of the drag view
        // don't let it go past the top or the bottom too far
        newLocation = [self locationWithinBounds:newLocation];
        self.draggingView.center = newLocation;
        
        CGRect rect = self.bounds;
        // adjust rect for content inset as we will use it below for calculating scroll zones
        rect.size.height -= self.contentInset.top;
        
        [self updateCurrentLocation:gesture];
        
        // tell us if we should scroll and which direction
        CGFloat scrollZoneHeight = rect.size.height / 6;
        CGFloat bottomScrollBeginning = self.contentOffset.y + self.contentInset.top + rect.size.height - scrollZoneHeight;
        CGFloat topScrollBeginning = self.contentOffset.y + self.contentInset.top  + scrollZoneHeight;
        // we're in the bottom zone
        if (location.y >= bottomScrollBeginning) {
            self.scrollRate = (location.y - bottomScrollBeginning) / scrollZoneHeight;
        }
        // we're in the top zone
        else if (location.y <= topScrollBeginning) {
            self.scrollRate = (location.y - topScrollBeginning) / scrollZoneHeight;
        }
        else {
            self.scrollRate = 0;
        }

        // NSLog(@"  Update: %f %f", location.y, self.draggingView.center.y);
    }
    // dropped
    else if (gesture.state == UIGestureRecognizerStateEnded) {
        
        indexPath = self.currentLocationIndexPath;
        
        // remove scrolling timer
        [self.scrollingTimer invalidate];
        self.scrollingTimer = nil;
        self.scrollRate = 0;
        
        // animate the drag view to the newly hovered cell
        [UIView animateWithDuration:0.2
                         animations:^{
                             CGRect rect = [self rectForRowAtIndexPath:indexPath];
                             rect = [self convertRect:rect toView:self.superview];
                             self.draggingView.transform = CGAffineTransformIdentity;
                             self.draggingView.frame = rect;
                         } completion:^(BOOL finished) {
                             [UIView animateWithDuration:0.2 animations:^{
                                 self.draggingView.alpha = 0;
                             } completion:^(BOOL finished2) {
                                 [self.draggingView removeFromSuperview];
                             }];
                             
             [self beginUpdates];
             [self deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationNone];
             [self insertRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationNone];
             [self.delegate tableView:self didFinishReorderingWithObject:self.savedObject atIndexPath:indexPath];
             [self endUpdates];
             
             // reload the rows that were affected just to be safe
             NSMutableArray *visibleRows = [[self indexPathsForVisibleRows] mutableCopy];
             [visibleRows removeObject:indexPath];
             [self reloadRowsAtIndexPaths:visibleRows withRowAnimation:UITableViewRowAnimationNone];
                             
             UITableViewCell *cell = [self cellForRowAtIndexPath:indexPath];
             cell.highlighted = YES;
             [cell setHighlighted:NO animated:YES];
             
             self.currentLocationIndexPath = nil;
             self.draggingView = nil;
         }];
    }
}


- (void)updateCurrentLocation:(UILongPressGestureRecognizer *)gesture {
    NSIndexPath *indexPath  = nil;
    CGPoint location = CGPointZero;
    
    // refresh index path
    location  = [gesture locationInView:self];
    indexPath = [self indexPathForRowAtPoint:location];
    
    if ([self.delegate respondsToSelector:@selector(tableView:targetIndexPathForMoveFromRowAtIndexPath:toProposedIndexPath:)]) {
        indexPath = [self.delegate tableView:self targetIndexPathForMoveFromRowAtIndexPath:self.initialIndexPath toProposedIndexPath:indexPath];
    }
    
    NSInteger oldHeight = [self rectForRowAtIndexPath:self.currentLocationIndexPath].size.height;
    NSInteger newHeight = [self rectForRowAtIndexPath:indexPath].size.height;
    
    if (indexPath && ![indexPath isEqual:self.currentLocationIndexPath] && [gesture locationInView:[self cellForRowAtIndexPath:indexPath]].y > newHeight - oldHeight) {
        [self beginUpdates];
        [self deleteRowsAtIndexPaths:[NSArray arrayWithObject:self.currentLocationIndexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        [self insertRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
        [self.delegate tableView:self didMoveRowAtIndexPath:self.currentLocationIndexPath toIndexPath:indexPath];
        self.currentLocationIndexPath = indexPath;
        [self endUpdates];
    }
}

- (void)scrollTableWithCell:(NSTimer *)timer {
    if (self.scrollRate != 0)
    {
        CGPoint currentOffset = self.contentOffset;
        CGPoint newOffset = CGPointMake(currentOffset.x, currentOffset.y + self.scrollRate);
        
        if (newOffset.y < -self.contentInset.top) {
            newOffset.y = -self.contentInset.top;
        } else if (self.contentSize.height < self.frame.size.height) {
            newOffset = currentOffset;
        } else if (newOffset.y > self.contentSize.height - self.frame.size.height) {
            newOffset.y = self.contentSize.height - self.frame.size.height;
        }
        if (!CGPointEqualToPoint(newOffset, currentOffset))
        {
            [self setContentOffset:newOffset];
            self.draggingView.center = [self locationWithinBounds:self.draggingView.center];

            UILongPressGestureRecognizer *gesture = [timer.userInfo objectForKey:@"gesture"];
            [self updateCurrentLocation:gesture];
        }
    }
}

- (void)cancelGesture {
    self.longPress.enabled = NO;
    self.longPress.enabled = YES;
}

@end
