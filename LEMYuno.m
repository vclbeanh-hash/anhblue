/* LEM Yuno v1.0 — independent iOS tweak, inspired by Yuno.
   Runtime selector references: https://github.com/dayanch96/YTLite
   Design reference: https://github.com/danielkanan/Yuno/tree/v1.1.1 */
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <math.h>
#import <QuartzCore/QuartzCore.h>

static NSString * const Kbg=@"LEMYuno.background";
static NSString * const Kad=@"LEMYuno.adResponse";
static NSString * const Krate=@"LEMYuno.speed";
static NSString * const Ksb=@"LEMYuno.sponsor";
static NSString * const Khd=@"LEMYuno.hd";
static NSString * const Kglass=@"LEMYuno.glass";
static NSString * const Kmini=@"LEMYuno.mini";
static char videoKey,glassKey,glassEffectKey,glassBgKey;
static __weak id lastTickPlayer;
static CFTimeInterval lastTickAt;
static NSString *lastRateID;
static NSUInteger rateAttempts;
static CFTimeInterval lastRateAt;
static IMP origTick,origPivot,origMini;
static NSString *sbID;
static NSArray<NSArray<NSNumber *> *> *segments;
static NSMutableSet<NSNumber *> *skipped;
static NSURLSessionDataTask *sbTask;
static NSString *qualityID;
static NSUInteger qualityAttempts;
static CFTimeInterval lastQuality;
static __weak UIViewController *activeOverlay;
static IMP origOrder,origCategory;
static const NSUInteger LemCategory=74193;
static IMP origBG,origML,origAd,origLayout;
static BOOL enabled(NSString *k){return [[NSUserDefaults standardUserDefaults] boolForKey:k];}
static void toggle(NSString *k){[[NSUserDefaults standardUserDefaults] setBool:!enabled(k) forKey:k];}
static BOOL yesBG(id t,SEL s){return enabled(Kbg)?YES:((BOOL(*)(id,SEL))origBG)(t,s);}
static BOOL yesML(id t,SEL s){return enabled(Kbg)?YES:((BOOL(*)(id,SEL))origML)(t,s);}
static BOOL noAd(id t,SEL s){return enabled(Kad)?NO:((BOOL(*)(id,SEL))origAd)(t,s);}
static IMP hook(Class c,SEL s,IMP replacement,BOOL boolOnly){
  if(!c)return NULL;
  Method m=class_getInstanceMethod(c,s);
  if(!m||method_getNumberOfArguments(m)!=2)return NULL;
  char ret[16]={0};method_getReturnType(m,ret,sizeof ret);
  if(boolOnly?(ret[0]!='B'&&ret[0]!='c'):(ret[0]!='v'))return NULL;
  IMP old=method_getImplementation(m);if(!old||old==replacement)return NULL;
  class_replaceMethod(c,s,replacement,method_getTypeEncoding(m));return old;
}
static BOOL applyRate(id obj,double rate){
  SEL s=NSSelectorFromString(@"setPlaybackRate:");
  if(![obj respondsToSelector:s])return NO;
  Method m=class_getInstanceMethod([obj class],s);
  if(!m||method_getNumberOfArguments(m)!=3)return NO;
  char arg[16]={0},ret[16]={0};
  method_getArgumentType(m,2,arg,sizeof arg);method_getReturnType(m,ret,sizeof ret);
  if(ret[0]!='v')return NO;
  if(arg[0]=='d'){((void(*)(id,SEL,double))objc_msgSend)(obj,s,rate);return YES;}
  if(arg[0]=='f'){((void(*)(id,SEL,float))objc_msgSend)(obj,s,(float)rate);return YES;}
  return NO;
}
static NSArray<NSNumber *> *rates(void){return @[@0.5,@0.75,@1,@1.25,@1.5,@2,@2.5,@3];}
static double savedRate(void){double x=[NSUserDefaults.standardUserDefaults doubleForKey:Krate];return x>=.5&&x<=3?x:1;}
static void chooseRate(UIViewController *vc){
    if(!vc||vc.presentedViewController)return;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Tốc độ mặc định" message:@"Được lưu cho video tiếp theo." preferredStyle:UIAlertControllerStyleAlert];
    for(NSNumber *n in rates()){
        double val=n.doubleValue;
        NSString *title=[NSString stringWithFormat:@"%@x%@",n,fabs(savedRate()-val)<0.001?@" ✓":@""];
        [a addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){
            [NSUserDefaults.standardUserDefaults setDouble:val forKey:Krate];
            UIViewController *p=activeOverlay;
            if(!applyRate(p,val))applyRate(p.parentViewController,val);
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];
    [vc presentViewController:a animated:YES completion:nil];
}
static void layout(UIViewController *t,SEL s){
    ((void(*)(id,SEL))origLayout)(t,s);
    if(!t.viewIfLoaded.window)return;
    activeOverlay=t;
    SEL vid=NSSelectorFromString(@"videoID");
    if(![t respondsToSelector:vid])return;
    Method m=class_getInstanceMethod([t class],vid);
    char type[16]={0};if(!m)return;method_getReturnType(m,type,sizeof type);if(type[0]!='@')return;
    id ident=((id(*)(id,SEL))objc_msgSend)(t,vid);
    if(![ident isKindOfClass:NSString.class]||![ident length])return;
    if([ident isEqual:objc_getAssociatedObject(t,&videoKey)])return;
    objc_setAssociatedObject(t,&videoKey,ident,OBJC_ASSOCIATION_COPY_NONATOMIC);
    // Leave the app's normal playback behavior alone until a speed is selected.
    if(!origTick&&[NSUserDefaults.standardUserDefaults objectForKey:Krate]){
        if(!applyRate(t,savedRate()))applyRate(t.parentViewController,savedRate());
    }
}
static BOOL available(id obj,SEL sel,unsigned int argc){
    if(!obj||![obj respondsToSelector:sel])return NO;
    Method m=class_getInstanceMethod(object_getClass(obj),sel);
    return m&&method_getNumberOfArguments(m)==argc;
}
// Private video methods are called only with the expected runtime signature.
static id getObj(id obj,NSString *name){
    SEL sel=NSSelectorFromString(name);
    if(!available(obj,sel,2))return nil;
    Method m=class_getInstanceMethod([obj class],sel);
    char ret[16]={0};method_getReturnType(m,ret,sizeof ret);
    return ret[0]=='@'?((id(*)(id,SEL))objc_msgSend)(obj,sel):nil;
}
static double getTime(id obj,NSString *name){
    SEL sel=NSSelectorFromString(name);
    if(!available(obj,sel,2))return NAN;
    Method m=class_getInstanceMethod([obj class],sel);
    char ret[16]={0};method_getReturnType(m,ret,sizeof ret);
    if(ret[0]=='d')return ((double(*)(id,SEL))objc_msgSend)(obj,sel);
    if(ret[0]=='f')return ((float(*)(id,SEL))objc_msgSend)(obj,sel);
    return NAN;
}
static BOOL seek(id obj,double time){
    for(NSString *name in @[@"seekToTime:",@"scrubToTime:"]){
        SEL sel=NSSelectorFromString(name);
        if(!available(obj,sel,3))continue;
        Method m=class_getInstanceMethod([obj class],sel);
        char arg[16]={0},ret[16]={0};method_getArgumentType(m,2,arg,sizeof arg);method_getReturnType(m,ret,sizeof ret);
        if(ret[0]!='v')continue;
        if(arg[0]=='d'){((void(*)(id,SEL,double))objc_msgSend)(obj,sel,time);return YES;}
        if(arg[0]=='f'){((void(*)(id,SEL,float))objc_msgSend)(obj,sel,(float)time);return YES;}
    }
    return NO;
}
static BOOL validID(id ident){
    if(![ident isKindOfClass:NSString.class]||[ident length]!=11)return NO;
    NSCharacterSet *allowed=[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"];
    return [ident rangeOfCharacterFromSet:allowed.invertedSet].location==NSNotFound;
}
static void resetSponsor(void){
    [sbTask cancel];sbTask=nil;sbID=nil;segments=nil;skipped=nil;
}
static void getSegments(NSString *ident){
    [sbTask cancel];sbID=[ident copy];segments=nil;skipped=[NSMutableSet set];
    NSURLComponents *u=[NSURLComponents componentsWithString:@"https://sponsor.ajay.app/api/skipSegments"];
    u.queryItems=@[[NSURLQueryItem queryItemWithName:@"videoID" value:ident],[NSURLQueryItem queryItemWithName:@"categories" value:@"[\"sponsor\"]"]];
    NSMutableURLRequest *req=[NSMutableURLRequest requestWithURL:u.URL cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:12];
    // This endpoint receives the public video ID, never account cookies or credentials.
    NSURLSessionConfiguration *cfg=NSURLSessionConfiguration.ephemeralSessionConfiguration;
    cfg.HTTPCookieStorage=nil;cfg.HTTPShouldSetCookies=NO;cfg.URLCredentialStorage=nil;
    NSURLSession *session=[NSURLSession sessionWithConfiguration:cfg];
    sbTask=[session dataTaskWithRequest:req completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){
        NSArray *json=nil;
        if(!error&&data.length<262144&&[(NSHTTPURLResponse *)response statusCode]==200)
            json=[NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSMutableArray *out=[NSMutableArray array];
        if([json isKindOfClass:NSArray.class])for(id row in json){
            if(![row isKindOfClass:NSDictionary.class]||![row[@"category"] isEqual:@"sponsor"])continue;
            id p=row[@"segment"];if(![p isKindOfClass:NSArray.class]||[p count]!=2)continue;
            if(![p[0] isKindOfClass:NSNumber.class]||![p[1] isKindOfClass:NSNumber.class])continue;
            double a=[p[0] doubleValue],b=[p[1] doubleValue];
            if(isfinite(a)&&isfinite(b)&&a>=0&&b>a+.1&&b<43200)[out addObject:@[@(a),@(b)]];
        }
        dispatch_async(dispatch_get_main_queue(),^{if(enabled(Ksb)&&[sbID isEqual:ident])segments=[out copy];});
        [session finishTasksAndInvalidate];
    }];
    [sbTask resume];
}
static BOOL preferHD(id player){
    id video=getObj(player,@"contentVideo") ?: getObj(player,@"activeVideo");
    id formats=getObj(video,@"selectableVideoFormats");
    if(![formats isKindOfClass:NSArray.class]||![formats count])return NO;
    NSString *best=nil;NSInteger max=0;
    for(id f in formats){
        id label=getObj(f,@"qualityLabel");
        if(![label isKindOfClass:NSString.class]||[label rangeOfString:@"p"].location==NSNotFound)continue;
        NSInteger n=[label integerValue];
        if(n>0&&n<=1080&&n>=max){
            if(n>max||!best||[label hasSuffix:@"60"]){max=n;best=label;}
        }
    }
    if(!best)return NO;
    Class fc=NSClassFromString(@"MLQuickMenuVideoQualitySettingFormatConstraint");
    SEL init=NSSelectorFromString(@"initWithVideoQualitySetting:formatSelectionReason:qualityLabel:");
    SEL set=NSSelectorFromString(@"setVideoFormatConstraint:");
    id obj=[fc alloc];
    if(!available(obj,init,5)||!available(video,set,3))return NO;
    Method im=class_getInstanceMethod(fc,init);
    char a[16]={0},b[16]={0},c[16]={0},ret[16]={0};
    method_getArgumentType(im,2,a,sizeof a);method_getArgumentType(im,3,b,sizeof b);method_getArgumentType(im,4,c,sizeof c);method_getReturnType(im,ret,sizeof ret);
    if(a[0]!='i'||(b[0]!='q'&&b[0]!='Q')||c[0]!='@'||ret[0]!='@')return NO;
    id constraint=((id(*)(id,SEL,int,NSInteger,id))objc_msgSend)(obj,init,3,2,best);
    if(!constraint)return NO;
    ((void(*)(id,SEL,id))objc_msgSend)(video,set,constraint);
    return YES;
}
static void playerTick(id player){
    NSString *ident=getObj(player,@"contentVideoID");
    if(!validID(ident))return;
    NSString *current=getObj(player,@"currentVideoID");
    if(![current isEqual:ident])return; // Do not seek inside a different active stream.
    if(![lastRateID isEqual:ident]){lastRateID=[ident copy];rateAttempts=0;lastRateAt=0;}
    if([NSUserDefaults.standardUserDefaults objectForKey:Krate]&&rateAttempts<2&&CACurrentMediaTime()-lastRateAt>1.0){
        lastRateAt=CACurrentMediaTime();rateAttempts++;
        if(applyRate(player,savedRate()))rateAttempts=2;
    }
    if(enabled(Khd)){
        if(![qualityID isEqual:ident]){qualityID=[ident copy];qualityAttempts=0;lastQuality=0;}
        CFTimeInterval now=CACurrentMediaTime();
        if(qualityAttempts<4&&now-lastQuality>2){
            lastQuality=now;qualityAttempts++;
            if(preferHD(player))qualityAttempts=4;
        }
    }
    if(!enabled(Ksb)){if(sbID)resetSponsor();return;}
    if(![sbID isEqual:ident]){getSegments(ident);return;}
    if(!segments.count)return;
    id overlay=getObj(player,@"activeVideoPlayerOverlay");
    double now=getTime(player,@"currentVideoMediaTime");
    if(!isfinite(now))now=getTime(overlay,@"mediaTime");
    if(!isfinite(now))return;
    double total=getTime(player,@"currentVideoTotalMediaTime");
    for(NSUInteger i=0;i<segments.count;i++){
        NSArray *p=segments[i];double a=[p[0] doubleValue],b=[p[1] doubleValue];
        if([skipped containsObject:@(i)]||now<a||now>=b-.15)continue;
        if(isfinite(total)&&total>0&&b>=total)continue;
        [skipped addObject:@(i)];if(!seek(player,b))[skipped removeObject:@(i)];break;
    }
}
static void tick(id t,SEL s,id v,id tm){
    ((void(*)(id,SEL,id,id))origTick)(t,s,v,tm);
    // Some builds deliver player observer callbacks off-main. Move UI and state work to main.
    __weak id weakPlayer=t;
    void (^process)(void)=^{
        id player=weakPlayer;if(!player)return;
        CFTimeInterval now=CACurrentMediaTime();
        if(lastTickPlayer==player&&now-lastTickAt<.22)return;
        lastTickPlayer=player;lastTickAt=now;
        @try{playerTick(player);}@catch(NSException *e){NSLog(@"[LEMYuno] player: %@",e.reason);}
    };
    if(NSThread.isMainThread)process();else dispatch_async(dispatch_get_main_queue(),process);
}
static BOOL mini(id t,SEL s){return enabled(Kmini)?NO:((BOOL(*)(id,SEL))origMini)(t,s);}
// v1.0 — floating glass shell, no changes to native tab frames or hit testing.
static char shellKey,oldHiddenKey,oldMaskKey,oldContentColorKey,indicatorKey,nativeMaskOwnerKey;
static __weak UIView *lastPivotView;
static void restoreHidden(UIView *v){
    if(!v)return;
    NSNumber *old=objc_getAssociatedObject(v,&oldHiddenKey);
    if(old){v.hidden=old.boolValue;objc_setAssociatedObject(v,&oldHiddenKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
}
static void hideDecor(UIView *v){
    if(!v)return;
    if(!objc_getAssociatedObject(v,&oldHiddenKey))objc_setAssociatedObject(v,&oldHiddenKey,@(v.hidden),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    v.hidden=YES;
}
static void restoreBackground(UIView *v,const void *key){
    if(!v)return;
    id old=objc_getAssociatedObject(v,key);
    if(old){v.backgroundColor=old==NSNull.null?nil:old;objc_setAssociatedObject(v,key,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
}
static void clearBackground(UIView *v,const void *key){
    if(!v)return;
    if(!objc_getAssociatedObject(v,key))objc_setAssociatedObject(v,key,v.backgroundColor?:NSNull.null,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    v.backgroundColor=UIColor.clearColor;
}
// Small, local optical sample. Render only content behind the pivot bar,
// never the window (which would contain our own overlay).
static UIView *lemBackdropSource(UIView *pivot,CGRect windowRect){
    UIView *branch=pivot;
    for(int level=0;branch.superview&&level<8;level++){
        UIView *parent=branch.superview;
        NSArray *siblings=parent.subviews;
        NSUInteger index=[siblings indexOfObjectIdenticalTo:branch];
        if(index!=NSNotFound&&index>0){
            for(NSInteger j=(NSInteger)index-1;j>=0;j--){
                UIView *candidate=siblings[j];
                if(candidate.hidden||candidate.alpha<.1||[candidate isKindOfClass:UIControl.class]||[candidate isKindOfClass:UIVisualEffectView.class])continue;
                CGRect frame=[candidate convertRect:candidate.bounds toView:pivot.window];
                CGRect hit=CGRectIntersection(frame,windowRect);
                if(!CGRectIsNull(hit)&&hit.size.width>=windowRect.size.width*.90&&hit.size.height>=windowRect.size.height*.82&&candidate.bounds.size.height>100)return candidate;
            }
        }
        branch=parent;
    }
    return nil;
}
static CGImageRef lemLensImage(UIView *source,CGRect rect,CGFloat scale) CF_RETURNS_RETAINED;
static CGImageRef lemLensImage(UIView *source,CGRect rect,CGFloat scale){
    if(!source||rect.size.width<10||rect.size.height<10)return NULL;
    size_t w=(size_t)MAX(12,MIN(220,ceil(rect.size.width*scale)));
    size_t h=(size_t)MAX(12,MIN(64,ceil(rect.size.height*scale)));
    size_t stride=w*4;
    CGColorSpaceRef cs=CGColorSpaceCreateDeviceRGB();
    CGContextRef input=CGBitmapContextCreate(NULL,w,h,8,stride,cs,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    CGContextRef output=CGBitmapContextCreate(NULL,w,h,8,stride,cs,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(cs);
    if(!input||!output){if(input)CGContextRelease(input);if(output)CGContextRelease(output);return NULL;}
    CGContextTranslateCTM(input,0,h);
    CGContextScaleCTM(input,w/rect.size.width,-(CGFloat)h/rect.size.height);
    CGContextTranslateCTM(input,-rect.origin.x,-rect.origin.y);
    [source.layer renderInContext:input];
    unsigned char *a=CGBitmapContextGetData(input),*b=CGBitmapContextGetData(output);
    int opaque=0;double minL=255,maxL=0;
    for(size_t y=0;y<h;y++)for(size_t x=0;x<w;x++){
        unsigned char *p=a+y*stride+x*4;
        if(p[3]>200){opaque++;double l=.2126*p[0]+.7152*p[1]+.0722*p[2];if(l<minL)minL=l;if(l>maxL)maxL=l;}
    }
    if(opaque<(int)(w*h*.82)||maxL-minL<12){CGContextRelease(input);CGContextRelease(output);return NULL;}
    // Capsule SDF: pull samples inward along the curved edge, with a small
    // wavelength-dependent offset. At 0.5x resolution this is cheap.
    float radius=(float)h*.5f, half=(float)w*.5f;
    for(size_t y=0;y<h;y++)for(size_t x=0;x<w;x++){
        float px=(float)x+.5f-half,py=(float)y+.5f-radius;
        float cx=fmaxf(-(half-radius),fminf(half-radius,px));
        float dx=px-cx,dy=py,d=hypotf(dx,dy),edge=radius-d;
        float u=fmaxf(0.f,fminf(1.f,1.f-edge/9.f));
        float displacement=5.7f*u*u;
        float nx=d>.01f?dx/d:0,ny=d>.01f?dy/d:0;
        unsigned char *q=b+y*stride+x*4;
        for(int c=0;c<3;c++){
            float shift=displacement+(1-c)*.38f*u;
            float sx=(float)x-nx*shift,sy=(float)y-ny*shift;
            int sum=0,weight=0;
            for(int yy=-1;yy<=1;yy++)for(int xx=-1;xx<=1;xx++){
                int ix=MAX(0,MIN((int)w-1,(int)lrintf(sx)+xx));
                int iy=MAX(0,MIN((int)h-1,(int)lrintf(sy)+yy));
                int k=xx==0&&yy==0?4:1;
                sum+=k*a[iy*stride+ix*4+c];weight+=k;
            }
            q[c]=(unsigned char)(sum/weight);
        }
        q[3]=255;
    }
    CGImageRef image=CGBitmapContextCreateImage(output);
    CGContextRelease(input);CGContextRelease(output);return image;
}
@interface LEMYunoGlassShell : UIView
@property(nonatomic,strong) CAGradientLayer *rim;
@property(nonatomic,strong) CAShapeLayer *rimMask;
@property(nonatomic,strong) CAGradientLayer *shine;
@property(nonatomic) CGFloat shapeRadius;
@property(nonatomic,weak) UIView *lensHost;
@property(nonatomic,strong) CALayer *lens;
@property(nonatomic,strong) CAShapeLayer *lensMask;
@property(nonatomic,strong) NSTimer *lensTimer;
@property(nonatomic) CFTimeInterval lensCooldown;
- (void)enableLensForHost:(UIView *)host;
@end
@implementation LEMYunoGlassShell
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])){
        self.userInteractionEnabled=NO;
        self.backgroundColor=UIColor.clearColor;
        self.rim=[CAGradientLayer layer];
        self.rim.startPoint=CGPointMake(.15,0);self.rim.endPoint=CGPointMake(.85,1);
        self.rim.colors=@[(id)[UIColor colorWithWhite:1 alpha:.30].CGColor,(id)[UIColor colorWithWhite:1 alpha:.035].CGColor,(id)[UIColor colorWithWhite:1 alpha:.18].CGColor];
        self.rim.locations=@[@0,@.48,@1];
        self.rimMask=[CAShapeLayer layer];self.rimMask.fillColor=nil;self.rimMask.strokeColor=UIColor.whiteColor.CGColor;self.rimMask.lineWidth=.5;
        self.rim.mask=self.rimMask;[self.layer addSublayer:self.rim];
        self.shine=[CAGradientLayer layer];self.shine.colors=@[(id)[UIColor colorWithWhite:1 alpha:.025].CGColor,(id)[UIColor colorWithWhite:1 alpha:0].CGColor,(id)[UIColor colorWithWhite:1 alpha:.015].CGColor];
        self.shine.locations=@[@0,@.5,@1];[self.layer insertSublayer:self.shine below:self.rim];
        self.layer.masksToBounds=YES;
        self.lens=[CALayer layer];self.lens.opacity=.68;self.lens.contentsGravity=kCAGravityResize;
        self.lensMask=[CAShapeLayer layer];self.lensMask.fillRule=kCAFillRuleEvenOdd;self.lensMask.fillColor=UIColor.blackColor.CGColor;
        self.lens.mask=self.lensMask;[self.layer insertSublayer:self.lens atIndex:0];
    }return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    [CATransaction begin];[CATransaction setDisableActions:YES];
    CGFloat rad=self.shapeRadius>0?MIN(self.shapeRadius,MIN(self.bounds.size.width,self.bounds.size.height)*.5):MIN(self.bounds.size.width,self.bounds.size.height)*.5;
    self.layer.cornerRadius=rad;self.layer.cornerCurve=kCACornerCurveContinuous;
    self.rim.frame=self.bounds;self.rimMask.frame=self.bounds;
    self.rimMask.path=[UIBezierPath bezierPathWithRoundedRect:CGRectInset(self.bounds,.8,.8) cornerRadius:rad-.8].CGPath;
    self.shine.frame=self.bounds;self.lens.frame=self.bounds;self.lensMask.frame=self.bounds;
    UIBezierPath *ring=[UIBezierPath bezierPathWithRoundedRect:self.bounds cornerRadius:rad];
    CGRect inner=CGRectInset(self.bounds,7,7);
    if(inner.size.width>0&&inner.size.height>0)[ring appendPath:[UIBezierPath bezierPathWithRoundedRect:inner cornerRadius:MAX(1,rad-7)]];
    self.lensMask.path=ring.CGPath;
    [CATransaction commit];
}
- (void)updateLens {
    if(!self.window||!self.lensHost||!enabled(Kglass)||UIAccessibilityIsReduceTransparencyEnabled()||NSProcessInfo.processInfo.lowPowerModeEnabled){
        self.lens.contents=nil;return;
    }
    if(CACurrentMediaTime()<self.lensCooldown)return;
    CGRect wrect=[self convertRect:self.bounds toView:self.window];
    UIView *src=lemBackdropSource(self.lensHost,wrect);
    if(!src){self.lens.contents=nil;return;}
    CFTimeInterval start=CACurrentMediaTime();
    @try{
        CGRect region=[src convertRect:wrect fromView:self.window];
        CGImageRef im=lemLensImage(src,region,.5);
        [CATransaction begin];[CATransaction setDisableActions:YES];
        self.lens.contents=im?(__bridge id)im:nil;[CATransaction commit];
        if(im)CGImageRelease(im);
    }@catch(NSException *e){self.lens.contents=nil;self.lensCooldown=CACurrentMediaTime()+3;}
    if(CACurrentMediaTime()-start>.022)self.lensCooldown=CACurrentMediaTime()+1.0;
}
- (void)enableLensForHost:(UIView *)host {
    self.lensHost=host;
    if(!self.window||self.lensTimer)return;
    __weak typeof(self) weakSelf=self;
    self.lensTimer=[NSTimer timerWithTimeInterval:.18 repeats:YES block:^(NSTimer *timer){
        LEMYunoGlassShell *strong=weakSelf;
        if(!strong||!strong.window||!strong.lensHost){[timer invalidate];return;}
        [strong updateLens];
    }];
    self.lensTimer.tolerance=.03;
    [[NSRunLoop mainRunLoop] addTimer:self.lensTimer forMode:NSRunLoopCommonModes];
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if(!self.window){[self.lensTimer invalidate];self.lensTimer=nil;self.lens.contents=nil;}
    else if(self.lensHost)[self enableLensForHost:self.lensHost];
}
- (void)dealloc {[self.lensTimer invalidate];}
@end
// Keep the app's native backdrop alive. Its rendered content is preferable
// to blurring a flat black/color background in a second UIKit effect.
static void restoreNativeMask(UIView *v){
    if(!v)return;id old=objc_getAssociatedObject(v,&oldMaskKey);
    if(old){v.layer.mask=old==NSNull.null?nil:old;objc_setAssociatedObject(v,&oldMaskKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
}
static void pivot(UIView *t,SEL s){
    ((void(*)(id,SEL))origPivot)(t,s);
    if(!t.window||t.bounds.size.width<120||t.bounds.size.height<30)return;
    lastPivotView=t;
    UIVisualEffectView *glass=objc_getAssociatedObject(t,&glassKey);
    LEMYunoGlassShell *shell=objc_getAssociatedObject(t,&shellKey);
    UIView *blur=getObj(t,@"blurView"),*separator=getObj(t,@"separatorView"),*content=getObj(t,@"contentView");
    if(![blur isKindOfClass:UIView.class]||blur==t)blur=nil;
    if(![separator isKindOfClass:UIView.class]||separator==t)separator=nil;
    if(![content isKindOfClass:UIView.class]||content==t)content=nil;
    BOOL independent=blur&&(!content||![content isDescendantOfView:blur])&&blur!=content;
    CGRect itemRect=CGRectNull,selectedRect=CGRectNull;
    id items=getObj(t,@"itemViews");
    if(![items isKindOfClass:NSArray.class]){
        NSMutableArray *list=[NSMutableArray array];
        for(int i=1;i<=6;i++){id v=getObj(t,[NSString stringWithFormat:@"itemView%d",i]);if(v)[list addObject:v];}
        items=list;
    }
    for(id item in items){
        if(![item isKindOfClass:UIView.class]||[item isHidden])continue;
        UIView *iv=item;
        if(blur&&[iv isDescendantOfView:blur])independent=NO;
        if(separator&&(iv==separator||[iv isDescendantOfView:separator]))separator=nil;
        CGRect f=[iv convertRect:iv.bounds toView:t];
        if(f.size.width<=0||f.size.height<=0)continue;
        itemRect=CGRectUnion(itemRect,f);
        SEL sel=NSSelectorFromString(@"selected");
        BOOL selected=(iv.accessibilityTraits&UIAccessibilityTraitSelected)!=0;
        Method m=class_getInstanceMethod([iv class],sel);char ret[8]={0};
        if(m&&method_getNumberOfArguments(m)==2){method_getReturnType(m,ret,sizeof ret);if(ret[0]=='B'||ret[0]=='c')selected=((BOOL(*)(id,SEL))objc_msgSend)(iv,sel);}
        if(selected)selectedRect=f;
    }
    UIView *previousNative=objc_getAssociatedObject(t,&nativeMaskOwnerKey);
    if(previousNative&&previousNative!=blur){restoreNativeMask(previousNative);objc_setAssociatedObject(t,&nativeMaskOwnerKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
    UIView *indicator=objc_getAssociatedObject(t,&indicatorKey);
    if(!enabled(Kglass)){
        [glass removeFromSuperview];[shell removeFromSuperview];[indicator removeFromSuperview];
        objc_setAssociatedObject(t,&glassKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);objc_setAssociatedObject(t,&shellKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);objc_setAssociatedObject(t,&indicatorKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        restoreNativeMask(blur);objc_setAssociatedObject(t,&nativeMaskOwnerKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        restoreBackground(t,&glassBgKey);restoreBackground(content,&oldContentColorKey);restoreHidden(separator);return;
    }
    CGRect bounds=t.bounds;
    CGFloat usable=MAX(32,bounds.size.height-t.safeAreaInsets.bottom);
    CGFloat h=MIN(58,usable);CGFloat y=bounds.origin.y+MAX(0,(usable-h)*.5);
    if(!CGRectIsNull(itemRect)&&itemRect.size.height>=24&&itemRect.size.height<=80){
        CGFloat start=MAX(bounds.origin.y,CGRectGetMinY(itemRect)-3);
        CGFloat finish=MIN(CGRectGetMaxY(bounds),CGRectGetMaxY(itemRect)+3);
        if(finish-start>=30){y=start;h=finish-start;}
    }
    CGRect f=CGRectMake(bounds.origin.x+7,y,bounds.size.width-14,h);
    clearBackground(t,&glassBgKey);
    if(content&&content!=blur)clearBackground(content,&oldContentColorKey);
    if(separator)hideDecor(separator);
    BOOL useNative=independent&&!blur.hidden&&blur.alpha>.05&&blur.superview&&blur.bounds.size.height>=30;
    if(useNative){
        // Clip only the noninteractive native backdrop; keep tab hierarchy intact.
        CGRect q=[t convertRect:f toView:blur];q=CGRectIntersection(q,blur.bounds);
        if(CGRectIsNull(q)||q.size.width<120||q.size.height<25)useNative=NO;
        else{
            if(!objc_getAssociatedObject(blur,&oldMaskKey))objc_setAssociatedObject(blur,&oldMaskKey,blur.layer.mask?:NSNull.null,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(t,&nativeMaskOwnerKey,blur,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            CAShapeLayer *mask=[CAShapeLayer layer];mask.frame=blur.bounds;
            CGRect local=q;local.origin.x-=blur.bounds.origin.x;local.origin.y-=blur.bounds.origin.y;
            mask.path=[UIBezierPath bezierPathWithRoundedRect:local cornerRadius:local.size.height*.5].CGPath;mask.fillColor=UIColor.blackColor.CGColor;
            [CATransaction begin];[CATransaction setDisableActions:YES];blur.layer.mask=mask;[CATransaction commit];
            [glass removeFromSuperview];objc_setAssociatedObject(t,&glassKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);glass=nil;
        }
    }
    if(!useNative){
        restoreNativeMask(blur);
        if(!glass){
            glass=[[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial]];
            glass.userInteractionEnabled=NO;glass.clipsToBounds=YES;glass.layer.cornerCurve=kCACornerCurveContinuous;
            glass.contentView.backgroundColor=UIColor.clearColor;
            objc_setAssociatedObject(t,&glassKey,glass,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if(glass.superview!=t)[t insertSubview:glass atIndex:0];else if(t.subviews.firstObject!=glass)[t sendSubviewToBack:glass];
        glass.layer.cornerRadius=h*.5;if(!CGRectEqualToRect(glass.frame,f))glass.frame=f;
    }
    UIView *holder=content?:t;
    if(!indicator){indicator=[UIView new];indicator.userInteractionEnabled=NO;indicator.alpha=0;indicator.layer.cornerCurve=kCACornerCurveContinuous;objc_setAssociatedObject(t,&indicatorKey,indicator,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
    if(indicator.superview!=holder){
        if(holder==t&&glass&&glass.superview==t)[t insertSubview:indicator aboveSubview:glass];
        else if(holder==t&&useNative&&blur.superview==t)[t insertSubview:indicator aboveSubview:blur];
        else [holder insertSubview:indicator atIndex:0];
    }
    if(!CGRectIsNull(selectedRect)){
        CGRect target=CGRectIntersection(CGRectInset(f,4,4),CGRectInset(selectedRect,3,0));
        if(!CGRectIsNull(target)&&target.size.width>12&&target.size.height>20){
            target=[t convertRect:target toView:holder];
            BOOL dark=t.traitCollection.userInterfaceStyle!=UIUserInterfaceStyleLight;
            indicator.backgroundColor=dark?[UIColor colorWithWhite:1 alpha:.12]:[UIColor colorWithWhite:1 alpha:.32];
            if(indicator.alpha==0||UIAccessibilityIsReduceMotionEnabled()){indicator.frame=target;indicator.alpha=1;indicator.layer.cornerRadius=target.size.height*.5;}
            else if(!CGRectEqualToRect(indicator.frame,target)){
                [UIView animateWithDuration:.38 delay:0 usingSpringWithDamping:.72 initialSpringVelocity:.1 options:UIViewAnimationOptionBeginFromCurrentState|UIViewAnimationOptionAllowUserInteraction animations:^{indicator.frame=target;indicator.layer.cornerRadius=target.size.height*.5;} completion:nil];
            }
        }else indicator.alpha=0;
    }else indicator.alpha=0;
    if(!shell){shell=[[LEMYunoGlassShell alloc] initWithFrame:f];objc_setAssociatedObject(t,&shellKey,shell,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
    shell.shapeRadius=h*.5;
    if(shell.superview!=t)[t addSubview:shell];else if(t.subviews.lastObject!=shell)[t bringSubviewToFront:shell];
    if(!CGRectEqualToRect(shell.frame,f))shell.frame=f;
    [shell enableLensForHost:t];
}
// v1.0 — Yuno 1.1.1 inspired glass surfaces + separately guarded ad filters.
// Native iOS controls remain in place; only decorative views are added.
static char surfaceKey,surfaceRimKey,surfaceBackgroundKey;
static NSHashTable<UIView *> *glassSurfaces;
static NSUInteger glassHookCount,adHookCount;
static BOOL directMethod(Class c,SEL sel){
    if(!c)return NO;unsigned int count=0;
    Method *list=class_copyMethodList(c,&count);
    BOOL found=NO;for(unsigned int i=0;i<count;i++){if(method_getName(list[i])==sel){found=YES;break;}}
    free(list);return found;
}
static void decorateSurface(UIView *v,CGFloat radius,BOOL rimOnly){
    if(!v||[v isKindOfClass:UIVisualEffectView.class])return;
    UIVisualEffectView *blur=objc_getAssociatedObject(v,&surfaceKey);
    LEMYunoGlassShell *rim=objc_getAssociatedObject(v,&surfaceRimKey);
    if(!enabled(Kglass)){
        [blur removeFromSuperview];[rim removeFromSuperview];
        objc_setAssociatedObject(v,&surfaceKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(v,&surfaceRimKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        restoreBackground(v,&surfaceBackgroundKey);return;
    }
    CGRect f=v.bounds;
    if(!v.window||f.size.width<24||f.size.height<22||f.size.height>210)return;
    [glassSurfaces addObject:v];
    CGFloat rad=MIN(radius,MIN(f.size.width,f.size.height)*.5);
    if(!rimOnly){
        clearBackground(v,&surfaceBackgroundKey);
        if(!blur){
            blur=[[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial]];
            blur.userInteractionEnabled=NO;blur.clipsToBounds=YES;blur.layer.cornerCurve=kCACornerCurveContinuous;
            blur.contentView.backgroundColor=[UIColor colorWithWhite:1 alpha:.035];
            objc_setAssociatedObject(v,&surfaceKey,blur,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if(blur.superview!=v)[v insertSubview:blur atIndex:0];else if(v.subviews.firstObject!=blur)[v sendSubviewToBack:blur];
        if(!CGRectEqualToRect(blur.frame,f))blur.frame=f;
        blur.layer.cornerRadius=rad;
    }
    if(!rim){rim=[[LEMYunoGlassShell alloc] initWithFrame:f];rim.alpha=rimOnly?.38:.52;objc_setAssociatedObject(v,&surfaceRimKey,rim,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
    if(rim.superview!=v)[v addSubview:rim];else if(v.subviews.lastObject!=rim)[v bringSubviewToFront:rim];
    if(!CGRectEqualToRect(rim.frame,f))rim.frame=f;
    rim.shapeRadius=rad;rim.layer.cornerRadius=rad;rim.layer.cornerCurve=kCACornerCurveContinuous;
    rim.rimMask.path=[UIBezierPath bezierPathWithRoundedRect:CGRectInset(rim.bounds,.8,.8) cornerRadius:MAX(1,rad-.8)].CGPath;
}
static void decorateGetter(UIView *parent,NSString *name,CGFloat rad,BOOL rimOnly){
    id v=getObj(parent,name);
    if([v isKindOfClass:UIView.class]&&v!=parent&&[v isDescendantOfView:parent])decorateSurface(v,rad,rimOnly);
}
static void installSurface(NSString *name,CGFloat radius,BOOL rimOnly,NSArray<NSString *> *children){
    Class c=NSClassFromString(name);SEL sel=@selector(layoutSubviews);
    if(!c||![c isSubclassOfClass:UIView.class]||!directMethod(c,sel))return;
    Method m=class_getInstanceMethod(c,sel);
    if(!m||method_getNumberOfArguments(m)!=2)return;
    char ret[16]={0};method_getReturnType(m,ret,sizeof ret);if(ret[0]!='v')return;
    IMP old=method_getImplementation(m);
    IMP impl=imp_implementationWithBlock(^(UIView *v){
        ((void(*)(id,SEL))old)(v,sel);
        @try{
            if(radius>0)decorateSurface(v,radius,rimOnly);
            for(NSString *g in children)decorateGetter(v,g,19,NO);
        }@catch(NSException *e){NSLog(@"[LEMYuno] surface %@: %@",name,e.reason);}
    });
    class_replaceMethod(c,sel,impl,method_getTypeEncoding(m));glassHookCount++;
}
static void nativeFrostFlag(NSString *name){
    Class c=NSClassFromString(@"YTColdConfig");
    SEL sel=NSSelectorFromString(name);
    Method m=c?class_getInstanceMethod(c,sel):NULL;
    if(!m||method_getNumberOfArguments(m)!=2)return;
    char ret[8]={0};method_getReturnType(m,ret,sizeof ret);if(ret[0]!='B'&&ret[0]!='c')return;
    IMP old=method_getImplementation(m);
    IMP impl=imp_implementationWithBlock(^BOOL(id t){return enabled(Kglass)?YES:((BOOL(*)(id,SEL))old)(t,sel);});
    class_replaceMethod(c,sel,impl,method_getTypeEncoding(m));glassHookCount++;
}
static void frostFloat(NSString *name,float value){
    Class c=NSClassFromString(@"YTColdConfig");SEL sel=NSSelectorFromString(name);
    Method m=c?class_getInstanceMethod(c,sel):NULL;char rt[8]={0};
    if(!m||method_getNumberOfArguments(m)!=2)return;method_getReturnType(m,rt,sizeof rt);if(rt[0]!='f')return;
    IMP old=method_getImplementation(m);
    IMP impl=imp_implementationWithBlock(^float(id obj){return enabled(Kglass)?value:((float(*)(id,SEL))old)(obj,sel);});
    class_replaceMethod(c,sel,impl,method_getTypeEncoding(m));glassHookCount++;
}
static void installGlassSurfaces(void){
    glassSurfaces=[NSHashTable weakObjectsHashTable];
    // Native iOS 16-compatible frosted chrome. Do not enable iOS 26/27-only APIs.
    for(NSString *flag in @[@"mainAppCoreClientEnableModernIaFrostedBottomBar",@"mainAppCoreClientEnableModernIaFrostedPivotBar",@"mainAppCoreClientEnableModernIaFrostedPivotBarUpdatedBackdrop",@"mainAppCoreClientEnableHomeFrostedTopBar",@"mainAppCoreClientEnableSearchFrostedTopBar",@"enableFrostedGlassForImpPlayerControls",@"enableFrostedGlassMiniplayerControls"])nativeFrostFlag(flag);
    frostFloat(@"mainAppCoreClientFrostedPivotBarBlurRadius",5.5f);
    frostFloat(@"mainAppCoreClientFrostedPivotBarPaintOpacity",.12f);
    installSurface(@"YTRightNavigationButtons",24,NO,@[]);
    installSurface(@"YTSearchBoxView",20,NO,@[]);
    installSurface(@"YTWatchFloatingMiniplayerWithPersistentControlsView",20,YES,@[]);
    installSurface(@"YTReelBottomActionBarView",24,NO,@[]);
    // Plain native filter labels: no artificial rounded double borders.
    Class p=NSClassFromString(@"YTPivotBarView");SEL change=NSSelectorFromString(@"selectItemWithPivotIdentifier:");
    Method pm=p?class_getInstanceMethod(p,change):NULL;
    if(pm&&method_getNumberOfArguments(pm)==3){
        char ret[8]={0},arg[8]={0};method_getReturnType(pm,ret,sizeof ret);method_getArgumentType(pm,2,arg,sizeof arg);
        if(ret[0]=='v'&&arg[0]=='@'){
            IMP old=method_getImplementation(pm);
            IMP impl=imp_implementationWithBlock(^(UIView *v,id ident){((void(*)(id,SEL,id))old)(v,change,ident);[v setNeedsLayout];});
            class_replaceMethod(p,change,impl,method_getTypeEncoding(pm));
        }
    }
}
static void refreshGlass(void){
    [lastPivotView setNeedsLayout];
    for(UIView *v in glassSurfaces.allObjects){
        if(!enabled(Kglass))decorateSurface(v,20,YES);
        [v setNeedsLayout];
    }
}
static BOOL exactBool(id obj,NSString *name){
    SEL sel=NSSelectorFromString(name);
    if(!available(obj,sel,2))return NO;
    Method m=class_getInstanceMethod([obj class],sel);
    char rt[8]={0};method_getReturnType(m,rt,sizeof rt);
    if(rt[0]!='B'&&rt[0]!='c')return NO;
    return ((BOOL(*)(id,SEL))objc_msgSend)(obj,sel);
}
static BOOL isAdElement(id e){
    if(!e)return NO;
    if(exactBool(e,@"hasShoppingCompanionAdRenderer")||exactBool(e,@"hasCompanionAdRenderer"))return YES;
    id compat=getObj(e,@"compatibilityOptions");
    // Ad-layout metadata is more specific than generic logging. Never erase elementData.
    if(exactBool(compat,@"hasAdLayoutLoggingData"))return YES;
    return NO;
}
static BOOL isAdRenderer(id row){
    if(!row)return NO;
    static NSArray *keys;static dispatch_once_t once;
    dispatch_once(&once,^{keys=@[
      @"hasAdSlotRenderer",@"hasPromotedVideoRenderer",@"hasCompactPromotedVideoRenderer",
      @"hasPromotedVideoInlineMutedRenderer",@"hasPromotedSparklesTextHomeRenderer",
      @"hasPromotedSparklesTextSearchRenderer",@"hasPromotedSparklesTextCtdHomeRenderer",
      @"hasPromotedSparklesTextCtdHomeCompactFormRenderer",@"hasPromotedAppInstallRenderer",
      @"hasPromotedDiscoveryAppPromoCompactFormRenderer",@"hasPromotedTextBannerRenderer",
      @"hasPromotedSparklesTextCtdWatchWideFormRenderer",@"hasPromotedSparklesTextCtdWatchGridFormRenderer",
      @"hasPromotedSparklesTextProductHomeRenderer",@"hasPromotedSparklesTextProductWatchRenderer",
      @"hasPromotedSparklesTextWatchWideFormRenderer",@"hasPromotedSparklesTextWatchGridFormRenderer",
      @"hasSearchPyvRenderer",@"hasVideoMastheadAdRenderer",@"hasDisplayAdViewModel",
      @"hasCompanionAdRenderer",@"hasShoppingCompanionAdRenderer"
    ];});
    for(NSString *k in keys)if(exactBool(row,k))return YES;
    Class ec=NSClassFromString(@"YTIElementRenderer");
    if(ec&&[row isKindOfClass:ec])return isAdElement(row);
    id e=getObj(row,@"elementRenderer");return e&&isAdElement(e);
}
static NSUInteger removedAds;
static NSArray *prunedArray(id arr,NSUInteger depth);
static BOOL pruneRow(id row,NSUInteger depth){
    if(!row||depth>5)return NO;
    if(isAdRenderer(row))return YES;
    // Renderer wrappers vary by feed. Filter only explicit content arrays, not arbitrary fields.
    id container=getObj(row,@"itemSectionRenderer");
    if(!container)container=row;
    for(NSString *key in @[@"contentsArray",@"itemsArray"]){
        id arr=getObj(container,key);
        if(![arr isKindOfClass:NSArray.class]||![arr count]||[arr count]>1000)continue;
        NSArray *clean=prunedArray(arr,depth+1);
        if(clean==arr)continue;
        if(clean.count==0)return YES;
        if([arr isKindOfClass:NSMutableArray.class])[(NSMutableArray *)arr setArray:clean];
    }
    return NO;
}
static NSArray *prunedArray(id arr,NSUInteger depth){
    if(!enabled(Kad)||![arr isKindOfClass:NSArray.class]||depth>5||[arr count]>1000)return arr;
    NSMutableArray *clean=nil;
    NSUInteger ix=0;
    for(id row in arr){
        if(pruneRow(row,depth)){
            if(!clean)clean=[NSMutableArray arrayWithArray:[arr subarrayWithRange:NSMakeRange(0,ix)]];
            removedAds++;
        }else if(clean)[clean addObject:row];
        ix++;
    }
    return clean?:arr;
}
static NSArray *safePrune(id array){
    @try{return prunedArray(array,0);}@catch(NSException *e){NSLog(@"[LEMYuno] filter: %@",e.reason);return array;}
}
static void filterSectionModel(id model){
    if(!enabled(Kad)||!model)return;
    @try{
        id arr=getObj(model,@"contentsArray");
        if([arr isKindOfClass:NSMutableArray.class]){
            NSArray *clean=safePrune(arr);if(clean!=arr)[arr setArray:clean];
        }
    }@catch(NSException *e){NSLog(@"[LEMYuno] model: %@",e.reason);}
}
static IMP origFeedLoad,origFeedSetup,origCue,origSectionBuild;
static void feedLoad(id t,SEL s,id model){filterSectionModel(model);((void(*)(id,SEL,id))origFeedLoad)(t,s,model);}
static void feedSetup(id t,SEL s,id model,BOOL more,BOOL refreshing,BOOL preserve){filterSectionModel(model);((void(*)(id,SEL,id,BOOL,BOOL,BOOL))origFeedSetup)(t,s,model,more,refreshing,preserve);}
static id sectionBuild(id t,SEL s,id rows,id reloading){return ((id(*)(id,SEL,id,id))origSectionBuild)(t,s,safePrune(rows),reloading);}
static BOOL cueAds(id t,SEL s){return enabled(Kad)?NO:((BOOL(*)(id,SEL))origCue)(t,s);}
static IMP installTyped(Class c,NSString *name,IMP replacement,const char *types,unsigned int n){
    if(!c)return NULL;SEL sel=NSSelectorFromString(name);
    Method m=class_getInstanceMethod(c,sel);
    if(!m||method_getNumberOfArguments(m)!=n)return NULL;
    char b[16]={0};method_getReturnType(m,b,sizeof b);
    if(b[0]!=types[0])return NULL;
    for(unsigned int i=2;i<n;i++){method_getArgumentType(m,i,b,sizeof b);if(b[0]!=types[i-1])return NULL;}
    IMP old=method_getImplementation(m);if(!old)return NULL;
    class_replaceMethod(c,sel,replacement,method_getTypeEncoding(m));adHookCount++;return old;
}
static void installRowPath(Class c,NSString *name){
    SEL sel=NSSelectorFromString(name);
    Method m=c?class_getInstanceMethod(c,sel):NULL;
    if(!m||!directMethod(c,sel)||method_getNumberOfArguments(m)!=3)return;
    char rt[8]={0},arg[8]={0};method_getReturnType(m,rt,sizeof rt);method_getArgumentType(m,2,arg,sizeof arg);
    if(rt[0]!='v'||arg[0]!='@')return;
    IMP old=method_getImplementation(m);
    IMP impl=imp_implementationWithBlock(^(id t,id rows){((void(*)(id,SEL,id))old)(t,sel,safePrune(rows));});
    class_replaceMethod(c,sel,impl,method_getTypeEncoding(m));adHookCount++;
}
static void installAdFilters(void){
    Class feed=NSClassFromString(@"YTSectionListViewController");
    origFeedLoad=installTyped(feed,@"loadWithModel:",(IMP)feedLoad,"v@",3);
    origFeedSetup=installTyped(feed,@"setupSectionListWithModel:isLoadingMore:isRefreshingFromContinuation:shouldPreserveHeaderOnRefresh:",(IMP)feedSetup,"v@BBB",6);
    Class base=NSClassFromString(@"YTInnerTubeCollectionViewController");
    origSectionBuild=installTyped(base,@"sectionControllersForSectionRenderers:reloadingSectionControllerByRenderer:",(IMP)sectionBuild,"@@@",4);
    installRowPath(base,@"addSectionsFromArray:");
    Class watch=NSClassFromString(@"YTWatchNextResultsViewController");
    installRowPath(watch,@"addSectionsFromArray:");
    // Companion advertisements are separate from ordinary watch-next recommendations.
    SEL c1=NSSelectorFromString(@"setCompanionAd:");
    Method cm=watch?class_getInstanceMethod(watch,c1):NULL;
    if(cm&&method_getNumberOfArguments(cm)==3){char rt[8]={0},arg[8]={0};method_getReturnType(cm,rt,sizeof rt);method_getArgumentType(cm,2,arg,sizeof arg);
       if(rt[0]=='v'&&arg[0]=='@'){IMP old=method_getImplementation(cm);IMP impl=imp_implementationWithBlock(^(id t,id ad){if(!enabled(Kad)||!ad)((void(*)(id,SEL,id))old)(t,c1,ad);});class_replaceMethod(watch,c1,impl,method_getTypeEncoding(cm));adHookCount++;}
    }
    SEL c3=NSSelectorFromString(@"setCompanionAd:layoutID:interactionLoggingAdsClientData:");
    Method cm3=watch?class_getInstanceMethod(watch,c3):NULL;
    if(cm3&&method_getNumberOfArguments(cm3)==5){char rt[8]={0},x[8]={0},y[8]={0},z[8]={0};method_getReturnType(cm3,rt,sizeof rt);method_getArgumentType(cm3,2,x,sizeof x);method_getArgumentType(cm3,3,y,sizeof y);method_getArgumentType(cm3,4,z,sizeof z);
       if(rt[0]=='v'&&x[0]=='@'&&y[0]=='@'&&z[0]=='@'){IMP old=method_getImplementation(cm3);IMP impl=imp_implementationWithBlock(^(id t,id ad,id layout,id logging){if(!enabled(Kad)||!ad)((void(*)(id,SEL,id,id,id))old)(t,c3,ad,layout,logging);});class_replaceMethod(watch,c3,impl,method_getTypeEncoding(cm3));adHookCount++;}
    }
    Class response=NSClassFromString(@"YTIPlayerResponse");
    origCue=hook(response,NSSelectorFromString(@"isCuepointAdsEnabled"),(IMP)cueAds,YES);
    // Retain existing ad-only playback hooks, but never modify content renderer bytes.
    for(NSString *name in @[@"adPlacementsArray",@"adSlotsArray",@"playerAdsArray"]){
        SEL sel=NSSelectorFromString(name);
        if(![response instancesRespondToSelector:sel])continue;
        Method m=class_getInstanceMethod(response,sel);char t[8]={0};
        if(!m||method_getNumberOfArguments(m)!=2)continue;
        method_getReturnType(m,t,sizeof t);if(t[0]!='@')continue;
        IMP old=method_getImplementation(m);
        IMP impl=imp_implementationWithBlock(^id(id obj){id original=((id(*)(id,SEL))old)(obj,sel);if(enabled(Kad)&&[original isKindOfClass:NSArray.class])return [NSMutableArray array];return original;});
        class_replaceMethod(response,sel,impl,method_getTypeEncoding(m));adHookCount++;
    }
    NSLog(@"[LEMYuno] ad filters %lu",(unsigned long)adHookCount);
}
static void installExtra(void){
    Class pc=NSClassFromString(@"YTPlayerViewController");
    SEL ts=NSSelectorFromString(@"potentiallyMutatedSingleVideo:currentVideoTimeDidChange:");
    if(!class_getInstanceMethod(pc,ts))ts=NSSelectorFromString(@"singleVideo:currentVideoTimeDidChange:");
    Method tm=class_getInstanceMethod(pc,ts);
    if(tm&&method_getNumberOfArguments(tm)==4){
        char ret[16]={0},a[16]={0},b[16]={0};method_getReturnType(tm,ret,sizeof ret);method_getArgumentType(tm,2,a,sizeof a);method_getArgumentType(tm,3,b,sizeof b);
        if(ret[0]=='v'&&a[0]=='@'&&b[0]=='@'){origTick=method_getImplementation(tm);class_replaceMethod(pc,ts,(IMP)tick,method_getTypeEncoding(tm));}
    }
    Class p=NSClassFromString(@"YTPivotBarView");
    if(p&&[p isSubclassOfClass:UIView.class])origPivot=hook(p,@selector(layoutSubviews),(IMP)pivot,NO);
    origMini=hook(NSClassFromString(@"YTWatchFloatingMiniplayerViewController"),NSSelectorFromString(@"isMiniplayerRendererPlaybackModePauseOnly"),(IMP)mini,YES);
}
static id switches(NSString *title,NSString *description,NSString *key){
    Class c=NSClassFromString(@"YTSettingsSectionItem");
    SEL s=NSSelectorFromString(@"switchItemWithTitle:titleDescription:accessibilityIdentifier:switchOn:switchBlock:settingItemId:");
    if(!available(c,s,8))return nil;
    BOOL (^block)(id,BOOL)=^BOOL(id cell,BOOL on){
        [NSUserDefaults.standardUserDefaults setBool:on forKey:key];if([key isEqual:Ksb]&&!on)resetSponsor();if([key isEqual:Khd])qualityID=nil;if([key isEqual:Kglass])refreshGlass();return YES;
    };
    return ((id(*)(id,SEL,id,id,id,BOOL,id,NSInteger))objc_msgSend)(c,s,title,description,key,enabled(key),block,0);
}
static id order(id t,SEL s){
    id result=((id(*)(id,SEL))origOrder)(t,s);
    if(![result isKindOfClass:NSArray.class]||[result containsObject:@(LemCategory)])return result;
    NSMutableArray *arr=[result mutableCopy];
    NSUInteger i=[arr indexOfObject:@1];
    [arr insertObject:@(LemCategory) atIndex:i==NSNotFound?0:i+1];
    return arr;
}
static void category(id t,SEL s,NSUInteger n,id entry){
    if(n!=LemCategory){((void(*)(id,SEL,NSUInteger,id))origCategory)(t,s,n,entry);return;}
    @try {
        id vc=[t valueForKey:@"_settingsViewControllerDelegate"];
        if(!vc)return;
        NSMutableArray *rows=[NSMutableArray array];
        id bg=switches(@"Phát nền",@"Tiếp tục phát khi rời YouTube",Kbg);
        id ad=switches(@"Chặn quảng cáo",@"Bật khi mở ứng dụng; có thể tắt tại đây",Kad);
        if(bg&&(origBG||origML))[rows addObject:bg];
        if(ad&&origAd)[rows addObject:ad];
        id sb=switches(@"SponsorBlock",@"Tự bỏ qua đoạn tài trợ; gửi ID video tới sponsor.ajay.app",Ksb);
        id hd=switches(@"Ưu tiên 1080p",@"Chọn chất lượng tốt nhất không quá 1080p khi có",Khd);
        id gl=switches(@"Liquid Glass",@"Hiệu ứng kính trên thanh điều hướng (thử nghiệm)",Kglass);
        id mi=switches(@"Mini Player tăng cường",@"Thử nghiệm; tắt nếu xung đột với YouMod",Kmini);
        if(origTick&&sb)[rows addObject:sb];
        if(origTick&&hd)[rows addObject:hd];
        if(origPivot&&gl)[rows addObject:gl];
        if(origMini&&mi)[rows addObject:mi];
        Class c=NSClassFromString(@"YTSettingsSectionItem");
        SEL item=NSSelectorFromString(@"itemWithTitle:accessibilityIdentifier:detailTextBlock:selectBlock:");
        if(available(c,item,6)){
            __weak id weakVC=vc;
            NSString *(^detail)(void)=^NSString *{return [NSString stringWithFormat:@"%gx",savedRate()];};
            BOOL (^select)(id,NSUInteger)=^BOOL(id cell,NSUInteger index){
                UIViewController *p=weakVC;
                chooseRate(p);
                return YES;
            };
            id rate=((id(*)(id,SEL,id,id,id,id))objc_msgSend)(c,item,@"Tốc độ mặc định",@"LEMYuno.speed",detail,select);
            if(rate)[rows addObject:rate];
        }
        SEL modern=NSSelectorFromString(@"setSectionItems:forCategory:title:icon:titleDescription:headerHidden:");
        SEL legacy=NSSelectorFromString(@"setSectionItems:forCategory:title:titleDescription:headerHidden:");
        if(available(vc,modern,8))((void(*)(id,SEL,id,NSUInteger,id,id,id,BOOL))objc_msgSend)(vc,modern,rows,LemCategory,@"LEM Yuno",nil,@"v1.0",NO);
        else if(available(vc,legacy,7))((void(*)(id,SEL,id,NSUInteger,id,id,BOOL))objc_msgSend)(vc,legacy,rows,LemCategory,@"LEM Yuno",@"v1.0",NO);
    }@catch(NSException *e){NSLog(@"[LEMYuno] Settings: %@",e.reason);}
}
static void installSettings(void){
    Class orderClass=NSClassFromString(@"YTAppSettingsPresentationData");
    Class manager=NSClassFromString(@"YTSettingsSectionItemManager");
    Class vc=NSClassFromString(@"YTSettingsViewController");
    Class item=NSClassFromString(@"YTSettingsSectionItem");
    SEL os=NSSelectorFromString(@"settingsCategoryOrder");
    SEL cs=NSSelectorFromString(@"updateSectionForCategory:withEntry:");
    Method om=class_getClassMethod(orderClass,os);
    Method cm=class_getInstanceMethod(manager,cs);
    if(!om||!cm||!vc||!item||method_getNumberOfArguments(om)!=2||method_getNumberOfArguments(cm)!=4)return;
    if(!class_getClassMethod(item,NSSelectorFromString(@"switchItemWithTitle:titleDescription:accessibilityIdentifier:switchOn:switchBlock:settingItemId:")))return;
    if(!class_getInstanceMethod(vc,NSSelectorFromString(@"setSectionItems:forCategory:title:icon:titleDescription:headerHidden:"))&&!class_getInstanceMethod(vc,NSSelectorFromString(@"setSectionItems:forCategory:title:titleDescription:headerHidden:")))return;
    char ret[16]={0},arg[16]={0};
    method_getReturnType(om,ret,sizeof ret);if(ret[0]!='@')return;
    method_getReturnType(cm,ret,sizeof ret);method_getArgumentType(cm,2,arg,sizeof arg);if(ret[0]!='v'||(arg[0]!='Q'&&arg[0]!='q'))return;
    origCategory=method_getImplementation(cm);
    class_replaceMethod(manager,cs,(IMP)category,method_getTypeEncoding(cm));
    origOrder=method_getImplementation(om);
    class_replaceMethod(object_getClass(orderClass),os,(IMP)order,method_getTypeEncoding(om));
}

// v1.0: settings entry independent of YouTube's changing category model.
@interface LEMYunoPreferencesController : UITableViewController
@property(nonatomic,strong) NSArray<NSDictionary *> *options;
@end
@implementation LEMYunoPreferencesController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=@"LEM Yuno";
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(lemClose)];
    self.options=@[
      @{@"key":Kad,@"title":@"Chặn quảng cáo",@"note":@"Lọc thẻ trước layout; không xóa dữ liệu video"},
      @{@"key":Kbg,@"title":@"Phát nền",@"note":@"Nghe khi tắt màn hình"},
      @{@"key":Ksb,@"title":@"SponsorBlock",@"note":@"Tra cứu ID video trên SponsorBlock"},
      @{@"key":Khd,@"title":@"Ưu tiên 1080p",@"note":@"Khi chất lượng video có sẵn"},
      @{@"key":Kglass,@"title":@"Liquid Glass",@"note":@"Kính trong, mô phỏng khúc xạ mép (thử nghiệm)"},
      @{@"key":Kmini,@"title":@"Mini Player tăng cường",@"note":@"Cho phép phát trong mini player khi chế độ chỉ tạm dừng được yêu cầu"}
    ];
    self.tableView.rowHeight=66;
}
- (void)lemClose {[self dismissViewControllerAnimated:YES completion:nil];}
- (void)viewWillAppear:(BOOL)animated {[super viewWillAppear:animated];[self.tableView reloadData];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{return 2;}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)section{return section==0?self.options.count:1;}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)section{return section==0?@"Tính năng":@"Trình phát";}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)section{return section==0?@"Các lựa chọn được lưu tự động. PiP, Shorts và Google giữ nguyên từ ứng dụng YouTube.":@"LEM Yuno v1.0 • YouTube 21.33.6";}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip{
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    if(ip.section==0){
        NSDictionary *row=self.options[ip.row]; NSString *key=row[@"key"];
        cell.textLabel.text=row[@"title"];cell.detailTextLabel.text=row[@"note"];cell.detailTextLabel.numberOfLines=2;
        UISwitch *sw=[UISwitch new];sw.on=enabled(key);sw.tag=ip.row;
        BOOL supported=([key isEqual:Kad]?(origAd!=NULL||adHookCount>0):[key isEqual:Kbg]?(origBG||origML)!=0:([key isEqual:Ksb]||[key isEqual:Khd])?origTick!=NULL:[key isEqual:Kglass]?(origPivot!=NULL||glassHookCount>0):origMini!=NULL);
        sw.enabled=supported; if(!supported){sw.on=NO;cell.detailTextLabel.text=@"Không tìm thấy hook trên bản này";}
        [sw addTarget:self action:@selector(lemToggle:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView=sw;cell.selectionStyle=UITableViewCellSelectionStyleNone;
    }else{
        cell.textLabel.text=@"Tốc độ mặc định";cell.detailTextLabel.text=[NSString stringWithFormat:@"%gx",savedRate()];cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}
- (void)lemToggle:(UISwitch *)sw{
    if(sw.tag<0||sw.tag>=self.options.count)return;
    NSString *key=self.options[sw.tag][@"key"];
    [NSUserDefaults.standardUserDefaults setBool:sw.on forKey:key];
    if([key isEqual:Ksb]&&!sw.on)resetSponsor();if([key isEqual:Khd])qualityID=nil;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip{
    [t deselectRowAtIndexPath:ip animated:YES];if(ip.section!=1)return;
    UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Tốc độ mặc định" message:nil preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf=self;
    for(NSNumber *n in rates()){
        double v=n.doubleValue;
        [a addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%gx%@",v,fabs(savedRate()-v)<.001?@" ✓":@""] style:UIAlertActionStyleDefault handler:^(UIAlertAction *x){
            [NSUserDefaults.standardUserDefaults setDouble:v forKey:Krate];
            UIViewController *p=activeOverlay;if(!applyRate(p,v))applyRate(p.parentViewController,v);
            [weakSelf.tableView reloadData];
        }]];
    }
    [a addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];[self presentViewController:a animated:YES completion:nil];
}
@end
static char lemEntryKey;
static IMP origSettingsLayout,origSearchSettingsLayout;
static void openLem(UIViewController *t,SEL s,id sender){
    (void)s;(void)sender;
    if(t.presentedViewController)return;
    LEMYunoPreferencesController *p=[[LEMYunoPreferencesController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:p];
    nav.modalPresentationStyle=UIModalPresentationPageSheet;
    [t presentViewController:nav animated:YES completion:nil];
}
static void entry(UIViewController *t){
    UIView *v=t.viewIfLoaded;
    if(!v.window||v.bounds.size.width<200||v.bounds.size.height<150)return;
    // Prefer the outer settings controller when the searchable view is a child.
    UIViewController *parent=t.parentViewController;
    Class top=NSClassFromString(@"YTSettingsViewController");
    Class search=NSClassFromString(@"YTSearchableSettingsViewController");
    if(parent&&((top&&[parent isKindOfClass:top])||(search&&[parent isKindOfClass:search])))return;
    UIButton *b=objc_getAssociatedObject(t,&lemEntryKey);
    if(!b){
      b=[UIButton buttonWithType:UIButtonTypeSystem];
      [b setTitle:@"LEM Yuno" forState:UIControlStateNormal];
      b.titleLabel.font=[UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
      b.accessibilityIdentifier=@"LEM.Yuno.Settings.Entry";
      b.backgroundColor=UIColor.secondarySystemBackgroundColor;b.layer.cornerRadius=14;
      b.layer.borderWidth=.5;b.layer.borderColor=UIColor.separatorColor.CGColor;
      [b addTarget:t action:NSSelectorFromString(@"lemYunoOpenPreferences:") forControlEvents:UIControlEventTouchUpInside];
      [v addSubview:b];objc_setAssociatedObject(t,&lemEntryKey,b,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    b.frame=CGRectMake(v.bounds.size.width-v.safeAreaInsets.right-106,v.safeAreaInsets.top+7,94,32);
    [v bringSubviewToFront:b];
}
static void settingsLayout(UIViewController *t,SEL s){((void(*)(id,SEL))origSettingsLayout)(t,s);entry(t);}
static void searchSettingsLayout(UIViewController *t,SEL s){((void(*)(id,SEL))origSearchSettingsLayout)(t,s);entry(t);}
static void installSettingsEntry(void){
    Class a=NSClassFromString(@"YTSettingsViewController"),b=NSClassFromString(@"YTSearchableSettingsViewController");
    SEL action=NSSelectorFromString(@"lemYunoOpenPreferences:");
    if(a&&[a isSubclassOfClass:UIViewController.class]){
        class_addMethod(a,action,(IMP)openLem,"v@:@");origSettingsLayout=hook(a,@selector(viewDidLayoutSubviews),(IMP)settingsLayout,NO);
    }
    if(b&&b!=a&&[b isSubclassOfClass:UIViewController.class]){
        if(!class_getInstanceMethod(b,action))class_addMethod(b,action,(IMP)openLem,"v@:@");
        origSearchSettingsLayout=hook(b,@selector(viewDidLayoutSubviews),(IMP)searchSettingsLayout,NO);
    }
}
__attribute__((constructor)) static void initialize(void){
 @autoreleasepool {
  NSBundle *bundle=NSBundle.mainBundle;
  if(![bundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"])return;
  if(![[bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] isEqualToString:@"21.33.6"])return;
  [NSUserDefaults.standardUserDefaults registerDefaults:@{Kbg:@YES,Kad:@YES,Ksb:@YES,Khd:@YES,Kglass:@YES,Kmini:@NO}];
  dispatch_async(dispatch_get_main_queue(), ^{
    Class c=NSClassFromString(@"YTMainAppVideoPlayerOverlayViewController");
    SEL s=@selector(viewDidLayoutSubviews);
    if(c)origLayout=hook(c,s,(IMP)layout,NO);
    origBG=hook(NSClassFromString(@"YTIPlayabilityStatus"),NSSelectorFromString(@"isPlayableInBackground"),(IMP)yesBG,YES);
    origML=hook(NSClassFromString(@"MLVideo"),NSSelectorFromString(@"playableInBackground"),(IMP)yesML,YES);
    origAd=hook(NSClassFromString(@"YTIPlayerResponse"),NSSelectorFromString(@"isMonetized"),(IMP)noAd,YES);
    installExtra();
    installGlassSurfaces();
    installAdFilters();
    installSettingsEntry();
    NSLog(@"[LEMYuno] Loaded settings=%d background=%d ad=%d",(origSettingsLayout||origSearchSettingsLayout)!=0,(origBG||origML)!=0,origAd!=NULL);
  });
 }
}
