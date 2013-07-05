//
//  EmotionAttributedLabel.m
//  Espressos
//
//  Created by Chen Qizhi on 7/6/13.
//  
//

#import "EmotionAttributedLabel.h"

static inline NSRegularExpression * EmotionRegularExpression() {
    
    static NSRegularExpression *_emotionRegularExpression = nil;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _emotionRegularExpression = [[NSRegularExpression alloc] initWithPattern:@"\\[[^\\[\\]]*\\]" options:NSRegularExpressionCaseInsensitive error:nil];
    });
    
    return _emotionRegularExpression;
}

#define kEmotionDefaultWidth 24.0
#define kEmotionLocation @"kEmotionLocation"
#define kEmotionImageName @"kEmotionImageName"
#define kEmotionPlaceholder @" "

@interface TTTAttributedLabel (DeclarePrivateMethodsForT3)

- (void)drawStrike:(CTFrameRef)frame
            inRect:(CGRect)rect
           context:(CGContextRef)c;

@end

@interface EmotionAttributedLabel ()

@property (nonatomic, strong) NSMutableArray *emotions;

@end

@implementation EmotionAttributedLabel

- (NSDictionary *)emotionDictionary
{
    static NSMutableDictionary *_emotionDictionary = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _emotionDictionary = [[NSMutableDictionary alloc] initWithDictionary:@{@"[:-)]": @"emotion"}];
    });
    
    return _emotionDictionary;
}

- (NSMutableArray *)emotions
{
    if (_emotions == nil) {
        _emotions = [[NSMutableArray alloc] initWithCapacity:10];
    }
    
    return _emotions;
}

- (void)drawEmotionWithFrame:(CTFrameRef)f context:(CGContextRef)ctx
{
    CFArrayRef lines = CTFrameGetLines(f);
    NSUInteger linesCount = CFArrayGetCount(lines);
    
    CGPoint origins[linesCount];
    CTFrameGetLineOrigins(f, CFRangeMake(0, 0), origins);
    
    int imgIndex = 0;
    NSDictionary* nextImage = self.emotions[imgIndex];
    int imgLocation = [nextImage[kEmotionLocation] intValue];
    
    CFRange frameRange = CTFrameGetVisibleStringRange(f);
    while (imgLocation < frameRange.location) {
        imgIndex ++;
        if (imgIndex >= self.emotions.count) {
            return;
        }
        else {
            nextImage = self.emotions[imgIndex];
            imgLocation = [nextImage[kEmotionLocation] intValue];
        }
    }
    
    NSUInteger lineIndex = 0;
    for (int i = 0; i < linesCount; i++) {
        
        CTLineRef line = CFArrayGetValueAtIndex(lines, i);
        CFArrayRef runs = CTLineGetGlyphRuns(line);
        NSUInteger runsCount = CFArrayGetCount(runs);
        
        for (int j = 0; j < runsCount; j++) {
            
            CTRunRef run =  CFArrayGetValueAtIndex(runs, j);
            CFRange runRange = CTRunGetStringRange(run);
            
            if ( runRange.location <= imgLocation && runRange.location + runRange.length > imgLocation ) {
                
	            CGRect runBounds;
	            CGFloat ascent;
	            CGFloat descent;
	            runBounds.size.width = CTRunGetTypographicBounds(run, CFRangeMake(0, 0), &ascent, &descent, NULL);
	            runBounds.size.height = ascent + descent;
                
	            CGFloat xOffset = CTLineGetOffsetForStringIndex(line, CTRunGetStringRange(run).location, NULL);
	            runBounds.origin.x = origins[lineIndex].x  + xOffset;
	            runBounds.origin.y = origins[lineIndex].y;
	            runBounds.origin.y -= descent;
                
                CGPathRef pathRef = CTFrameGetPath(f);
                CGRect colRect = CGPathGetBoundingBox(pathRef);
                CGRect imgBounds = CGRectOffset(runBounds, colRect.origin.x, colRect.origin.y);
                
                ///////////////////////////////////////////////////////////////////////////////////////////////////////////
                // :-(
                // To fix a bug appear in iOS 6 :
                // https://github.com/qchenqizhi/TTTAttributedLabel/commit/1c4dd88dab47de0849484ce5d34e9a46a7a59dfa
                ///////////////////////////////////////////////////////////////////////////////////////////////////////////
                
                int imgCount = (int)roundf(imgBounds.size.width / kEmotionDefaultWidth);
                if (imgCount > 1) {
                    //Bug appear!
                    for (int i = 0; i < imgCount; i++) {
                        CGRect imageRect = CGRectMake(imgBounds.origin.x + kEmotionDefaultWidth * i, imgBounds.origin.y, kEmotionDefaultWidth, kEmotionDefaultWidth);
                        if (imgIndex < self.emotions.count) {
                            NSDictionary *imageInfo = self.emotions[imgIndex];
                            UIImage *img = [UIImage imageNamed:imageInfo[kEmotionImageName]];
                            CGContextDrawImage(ctx, imageRect, img.CGImage);
                        }
                        
                        imgIndex++;
                    }
                }
                else {
                    //Normal
                    UIImage *img = [UIImage imageNamed:nextImage[kEmotionImageName]];
                    CGContextDrawImage(ctx, imgBounds, img.CGImage);
                    imgIndex++;
                }
                
                ///////////////////////////////////////////////////////////////////////////////////////////////////////////
                                
                if (imgIndex < self.emotions.count) {
                    nextImage = self.emotions[imgIndex];
                    imgLocation = [nextImage[kEmotionLocation] intValue];
                }
                
            }
        }
        lineIndex++;
        
    }
}

- (void)setTextMaybeWithEmotion:(id)text
{
    __weak EmotionAttributedLabel *weakSelf = self;
    
    [self.emotions removeAllObjects];
    
    [self setText:text afterInheritingLabelAttributesAndConfiguringWithBlock:^NSMutableAttributedString *(NSMutableAttributedString *mutableAttributedString) {
        
        NSRange stringRange = NSMakeRange(0, mutableAttributedString.length);
        
        NSRegularExpression *regexp = EmotionRegularExpression();
        
        NSString *originString = [NSString stringWithString:mutableAttributedString.string];
        
        __block NSUInteger rangeOffsex = 0;
        
        [regexp enumerateMatchesInString:originString options:0 range:stringRange usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
            
            NSString *str = [originString substringWithRange:result.range];
            NSString *emotionImageName = [weakSelf emotionDictionary][str];
            if (emotionImageName.length > 0) {
                [weakSelf.emotions addObject:@{
                           kEmotionImageName: emotionImageName,
                            kEmotionLocation: [NSNumber numberWithInt:(result.range.location - rangeOffsex)]}];
                
                NSRange range = result.range;
                range.location -= rangeOffsex;
                
                CTRunDelegateCallbacks callbacks;
                callbacks.version = kCTRunDelegateVersion1;
                callbacks.getAscent = ascentCallback;
                callbacks.getDescent = descentCallback;
                callbacks.getWidth = widthCallback;
                callbacks.dealloc = deallocCallback;
                
                CTRunDelegateRef delegate = CTRunDelegateCreate(&callbacks, NULL);
                
                
                
                NSDictionary *attrDictionaryDelegate = @{
                                                         (NSString *)kCTRunDelegateAttributeName: (__bridge id)delegate,
                                                         (NSString *)kCTForegroundColorAttributeName: (id)[UIColor clearColor].CGColor,
                                                         };
                
                NSAttributedString *emotionString = [[NSAttributedString alloc] initWithString:kEmotionPlaceholder attributes:attrDictionaryDelegate];
                
                [mutableAttributedString removeAttribute:(NSString *)kCTFontAttributeName range:range];
                [mutableAttributedString removeAttribute:(NSString *)kCTForegroundColorAttributeName range:range];
                
                [mutableAttributedString replaceCharactersInRange:range withAttributedString:emotionString];
                
                rangeOffsex += (result.range.length - [kEmotionPlaceholder length]);
                
                CFRelease(delegate);
            }
            
        }];
        
        CTParagraphStyleSetting lineBreakMode;
        CTLineBreakMode lineBreak = kCTLineBreakByCharWrapping;
        lineBreakMode.spec = kCTParagraphStyleSpecifierLineBreakMode;
        lineBreakMode.value = &lineBreak;
        lineBreakMode.valueSize = sizeof(CTLineBreakMode);
        
        CTParagraphStyleSetting settings[] = {
            lineBreakMode
        };
        
        CTParagraphStyleRef style = CTParagraphStyleCreate(settings, 1);
        
        [mutableAttributedString addAttribute:(NSString *)kCTParagraphStyleAttributeName value:(__bridge id)style range:NSMakeRange(0, mutableAttributedString.length)];
        
        CFRelease(style);
        
        return mutableAttributedString;
        
    }];
}

#pragma mark - TTTAttributedLabel
- (void)drawStrike:(CTFrameRef)frame
            inRect:(CGRect)rect
           context:(CGContextRef)c;
{
    [super drawStrike:frame
               inRect:rect
              context:c];
    
    if (self.emotions.count > 0) {
        [self drawEmotionWithFrame:frame context:c];
    }
}

#pragma mark - CTRunDelegateCallbacks
static void deallocCallback(void *ref)
{
    CFBridgingRelease(ref);
}

static CGFloat ascentCallback(void *ref)
{
    return 17;
}

static CGFloat descentCallback(void *ref)
{
    return 7;
}

static CGFloat widthCallback(void *ref)
{
    return kEmotionDefaultWidth;
}

@end
