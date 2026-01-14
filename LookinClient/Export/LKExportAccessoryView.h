//
//  LKExportAccessoryView.h
//  Lookin
//
//  Created by Li Kai on 2019/5/13.
//  https://lookin.work
//

#import "LKBaseView.h"
#import "LKExportManager.h"

typedef NS_ENUM(NSUInteger, LKExportFormat) {
    LKExportFormatLookin,
    LKExportFormatXML
};

@interface LKExportAccessoryView : LKBaseView

@property(nonatomic, assign) NSUInteger dataSize;
@property(nonatomic, assign, readonly) LKExportFormat selectedFormat;

@end
