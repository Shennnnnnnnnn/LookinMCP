//
//  LKExportManager.m
//  Lookin
//
//  Created by Li Kai on 2019/5/12.
//  https://lookin.work
//

#import "LKExportManager.h"
#import "LookinHierarchyInfo.h"
#import "LookinHierarchyFile.h"
#import "LookinAppInfo.h"
#import "LookinDisplayItem.h"
#import "LookinDocument.h"
#import "LKHelper.h"
#import "LKNavigationManager.h"
#import "LookinDisplayItem.h"
#import "LookinAttributesGroup.h"
#import "LookinAttributesSection.h"
#import "LookinAttribute.h"
#import "LookinAttrType.h"
#import "LookinDashboardBlueprint.h"
#import "LookinAttribute.h"
#import "LKPreferenceManager.h"
#import "LKEnumListRegistry.h"

@implementation LKExportManager

+ (instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    static LKExportManager *instance = nil;
    dispatch_once(&onceToken,^{
        instance = [[super allocWithZone:NULL] init];
    });
    return instance;
}

+ (id)allocWithZone:(struct _NSZone *)zone{
    return [self sharedInstance];
}

- (NSData *)dataFromHierarchyInfo:(LookinHierarchyInfo *)info imageCompression:(CGFloat)compression fileName:(NSString **)fileName {
    LookinHierarchyFile *file = [LookinHierarchyFile new];
    file.serverVersion = info.serverVersion;
    file.hierarchyInfo = info;
    
    NSMutableDictionary<NSString *, NSData *> *soloScreenshots = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSData *> *groupScreenshots = [NSMutableDictionary dictionary];
    
    NSArray<LookinDisplayItem *> *allItems = [LookinDisplayItem flatItemsFromHierarchicalItems:info.displayItems];
    [allItems enumerateObjectsUsingBlock:^(LookinDisplayItem * _Nonnull displayItem, NSUInteger idx, BOOL * _Nonnull stop) {
        displayItem.screenshotEncodeType = LookinDisplayItemImageEncodeTypeNone;
        soloScreenshots[@(displayItem.layerObject.oid)] = [self _compressedDataFromImage:displayItem.soloScreenshot compression:compression];
        groupScreenshots[@(displayItem.layerObject.oid)] = [self _compressedDataFromImage:displayItem.groupScreenshot compression:compression];
    }];
    file.soloScreenshots = soloScreenshots.copy;
    file.groupScreenshots = groupScreenshots.copy;
    
    LookinDocument *document = [[LookinDocument alloc] init];
    document.hierarchyFile = file;
    NSError *error;
    NSData *exportedData = [document dataOfType:@"com.lookin.lookin" error:&error];
    if (error) {
        NSAssert(NO, @"");
    }
    
    if (fileName) {
        NSString *timeString = ({
            NSDate *date = [NSDate date];
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            [formatter setDateFormat:@"MMddHHmm"];
            [formatter stringFromDate:date];
        });
        NSString *iOSVersion = ({
            NSString *str = info.appInfo.osDescription;
            NSUInteger dotIdx = [str rangeOfString:@"."].location;
            if (dotIdx != NSNotFound) {
                str = [str substringToIndex:dotIdx];
            }
            str;
        });
        *fileName = [NSString stringWithFormat:@"%@_ios%@_%@.lookin", info.appInfo.appName, iOSVersion, timeString];
        
    }
    
    return exportedData;
}

/// compression 范围从 0.01 ~ 1
- (NSData *)_compressedDataFromImage:(LookinImage *)sourceImage compression:(CGFloat)compression {
    if (!sourceImage) {
        return nil;
    }
    
#if TARGET_OS_IPHONE
    return nil;
    
#elif TARGET_OS_MAC
    
    compression = MAX(MIN(compression, 1), 0.01);
    
    NSSize targetSize = NSMakeSize(sourceImage.size.width * compression, sourceImage.size.height * compression);
    NSRect targetFrame = NSMakeRect(0, 0, targetSize.width, targetSize.height);
    NSImageRep *sourceImageRep = [sourceImage bestRepresentationForRect:targetFrame context:nil hints:nil];
    
    NSImage *resizedImage = [[NSImage alloc] initWithSize:targetSize];
    [resizedImage lockFocus];
    [sourceImageRep drawInRect:targetFrame];
    [resizedImage unlockFocus];
    
    NSBitmapImageRep *imageRep = [[NSBitmapImageRep alloc] initWithData:[resizedImage TIFFRepresentation]];
    NSData *compressedData = [imageRep TIFFRepresentationUsingCompression:NSTIFFCompressionLZW factor:1];
    return compressedData;
#endif
}

+ (void)exportScreenshotWithDisplayItem:(LookinDisplayItem *)displayItem {
    NSImage *image = displayItem.groupScreenshot;
    if (!image) {
        AlertError(LookinErr_Inner, CurrentKeyWindow);
        return;
    }
    
    NSData *imageData = [image TIFFRepresentationUsingCompression:NSTIFFCompressionLZW factor:1];
    if (!imageData) {
        AlertError(LookinErr_Inner, CurrentKeyWindow);
        return;
    }
    
    NSString *fileName = [displayItem title] ? : @"LookinImage";

    NSSavePanel *panel = [NSSavePanel savePanel];
    [panel setNameFieldStringValue:fileName];
    [panel setAllowsOtherFileTypes:NO];
    [panel setAllowedFileTypes:@[@"tiff"]];
    [panel setExtensionHidden:YES];
    [panel setCanCreateDirectories:YES];
    [panel beginSheetModalForWindow:CurrentKeyWindow completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            NSString *path = [[panel URL] path];
            NSError *writeError;
            BOOL writeSucc = [imageData writeToFile:path options:0 error:&writeError];
            if (!writeSucc) {
                AlertError(writeError, CurrentKeyWindow);
                NSAssert(NO, @"");
            }
        }
    }];
}

+ (void)exportXMLWithDisplayItem:(LookinDisplayItem *)displayItem {
    if (!displayItem) {
        AlertError(LookinErr_Inner, CurrentKeyWindow);
        return;
    }
    
    // Generate XML string for this item and its children
    NSString *xmlString = [[self sharedInstance] _xmlStringFromDisplayItem:displayItem];
    if (!xmlString || xmlString.length == 0) {
        AlertError(LookinErr_Inner, CurrentKeyWindow);
        return;
    }
    
    NSData *xmlData = [xmlString dataUsingEncoding:NSUTF8StringEncoding];
    if (!xmlData) {
        AlertError(LookinErr_Inner, CurrentKeyWindow);
        return;
    }
    
    NSString *fileName = [displayItem title] ? : @"LookinHierarchy";
    
    NSSavePanel *panel = [NSSavePanel savePanel];
    [panel setNameFieldStringValue:fileName];
    [panel setAllowsOtherFileTypes:NO];
    [panel setAllowedFileTypes:@[@"xml"]];
    [panel setExtensionHidden:YES];
    [panel setCanCreateDirectories:YES];
    [panel beginSheetModalForWindow:CurrentKeyWindow completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            NSString *path = [[panel URL] path];
            NSError *writeError;
            BOOL writeSucc = [xmlData writeToFile:path options:0 error:&writeError];
            if (!writeSucc) {
                AlertError(writeError, CurrentKeyWindow);
                NSAssert(NO, @"");
            }
        }
    }];
}

- (NSString *)_xmlStringFromDisplayItem:(LookinDisplayItem *)item {
    NSMutableString *xml = [NSMutableString string];
    
    // XML header
    [xml appendString:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"];
    [xml appendString:@"<hierarchy>\n"];
    
    // Display item and its children
    [self _appendDisplayItem:item toString:xml indentLevel:1];
    
    [xml appendString:@"</hierarchy>"];
    
    return xml;
}

+ (void)copyXMLWithDisplayItem:(LookinDisplayItem *)displayItem {
    if (!displayItem) {
        AlertError(LookinErr_Inner, CurrentKeyWindow);
        return;
    }
    
    // Generate XML string for this item and its children
    NSString *xmlString = [[self sharedInstance] _xmlStringFromDisplayItem:displayItem];
    if (!xmlString || xmlString.length == 0) {
        AlertError(LookinErr_Inner, CurrentKeyWindow);
        return;
    }
    
    // Copy to clipboard
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:xmlString forType:NSPasteboardTypeString];
}

#pragma mark - XML Export

- (NSString *)xmlStringFromHierarchyInfo:(LookinHierarchyInfo *)info {
    NSMutableString *xml = [NSMutableString string];
    
    // XML header
    [xml appendString:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"];
    [xml appendString:@"<hierarchy>\n"];
    
    // App info
    if (info.appInfo) {
        [xml appendFormat:@"  <appInfo>\n"];
        [xml appendFormat:@"    <appName>%@</appName>\n", [self _escapeXMLString:info.appInfo.appName]];
        [xml appendFormat:@"    <osDescription>%@</osDescription>\n", [self _escapeXMLString:info.appInfo.osDescription]];
        [xml appendFormat:@"  </appInfo>\n"];
    }
    
    // Display items
    [xml appendString:@"  <displayItems>\n"];
    for (LookinDisplayItem *item in info.displayItems) {
        [self _appendDisplayItem:item toString:xml indentLevel:2];
    }
    [xml appendString:@"  </displayItems>\n"];
    
    [xml appendString:@"</hierarchy>"];
    
    return xml;
}

- (void)_appendDisplayItem:(LookinDisplayItem *)item toString:(NSMutableString *)xml indentLevel:(NSInteger)level {
    NSString *indent = [@"" stringByPaddingToLength:level * 2 withString:@" " startingAtIndex:0];
    
    // Start element tag
    [xml appendFormat:@"%@<view", indent];
    
    // Basic attributes
    if (item.viewObject) {
        [xml appendFormat:@" class=\"%@\"", [self _escapeXMLString:item.viewObject.className]];
        [xml appendFormat:@" oid=\"%lu\"", (unsigned long)item.viewObject.oid];
    } else if (item.layerObject) {
        [xml appendFormat:@" class=\"%@\"", [self _escapeXMLString:item.layerObject.className]];
        [xml appendFormat:@" oid=\"%lu\"", (unsigned long)item.layerObject.oid];
    }
    
    if (item.customDisplayTitle) {
        [xml appendFormat:@" title=\"%@\"", [self _escapeXMLString:item.customDisplayTitle]];
    }
    
    [xml appendString:@">\n"];
    
    // Frame
    [xml appendFormat:@"%@  <frame x=\"%.2f\" y=\"%.2f\" width=\"%.2f\" height=\"%.2f\" />\n",
     indent, item.frame.origin.x, item.frame.origin.y, item.frame.size.width, item.frame.size.height];
    
    // Bounds
    [xml appendFormat:@"%@  <bounds x=\"%.2f\" y=\"%.2f\" width=\"%.2f\" height=\"%.2f\" />\n",
     indent, item.bounds.origin.x, item.bounds.origin.y, item.bounds.size.width, item.bounds.size.height];
    
    // Visibility
    [xml appendFormat:@"%@  <visibility hidden=\"%@\" alpha=\"%.2f\" />\n",
     indent, item.isHidden ? @"true" : @"false", item.alpha];
    
    // Background color
    if (item.backgroundColor) {
        CGFloat red = 0, green = 0, blue = 0, alpha = 0;
#if TARGET_OS_MAC
        NSColor *rgbColor = [item.backgroundColor colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
        [rgbColor getRed:&red green:&green blue:&blue alpha:&alpha];
#else
        [item.backgroundColor getRed:&red green:&green blue:&blue alpha:&alpha];
#endif
        [xml appendFormat:@"%@  <backgroundColor red=\"%.3f\" green=\"%.3f\" blue=\"%.3f\" alpha=\"%.3f\" hex=\"#%02X%02X%02X\" />\n",
         indent, red, green, blue, alpha,
         (int)(red * 255), (int)(green * 255), (int)(blue * 255)];
    }
    
    // Extract detailed attributes from attributesGroupList
    NSArray<LookinAttributesGroup *> *allGroups = [item queryAllAttrGroupList];
    if (allGroups.count > 0) {
        [xml appendFormat:@"%@  <attributes>\n", indent];
        
        for (LookinAttributesGroup *group in allGroups) {
            for (LookinAttributesSection *section in group.attrSections) {
                for (LookinAttribute *attr in section.attributes) {
                    [self _appendAttribute:attr toString:xml indentLevel:level + 2];
                }
            }
        }
        
        [xml appendFormat:@"%@  </attributes>\n", indent];
    }
    
    // Subitems
    if (item.subitems.count > 0) {
        [xml appendFormat:@"%@  <subitems>\n", indent];
        for (LookinDisplayItem *subitem in item.subitems) {
            [self _appendDisplayItem:subitem toString:xml indentLevel:level + 2];
        }
        [xml appendFormat:@"%@  </subitems>\n", indent];
    }
    
    // Close element tag
    [xml appendFormat:@"%@</view>\n", indent];
}

- (void)_appendAttribute:(LookinAttribute *)attr toString:(NSMutableString *)xml indentLevel:(NSInteger)level {
    NSString *indent = [@"" stringByPaddingToLength:level * 2 withString:@" " startingAtIndex:0];
    
    NSString *attrName = attr.displayTitle ?: attr.identifier;
    if (!attrName || attrName.length == 0) {
        return;
    }
    
    NSString *valueString = [self _stringValueForAttribute:attr];
    if (valueString) {
        [xml appendFormat:@"%@<attr name=\"%@\" type=\"%@\" value=\"%@\" />\n",
         indent,
         [self _escapeXMLString:attrName],
         [self _attrTypeString:attr.attrType],
         [self _escapeXMLString:valueString]];
    }
}

- (NSString *)_stringValueForAttribute:(LookinAttribute *)attribute {
    if (!attribute.value) {
        return nil;
    }
    
    switch (attribute.attrType) {
        case LookinAttrTypeChar:
        case LookinAttrTypeInt:
        case LookinAttrTypeShort:
        case LookinAttrTypeLong:
        case LookinAttrTypeLongLong:
        case LookinAttrTypeUnsignedChar:
        case LookinAttrTypeUnsignedInt:
        case LookinAttrTypeUnsignedShort:
        case LookinAttrTypeUnsignedLong:
        case LookinAttrTypeUnsignedLongLong:
        case LookinAttrTypeFloat:
        case LookinAttrTypeDouble:
        case LookinAttrTypeSel:
        case LookinAttrTypeClass:
        case LookinAttrTypeCGVector:
        case LookinAttrTypeCGAffineTransform:
        case LookinAttrTypeUIOffset:
            return [attribute.value description];
            
        case LookinAttrTypeBOOL: {
            BOOL boolValue = [(NSNumber *)attribute.value boolValue];
            return boolValue ? @"YES" : @"NO";
        }
            
        case LookinAttrTypeCGPoint:
            return [NSString lookin_stringFromPoint:[(NSValue *)attribute.value pointValue]];
        case LookinAttrTypeCGSize:
            return [NSString lookin_stringFromSize:[(NSValue *)attribute.value sizeValue]];
        case LookinAttrTypeCGRect:
            return [NSString lookin_stringFromRect:[(NSValue *)attribute.value rectValue]];
        case LookinAttrTypeUIEdgeInsets:
            return [NSString lookin_stringFromInset:[(NSValue *)attribute.value edgeInsetsValue]];
            
        case LookinAttrTypeNSString:
        case LookinAttrTypeEnumString:
            return attribute.value;
            
        case LookinAttrTypeEnumInt:
        case LookinAttrTypeEnumLong: {
            NSInteger enumValue = [attribute.value integerValue];
            NSString *enumListName = [LookinDashboardBlueprint enumListNameWithAttrID:attribute.identifier];
            NSString *enumString = [[LKEnumListRegistry sharedInstance] descForEnumName:enumListName value:enumValue];
            return enumString;
        }

        case LookinAttrTypeUIColor: {
            NSColor *color = [NSColor lk_colorFromRGBAComponents:attribute.value];
            if (color) {
                return [LKPreferenceManager mainManager].rgbaFormat ? color.rgbaString : color.hexString;
            } else {
                return @"nil";
            }
        }
        default:
            return [attribute.value description];
    }
}

- (NSString *)_attrTypeString:(LookinAttrType)type {
    switch (type) {
        case LookinAttrTypeNone: return @"none";
        case LookinAttrTypeVoid: return @"void";
        case LookinAttrTypeChar: return @"char";
        case LookinAttrTypeInt: return @"int";
        case LookinAttrTypeShort: return @"short";
        case LookinAttrTypeLong: return @"long";
        case LookinAttrTypeLongLong: return @"longlong";
        case LookinAttrTypeUnsignedChar: return @"uchar";
        case LookinAttrTypeUnsignedInt: return @"uint";
        case LookinAttrTypeUnsignedShort: return @"ushort";
        case LookinAttrTypeUnsignedLong: return @"ulong";
        case LookinAttrTypeUnsignedLongLong: return @"ulonglong";
        case LookinAttrTypeFloat: return @"float";
        case LookinAttrTypeDouble: return @"double";
        case LookinAttrTypeBOOL: return @"bool";
        case LookinAttrTypeSel: return @"selector";
        case LookinAttrTypeClass: return @"class";
        case LookinAttrTypeCGPoint: return @"point";
        case LookinAttrTypeCGVector: return @"vector";
        case LookinAttrTypeCGSize: return @"size";
        case LookinAttrTypeCGRect: return @"rect";
        case LookinAttrTypeCGAffineTransform: return @"transform";
        case LookinAttrTypeUIEdgeInsets: return @"insets";
        case LookinAttrTypeUIOffset: return @"offset";
        case LookinAttrTypeNSString: return @"string";
        case LookinAttrTypeEnumInt: return @"enum_int";
        case LookinAttrTypeEnumLong: return @"enum_long";
        case LookinAttrTypeUIColor: return @"color";
        case LookinAttrTypeCustomObj: return @"custom";
        case LookinAttrTypeEnumString: return @"enum";
        case LookinAttrTypeShadow: return @"shadow";
        case LookinAttrTypeJson: return @"json";
        default: return @"unknown";
    }
}

- (NSString *)_escapeXMLString:(NSString *)string {
    if (!string) {
        return @"";
    }
    
    NSMutableString *escaped = [string mutableCopy];
    [escaped replaceOccurrencesOfString:@"&" withString:@"&amp;" options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"<" withString:@"&lt;" options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@">" withString:@"&gt;" options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"\"" withString:@"&quot;" options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"'" withString:@"&apos;" options:0 range:NSMakeRange(0, escaped.length)];
    
    return escaped;
}

@end
