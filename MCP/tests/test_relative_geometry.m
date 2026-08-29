#import <Foundation/Foundation.h>
#import "../../LookinClient/Manager/LKMCPGeometry.h"

static void Assert(BOOL condition, NSString *message) {
  if (!condition) {
    NSLog(@"FAIL: %@", message);
    exit(1);
  }
}

static BOOL NumberEquals(NSNumber *number, double expected) {
  return fabs(number.doubleValue - expected) < 0.0001;
}

int main(void) {
  @autoreleasepool {
    NSDictionary *left = LKMCPRelationshipForFrames(
        CGRectMake(0, 0, 10, 10), CGRectMake(20, 0, 10, 10));
    Assert([left[@"coordinate_space"] isEqualToString:@"root_axis_aligned"],
           @"coordinate space");
    Assert([left[@"distance_unit"] isEqualToString:@"point"], @"distance unit");
    Assert([left[@"horizontal_relation"] isEqualToString:@"left"], @"left relation");
    Assert(NumberEquals(left[@"horizontal_distance_point"], 10), @"horizontal gap");
    Assert(NumberEquals(left[@"minimum_distance_point"], 10), @"minimum gap");
    Assert(![left[@"overlap"] boolValue], @"separate rectangles do not overlap");

    NSDictionary *diagonal = LKMCPRelationshipForFrames(
        CGRectMake(0, 0, 2, 2), CGRectMake(5, 6, 2, 2));
    Assert(NumberEquals(diagonal[@"horizontal_distance_point"], 3), @"diagonal x gap");
    Assert(NumberEquals(diagonal[@"vertical_distance_point"], 4), @"diagonal y gap");
    Assert(NumberEquals(diagonal[@"minimum_distance_point"], 5), @"3-4-5 distance");

    NSDictionary *partial = LKMCPRelationshipForFrames(
        CGRectMake(0, 0, 10, 10), CGRectMake(5, 5, 10, 10));
    Assert([partial[@"overlap"] boolValue], @"partial overlap");
    Assert([partial[@"containment_relation"] isEqualToString:@"partial_overlap"],
           @"partial containment relation");
    Assert(NumberEquals(partial[@"overlap_area"], 25), @"partial overlap area");

    NSDictionary *contained = LKMCPRelationshipForFrames(
        CGRectMake(0, 0, 20, 20), CGRectMake(5, 5, 5, 5));
    Assert([contained[@"containment_relation"]
               isEqualToString:@"element_1_contains_element_2"],
           @"containment");
    Assert(NumberEquals(contained[@"overlap_ratio_element_2"], 1),
           @"contained coverage");

    NSDictionary *equal = LKMCPRelationshipForFrames(
        CGRectMake(1, 2, 3, 4), CGRectMake(1, 2, 3, 4));
    Assert([equal[@"containment_relation"] isEqualToString:@"equal"],
           @"equal rectangles");

    NSDictionary *touching = LKMCPRelationshipForFrames(
        CGRectMake(0, 0, 10, 10), CGRectMake(10, 2, 4, 4));
    Assert([touching[@"touching"] boolValue], @"edge touching");
    Assert(![touching[@"overlap"] boolValue], @"touching has no positive area");
    Assert(NumberEquals(touching[@"minimum_distance_point"], 0), @"touching distance");

    NSDictionary *above = LKMCPRelationshipForFrames(
        CGRectMake(0, 0, 10, 10), CGRectMake(0, 12, 10, 10));
    Assert([above[@"vertical_relation"] isEqualToString:@"above"], @"above relation");
    Assert(NumberEquals(above[@"vertical_distance_point"], 2), @"vertical gap");
  }
  return 0;
}
