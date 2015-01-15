//
//  TSClusterAnnotationView.m
//  ClusterDemo
//
//  Created by Adam Share on 1/14/15.
//  Copyright (c) 2015 Applidium. All rights reserved.
//

#import "TSClusterAnnotationView.h"
#import "ADClusterAnnotation.h"

@interface TSClusterAnnotationView ()

@property (strong, nonatomic) UIView *contentView;

@end

@implementation TSClusterAnnotationView

- (instancetype)initWithAnnotation:(id<MKAnnotation>)annotation reuseIdentifier:(NSString *)reuseIdentifier containingAnnotationView:(MKAnnotationView *)contentView {
    
    self = [super initWithAnnotation:annotation reuseIdentifier:reuseIdentifier];
    
    if (self) {
        self.contentView = [[UIView alloc] initWithFrame:contentView.bounds];
        [self addSubview:self.contentView];
        [self updateWithAnnotationView:contentView];
    }
    
    return self;
}

- (MKAnnotationView *)updateWithAnnotationView:(MKAnnotationView *)annotationView {
    
    MKAnnotationView *viewToCache;
    for (MKAnnotationView *view in self.contentView.subviews) {
        if ([view isKindOfClass:[MKAnnotationView class]]) {
            viewToCache = view;
            [view removeFromSuperview];
        }
    }
    
    annotationView.frame = annotationView.bounds;
    
    if (!CGRectEqualToRect(self.bounds, annotationView.bounds)) {
        NSLog(@"%@",self);
        self.frame = annotationView.bounds;
        self.contentView.frame = annotationView.bounds;
    }
    
    if (!CGPointEqualToPoint(self.centerOffset, annotationView.centerOffset)) {
        self.centerOffset = annotationView.centerOffset;
    }
    
    [self.contentView addSubview:annotationView];
    
    self.canShowCallout = annotationView.canShowCallout;
    self.calloutOffset = annotationView.calloutOffset;
    self.enabled = annotationView.enabled;
    self.highlighted = annotationView.highlighted;
    self.selected = annotationView.selected;
    self.leftCalloutAccessoryView = annotationView.leftCalloutAccessoryView;
    self.rightCalloutAccessoryView = annotationView.rightCalloutAccessoryView;
    self.draggable = annotationView.isDraggable;
    
    return viewToCache;
}

- (void)setAnnotation:(id<MKAnnotation>)annotation {
    
    [super setAnnotation:annotation];
    
    if ([annotation isKindOfClass:[ADClusterAnnotation class]]) {
        ((ADClusterAnnotation *)annotation).annotationView = self;
    }
}

@end