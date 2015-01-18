//
//  ADMapCluster.m
//  ADClusterMapView
//
//  Created by Patrick Nollet on 27/06/11.
//  Copyright 2011 Applidium. All rights reserved.
//

#import "ADMapCluster.h"
#import "ADMapPointAnnotation.h"
#import "NSDictionary+MKMapRect.h"
#import "CLLocation+Utilities.h"
#import "ADClusterMapView.h"

#define ADMapClusterDiscriminationPrecision 1E-4

@interface ADMapCluster ()

@property (nonatomic, strong) ADMapCluster *leftChild;
@property (nonatomic, strong) ADMapCluster *rightChild;
@property (nonatomic, strong) NSString *clusterTitle;

@property (nonatomic, assign) double gamma;
@property (nonatomic, assign) double progress;
@property (nonatomic, assign) float percentage;

@end

@implementation ADMapCluster

+ (void)rootClusterForAnnotations:(NSSet *)annotations mapView:(ADClusterMapView *)mapView completion:(KdtreeCompletionBlock)completion {
    
    [mapView mapView:mapView willBeginBuildingClusterTreeForMapPoints:annotations];
    
    [ADMapCluster rootClusterForAnnotations:annotations discriminationPower:mapView.clusterDiscriminationPower title:mapView.clusterTitle showSubtitle:mapView.clusterShouldShowSubtitle completion:^(ADMapCluster *mapCluster) {
        [mapView mapView:mapView didFinishBuildingClusterTreeForMapPoints:annotations];
        
        completion(mapCluster);
    }];
}

+ (void)rootClusterForAnnotations:(NSSet *)annotations discriminationPower:(double)gamma title:(NSString *)clusterTitle showSubtitle:(BOOL)showSubtitle completion:(KdtreeCompletionBlock)completion {
    
    // KDTree
    //NSLog(@"Computing KD-tree for %lu annotations...", (unsigned long)annotations.count);
    
    MKMapRect boundaries = MKMapRectMake(HUGE_VALF, HUGE_VALF, 0.0, 0.0);
    
    for (ADMapPointAnnotation * annotation in annotations) {
        MKMapPoint point = annotation.mapPoint;
        if (point.x < boundaries.origin.x) {
            boundaries.origin.x = point.x;
        }
        if (point.y < boundaries.origin.y) {
            boundaries.origin.y = point.y;
        }
        if (point.x > boundaries.origin.x + boundaries.size.width) {
            boundaries.size.width = point.x - boundaries.origin.x;
        }
        if (point.y > boundaries.origin.y + boundaries.size.height) {
            boundaries.size.height = point.y - boundaries.origin.y;
        }
    }
    
    
    ADMapCluster * cluster = [[ADMapCluster alloc] initWithAnnotations:annotations atDepth:0 inMapRect:boundaries gamma:gamma clusterTitle:clusterTitle showSubtitle:showSubtitle parentCluster:nil rootCluster:nil];
    
    //NSLog(@"Computation done !");
    
    completion(cluster);
}

- (id)initWithAnnotations:(NSSet *)annotations atDepth:(NSInteger)depth inMapRect:(MKMapRect)mapRect gamma:(double)gamma clusterTitle:(NSString *)clusterTitle showSubtitle:(BOOL)showSubtitle parentCluster:(ADMapCluster *)parentCluster rootCluster:(ADMapCluster *)rootCluster {
    self = [super init];
    if (self) {
        _depth = depth;
        _mapRect = mapRect;
        _clusterTitle = clusterTitle;
        _showSubtitle = showSubtitle;
        _gamma = gamma;
        _parentCluster = parentCluster;
        _clusterCount = annotations.count;
        _progress = 0;
        
        if (depth == 0) {
            rootCluster = self;
        }
        
        if (annotations.count == 0) {
            _leftChild = nil;
            _rightChild = nil;
            self.annotation = nil;
            self.clusterCoordinate = kCLLocationCoordinate2DInvalid;
        } else if (annotations.count == 1) {
            _leftChild = nil;
            _rightChild = nil;
            self.annotation = [annotations.allObjects lastObject];
            self.clusterCoordinate = self.annotation.annotation.coordinate;
            [rootCluster annotationReached];
        } else {
            self.annotation = nil;
            
            // Principal Component Analysis
            // If cov(x,y) = ∑(x-x_mean) * (y-y_mean) != 0 (covariance different from zero), we are looking for the following principal vector:
            // a (aX)
            //   (aY)
            //
            // x_ = x - x_mean ; y_ = y - y_mean
            //
            // aX = cov(x_,y_)
            //
            //
            // aY = 0.5/n * ( ∑(x_^2) + ∑(y_^2) + sqrt( (∑(x_^2) + ∑(y_^2))^2 + 4 * cov(x_,y_)^2 ) )
            
            MKMapPoint centerMapPoint = [self meanCoordinateForAnnotations:annotations gamma:gamma];
            _clusterCoordinate = MKCoordinateForMapPoint(centerMapPoint);
            
            NSArray *splitAnnotations = [self splitAnnotations:annotations centerPoint:centerMapPoint];
            
            MKMapRect leftMapRect = [ADMapCluster boundariesForAnnotations:splitAnnotations[0]];
            MKMapRect rightMapRect = [ADMapCluster boundariesForAnnotations:splitAnnotations[1]];
            
            _leftChild = [[ADMapCluster alloc] initWithAnnotations:splitAnnotations[0] atDepth:depth+1 inMapRect:leftMapRect gamma:gamma clusterTitle:clusterTitle showSubtitle:showSubtitle parentCluster:self rootCluster:rootCluster];
            _rightChild = [[ADMapCluster alloc] initWithAnnotations:splitAnnotations[1] atDepth:depth+1 inMapRect:rightMapRect gamma:gamma clusterTitle:clusterTitle showSubtitle:showSubtitle parentCluster:self rootCluster:rootCluster];
        }
    }
    return self;
}

- (NSArray *)splitAnnotations:(NSSet *)annotations centerPoint:(MKMapPoint)center {
    
    // compute coefficients
    
    double sumXsquared = 0.0;
    double sumYsquared = 0.0;
    double sumXY = 0.0;
    
    for (ADMapPointAnnotation * annotation in annotations) {
        double x = annotation.mapPoint.x - center.x;
        double y = annotation.mapPoint.y - center.y;
        sumXsquared += x * x;
        sumYsquared += y * y;
        sumXY += x * y;
    }
    
    double aX = 0.0;
    double aY = 0.0;
    
    if (fabs(sumXY)/annotations.count > ADMapClusterDiscriminationPrecision) {
        aX = sumXY;
        double lambda = 0.5 * ((sumXsquared + sumYsquared) + sqrt((sumXsquared + sumYsquared) * (sumXsquared + sumYsquared) + 4 * sumXY * sumXY));
        aY = lambda - sumXsquared;
    }
    else {
        aX = sumXsquared > sumYsquared ? 1.0 : 0.0;
        aY = sumXsquared > sumYsquared ? 0.0 : 1.0;
    }
    
    NSMutableSet * leftAnnotations = nil;
    NSMutableSet * rightAnnotations = nil;
    
    if (fabs(sumXsquared)/annotations.count < ADMapClusterDiscriminationPrecision || fabs(sumYsquared)/annotations.count < ADMapClusterDiscriminationPrecision) { // all X and Y are the same => same coordinates
        // then every x equals XMean and we have to arbitrarily choose where to put the pivotIndex
        NSInteger pivotIndex = annotations.count /2 ;
        NSArray *all = annotations.allObjects;
        leftAnnotations = [NSMutableSet setWithArray:[all subarrayWithRange:NSMakeRange(0, pivotIndex)]];
        rightAnnotations = [NSMutableSet setWithArray:[all subarrayWithRange:NSMakeRange(pivotIndex, annotations.count-pivotIndex)]];
    }
    else {
        // compute scalar product between the vector of this regression line and the vector
        // (x - x(mean))
        // (y - y(mean))
        // the sign of this scalar product determines which cluster the point belongs to
        leftAnnotations = [[NSMutableSet alloc] initWithCapacity:annotations.count];
        rightAnnotations = [[NSMutableSet alloc] initWithCapacity:annotations.count];
        for (ADMapPointAnnotation * annotation in annotations) {
            const MKMapPoint point = annotation.mapPoint;
            BOOL positivityConditionOfScalarProduct = YES;
            if (YES) {
                positivityConditionOfScalarProduct = (point.x - center.x) * aX + (point.y - center.y) * aY > 0.0;
            } else {
                positivityConditionOfScalarProduct = (point.y - center.y) > 0.0;
            }
            if (positivityConditionOfScalarProduct) {
                [leftAnnotations addObject:annotation];
            } else {
                [rightAnnotations addObject:annotation];
            }
        }
    }
    
    return @[leftAnnotations, rightAnnotations];
}

- (MKMapPoint)meanCoordinateForAnnotations:(NSSet *)annotations gamma:(double)gamma {
    
    // compute the means of the coordinate
    double XSum = 0.0;
    double YSum = 0.0;
    for (ADMapPointAnnotation * annotation in annotations) {
        XSum += annotation.mapPoint.x;
        YSum += annotation.mapPoint.y;
    }
    double XMean = XSum / (double)annotations.count;
    double YMean = YSum / (double)annotations.count;
    
    if (gamma != 1.0) {
        // take gamma weight into account
        double gammaSumX = 0.0;
        double gammaSumY = 0.0;
        
        double maxDistance = 0.0;
        MKMapPoint meanCenter = MKMapPointMake(XMean, YMean);
        for (ADMapPointAnnotation * annotation in annotations) {
            const double distance = MKMetersBetweenMapPoints(annotation.mapPoint, meanCenter);
            if (distance > maxDistance) {
                maxDistance = distance;
            }
        }
        
        double totalWeight = 0.0;
        for (ADMapPointAnnotation * annotation in annotations) {
            const MKMapPoint point = annotation.mapPoint;
            const double distance = MKMetersBetweenMapPoints(point, meanCenter);
            const double normalizedDistance = maxDistance != 0.0 ? distance/maxDistance : 1.0;
            const double weight = pow(normalizedDistance, gamma-1.0);
            gammaSumX += point.x * weight;
            gammaSumY += point.y * weight;
            totalWeight += weight;
        }
        XMean = gammaSumX/totalWeight;
        YMean = gammaSumY/totalWeight;
    }
    
    return MKMapPointMake(XMean, YMean);
}

+ (MKMapRect)boundariesForAnnotations:(NSSet *)annotations
{
    double XMin = MAXFLOAT, XMax = 0.0, YMin = MAXFLOAT, YMax = 0.0;
    for (ADMapPointAnnotation * annotation in annotations) {
        const MKMapPoint point = annotation.mapPoint;
        if (point.x > XMax) {
            XMax = point.x;
        }
        if (point.y > YMax) {
            YMax = point.y;
        }
        if (point.x < XMin) {
            XMin = point.x;
        }
        if (point.y < YMin) {
            YMin = point.y;
        }
    }
    
    return MKMapRectMake(XMin, YMin, XMax - XMin, YMax - YMin);
}

- (void)setParentCluster:(ADMapCluster *)parentCluster {
    
    _parentCluster = parentCluster;
    
    //add annotation children count
    _parentCluster.clusterCount += _clusterCount;
}

- (void)setClusterCount:(NSInteger)clusterCount {
    
    NSInteger change = clusterCount - _clusterCount;
    
    _clusterCount = clusterCount;
    
    //add difference of cluster count change
    _parentCluster.clusterCount += change;
}

- (void)mapView:(ADClusterMapView *)mapView addAnnotation:(ADMapPointAnnotation *)mapPointAnnotation completion:(void(^)(BOOL added))completion {
    
    //NSLog(@"begin Adding single annotation");
    
    //Outside original rect should do a full tree refresh
    if (!MKMapRectContainsPoint(self.mapRect, mapPointAnnotation.mapPoint)) {
        if (completion) {
            completion(NO);
        }
    }
    
    ADMapCluster *closestCluster = closestCluster = [self childRectContainingPoint:mapPointAnnotation.mapPoint];
    
    if (!closestCluster || !closestCluster.parentCluster) {
        if (completion) {
            completion(NO);
        }
    }
    
    NSMutableSet *annotationsToRecalculate = [[NSMutableSet alloc] initWithArray:closestCluster.originalMapPointAnnotations];
    [annotationsToRecalculate addObject:mapPointAnnotation];
    
    closestCluster.clusterCount = 0;
    
    [ADMapCluster rootClusterForAnnotations:annotationsToRecalculate mapView:mapView completion:^(ADMapCluster *mapCluster) {
        if (closestCluster.parentCluster.rightChild == closestCluster) {
            closestCluster.parentCluster.rightChild = mapCluster;
        }
        else if (closestCluster.parentCluster.leftChild == closestCluster) {
            closestCluster.parentCluster.leftChild = mapCluster;
        }
        
        mapCluster.parentCluster = closestCluster.parentCluster;
        
        if (completion) {
            completion(YES);
        }
    }];
}


- (void)mapView:(ADClusterMapView *)mapView removeAnnotation:(id<MKAnnotation>)annotation completion:(void(^)(BOOL added))completion {
    
    ADMapCluster *clusterToRemove = [self clusterForAnnotation:annotation];
    
    if (!clusterToRemove || clusterToRemove.depth < 2) {
        if (completion) {
            completion(NO);
        }
        return;
    }
    
    //Go up two cluster to ensure a more complete result
    ADMapCluster *clusterParent = clusterToRemove.parentCluster.parentCluster;
    NSMutableSet *annotationsToRecalculate = [[NSMutableSet alloc] initWithArray:clusterParent.originalMapPointAnnotations];
    [annotationsToRecalculate removeObject:clusterToRemove.annotation];
    
    clusterParent.clusterCount = 0;
    
    [ADMapCluster rootClusterForAnnotations:annotationsToRecalculate mapView:mapView completion:^(ADMapCluster *mapCluster) {
        
        if (clusterParent.parentCluster.rightChild == clusterParent) {
            clusterParent.parentCluster.rightChild = mapCluster;
        }
        else if (clusterParent.parentCluster.leftChild == clusterParent) {
            clusterParent.parentCluster.leftChild = mapCluster;
        }
        
        mapCluster.parentCluster = clusterParent.parentCluster;
        
        if (completion) {
            completion(YES);
        }
    }];
}

- (ADMapCluster *)childRectContainingPoint:(MKMapPoint)point {
    
    ADMapCluster *cluster;
    
    if (MKMapRectContainsPoint(self.mapRect, point)) {
        cluster = self;
        ADMapCluster *leftCluster = [_leftChild childRectContainingPoint:point];
        ADMapCluster *rightCluster = [_rightChild childRectContainingPoint:point];
        
        if (leftCluster) {
            cluster = leftCluster;
        }
        
        if (rightCluster) {
            cluster = rightCluster;
        }
        
        if (leftCluster && rightCluster) {
            if (MKMapRectSizeIsGreaterThanOrEqual(rightCluster.mapRect, leftCluster.mapRect)) {
                cluster = leftCluster;
            }
        }
    }
    
    return cluster;
}


#pragma mark - Cluster querying

- (NSSet *)find:(NSInteger)N childrenInMapRect:(MKMapRect)mapRect {
    
    // Start from the root (self)
    // Adopt a breadth-first search strategy
    // If MapRect intersects the bounds, then keep this element for next iteration
    // Stop if there are N elements or more
    // Or if the bottom of the tree was reached (d'oh!)
    
    NSMutableSet * clusters = [[NSMutableSet alloc] initWithObjects:self, nil];
    NSMutableSet * annotations = [[NSMutableSet alloc] init];
    NSMutableSet * previousLevelClusters = nil;
    NSMutableSet * previousLevelAnnotations = nil;
    BOOL clustersDidChange = YES; // prevents infinite loop at the bottom of the tree
    while (clusters.count + annotations.count < N-1 && clusters.count > 0 && clustersDidChange) {
        previousLevelAnnotations = [annotations mutableCopy];
        previousLevelClusters = [clusters mutableCopy];
        [clusters removeAllObjects];
        
        clustersDidChange = NO;
        for (ADMapCluster * cluster in [previousLevelClusters copy]) {
            
            NSArray *children = [cluster children];
            
            if (children.count + clusters.count + annotations.count + previousLevelClusters.count > N) {
                [clusters unionSet:previousLevelClusters];
                break;
            }
            
            for (ADMapCluster * child in children) {
                
                if (child.annotation) {
                    [annotations addObject:child];
                } else {
                    if (MKMapRectIntersectsRect(mapRect, child.mapRect)) {
                        [clusters addObject:child];
                        clustersDidChange = YES;
                    }
                }
            }
            
            [previousLevelClusters removeObject:cluster];
        }
    }
    [self cleanClusters:clusters fromAncestorsOfClusters:annotations];
    
    if (clusters.count + annotations.count > N) { // if there are too many clusters and annotations, that means that we went one level too far in depth
        clusters = previousLevelClusters;
        annotations = previousLevelAnnotations;
        [self cleanClusters:clusters fromAncestorsOfClusters:annotations];
    }
    [self cleanClusters:clusters outsideMapRect:mapRect];
    [annotations unionSet:clusters];
    
    return annotations;
}

- (NSUInteger)numberOfMapRectsContainingChildren:(NSSet *)mapRects {
    
    NSMutableSet * mutableSet = [[NSMutableSet alloc] init];
    for (NSDictionary *dictionary in mapRects) {
        [mutableSet unionSet:[self findClustersInMapRect:[dictionary mapRectForDictionary]]];
    }
    
    return mutableSet.count;
}

- (BOOL)isInMapRect:(MKMapRect)mapRect {
    
    return MKMapRectContainsPoint(mapRect, MKMapPointForCoordinate(self.clusterCoordinate));
}

- (NSSet *)findClustersInMapRect:(MKMapRect)mapRect {
    
    NSMutableSet * clusters = [[NSMutableSet alloc] initWithObjects:self, nil];
    NSMutableSet * clustersWithCoordinateInMapRect = [[NSMutableSet alloc] init];
    NSMutableSet * annotations = [[NSMutableSet alloc] init];
    
    BOOL shouldContinueSearching = YES; // prevents infinite loop at the bottom of the tree
    while (shouldContinueSearching &&
           !clustersWithCoordinateInMapRect.count &&
           !annotations.count) {
        
        shouldContinueSearching = NO;
        NSMutableSet * nextLevelClusters = [[NSMutableSet alloc] init];
        for (ADMapCluster * cluster in clusters) {
            for (ADMapCluster * child in [cluster children]) {
                if (child.annotation) {
                    if ([child isInMapRect:mapRect]) {
                        [annotations addObject:child];
                    }
                } else {
                    if ([child isInMapRect:mapRect]) {
                        [clustersWithCoordinateInMapRect addObject:child];
                    }
                    else if (MKMapRectIntersectsRect(mapRect, [child mapRect])) {
                        [nextLevelClusters addObject:child];
                    }
                }
            }
        }
        if (nextLevelClusters.count > 0) {
            clusters = nextLevelClusters;
            shouldContinueSearching = YES;
        }
    }
    
    [annotations unionSet:clustersWithCoordinateInMapRect];
    
    return annotations;
}

- (NSArray *)children {
    
    NSMutableArray * children = [[NSMutableArray alloc] initWithCapacity:2];
    
    if (_leftChild) {
        [children addObject:_leftChild];
    }
    if (_rightChild) {
        [children addObject:_rightChild];
    }
    return children;
}

- (NSMutableSet *)allChildClusters {
    
    NSMutableSet * allChildrenSet = [[NSMutableSet alloc] initWithCapacity:1];
    
    [allChildrenSet addObject:self];
    
    if (_leftChild) {
        [allChildrenSet unionSet:_leftChild.allChildClusters];
    }
    if (_rightChild) {
        [allChildrenSet unionSet:_rightChild.allChildClusters];
    }
    
    return allChildrenSet;
}

- (BOOL)isAncestorOf:(ADMapCluster *)mapCluster {
    return _depth < mapCluster.depth && (_leftChild == mapCluster || _rightChild == mapCluster || [_leftChild isAncestorOf:mapCluster] || [_rightChild isAncestorOf:mapCluster]);
}

- (BOOL)isRootClusterForAnnotation:(id<MKAnnotation>)annotation {
    return _annotation.annotation == annotation || [_leftChild isRootClusterForAnnotation:annotation] || [_rightChild isRootClusterForAnnotation:annotation];
}

- (NSString *)title {
    if (!self.annotation) {
        if (_clusterTitle) {
            return [NSString stringWithFormat:_clusterTitle, self.clusterCount];
        }
    } else {
        if ([self.annotation.annotation respondsToSelector:@selector(title)]) {
            return self.annotation.annotation.title;
        }
    }
    return nil;
}

- (NSString *)subtitle {
    if (!self.annotation && self.showSubtitle && self.clusterCount < 20) {
        return [self.clusteredAnnotationTitles componentsJoinedByString:@", "];
    } else if ([self.annotation.annotation respondsToSelector:@selector(subtitle)]) {
        return self.annotation.annotation.subtitle;
    }
    return nil;
}


- (NSArray *)clusteredAnnotationTitles {
    if (self.annotation) {
        return [NSArray arrayWithObject:self.annotation.annotation.title];
    } else {
        NSMutableArray * names = [NSMutableArray arrayWithArray:_leftChild.clusteredAnnotationTitles];
        [names addObjectsFromArray:_rightChild.clusteredAnnotationTitles];
        return names;
    }
}

- (NSString *)description {
    return [self title];
}

- (NSMutableArray *)originalMapPointAnnotations {
    NSMutableArray * originalAnnotations = [[NSMutableArray alloc] initWithCapacity:1];
    
    if (self.annotation) {
        [originalAnnotations addObject:self.annotation];
    }
    
    if (_leftChild) {
        [originalAnnotations addObjectsFromArray:_leftChild.originalMapPointAnnotations];
    }
    if (_rightChild) {
        [originalAnnotations addObjectsFromArray:_rightChild.originalMapPointAnnotations];
    }
    return originalAnnotations;
}

- (NSMutableArray *)originalAnnotations {
    NSMutableArray * originalAnnotations = [[NSMutableArray alloc] initWithCapacity:1];
    if (self.annotation) {
        [originalAnnotations addObject:self.annotation.annotation];
    } else {
        if (_leftChild) {
            [originalAnnotations addObjectsFromArray:_leftChild.originalAnnotations];
        }
        if (_rightChild) {
            [originalAnnotations addObjectsFromArray:_rightChild.originalAnnotations];
        }
    }
    return originalAnnotations;
}

- (ADMapCluster *)clusterForAnnotation:(id<MKAnnotation>)annotation {
    
    ADMapCluster *matched = [self clusterMatched:annotation];
    if (matched) {
        return matched;
    }
    
    return nil;
}

- (ADMapCluster *)clusterMatched:(id<MKAnnotation>)annotation {
    
    if (self.annotation.annotation == annotation) {
        return self;
    }
    
    if (_leftChild) {
        ADMapCluster *leftMatched = [_leftChild clusterMatched:annotation];
        if (leftMatched) {
            return leftMatched;
        }
    }
    
    if (_rightChild) {
        ADMapCluster *rightMatched = [_rightChild clusterMatched:annotation];
        if (rightMatched) {
            return rightMatched;
        }
    }
    return nil;
}

#pragma mark - Clean Clusters

- (void)cleanClusters:(NSMutableSet *)clusters fromAncestorsOfClusters:(NSSet *)referenceClusters {
    NSMutableSet *clustersToRemove = [[NSMutableSet alloc] init];
    for (ADMapCluster *cluster in clusters) {
        for (ADMapCluster *referenceCluster in referenceClusters) {
            if ([cluster isAncestorOf:referenceCluster]) {
                [clustersToRemove addObject:cluster];
                break;
            }
        }
    }
    [clusters minusSet:clustersToRemove];
}
- (void)cleanClusters:(NSMutableSet *)clusters outsideMapRect:(MKMapRect)mapRect {
    NSMutableSet *clustersToRemove = [[NSMutableSet alloc] init];
    for (ADMapCluster *cluster in clusters) {
        if (!MKMapRectContainsPoint(mapRect, MKMapPointForCoordinate(cluster.clusterCoordinate))) {
            [clustersToRemove addObject:cluster];
        }
    }
    [clusters minusSet:clustersToRemove];
}

- (NSMutableSet *)findChildrenForClusterInSet:(NSSet *)set {
    
    NSMutableSet *children = [[NSMutableSet alloc] initWithCapacity:set.count];
    for (ADMapCluster *cluster in set) {
        if ([self isAncestorOf:cluster]) {
            [children addObject:cluster];
        }
    }
    
    return children;
}

- (ADMapCluster *)findAncestorForClusterInSet:(NSSet *)set {
    for (ADMapCluster *cluster in set) {
        if ([cluster isAncestorOf:self] || [cluster isEqual:self]) {
            return cluster;
        }
    }
    return nil;
}

- (MKMapRect)childMapRect {
    
    double XMin = MAXFLOAT, XMax = 0.0, YMin = MAXFLOAT, YMax = 0.0;
    for (ADMapCluster * cluster in self.children) {
        MKMapPoint point = MKMapPointForCoordinate(cluster.clusterCoordinate);
        if (point.x > XMax) {
            XMax = point.x;
        }
        if (point.y > YMax) {
            YMax = point.y;
        }
        if (point.x < XMin) {
            XMin = point.x;
        }
        if (point.y < YMin) {
            YMin = point.y;
        }
    }
    return MKMapRectMake(XMin, YMin, XMax - XMin, YMax - YMin);
}


- (void)annotationReached {
    
    _progress++;
    
    double percentage = _progress/_clusterCount;
    
    float progress = (round(percentage*100)) / 100.0;
    
    if (_percentage == progress) {
        return;
    }
    
    _percentage = progress;
    
    [[NSNotificationCenter defaultCenter] postNotificationName:KDTreeClusteringProgress object:@(percentage)];
}

@end
