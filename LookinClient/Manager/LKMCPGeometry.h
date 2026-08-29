#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <math.h>

NS_ASSUME_NONNULL_BEGIN

NS_INLINE NSDictionary *LKMCPBoundsForRect(CGRect rect) {
  return @{
    @"left" : @(CGRectGetMinX(rect)),
    @"right" : @(CGRectGetMaxX(rect)),
    @"top" : @(CGRectGetMinY(rect)),
    @"bottom" : @(CGRectGetMaxY(rect)),
    @"width" : @(CGRectGetWidth(rect)),
    @"height" : @(CGRectGetHeight(rect))
  };
}

NS_INLINE NSDictionary *LKMCPRelationshipForFrames(CGRect rawFrame1,
                                                     CGRect rawFrame2) {
  CGRect frame1 = CGRectStandardize(rawFrame1);
  CGRect frame2 = CGRectStandardize(rawFrame2);

  NSString *horizontalRelation = nil;
  NSString *horizontalDescription = nil;
  CGFloat horizontalDistance = 0;
  if (CGRectGetMaxX(frame1) <= CGRectGetMinX(frame2)) {
    horizontalRelation = @"left";
    horizontalDescription = @"element_1 在 element_2 左侧";
    horizontalDistance = CGRectGetMinX(frame2) - CGRectGetMaxX(frame1);
  } else if (CGRectGetMinX(frame1) >= CGRectGetMaxX(frame2)) {
    horizontalRelation = @"right";
    horizontalDescription = @"element_1 在 element_2 右侧";
    horizontalDistance = CGRectGetMinX(frame1) - CGRectGetMaxX(frame2);
  } else {
    horizontalRelation = @"intersects";
    horizontalDescription = @"element_1 与 element_2 水平存在交集";
  }

  NSString *verticalRelation = nil;
  NSString *verticalDescription = nil;
  CGFloat verticalDistance = 0;
  if (CGRectGetMaxY(frame1) <= CGRectGetMinY(frame2)) {
    verticalRelation = @"above";
    verticalDescription = @"element_1 在 element_2 上方";
    verticalDistance = CGRectGetMinY(frame2) - CGRectGetMaxY(frame1);
  } else if (CGRectGetMinY(frame1) >= CGRectGetMaxY(frame2)) {
    verticalRelation = @"below";
    verticalDescription = @"element_1 在 element_2 下方";
    verticalDistance = CGRectGetMinY(frame1) - CGRectGetMaxY(frame2);
  } else {
    verticalRelation = @"intersects";
    verticalDescription = @"element_1 与 element_2 垂直存在交集";
  }

  CGRect intersection = CGRectIntersection(frame1, frame2);
  BOOL overlap = !CGRectIsNull(intersection) &&
                 CGRectGetWidth(intersection) > 0 &&
                 CGRectGetHeight(intersection) > 0;
  BOOL touching = !overlap && horizontalDistance == 0 && verticalDistance == 0;
  CGFloat overlapArea = overlap ? CGRectGetWidth(intersection) *
                                      CGRectGetHeight(intersection)
                                : 0;
  CGFloat area1 = CGRectGetWidth(frame1) * CGRectGetHeight(frame1);
  CGFloat area2 = CGRectGetWidth(frame2) * CGRectGetHeight(frame2);

  NSString *containmentRelation = @"none";
  NSString *containmentDescription = @"无重叠";
  if (overlap) {
    if (CGRectEqualToRect(frame1, frame2)) {
      containmentRelation = @"equal";
      containmentDescription = @"element_1 与 element_2 边界相同";
    } else if (CGRectContainsRect(frame1, frame2)) {
      containmentRelation = @"element_1_contains_element_2";
      containmentDescription = @"element_1 完全包含 element_2";
    } else if (CGRectContainsRect(frame2, frame1)) {
      containmentRelation = @"element_2_contains_element_1";
      containmentDescription = @"element_2 完全包含 element_1";
    } else {
      containmentRelation = @"partial_overlap";
      containmentDescription = @"部分重叠";
    }
  } else if (touching) {
    containmentDescription = @"边界接触但无面积重叠";
  }

  return @{
    @"coordinate_space" : @"root_axis_aligned",
    @"distance_unit" : @"point",
    @"element_1_bounds" : LKMCPBoundsForRect(frame1),
    @"element_2_bounds" : LKMCPBoundsForRect(frame2),
    @"horizontal_relation" : horizontalRelation,
    @"horizontal" : horizontalDescription,
    @"horizontal_distance_point" : @(horizontalDistance),
    @"vertical_relation" : verticalRelation,
    @"vertical" : verticalDescription,
    @"vertical_distance_point" : @(verticalDistance),
    @"minimum_distance_point" :
        @(hypot(horizontalDistance, verticalDistance)),
    @"center_distance_point" :
        @(hypot(CGRectGetMidX(frame1) - CGRectGetMidX(frame2),
                CGRectGetMidY(frame1) - CGRectGetMidY(frame2))),
    @"overlap" : @(overlap),
    @"touching" : @(touching),
    @"containment_relation" : containmentRelation,
    @"containment" : containmentDescription,
    @"intersection_size" : @{
      @"width" : @(overlap ? CGRectGetWidth(intersection) : 0),
      @"height" : @(overlap ? CGRectGetHeight(intersection) : 0)
    },
    @"overlap_area" : @(overlapArea),
    @"overlap_ratio_element_1" : @(area1 > 0 ? overlapArea / area1 : 0),
    @"overlap_ratio_element_2" : @(area2 > 0 ? overlapArea / area2 : 0)
  };
}

NS_ASSUME_NONNULL_END
