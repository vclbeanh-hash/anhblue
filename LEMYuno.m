/* LEM Yuno Glass Studio 2.3 — independent UIKit implementation.
   Visual reference: https://github.com/danielkanan/Yuno/tree/v1.1.1
   No ad, player, network or account hooks. */
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <math.h>
#import <string.h>

static NSString *const buildName=@"LEM Glass Studio 2.3";
static char surfaceKey,pillKey,bgKey,oldHiddenKey,rimKey,dragKey,verticalKey,normalFrameKey,compactFrameKey,foldKey,tabGeometryKey,miniCornerKey,labelStateKey,fluidLayerKey,motionKey,ambientKey,studioEntryKey,searchPlateKey,searchStateKey,searchAnimKey,fullPlateKey,fullStateKey,seekKey;
static IMP oldPivot,oldRight,oldSelect,oldStyle,oldMiniLayout,oldMiniMove,oldMiniFrame,oldLayerLayout,oldPivotHit,oldWatchLayout,oldWatchDisappear,oldSearchLayout,oldSettingsLayout,oldSearchSettingsLayout;
static __weak UIView *currentPivot,*currentMini;
static __weak UIViewController *currentMiniController;
static BOOL resizePending=NO;
static CGFloat smallestWidth=0,largestWidth=0;
static __weak UIView *activeLayoutOwner;
static NSUInteger nativeLayoutDepth,frameHits,foldRequests,clearedPlates;
static NSString *lastFoldNote=@"Chưa vuốt";
static CFTimeInterval lastFoldAction;
// Local preferences; all UI and preference reads are main-thread confined.
static CGFloat studioTint=.15,studioElastic=.80,studioRefraction=1;
static NSInteger studioBlur=6,studioPreset=1;
static BOOL studioModules[7]={YES,YES,YES,YES,NO,NO,YES};
static NSArray<NSString *> *moduleKeys(void){return @[@"chips",@"player",@"actions",@"menus",@"info",@"comments",@"seek"];}
static NSArray<NSString *> *moduleTitles(void){return @[@"Glass Category Chips",@"Glass Player Overlay",@"Glass Action Row",@"Glass Menus / Sheets",@"Glass Title / Info (beta)",@"Glass Comments (beta)",@"Liquid Seekbar (beta)"];}
static BOOL studioHaptics=YES,studioPower=YES,studioMorph=YES,studioAmbient=YES,studioSearch=YES;
static BOOL economy(void){
    NSProcessInfo *p=NSProcessInfo.processInfo;
    return studioPreset==3||(studioPower&&(p.lowPowerModeEnabled||p.thermalState>=NSProcessInfoThermalStateSerious));
}
static void loadStudio(void){
    NSUserDefaults *d=NSUserDefaults.standardUserDefaults;
    [d registerDefaults:@{@"LEM.Studio.tint":@.15,@"LEM.Studio.blur":@6,@"LEM.Studio.elastic":@.8,@"LEM.Studio.refraction":@1,@"LEM.Studio.haptic":@YES,@"LEM.Studio.power":@YES,@"LEM.Studio.morph":@YES,@"LEM.Studio.ambient":@YES,@"LEM.Studio.search":@YES,@"LEM.Studio.preset":@1}];
    studioTint=MAX(0,MIN(.6,[d doubleForKey:@"LEM.Studio.tint"]));studioBlur=MAX(0,MIN(20,[d integerForKey:@"LEM.Studio.blur"]));
    studioElastic=MAX(0,MIN(1,[d doubleForKey:@"LEM.Studio.elastic"]));studioRefraction=MAX(0,MIN(1.5,[d doubleForKey:@"LEM.Studio.refraction"]));
    studioHaptics=[d boolForKey:@"LEM.Studio.haptic"];studioPower=[d boolForKey:@"LEM.Studio.power"];studioMorph=[d boolForKey:@"LEM.Studio.morph"];studioAmbient=[d boolForKey:@"LEM.Studio.ambient"];studioSearch=[d boolForKey:@"LEM.Studio.search"];studioPreset=[d integerForKey:@"LEM.Studio.preset"];
    for(NSUInteger i=0;i<7;i++){NSString *key=[@"LEM.Studio." stringByAppendingString:moduleKeys()[i]];id value=[d objectForKey:key];studioModules[i]=value?[value boolValue]:(i<4||i==6);}
}
static NSHashTable<UIView *> *studioSurfaces;
static id obj(id t,NSString *name){
    SEL sel=NSSelectorFromString(name);
    if(!t||![t respondsToSelector:sel])return nil;
    Method m=class_getInstanceMethod([t class],sel);
    char rt[12]={0};
    if(!m||method_getNumberOfArguments(m)!=2)return nil;
    method_getReturnType(m,rt,sizeof rt);
    return rt[0]=='@'?((id(*)(id,SEL))objc_msgSend)(t,sel):nil;
}
static UIView *view(id t,NSString *name){
    id x=obj(t,name);return [x isKindOfClass:UIView.class]?x:nil;
}
static BOOL selected(UIView *v){
    SEL sel=NSSelectorFromString(@"selected");
    Method m=class_getInstanceMethod([v class],sel);char rt[8]={0};
    if(m&&method_getNumberOfArguments(m)==2){method_getReturnType(m,rt,sizeof rt);if(rt[0]=='B'||rt[0]=='c')return ((BOOL(*)(id,SEL))objc_msgSend)(v,sel);}
    return (v.accessibilityTraits&UIAccessibilityTraitSelected)!=0;
}
static BOOL isCreation(UIView *item){
    SEL s=NSSelectorFromString(@"isCreationIconOnlyItem");Method m=class_getInstanceMethod(item.class,s);char rt[8]={0};
    if(m&&method_getNumberOfArguments(m)==2){method_getReturnType(m,rt,sizeof rt);if(rt[0]=='B'||rt[0]=='c')return ((BOOL(*)(id,SEL))objc_msgSend)(item,s);}
    return NO;
}
static void clear(UIView *v){
    if(!v)return;
    if(!objc_getAssociatedObject(v,&bgKey))objc_setAssociatedObject(v,&bgKey,v.backgroundColor?:NSNull.null,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if(v.backgroundColor&&!CGColorEqualToColor(v.backgroundColor.CGColor,UIColor.clearColor.CGColor))v.backgroundColor=UIColor.clearColor;
    if(v.layer.backgroundColor&&CGColorGetAlpha(v.layer.backgroundColor)>.001)v.layer.backgroundColor=UIColor.clearColor.CGColor;
    v.opaque=NO;
}
static void hideSafe(UIView *v,NSArray<UIView *> *protectedViews){
    if(!v)return;
    for(UIView *p in protectedViews)if(v==p||[p isDescendantOfView:v])return;
    if(!objc_getAssociatedObject(v,&oldHiddenKey))objc_setAssociatedObject(v,&oldHiddenKey,@(v.hidden),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    v.hidden=YES;
}
static NSArray<UIView *> *tabs(UIView *v){
    id all=obj(v,@"itemViews");NSMutableArray *a=[NSMutableArray array];
    if([all isKindOfClass:NSArray.class]){
        for(id x in all)if([x isKindOfClass:UIView.class]&&![x isHidden]&&[x window]==v.window)[a addObject:x];
    }
    if(!a.count)for(int i=1;i<=6;i++){UIView *x=view(v,[NSString stringWithFormat:@"itemView%d",i]);if(x&&!x.hidden&&x.window==v.window)[a addObject:x];}
    return a;
}
// Only consider siblings behind the navigation branch; never sample window,
// keyboard or any containing view that could include this very glass surface.
static UIView *backdrop(UIView *host,CGRect region){
    UIView *branch=host;
    for(int i=0;branch.superview&&i<9;i++){
        UIView *parent=branch.superview;
        NSInteger z=(NSInteger)[parent.subviews indexOfObjectIdenticalTo:branch];
        if(z!=NSNotFound&&z>0){
            for(NSInteger k=z-1;k>=0;k--){
                UIView *v=parent.subviews[k];
                if(v.hidden||v.alpha<.2||v.bounds.size.height<80||[v isKindOfClass:UIControl.class]||[v isKindOfClass:UIVisualEffectView.class])continue;
                CGRect r=[v convertRect:v.bounds toView:host.window], x=CGRectIntersection(r,region);
                if(!CGRectIsNull(x)&&x.size.width>=region.size.width*.96&&x.size.height>=region.size.height*.92)return v;
            }
        }
        branch=parent;
    }
    return nil;
}
static inline int clamp(int x,int lo,int hi){return MAX(lo,MIN(hi,x));}
static inline float sample(unsigned char *p,int w,int h,float x,float y,int c){
    x=fmaxf(0,fminf(w-1,x));y=fmaxf(0,fminf(h-1,y));
    int x0=(int)x,y0=(int)y,x1=MIN(w-1,x0+1),y1=MIN(h-1,y0+1);
    float a=x-x0,b=y-y0;
    return (p[(y0*w+x0)*4+c]*(1-a)+p[(y0*w+x1)*4+c]*a)*(1-b)+(p[(y1*w+x0)*4+c]*(1-a)+p[(y1*w+x1)*4+c]*a)*b;
}
// Glass 1.1.1 visual principles: a sampled backdrop, soft blur, refraction,
// chromatic edge and saturation. Independently implemented at 0.5x on iOS.
static CGImageRef opticalImage(UIView *source,CGRect rect,BOOL dark,BOOL top) CF_RETURNS_RETAINED;
static CGImageRef opticalImage(UIView *source,CGRect rect,BOOL dark,BOOL top){
    if(!source||CGRectIsEmpty(rect))return NULL;
    int w=(int)MAX(14,MIN(240,ceil(rect.size.width*.5))),h=(int)MAX(12,MIN(80,ceil(rect.size.height*.5)));
    size_t n=(size_t)w*h*4;
    unsigned char *tmp=calloc(1,n),*soft=calloc(1,n);
    CGColorSpaceRef cs=CGColorSpaceCreateDeviceRGB();
    CGContextRef c=CGBitmapContextCreate(NULL,w,h,8,w*4,cs,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    CGContextRef out=CGBitmapContextCreate(NULL,w,h,8,w*4,cs,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);CGColorSpaceRelease(cs);
    CGImageRef result=NULL;
    if(!c||!out||!tmp||!soft)goto cleanup;
    CGContextTranslateCTM(c,0,h);CGContextScaleCTM(c,w/rect.size.width,-h/rect.size.height);CGContextTranslateCTM(c,-rect.origin.x,-rect.origin.y);
    @try{[source.layer renderInContext:c];}@catch(NSException *e){goto cleanup;}
    unsigned char *raw=CGBitmapContextGetData(c),*dst=CGBitmapContextGetData(out);
    int opaque=0;float lo=255,hi=0;double sumL=0;
    for(int i=0;i<w*h;i++)if(raw[i*4+3]>225){opaque++;float y=.2126f*raw[i*4]+.7152f*raw[i*4+1]+.0722f*raw[i*4+2];lo=fminf(lo,y);hi=fmaxf(hi,y);sumL+=y;}
    // A video surface or empty snapshot can return black; leave it transparent instead.
    if(opaque<w*h*.92||hi-lo<9)goto cleanup;
    float average=(float)(sumL/MAX(1,opaque))/255.f;
    int radiusBlur=(int)round(studioBlur*(top?.5:.67));
    float adaptive=dark?fminf(.18f,fmaxf(0,(average-.32f)*.35f)):fminf(.18f,fmaxf(0,(.65f-average)*.35f));
    float contrast=fminf(.66f,(float)studioTint*.55f+adaptive);
    for(int y=0;y<h;y++)for(int x=0;x<w;x++)for(int k=0;k<3;k++){
        int sum=0;for(int j=-radiusBlur;j<=radiusBlur;j++)sum+=raw[(y*w+clamp(x+j,0,w-1))*4+k];tmp[(y*w+x)*4+k]=sum/(2*radiusBlur+1);
    }
    for(int y=0;y<h;y++)for(int x=0;x<w;x++)for(int k=0;k<3;k++){
        int sum=0;for(int j=-radiusBlur;j<=radiusBlur;j++)sum+=tmp[(clamp(y+j,0,h-1)*w+x)*4+k];soft[(y*w+x)*4+k]=sum/(2*radiusBlur+1);
    }
    for(int y=0;y<h;y++)for(int x=0;x<w;x++){
        float radius=fminf(w,h)*.5f,px=x+.5f-w*.5f,py=y+.5f-h*.5f;
        float half=fmaxf(0,w*.5f-radius),cx=fmaxf(-half,fminf(half,px)),dx=px-cx,dy=py,d=hypotf(dx,dy);
        float u=fmaxf(0,fminf(1,1-(radius-d)/fmaxf(4,radius*.65f)));
        float nx=d>.001f?dx/d:0,ny=d>.001f?dy/d:0;
        float rgb[3];
        for(int k=0;k<3;k++){
            float shift=(7.0f+(1-k)*.45f)*u*u*(float)studioRefraction;
            rgb[k]=sample(soft,w,h,x-nx*shift,y-ny*shift,k);
        }
        float l=.2126f*rgb[0]+.7152f*rgb[1]+.0722f*rgb[2];
        for(int k=0;k<3;k++){
            float value=l+(rgb[k]-l)*1.32f;
            // Clear glass rather than the old charcoal tint. Bright edge, no black fill.
            value=value*(1.f-contrast)+(dark?0.f:255.f)*contrast+5.f+9.f*u*u;
            dst[(y*w+x)*4+k]=(unsigned char)fmaxf(0,fminf(255,value));
        }
        dst[(y*w+x)*4+3]=255;
    }
    result=CGBitmapContextCreateImage(out);
cleanup:
    if(c)CGContextRelease(c);if(out)CGContextRelease(out);free(tmp);free(soft);return result;
}

@interface LEMGlass23Surface : UIView
@property(nonatomic,weak) UIView *host;
@property(nonatomic,strong) CALayer *picture;
@property(nonatomic,strong) UIVisualEffectView *fallback;
@property(nonatomic,strong) CAGradientLayer *edge;
@property(nonatomic,strong) CAShapeLayer *edgeMask;
@property(nonatomic,strong) CAGradientLayer *gleam;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic) CFTimeInterval nextCapture;
@property(nonatomic) BOOL topChrome;
- (void)refresh;
@end
@implementation LEMGlass23Surface
- (instancetype)initWithFrame:(CGRect)f {
    if((self=[super initWithFrame:f])){
        self.userInteractionEnabled=NO;self.opaque=NO;self.backgroundColor=UIColor.clearColor;
        [studioSurfaces addObject:self];
        self.layer.masksToBounds=YES;self.layer.cornerCurve=kCACornerCurveContinuous;
        self.fallback=[[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial]];
        self.fallback.userInteractionEnabled=NO;self.fallback.alpha=.36;self.fallback.backgroundColor=UIColor.clearColor;
        [self addSubview:self.fallback];
        self.picture=[CALayer layer];self.picture.contentsGravity=kCAGravityResize;[self.layer addSublayer:self.picture];
        self.gleam=[CAGradientLayer layer];self.gleam.colors=@[(id)[UIColor colorWithWhite:1 alpha:.11].CGColor,(id)[UIColor colorWithWhite:1 alpha:.015].CGColor,(id)[UIColor colorWithWhite:1 alpha:.07].CGColor];self.gleam.locations=@[@0,@.50,@1];[self.layer addSublayer:self.gleam];
        self.edge=[CAGradientLayer layer];self.edge.startPoint=CGPointMake(.1,0);self.edge.endPoint=CGPointMake(.9,1);
        self.edge.colors=@[(id)[UIColor colorWithWhite:1 alpha:.66].CGColor,(id)[UIColor colorWithWhite:1 alpha:.10].CGColor,(id)[UIColor colorWithWhite:1 alpha:.36].CGColor];self.edge.locations=@[@0,@.48,@1];
        self.edgeMask=[CAShapeLayer layer];self.edgeMask.fillColor=nil;self.edgeMask.strokeColor=UIColor.whiteColor.CGColor;self.edgeMask.lineWidth=0;self.edge.mask=self.edgeMask;self.edge.hidden=YES;[self.layer addSublayer:self.edge];
    }return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat r=MIN(self.bounds.size.height,self.bounds.size.width)*.5;
    [CATransaction begin];[CATransaction setDisableActions:YES];
    self.layer.cornerRadius=r;self.fallback.frame=self.bounds;self.picture.frame=self.bounds;self.gleam.frame=self.bounds;self.edge.frame=self.bounds;self.edgeMask.frame=self.bounds;
    self.edgeMask.path=[UIBezierPath bezierPathWithRoundedRect:CGRectInset(self.bounds,.55,.55) cornerRadius:MAX(1,r-.55)].CGPath;
    [CATransaction commit];
}
- (void)refresh {
    if(!self.window||!self.host||self.hidden||self.host.hidden||self.host.alpha<.05||UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)return;
    if(UIAccessibilityIsReduceTransparencyEnabled()){
        self.picture.contents=nil;self.fallback.hidden=YES;self.backgroundColor=UIColor.secondarySystemBackgroundColor;return;
    }
    self.backgroundColor=UIColor.clearColor;
    self.fallback.alpha=MIN(.88,.12+studioBlur*.028+studioTint*.65);
    self.gleam.opacity=MIN(1.5,.55+studioTint*2.5);
    if(economy()){self.picture.contents=nil;self.fallback.hidden=NO;return;}
    if(CACurrentMediaTime()<self.nextCapture)return;
    CGRect region=[self convertRect:self.bounds toView:self.window];
    UIView *src=backdrop(self.host,region);
    if(!src){self.picture.contents=nil;self.fallback.hidden=NO;return;}
    CFTimeInterval start=CACurrentMediaTime();
    CGImageRef image=opticalImage(src,[src convertRect:region fromView:self.window],self.traitCollection.userInterfaceStyle!=UIUserInterfaceStyleLight,self.topChrome);
    [CATransaction begin];[CATransaction setDisableActions:YES];self.picture.contents=image?(__bridge id)image:nil;self.fallback.hidden=image!=NULL;[CATransaction commit];if(image)CGImageRelease(image);
    CFTimeInterval elapsed=CACurrentMediaTime()-start;
    self.nextCapture=CACurrentMediaTime()+(elapsed>.018?.48:NSProcessInfo.processInfo.lowPowerModeEnabled?.5:.11);
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self.timer invalidate];self.timer=nil;
    if(!self.window){self.picture.contents=nil;return;}
    __weak typeof(self) weak=self;
    self.timer=[NSTimer timerWithTimeInterval:.14 repeats:YES block:^(NSTimer *t){LEMGlass23Surface *s=weak;if(!s){[t invalidate];return;}[s refresh];}];
    self.timer.tolerance=.025;[[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
}
- (void)dealloc{[self.timer invalidate];}
@end

// Edge stays above the old opaque account-page backdrop; it cannot consume touches.
@interface LEMGlass23Rim : UIView
@property(nonatomic,strong) CAGradientLayer *light;
@property(nonatomic,strong) CAShapeLayer *outline;
@end
@implementation LEMGlass23Rim
- (instancetype)initWithFrame:(CGRect)f{
    if((self=[super initWithFrame:f])){
        self.userInteractionEnabled=NO;self.opaque=NO;self.backgroundColor=UIColor.clearColor;
        self.light=[CAGradientLayer layer];self.light.startPoint=CGPointMake(.15,0);self.light.endPoint=CGPointMake(.85,1);
        self.light.colors=@[(id)[UIColor colorWithWhite:1 alpha:.62].CGColor,(id)[UIColor colorWithWhite:1 alpha:.10].CGColor,(id)[UIColor colorWithWhite:1 alpha:.34].CGColor];self.light.locations=@[@0,@.52,@1];
        self.outline=[CAShapeLayer layer];self.outline.fillColor=nil;self.outline.strokeColor=UIColor.whiteColor.CGColor;self.outline.lineWidth=.65;
        self.light.mask=self.outline;[self.layer addSublayer:self.light];
    }return self;
}
- (void)layoutSubviews{
    [super layoutSubviews];[CATransaction begin];[CATransaction setDisableActions:YES];
    self.light.frame=self.bounds;self.outline.frame=self.bounds;
    self.outline.path=[UIBezierPath bezierPathWithRoundedRect:CGRectInset(self.bounds,.6,.6) cornerRadius:MAX(1,MIN(self.bounds.size.width,self.bounds.size.height)*.5-.6)].CGPath;
    [CATransaction commit];
}
@end
static UIView *branchIn(UIView *child,UIView *ancestor){
    UIView *p=child;while(p&&p.superview!=ancestor)p=p.superview;return p;
}
static LEMGlass23Surface *ensureSurface(UIView *host,CGRect f){
    LEMGlass23Surface *s=objc_getAssociatedObject(host,&surfaceKey);
    if(!s){s=[[LEMGlass23Surface alloc] initWithFrame:f];s.host=host;objc_setAssociatedObject(host,&surfaceKey,s,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
    if(s.superview!=host)[host insertSubview:s atIndex:0];
    if(!CGRectEqualToRect(s.frame,f))s.frame=f;
    return s;
}
static void placeBehindTabs(UIView *v,NSArray<UIView *> *items,LEMGlass23Surface *surface){
    // Find the front-most safe insertion point just beneath the first actual tab branch,
    // rather than behind an opaque view inserted by YouTube on per-page style changes.
    NSUInteger first=NSNotFound;
    for(UIView *item in items){UIView *branch=branchIn(item,v);NSUInteger n=branch?[v.subviews indexOfObjectIdenticalTo:branch]:NSNotFound;if(n!=NSNotFound&&(first==NSNotFound||n<first))first=n;}
    if(first!=NSNotFound){UIView *front=v.subviews[first];if(front!=surface){
        NSUInteger index=[v.subviews indexOfObjectIdenticalTo:surface];
        if(index==NSNotFound||index+1!=first)[v insertSubview:surface belowSubview:front];
    }}
}
static void ensureRim(UIView *host,CGRect frame){
    LEMGlass23Rim *rim=objc_getAssociatedObject(host,&rimKey);
    if(!rim){rim=[[LEMGlass23Rim alloc] initWithFrame:frame];objc_setAssociatedObject(host,&rimKey,rim,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
    if(rim.superview!=host)[host addSubview:rim];else if(host.subviews.lastObject!=rim)[host bringSubviewToFront:rim];
    if(!CGRectEqualToRect(rim.frame,frame))rim.frame=frame;
}
static CGRect pillTarget(UIView *host,UIView *item,UIView *parent,CGRect shell){
    if(!item||!parent)return CGRectNull;
    CGRect r=[item convertRect:item.bounds toView:host];
    CGRect target=CGRectIntersection(CGRectInset(shell,4,4),CGRectInset(r,3,0));
    if(CGRectIsNull(target)||target.size.width<12||target.size.height<20)return CGRectNull;
    return [host convertRect:target toView:parent];
}
static void fluidVisual(UIView *pill,BOOL dragging){
    if(!pill)return;
    CAGradientLayer *g=objc_getAssociatedObject(pill,&fluidLayerKey);
    if(!g){
        g=[CAGradientLayer layer];g.startPoint=CGPointMake(.35,0);g.endPoint=CGPointMake(.65,1);
        g.locations=@[@0,@.48,@1];[pill.layer insertSublayer:g atIndex:0];
        objc_setAssociatedObject(pill,&fluidLayerKey,g,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [CATransaction begin];[CATransaction setDisableActions:YES];
    g.frame=pill.bounds;g.cornerRadius=MIN(pill.bounds.size.width,pill.bounds.size.height)*.5;
    g.colors=dragging?@[(id)[UIColor colorWithWhite:1 alpha:.27].CGColor,(id)[UIColor colorWithWhite:1 alpha:.065].CGColor,(id)[UIColor colorWithWhite:1 alpha:.16].CGColor]:@[(id)[UIColor colorWithWhite:1 alpha:.16].CGColor,(id)[UIColor colorWithWhite:1 alpha:.025].CGColor,(id)[UIColor colorWithWhite:1 alpha:.09].CGColor];
    pill.backgroundColor=[UIColor colorWithWhite:1 alpha:dragging?.13:.075];[CATransaction commit];
}
static void settle(UIView *pill,CGRect target,BOOL animated){
    if(!pill||CGRectIsNull(target))return;
    CGFloat rad=MIN(target.size.height,target.size.width)*.5;
    if(!animated||UIAccessibilityIsReduceMotionEnabled()){
        [pill.layer removeAllAnimations];pill.transform=CGAffineTransformIdentity;pill.frame=target;pill.layer.cornerRadius=rad;pill.alpha=1;fluidVisual(pill,NO);
    }else{
        [UIView animateWithDuration:.40 delay:0 usingSpringWithDamping:.72 initialSpringVelocity:.15 options:UIViewAnimationOptionBeginFromCurrentState|UIViewAnimationOptionAllowUserInteraction animations:^{pill.transform=CGAffineTransformIdentity;pill.frame=target;pill.layer.cornerRadius=rad;pill.alpha=1;fluidVisual(pill,NO);} completion:nil];
    }
}
@interface LEMGlass23Drag : NSObject<UIGestureRecognizerDelegate>
@property(nonatomic,weak) UIView *host;
@property(nonatomic,weak) UIView *pill;
@property(nonatomic,weak) UIView *originItem;
@property(nonatomic,strong) UIPanGestureRecognizer *gesture;
@property(nonatomic) BOOL dragging;
@property(nonatomic) CGPoint start;
@property(nonatomic) CGRect originalRect;
@property(nonatomic,weak) UIView *hoverItem;
@property(nonatomic,strong) UISelectionFeedbackGenerator *feedback;
- (void)press:(UILongPressGestureRecognizer *)g;
- (void)pan:(UIPanGestureRecognizer *)gr;
@end
@implementation LEMGlass23Drag
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer{
    UIView *host=self.host,*pill=self.pill; if(!host||!pill||pill.alpha<.2||!pill.superview)return NO;
    if([gestureRecognizer isKindOfClass:UILongPressGestureRecognizer.class])return !UIAccessibilityIsReduceMotionEnabled();
    UIPanGestureRecognizer *pan=(UIPanGestureRecognizer *)gestureRecognizer;
    CGPoint velocity=[pan velocityInView:host],point=[pan locationInView:pill.superview];CGPoint delta=[pan translationInView:pill.superview];point.x-=delta.x;point.y-=delta.y;
    // Start only over the currently selected tab; other native taps retain priority.
    if(fabs(velocity.x)<fabs(velocity.y)*1.5||fabs(velocity.x)<20)return NO;
    return CGRectContainsPoint(CGRectInset(pill.frame,-12,-12),point);
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)touch{
    if(![g isKindOfClass:UILongPressGestureRecognizer.class])return YES;
    UIView *p=self.pill;
    return p.superview&&p.alpha>.2&&CGRectContainsPoint(CGRectInset(p.frame,-5,-5),[touch locationInView:p.superview]);
}
- (void)press:(UILongPressGestureRecognizer *)g{
    UIView *p=self.pill;if(!p||UIAccessibilityIsReduceMotionEnabled()||economy()||studioElastic<=.01)return;
    if(g.state==UIGestureRecognizerStateBegan&&!self.dragging){
        CABasicAnimation *a=[CABasicAnimation animationWithKeyPath:@"transform.scale"];
        a.fromValue=@1;a.toValue=@(1+.085*studioElastic);a.duration=.15;a.timingFunction=[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];a.fillMode=kCAFillModeForwards;a.removedOnCompletion=NO;
        [p.layer addAnimation:a forKey:@"lem.press"];fluidVisual(p,YES);
    }else if(g.state==UIGestureRecognizerStateEnded||g.state==UIGestureRecognizerStateCancelled||g.state==UIGestureRecognizerStateFailed){
        [p.layer removeAnimationForKey:@"lem.press"];
        if(!self.dragging){fluidVisual(p,NO);CASpringAnimation *a=[CASpringAnimation animationWithKeyPath:@"transform.scale"];a.fromValue=@(1+.085*studioElastic);a.toValue=@1;a.mass=.8;a.stiffness=250;a.damping=20;a.duration=MIN(.45,a.settlingDuration);[p.layer addAnimation:a forKey:@"lem.release"];}
    }
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gr shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other{return [gr isKindOfClass:UILongPressGestureRecognizer.class]||[other isKindOfClass:UILongPressGestureRecognizer.class];}
- (void)pan:(UIPanGestureRecognizer *)gr{
    UIView *host=self.host,*pill=self.pill,*parent=pill.superview;
    LEMGlass23Surface *surface=objc_getAssociatedObject(host,&surfaceKey);
    if(!host||!pill||!parent||!surface)return;
    NSArray *items=tabs(host);
    if(gr.state==UIGestureRecognizerStateBegan){
        self.dragging=YES;CGPoint start=[gr locationInView:parent],delta=[gr translationInView:parent];self.start=CGPointMake(start.x-delta.x,start.y-delta.y);self.originalRect=pill.frame;self.originItem=nil;
        for(UIView *x in items)if(selected(x)){self.originItem=x;break;}
        [pill.layer removeAllAnimations];pill.transform=CGAffineTransformIdentity;
        self.hoverItem=self.originItem;self.feedback=studioHaptics?[UISelectionFeedbackGenerator new]:nil;[self.feedback prepare];fluidVisual(pill,YES);
        return;
    }
    if(!self.dragging)return;
    if(gr.state==UIGestureRecognizerStateChanged){
        CGRect bounds=[host convertRect:CGRectInset(surface.frame,4,4) toView:parent];
        CGRect f=self.originalRect;CGFloat dx=[gr locationInView:parent].x-self.start.x;
        f.origin.x=MAX(CGRectGetMinX(bounds),MIN(CGRectGetMaxX(bounds)-f.size.width,f.origin.x+dx));
        CGFloat speed=fabs([gr velocityInView:parent].x);
        // A subtle stretch in the direction of movement, like the demo.
        CGFloat extra=(UIAccessibilityIsReduceMotionEnabled()||economy())?0:MIN(20,speed*.015)*studioElastic;
        f.origin.x=MAX(CGRectGetMinX(bounds),f.origin.x-extra*.5);
        f.size.width=MIN(CGRectGetMaxX(bounds)-f.origin.x,f.size.width+extra);
        f.origin.y+=MIN(3.5,extra*.25);f.size.height-=MIN(7,extra*.50);
        [CATransaction begin];[CATransaction setDisableActions:YES];pill.frame=f;pill.layer.cornerRadius=f.size.height*.5;[CATransaction commit];fluidVisual(pill,YES);
        UIView *nearest=nil;CGFloat distance=CGFLOAT_MAX;
        for(UIView *item in items){
            if(isCreation(item)||!obj(item,@"renderer"))continue;
            CGRect slot=pillTarget(host,item,parent,surface.frame);if(CGRectIsNull(slot))continue;
            CGFloat d=fabs(CGRectGetMidX(slot)-CGRectGetMidX(f));if(d<distance){nearest=item;distance=d;}
        }
        if(nearest&&nearest!=self.hoverItem){self.hoverItem=nearest;[self.feedback selectionChanged];[self.feedback prepare];}
        return;
    }
    if(gr.state==UIGestureRecognizerStateEnded||gr.state==UIGestureRecognizerStateCancelled||gr.state==UIGestureRecognizerStateFailed){
        UIView *target=self.originItem;
        if(gr.state==UIGestureRecognizerStateEnded){
            CGFloat x=CGRectGetMidX(pill.frame),distance=CGFLOAT_MAX;
            for(UIView *item in items){
                if(isCreation(item)||!obj(item,@"renderer"))continue;
                CGRect f=pillTarget(host,item,parent,surface.frame);
                if(CGRectIsNull(f))continue;CGFloat d=fabs(CGRectGetMidX(f)-x);
                if(d<distance){distance=d;target=item;}
            }
        }
        self.dragging=NO;self.feedback=nil;self.hoverItem=nil;
        CGRect destination=pillTarget(host,target,parent,surface.frame);
        if(CGRectIsNull(destination))destination=self.originalRect;
        settle(pill,destination,YES);
        // Use the exact native item action found in 21.33.6, not a fake selected state.
        if(target&&target!=self.originItem&&gr.state==UIGestureRecognizerStateEnded){
            SEL tap=NSSelectorFromString(@"doTap");Method m=class_getInstanceMethod(target.class,tap);char rt[8]={0};
            if(m&&method_getNumberOfArguments(m)==2){method_getReturnType(m,rt,sizeof rt);if(rt[0]=='v')((void(*)(id,SEL))objc_msgSend)(target,tap);}
        }
        [host setNeedsLayout];
    }
}
@end
static LEMGlass23Drag *installDrag(UIView *host,UIView *pill){
    LEMGlass23Drag *d=objc_getAssociatedObject(host,&dragKey);
    if(!d){
        d=[LEMGlass23Drag new];d.host=host;d.gesture=[[UIPanGestureRecognizer alloc] initWithTarget:d action:@selector(pan:)];
        d.gesture.maximumNumberOfTouches=1;d.gesture.cancelsTouchesInView=YES;d.gesture.delegate=d;
        [host addGestureRecognizer:d.gesture];
        UILongPressGestureRecognizer *press=[[UILongPressGestureRecognizer alloc] initWithTarget:d action:@selector(press:)];press.minimumPressDuration=0;press.allowableMovement=12;press.cancelsTouchesInView=NO;press.delaysTouchesBegan=NO;press.delaysTouchesEnded=NO;press.delegate=d;[host addGestureRecognizer:press];
        objc_setAssociatedObject(host,&dragKey,d,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    d.pill=pill;return d;
}
static void installVertical(UIView *host);
static void installMotion(UIWindow *w);

static BOOL containsTabs(UIView *v,NSArray *items){
    for(UIView *i in items)if(i==v||[i isDescendantOfView:v])return YES;return NO;
}
static BOOL isNativePlate(UIView *v,UIView *host,NSArray *items){
    if(!v||v==host||[v isKindOfClass:LEMGlass23Surface.class]||[v isKindOfClass:LEMGlass23Rim.class]||v==objc_getAssociatedObject(host,&pillKey)||containsTabs(v,items))return NO;
    if([v isKindOfClass:UIControl.class]||[v isKindOfClass:UILabel.class]||[v isKindOfClass:UIScrollView.class])return NO;
    CGRect f=[v convertRect:v.bounds toView:host];
    if(f.size.width<host.bounds.size.width*.87||f.size.height<12||f.size.height>190||CGRectIsEmpty(CGRectIntersection(f,host.bounds)))return NO;
    NSString *n=NSStringFromClass(v.class).lowercaseString;
    BOOL known=[v isKindOfClass:UIVisualEffectView.class]||[v isKindOfClass:UIImageView.class]||[n containsString:@"background"]||[n containsString:@"backdrop"]||[n containsString:@"blur"]||[n containsString:@"material"];
    BOOL flat=(v.class==UIView.class&&!v.subviews.count);
    return known||flat;
}
static void removeOldPlate(UIView *host,NSArray *items){
    UIView *branch=host;
    for(int level=0;branch&&level<3;level++){
        CGRect f=[branch convertRect:branch.bounds toView:host];
        if(branch!=host&&(f.size.height>190||f.size.width<host.bounds.size.width*.87))break;
        clear(branch);branch.layer.backgroundColor=UIColor.clearColor.CGColor;
        branch.layer.borderWidth=0;
        for(UIView *v in [branch.subviews copy]){
            if(isNativePlate(v,host,items)){
                if(!v.hidden)clearedPlates++;
                hideSafe(v,items);
            }
        }
        branch=branch.superview;
    }
    // The UIKit root/content shell sometimes holds a solid background instead
    // of blurView. Clear only the tab ancestors within the narrow bottom bar.
    for(UIView *item in items){
        for(UIView *p=item.superview;p&&p!=host;p=p.superview){
            if(![p isDescendantOfView:host]||p.bounds.size.height>190)break;
            if(p.bounds.size.width>host.bounds.size.width*.80){clear(p);p.layer.backgroundColor=UIColor.clearColor.CGColor;p.layer.borderWidth=0;}
        }
    }
}
// Dock in the same row only when the native player parent can contain it.
static BOOL visible(UIView *v);
static BOOL busy(UIView *v);
static BOOL dockGeometry(UIView *mini,UIView *bar,CGRect *tabRect,CGRect *miniRect){
    if(!visible(mini)||!visible(bar)||mini.window!=bar.window||!mini.superview||busy(mini))return NO;
    CGRect b=bar.bounds;
    LEMGlass23Surface *surface=objc_getAssociatedObject(bar,&surfaceKey);
    CGFloat h=surface?surface.frame.size.height:MIN(58,b.size.height-bar.safeAreaInsets.bottom);
    CGFloat y=surface?surface.frame.origin.y:b.origin.y;
    if(b.size.width<300||h<40||h>75)return NO;
    NSValue *saved=objc_getAssociatedObject(mini,&normalFrameKey);
    CGRect native=saved?saved.CGRectValue:mini.frame;
    if(native.size.height<20||native.size.width<40)return NO;
    CGFloat ratio=MIN(2.3,MAX(1.20,native.size.width/native.size.height));
    CGFloat videoHeight=MIN(h-2,58),videoWidth=MIN(110,videoHeight*ratio);
    videoHeight=videoWidth/ratio;
    CGFloat right=CGRectGetMaxX(b)-7, gap=7;
    CGRect videoInBar=CGRectMake(right-videoWidth,y+(h-videoHeight)*.5,videoWidth,videoHeight);
    CGRect tab=CGRectMake(b.origin.x+7,y,CGRectGetMinX(videoInBar)-gap-(b.origin.x+7),h);
    if(tab.size.width<200)return NO;
    CGRect windowRect=[bar convertRect:videoInBar toView:bar.window];
    CGRect dest=[mini.superview convertRect:windowRect fromView:bar.window];
    if(!CGRectContainsRect(CGRectInset(mini.superview.bounds,-1,-1),dest))return NO;
    for(UIView *parent=mini.superview;parent&&parent!=mini.window;parent=parent.superview){
        if(parent.clipsToBounds&&!CGRectContainsRect(CGRectInset(parent.bounds,-1,-1),[parent convertRect:windowRect fromView:bar.window]))return NO;
    }
    if(tabRect)*tabRect=tab;if(miniRect)*miniRect=dest;return YES;
}
static BOOL isDocked(UIView *bar,CGRect *rect){
    UIView *mini=currentMini;
    if(![objc_getAssociatedObject(mini,&foldKey) boolValue])return NO;
    CGRect target=CGRectNull,tab=CGRectNull;
    if(!dockGeometry(mini,bar,&tab,&target))return NO;
    if(fabs(CGRectGetMidX(mini.frame)-CGRectGetMidX(target))>7||fabs(CGRectGetMidY(mini.frame)-CGRectGetMidY(target))>7||fabs(mini.frame.size.width-target.size.width)>7)return NO;
    if(rect)*rect=tab;return YES;
}
static void collectTabLabels(UIView *node,NSMutableArray *out,NSUInteger depth){
    if(!node||depth>5)return;
    for(UIView *child in node.subviews){
        if([child isKindOfClass:UILabel.class]){
            UILabel *label=(UILabel *)child;
            if(label.text.length||label.attributedText.length)[out addObject:label];
        }else collectTabLabels(child,out,depth+1);
    }
}
static void restoreTabLabels(UIView *item){
    NSArray *saved=objc_getAssociatedObject(item,&labelStateKey);
    for(NSArray *entry in saved){UIView *v=entry[0];if([v isDescendantOfView:item])v.alpha=[entry[1] doubleValue];}
    objc_setAssociatedObject(item,&labelStateKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static CGFloat hideTabLabels(UIView *item){
    NSMutableArray *labels=[NSMutableArray array];
    for(NSString *name in @[@"titleLabel",@"label",@"titleView",@"textLabel"]){
        UIView *v=view(item,name);
        if(v&&[v isKindOfClass:UILabel.class]&&[v isDescendantOfView:item]&&![labels containsObject:v])[labels addObject:v];
    }
    NSMutableArray *all=[NSMutableArray array];collectTabLabels(item,all,0);
    for(UIView *v in all)if(![labels containsObject:v]){
        CGRect rect=[v convertRect:v.bounds toView:item];
        if(CGRectGetMidY(rect)>CGRectGetMidY(item.bounds)&&rect.size.height<28)[labels addObject:v];
    }
    NSMutableArray *saved=[NSMutableArray array];CGFloat top=CGFLOAT_MAX;
    for(UIView *v in labels){
        if(v.hidden||v.alpha<.01)continue;
        CGRect rect=[v convertRect:v.bounds toView:item];
        if(rect.size.height<5||rect.size.height>30||CGRectGetMidY(rect)<CGRectGetMidY(item.bounds))continue;
        top=MIN(top,CGRectGetMinY(rect));[saved addObject:@[v,@(v.alpha)]];v.alpha=0;
    }
    if(saved.count)objc_setAssociatedObject(item,&labelStateKey,saved,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return top==CGFLOAT_MAX?0:MIN(8,MAX(0,(CGRectGetMaxY(item.bounds)-top)*.42));
}
static void restoreTabs(UIView *host){
    for(UIView *item in tabs(host)){
        restoreTabLabels(item);
        NSArray *saved=objc_getAssociatedObject(item,&tabGeometryKey);
        if(saved.count!=2)continue;
        item.transform=[saved[1] CGAffineTransformValue];item.center=[saved[0] CGPointValue];
        objc_setAssociatedObject(item,&tabGeometryKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}
static void arrangeDockTabs(UIView *host,NSArray<UIView *> *items,CGRect shell){
    NSArray *ordered=[items sortedArrayUsingComparator:^NSComparisonResult(UIView *a,UIView *b){
        CGFloat x=[a convertPoint:CGPointMake(CGRectGetMidX(a.bounds),CGRectGetMidY(a.bounds)) toView:host].x;
        CGFloat y=[b convertPoint:CGPointMake(CGRectGetMidX(b.bounds),CGRectGetMidY(b.bounds)) toView:host].x;
        return x<y?NSOrderedAscending:x>y?NSOrderedDescending:NSOrderedSame;
    }];
    CGFloat slot=(shell.size.width-8)/MAX(1,ordered.count);
    for(NSUInteger j=0;j<ordered.count;j++){
        UIView *item=ordered[j];if(!item.superview)continue;
        NSArray *saved=objc_getAssociatedObject(item,&tabGeometryKey);
        if(!saved){saved=@[[NSValue valueWithCGPoint:item.center],[NSValue valueWithCGAffineTransform:item.transform]];objc_setAssociatedObject(item,&tabGeometryKey,saved,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
        CGAffineTransform base=[saved[1] CGAffineTransformValue];
        CGFloat offset=hideTabLabels(item);
        CGFloat scale=MIN(.96,MAX(.60,(slot-3)/MAX(1,item.bounds.size.width)));
        item.transform=CGAffineTransformScale(base,scale,scale);
        CGPoint target=CGPointMake(CGRectGetMinX(shell)+4+slot*(j+.5),CGRectGetMidY(shell)+offset*scale);
        item.center=[host convertPoint:target toView:item.superview];
    }
}
static UIView *pivotHit(UIView *bar,SEL s,CGPoint point,UIEvent *event){
    UIView *result=((UIView *(*)(id,SEL,CGPoint,id))oldPivotHit)(bar,s,point,event);
    UIView *mini=currentMini;
    if(!isDocked(bar,NULL)||[mini isDescendantOfView:bar])return result;
    CGPoint local=[bar convertPoint:point toView:mini];
    // Route only touches inside the real live player, never replace normal tab taps.
    if(CGRectContainsPoint(mini.bounds,local)){UIView *hit=[mini hitTest:local withEvent:event];if(hit)return hit;}
    return result;
}
static void updatePivot(UIView *host){
    if(!host.window||host.bounds.size.width<160||host.bounds.size.height<30)return;
    NSArray<UIView *> *items=tabs(host);if(items.count<2)return;
    currentPivot=host;installVertical(host);installMotion(host.window);
    UIView *content=view(host,@"contentView"),*blur=view(host,@"blurView"),*sep=view(host,@"separatorView");
    NSMutableArray *protected=[items mutableCopy];
    if(content&&content!=host)[protected addObject:content];
    CGRect all=CGRectNull,chosen=CGRectNull;
    for(UIView *item in items){
        CGRect r=[item convertRect:item.bounds toView:host];
        if(r.size.width<10||r.size.height<10)continue;
        all=CGRectUnion(all,r);if(selected(item))chosen=r;
    }
    if(CGRectIsNull(all))return;
    CGRect b=host.bounds;
    CGFloat usable=MAX(32,b.size.height-host.safeAreaInsets.bottom);
    CGFloat h=MIN(60,MAX(42,all.size.height+6));
    h=MIN(h,b.size.height);CGFloat y=MAX(b.origin.y,MIN(CGRectGetMaxY(b)-h,CGRectGetMidY(all)-h*.5));
    if(all.size.height>85){h=MIN(62,usable);y=b.origin.y;}
    CGRect frame=CGRectMake(b.origin.x+7,y,b.size.width-14,h);
    CGRect docked=CGRectNull;
    if(isDocked(host,&docked)){
        frame=docked;arrangeDockTabs(host,items,frame);chosen=CGRectNull;
        for(UIView *item in items)if(selected(item)){chosen=[item convertRect:item.bounds toView:host];break;}
    }
    // Remove the native dark plate. Only explicitly known background views.
    clear(host);if(content&&content!=host)clear(content);
    if(blur&&blur!=host&&[blur isDescendantOfView:host])hideSafe(blur,protected);
    if(sep&&sep!=host&&[sep isDescendantOfView:host])hideSafe(sep,protected);
    // Some builds mount a separate flat background inside contentView.
    // Hide only full-width, decorative plain/image/effect views, never buttons or tab ancestors.
    NSArray *holders=content&&content!=host?@[host,content]:@[host];
    for(UIView *parent in holders)for(UIView *v in [parent.subviews copy]){
        if(v==blur||v==sep||v==content||[v isKindOfClass:LEMGlass23Surface.class]||v==objc_getAssociatedObject(host,&pillKey)||v==objc_getAssociatedObject(host,&rimKey))continue;
        if(v.bounds.size.width<parent.bounds.size.width*.87||v.bounds.size.height<25||v.bounds.size.height>180)continue;
        NSString *name=NSStringFromClass(v.class).lowercaseString;
        BOOL decorative=[v isKindOfClass:UIVisualEffectView.class]||[v isKindOfClass:UIImageView.class]||(!v.userInteractionEnabled&&([name containsString:@"background"]||[name containsString:@"backdrop"]||[name containsString:@"blur"]));
        if(decorative)hideSafe(v,protected);
    }
    removeOldPlate(host,items);
    LEMGlass23Surface *surface=ensureSurface(host,frame);
    placeBehindTabs(host,items,surface);
    surface.edge.hidden=YES;[objc_getAssociatedObject(host,&rimKey) removeFromSuperview];
    UIView *pill=objc_getAssociatedObject(host,&pillKey);
    UIView *parent=content&&content!=host&&[content isDescendantOfView:host]?content:host;
    if(!pill){
        pill=[UIView new];pill.userInteractionEnabled=NO;pill.opaque=NO;pill.alpha=0;pill.layer.cornerCurve=kCACornerCurveContinuous;
        pill.layer.borderColor=nil;pill.layer.borderWidth=0;objc_setAssociatedObject(host,&pillKey,pill,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if(pill.superview!=parent){
        if(parent==host)[host insertSubview:pill aboveSubview:surface];else [parent insertSubview:pill atIndex:0];
    }
    LEMGlass23Drag *drag=installDrag(host,pill);
    if(drag.dragging)return;
    if(CGRectIsNull(chosen)){pill.alpha=0;return;}
    CGRect target=CGRectIntersection(CGRectInset(frame,4,4),CGRectInset(chosen,3,0));
    if(!CGRectIsNull(docked)&&!CGRectIsNull(target)){target.origin.y=CGRectGetMinY(frame)+4;target.size.height=frame.size.height-8;}
    if(CGRectIsNull(target)||target.size.height<20||target.size.width<12){pill.alpha=0;return;}
    target=[host convertRect:target toView:parent];
    fluidVisual(pill,NO);
    CGFloat rad=MIN(target.size.height,target.size.width)*.5;
    if(pill.alpha==0||UIAccessibilityIsReduceMotionEnabled()){pill.frame=target;pill.layer.cornerRadius=rad;pill.alpha=1;}
    else if(!CGRectEqualToRect(pill.frame,target)){
        [UIView animateWithDuration:.36 delay:0 usingSpringWithDamping:.72 initialSpringVelocity:.1 options:UIViewAnimationOptionBeginFromCurrentState|UIViewAnimationOptionAllowUserInteraction animations:^{pill.frame=target;pill.layer.cornerRadius=rad;fluidVisual(pill,NO);} completion:nil];
    }
}
static void pivotLayout(UIView *v,SEL s){restoreTabs(v);((void(*)(id,SEL))oldPivot)(v,s);@try{updatePivot(v);}@catch(NSException *e){NSLog(@"[LEM Glass] %@",e.reason);}}
static void styleChrome(UIView *v,SEL s){((void(*)(id,SEL))oldStyle)(v,s);if(v.window&&objc_getAssociatedObject(v,&surfaceKey)){NSArray *items=tabs(v);if(items.count>=2)removeOldPlate(v,items);}}
static void selectTab(UIView *v,SEL s,id key){((void(*)(id,SEL,id))oldSelect)(v,s,key);[v setNeedsLayout];}
static void rightLayout(UIView *v,SEL s){
    ((void(*)(id,SEL))oldRight)(v,s);
    if(!v.window||v.bounds.size.width<35||v.bounds.size.width>260||v.bounds.size.height<25||v.bounds.size.height>90)return;
    @try{
        CGRect f=CGRectInset(v.bounds,2,3);if(f.size.width<28||f.size.height<24)return;
        clear(v);LEMGlass23Surface *surface=ensureSurface(v,f);surface.topChrome=YES;
    }@catch(NSException *e){}
}

// Standalone compact mini-player UI. The video and native controls remain intact.
static BOOL visible(UIView *v){
    if(!v.window)return NO;for(UIView *p=v;p;p=p.superview)if(p.hidden||p.alpha<.05)return NO;
    CGRect f=[v convertRect:v.bounds toView:v.window];return !CGRectIsNull(f)&&!CGRectIsEmpty(CGRectIntersection(f,v.window.bounds));
}
static BOOL boolGetter(id t,NSString *name){
    SEL q=NSSelectorFromString(name);Method m=t?class_getInstanceMethod([t class],q):NULL;char b[8]={0};
    if(!m||method_getNumberOfArguments(m)!=2)return NO;method_getReturnType(m,b,sizeof b);if(b[0]!='B'&&b[0]!='c')return NO;
    return ((BOOL(*)(id,SEL))objc_msgSend)(t,q);
}
static BOOL busy(UIView *v){
    return boolGetter(v,@"isCollapsingOrExpanding")||boolGetter(v,@"isRepositioning")||boolGetter(v,@"isResizingWithPinchGesture");
}
static BOOL normalFrame(CGRect f,UIView *v){
    CGFloat width=v.window.bounds.size.width;
    return isfinite(f.origin.x)&&isfinite(f.origin.y)&&isfinite(f.size.width)&&isfinite(f.size.height)&&f.size.width>=125&&f.size.height>=55&&width>0&&f.size.width<=width*.85&&f.size.height<=width*.65;
}
static BOOL canCompact(UIView *v){
    return visible(v)&&visible(currentPivot)&&v.window==currentPivot.window&&!busy(v)&&v.superview;
}
static CGRect compactFrame(CGRect f,UIView *v){
    CGRect dock=CGRectNull;if(dockGeometry(v,currentPivot,NULL,&dock))return dock;
    CGFloat ratio=MIN(1.,112./f.size.width),w=f.size.width*ratio,h=f.size.height*ratio;
    CGFloat parentWidth=v.superview.bounds.size.width;
    BOOL left=CGRectGetMidX(f)<CGRectGetMidX(v.superview.bounds);
    CGFloat x=left?CGRectGetMinX(f):CGRectGetMaxX(f)-w;
    if(parentWidth>0)x=MAX(CGRectGetMinX(v.superview.bounds),MIN(CGRectGetMaxX(v.superview.bounds)-w,x));
    return CGRectMake(x,CGRectGetMaxY(f)-h,w,h);
}
static void nativeSetFrame(UIView *v,CGRect frame){
    ((void(*)(id,SEL,CGRect))oldMiniFrame)(v,@selector(setFrame:),frame);
}
static BOOL applyingFrame;
static void miniFrame(UIView *v,SEL s,CGRect incoming){
    if(!oldMiniFrame)return;
    if(applyingFrame||!NSThread.isMainThread){((void(*)(id,SEL,CGRect))oldMiniFrame)(v,s,incoming);return;}
    if(busy(v)){
        if(boolGetter(v,@"isResizingWithPinchGesture")||boolGetter(v,@"isRepositioning"))objc_setAssociatedObject(v,&foldKey,@NO,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        ((void(*)(id,SEL,CGRect))oldMiniFrame)(v,s,incoming);return;
    }
    if(normalFrame(incoming,v)){
        objc_setAssociatedObject(v,&normalFrameKey,[NSValue valueWithCGRect:incoming],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if(canCompact(v)&&[objc_getAssociatedObject(v,&foldKey) boolValue]){
            incoming=compactFrame(incoming,v);
            objc_setAssociatedObject(v,&compactFrameKey,[NSValue valueWithCGRect:incoming],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    ((void(*)(id,SEL,CGRect))oldMiniFrame)(v,s,incoming);
}
static void applyCompact(UIView *v,BOOL compact,BOOL animate){
    if(!oldMiniFrame||!canCompact(v))return;
    CGRect f=v.frame;
    NSValue *saved=objc_getAssociatedObject(v,&normalFrameKey);
    if(normalFrame(f,v)){saved=[NSValue valueWithCGRect:f];objc_setAssociatedObject(v,&normalFrameKey,saved,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
    if(!saved)return;
    CGRect normal=saved.CGRectValue;
    if(!normalFrame(normal,v))return;
    CGRect target=compact?compactFrame(normal,v):normal;
    objc_setAssociatedObject(v,&foldKey,@(compact),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if(compact)objc_setAssociatedObject(v,&compactFrameKey,[NSValue valueWithCGRect:target],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    BOOL docked=compact&&dockGeometry(v,currentPivot,NULL,NULL);
    NSArray *corner=objc_getAssociatedObject(v,&miniCornerKey);
    if(compact&&!corner){corner=@[@(v.layer.cornerRadius),@(v.clipsToBounds)];objc_setAssociatedObject(v,&miniCornerKey,corner,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
    void (^change)(void)=^{
        applyingFrame=YES;@try{
            if(!CGRectEqualToRect(v.frame,target))nativeSetFrame(v,target);
            if(compact){v.layer.cornerCurve=kCACornerCurveContinuous;v.layer.cornerRadius=docked?MIN(19,target.size.height*.36):14;v.clipsToBounds=YES;}
            else if(corner){v.layer.cornerRadius=[corner[0] doubleValue];v.clipsToBounds=[corner[1] boolValue];objc_setAssociatedObject(v,&miniCornerKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
            [v setNeedsLayout];
            UIView *bar=currentPivot;if(bar){[bar setNeedsLayout];[bar layoutIfNeeded];}
        }@finally{applyingFrame=NO;}
    };
    if(animate&&!UIAccessibilityIsReduceMotionEnabled())[UIView animateWithDuration:.33 delay:0 usingSpringWithDamping:.82 initialSpringVelocity:0 options:UIViewAnimationOptionBeginFromCurrentState|UIViewAnimationOptionAllowUserInteraction animations:change completion:nil];else change();
}
static void observeMini(UIView *v){
    if(!canCompact(v))return;
    currentMini=v;
    if(!objc_getAssociatedObject(v,&foldKey)){
        // Begin expanded; an upward scroll folds the combined bottom row.
        if(!normalFrame(v.frame,v))return;
        objc_setAssociatedObject(v,&normalFrameKey,[NSValue valueWithCGRect:v.frame],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(v,&foldKey,@NO,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }else if([objc_getAssociatedObject(v,&foldKey) boolValue]&&normalFrame(v.frame,v)&&!applyingFrame){
        applyCompact(v,YES,NO);
    }
}
static void miniLayout(UIView *v,SEL s){
    ((void(*)(id,SEL))oldMiniLayout)(v,s);
    if(!applyingFrame&&canCompact(v)){
        currentMini=v;
        if(!objc_getAssociatedObject(v,&foldKey)||([objc_getAssociatedObject(v,&foldKey) boolValue]&&normalFrame(v.frame,v))){
            __weak UIView *weakV=v;dispatch_async(dispatch_get_main_queue(),^{observeMini(weakV);});
        }
    }
}
static void miniMove(UIView *v,SEL s){
    ((void(*)(id,SEL))oldMiniMove)(v,s);
    if(v.window){
        __weak UIView *weakV=v;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.45*NSEC_PER_SEC)),dispatch_get_main_queue(),^{observeMini(weakV);});
    }else{
        if(currentMini==v){currentMini=nil;[currentPivot setNeedsLayout];}
        objc_setAssociatedObject(v,&foldKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(v,&normalFrameKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSArray *corner=objc_getAssociatedObject(v,&miniCornerKey);if(corner){v.layer.cornerRadius=[corner[0] doubleValue];v.clipsToBounds=[corner[1] boolValue];objc_setAssociatedObject(v,&miniCornerKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
    }
}
static void layerLayout(UIView *v,SEL s){
    ((void(*)(id,SEL))oldLayerLayout)(v,s);
    UIView *mini=view(v,@"watchFloatingMiniplayerView");
    Class c=NSClassFromString(@"YTWatchFloatingMiniplayerWithPersistentControlsView");
    if(c&&[mini isKindOfClass:c]&&!applyingFrame)observeMini(mini);
}
static void requestFold(BOOL compact){
    UIView *mini=currentMini;
    if(!canCompact(mini))return;
    if(CACurrentMediaTime()-lastFoldAction<.30)return;
    lastFoldAction=CACurrentMediaTime();
    if([objc_getAssociatedObject(mini,&foldKey) boolValue]==compact)return;
    applyCompact(mini,compact,YES);
}
@interface LEMGlass23Vertical : NSObject<UIGestureRecognizerDelegate>
@property(nonatomic,weak) UIWindow *window;
@property(nonatomic) BOOL consumed;
- (void)pan:(UIPanGestureRecognizer *)g;
@end
@implementation LEMGlass23Vertical
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)touch{
    if(!canCompact(currentMini)||currentMini.window!=self.window)return NO;
    UIView *v=touch.view;
    if(v==currentMini||[v isDescendantOfView:currentMini])return NO;
    if(v==currentPivot||[v isDescendantOfView:currentPivot])return YES;
    for(UIView *p=v;p;p=p.superview){
        if([p isKindOfClass:UIScrollView.class]){
            UIScrollView *scroll=(UIScrollView *)p;
            if(scroll.bounds.size.height>220&&scroll.contentSize.height>scroll.bounds.size.height+45)return YES;
        }
    }
    return NO;
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g{
    CGPoint p=[(UIPanGestureRecognizer *)g velocityInView:self.window];return fabs(p.y)>fabs(p.x)*1.5;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other{return YES;}
- (void)pan:(UIPanGestureRecognizer *)g{
    if(g.state==UIGestureRecognizerStateBegan)self.consumed=NO;
    if((g.state==UIGestureRecognizerStateBegan||g.state==UIGestureRecognizerStateChanged||g.state==UIGestureRecognizerStateEnded)&&!self.consumed){
        CGPoint d=[g translationInView:self.window];
        if(fabs(d.y)>34&&fabs(d.y)>fabs(d.x)*1.5){self.consumed=YES;requestFold(d.y<0);}
    }
}
@end
static void installVertical(UIView *host){
    UIWindow *w=host.window;
    if(!w||objc_getAssociatedObject(w,&verticalKey))return;
    LEMGlass23Vertical *d=[LEMGlass23Vertical new];d.window=w;
    UIPanGestureRecognizer *g=[[UIPanGestureRecognizer alloc] initWithTarget:d action:@selector(pan:)];g.delegate=d;g.maximumNumberOfTouches=1;g.cancelsTouchesInView=NO;g.delaysTouchesBegan=NO;g.delaysTouchesEnded=NO;
    [w addGestureRecognizer:g];objc_setAssociatedObject(w,&verticalKey,d,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
// Motion is decorative only: the original thumbnail tap opens the native player.
@interface LEMGlass23Motion : NSObject<UIGestureRecognizerDelegate>
@property(nonatomic,weak) UIWindow *window;
@property(nonatomic,strong) UIImage *art;
@property(nonatomic,strong) UIColor *accent;
@property(nonatomic) CGRect origin;
@property(nonatomic) CFTimeInterval captured;
@property(nonatomic,weak) UIViewController *watch;
@property(nonatomic,weak) UIView *flying;
- (void)tap:(UITapGestureRecognizer *)g;
@end
static UIColor *artAccent(UIImage *image){
    CGImageRef im=image.CGImage;if(!im)return nil;
    unsigned char data[16*16*4]={0};CGColorSpaceRef cs=CGColorSpaceCreateDeviceRGB();
    CGContextRef c=CGBitmapContextCreate(data,16,16,8,16*4,cs,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);CGColorSpaceRelease(cs);
    if(!c)return nil;CGContextDrawImage(c,CGRectMake(0,0,16,16),im);CGContextRelease(c);
    double r=0,g=0,b=0,total=0;
    for(int i=0;i<256;i++){double x=data[i*4]/255.,y=data[i*4+1]/255.,z=data[i*4+2]/255.;double hi=fmax(x,fmax(y,z)),lo=fmin(x,fmin(y,z)),l=(x+y+z)/3;
        if(data[i*4+3]<210||l<.06||l>.94)continue;double weight=.3+(hi-lo)*2.;r+=x*weight;g+=y*weight;b+=z*weight;total+=weight;}
    if(total<1)return nil;
    return [UIColor colorWithRed:MIN(1,r/total*1.2) green:MIN(1,g/total*1.2) blue:MIN(1,b/total*1.2) alpha:1];
}
static UIImageView *thumbnailAt(UIView *root,CGPoint point,UIWindow *window,NSUInteger depth){
    if(!root||root.hidden||root.alpha<.1||depth>8)return nil;
    CGRect f=[root convertRect:root.bounds toView:window];
    if(!CGRectContainsPoint(f,point))return nil;
    if([root isKindOfClass:UIImageView.class]&&f.size.width>=140&&f.size.height>=75&&f.size.width/f.size.height>1.2&&f.size.width/f.size.height<2.7&&((UIImageView *)root).image)return (UIImageView *)root;
    for(UIView *child in root.subviews.reverseObjectEnumerator){UIImageView *im=thumbnailAt(child,point,window,depth+1);if(im)return im;}
    return nil;
}
@implementation LEMGlass23Motion
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other{return YES;}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)touch{
    self.art=nil;self.captured=0;
    if(!visible(currentPivot)||currentPivot.window!=self.window||economy()||(!studioMorph&&!studioAmbient))return NO;
    UIView *v=touch.view;
    if([v isDescendantOfView:currentPivot]||[v isDescendantOfView:currentMini])return NO;
    UIView *cell=nil;
    for(UIView *p=v;p&&p!=self.window;p=p.superview){
        if([p isKindOfClass:UICollectionViewCell.class]||[p isKindOfClass:UITableViewCell.class]){cell=p;break;}
    }
    if(!cell)return NO;
    CGPoint pt=[touch locationInView:self.window];UIImageView *im=thumbnailAt(cell,pt,self.window,0);
    if(!im)return NO;
    self.art=im.image;self.origin=[im convertRect:im.bounds toView:self.window];return YES;
}
- (void)tap:(UITapGestureRecognizer *)g{
    if(g.state==UIGestureRecognizerStateRecognized&&self.art){self.captured=CACurrentMediaTime();self.accent=artAccent(self.art);}
}
@end
static void installMotion(UIWindow *w){
    if(!w||objc_getAssociatedObject(w,&motionKey))return;
    LEMGlass23Motion *d=[LEMGlass23Motion new];d.window=w;
    UITapGestureRecognizer *g=[[UITapGestureRecognizer alloc] initWithTarget:d action:@selector(tap:)];g.delegate=d;g.cancelsTouchesInView=NO;g.delaysTouchesBegan=NO;g.delaysTouchesEnded=NO;
    [w addGestureRecognizer:g];objc_setAssociatedObject(w,&motionKey,d,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
@interface LEMGlass23Ambient : UIView
@property(nonatomic,strong) CAGradientLayer *glow;
@end
@implementation LEMGlass23Ambient
- (instancetype)initWithFrame:(CGRect)f{
    if((self=[super initWithFrame:f])){self.userInteractionEnabled=NO;self.opaque=NO;self.backgroundColor=UIColor.clearColor;self.glow=[CAGradientLayer layer];self.glow.startPoint=CGPointMake(.5,0);self.glow.endPoint=CGPointMake(.5,1);[self.layer addSublayer:self.glow];}return self;
}
- (void)layoutSubviews{[super layoutSubviews];self.glow.frame=self.bounds;}
@end
static void watchMotion(UIViewController *vc){
    UIView *v=vc.viewIfLoaded;UIWindow *w=v.window;if(!visible(v)||!w)return;
    LEMGlass23Motion *d=objc_getAssociatedObject(w,&motionKey);if(!d)return;
    CGRect target=[v convertRect:v.bounds toView:w];
    if(target.size.width<w.bounds.size.width*.80||target.size.height<110||target.size.height>320||target.size.width/target.size.height<1.15||CGRectGetMinY(target)>w.bounds.size.height*.48)return;
    if(d.art&&d.captured>0&&CACurrentMediaTime()-d.captured<1.6&&!d.flying){
        UIImage *art=d.art;CGRect from=d.origin;d.art=nil;d.captured=0;d.watch=vc;
        if(studioMorph&&!economy()&&!UIAccessibilityIsReduceMotionEnabled()&&!CGRectIsEmpty(from)&&!CGRectIsEmpty(CGRectIntersection(from,w.bounds))){
            UIImageView *ghost=[[UIImageView alloc] initWithImage:art];ghost.frame=from;ghost.contentMode=UIViewContentModeScaleAspectFill;ghost.clipsToBounds=YES;ghost.userInteractionEnabled=NO;ghost.layer.cornerRadius=9;ghost.accessibilityElementsHidden=YES;[w addSubview:ghost];d.flying=ghost;
            [UIView animateWithDuration:.30 delay:0 usingSpringWithDamping:.87 initialSpringVelocity:.2 options:UIViewAnimationOptionAllowUserInteraction|UIViewAnimationOptionBeginFromCurrentState animations:^{ghost.frame=target;ghost.layer.cornerRadius=0;} completion:^(BOOL finished){
                [UIView animateWithDuration:.13 animations:^{ghost.alpha=0;} completion:^(BOOL done){[ghost removeFromSuperview];}];
            }];
        }
    }
    // A subtle ambient band outside the player, not a filter over video frames.
    // Use only the color of the thumbnail that opened this specific watch view.
    if(!studioAmbient||economy()||d.watch!=vc||!d.accent||!v.superview||UIAccessibilityIsReduceTransparencyEnabled()){[objc_getAssociatedObject(vc,&ambientKey) removeFromSuperview];return;}
    UIView *parent=v.superview;CGRect span=[v convertRect:v.bounds toView:parent];CGFloat room=CGRectGetMaxY(parent.bounds)-CGRectGetMaxY(span);
    LEMGlass23Ambient *band=objc_getAssociatedObject(vc,&ambientKey);
    if(room<25){[band removeFromSuperview];return;}
    CGRect area=CGRectMake(span.origin.x,CGRectGetMaxY(span),span.size.width,MIN(75,room));
    if(!band){band=[[LEMGlass23Ambient alloc] initWithFrame:area];objc_setAssociatedObject(vc,&ambientKey,band,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
    band.frame=area;band.glow.colors=@[(id)[d.accent colorWithAlphaComponent:.33].CGColor,(id)[d.accent colorWithAlphaComponent:.10].CGColor,(id)[d.accent colorWithAlphaComponent:0].CGColor];band.glow.locations=@[@0,@.4,@1];
    if(band.superview!=parent)[parent addSubview:band];
}
static void watchLayout(UIViewController *vc,SEL sel){((void(*)(id,SEL))oldWatchLayout)(vc,sel);@try{watchMotion(vc);}@catch(NSException *e){NSLog(@"[LEM Glass] motion: %@",e.reason);}}
static void watchDisappear(UIViewController *vc,SEL sel,BOOL animated){
    ((void(*)(id,SEL,BOOL))oldWatchDisappear)(vc,sel,animated);
    [objc_getAssociatedObject(vc,&ambientKey) removeFromSuperview];objc_setAssociatedObject(vc,&ambientKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    LEMGlass23Motion *d=objc_getAssociatedObject(vc.viewIfLoaded.window,&motionKey);if(d.watch==vc){d.watch=nil;d.accent=nil;[d.flying removeFromSuperview];}
}
// Glass Search: target the real editable field, independently of private search-box class.
static NSHashTable<UITextField *> *studioSearchFields;
@interface LEMGlass23SearchPlate : UIView
@property(nonatomic,strong) UIVisualEffectView *blur;
@property(nonatomic,strong) CAGradientLayer *shine;
- (void)style;
@end
@implementation LEMGlass23SearchPlate
- (instancetype)initWithFrame:(CGRect)f{
    if((self=[super initWithFrame:f])){
        self.userInteractionEnabled=NO;self.accessibilityElementsHidden=YES;self.opaque=NO;self.layer.masksToBounds=YES;self.layer.cornerCurve=kCACornerCurveContinuous;
        self.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        self.blur=[[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial]];
        self.blur.userInteractionEnabled=NO;self.blur.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;[self addSubview:self.blur];
        self.shine=[CAGradientLayer layer];self.shine.startPoint=CGPointMake(.15,0);self.shine.endPoint=CGPointMake(.85,1);self.shine.locations=@[@0,@.21,@.62,@1];[self.layer addSublayer:self.shine];
        [self style];
    }return self;
}
- (void)style{
    BOOL dark=self.traitCollection.userInterfaceStyle!=UIUserInterfaceStyleLight;
    self.blur.alpha=MIN(.94,.35+studioBlur*.021+studioTint*.5);
    self.backgroundColor=[(dark?UIColor.whiteColor:UIColor.blackColor) colorWithAlphaComponent:dark?.055: .035];
    CGFloat highlight=MIN(.36,.16+studioTint*.18);
    self.shine.colors=dark?@[(id)[UIColor colorWithWhite:1 alpha:highlight].CGColor,(id)[UIColor colorWithWhite:1 alpha:.065].CGColor,(id)[UIColor colorWithWhite:1 alpha:.015].CGColor,(id)[UIColor colorWithWhite:1 alpha:.10].CGColor]:@[(id)[UIColor colorWithWhite:1 alpha:.7].CGColor,(id)[UIColor colorWithWhite:1 alpha:.35].CGColor,(id)[UIColor colorWithWhite:1 alpha:.10].CGColor,(id)[UIColor colorWithWhite:1 alpha:.35].CGColor];
    if(UIAccessibilityIsReduceTransparencyEnabled()){self.blur.alpha=0;self.backgroundColor=UIColor.secondarySystemBackgroundColor;self.shine.hidden=YES;}else self.shine.hidden=NO;
}
- (void)layoutSubviews{[super layoutSubviews];[CATransaction begin];[CATransaction setDisableActions:YES];self.layer.cornerRadius=self.bounds.size.height*.5;self.blur.frame=self.bounds;self.shine.frame=self.bounds;[CATransaction commit];}
- (void)traitCollectionDidChange:(UITraitCollection *)old{[super traitCollectionDidChange:old];[self style];}
@end
static BOOL isSearchField(UITextField *field){
    if(![field isKindOfClass:UITextField.class]||!field.window||field.secureTextEntry)return NO;
    CGRect f=[field convertRect:field.bounds toView:field.window];CGRect w=field.window.bounds;
    if(f.size.width<w.size.width*.38||f.size.height<24||f.size.height>76||CGRectGetMinY(f)>w.size.height*.28)return NO;
    NSString *hint=(field.placeholder?:field.attributedPlaceholder.string?:@"").lowercaseString;
    if([hint containsString:@"youtube"]&&([hint containsString:@"search"]||[hint containsString:@"tìm"]))return YES;
    for(UIView *v=field;v&&v!=field.window;v=v.superview){
        NSString *n=NSStringFromClass(v.class).lowercaseString;
        if([n hasPrefix:@"yt"]&&([n containsString:@"searchbox"]||[n containsString:@"searchfield"]||[n containsString:@"searchbar"]||[n containsString:@"searchtext"]))return YES;
    }
    for(UIResponder *v=field.nextResponder;v&&v!=field.window;v=v.nextResponder){
        NSString *n=NSStringFromClass(v.class).lowercaseString;
        if([n hasPrefix:@"yt"]&&[n containsString:@"search"]&&![n containsString:@"setting"])return YES;
    }
    return NO;
}
static void restoreSearch(UITextField *field){
    NSDictionary *state=objc_getAssociatedObject(field,&searchStateKey);
    [objc_getAssociatedObject(field,&searchPlateKey) removeFromSuperview];objc_setAssociatedObject(field,&searchPlateKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if(!state)return;
    id color=state[@"color"],image=state[@"image"];
    field.backgroundColor=color==NSNull.null?nil:color;field.background=image==NSNull.null?nil:image;
    field.borderStyle=[state[@"border"] integerValue];
    for(NSArray *entry in state[@"views"]){UIView *v=entry[0];if([v isDescendantOfView:field])v.hidden=[entry[1] boolValue];}
    objc_setAssociatedObject(field,&searchStateKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(field,&searchAnimKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void applySearch(UITextField *field,BOOL animate){
    if(!studioSearch){restoreSearch(field);return;}
    if(!isSearchField(field))return;
    [studioSearchFields addObject:field];
    NSMutableDictionary *state=objc_getAssociatedObject(field,&searchStateKey);
    if(!state){state=[@{@"color":field.backgroundColor?:NSNull.null,@"image":field.background?:NSNull.null,@"border":@(field.borderStyle),@"views":[NSMutableArray array]} mutableCopy];objc_setAssociatedObject(field,&searchStateKey,state,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
    // Do not replace UITextField, its delegate, left/right buttons, or editing state.
    field.backgroundColor=UIColor.clearColor;field.background=nil;
    // Keep native borderStyle so text rect/insets remain unchanged.
    LEMGlass23SearchPlate *plate=objc_getAssociatedObject(field,&searchPlateKey);
    if(!plate){plate=[[LEMGlass23SearchPlate alloc] initWithFrame:field.bounds];objc_setAssociatedObject(field,&searchPlateKey,plate,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
    NSMutableArray *saved=state[@"views"];
    for(UIView *v in [field.subviews copy]){
        if(v==plate||v==field.leftView||v==field.rightView||v.hidden||v.userInteractionEnabled)continue;
        NSString *n=NSStringFromClass(v.class).lowercaseString;
        if(v.bounds.size.width<field.bounds.size.width*.9||v.bounds.size.height<field.bounds.size.height*.8)continue;
        if([v isKindOfClass:UIImageView.class]||[n containsString:@"background"]){
            BOOL known=NO;for(NSArray *entry in saved)if(entry[0]==v){known=YES;break;}
            if(!known)[saved addObject:@[v,@(v.hidden)]];v.hidden=YES;
        }
    }
    if(plate.superview!=field)[field insertSubview:plate atIndex:0];else if(field.subviews.firstObject!=plate)[field sendSubviewToBack:plate];
    plate.frame=field.bounds;[plate style];
    if(animate&&!objc_getAssociatedObject(field,&searchAnimKey)&&!economy()&&!UIAccessibilityIsReduceMotionEnabled()){
        objc_setAssociatedObject(field,&searchAnimKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        CABasicAnimation *a=[CABasicAnimation animationWithKeyPath:@"transform.scale.x"];a.fromValue=@.84;a.toValue=@1;a.duration=.30;a.timingFunction=[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];[plate.layer addAnimation:a forKey:@"lem.search.open"];
    }
}
static void searchTree(UIView *v,NSUInteger depth){
    if(!v||depth>5)return;
    if([v isKindOfClass:UITextField.class]){applySearch((UITextField *)v,YES);return;}
    for(UIView *child in [v.subviews copy])searchTree(child,depth+1);
}
static void searchLayout(UIView *v,SEL sel){
    ((void(*)(id,SEL))oldSearchLayout)(v,sel);
    @try{searchTree(v,0);}@catch(NSException *e){NSLog(@"[LEM Glass] search layout: %@",e.reason);}
}
static void installSearchObserver(void){
    studioSearchFields=[NSHashTable weakObjectsHashTable];
    [NSNotificationCenter.defaultCenter addObserverForName:UITextFieldTextDidBeginEditingNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){
        if(![note.object isKindOfClass:UITextField.class])return;
        __weak UITextField *weak=note.object;
        @try{applySearch(weak,YES);}@catch(NSException *e){}
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(.20*NSEC_PER_SEC)),dispatch_get_main_queue(),^{UITextField *f=weak;if(f.isFirstResponder)@try{applySearch(f,YES);}@catch(NSException *e){}});
    }];
    [NSNotificationCenter.defaultCenter addObserverForName:UITextFieldTextDidEndEditingNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){
        if([note.object isKindOfClass:UITextField.class])objc_setAssociatedObject(note.object,&searchAnimKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }];
}
// Full Glass UI: scoped cosmetic modules, no replacement of native actions or data.
typedef NS_ENUM(NSInteger, LEMFullModule){LEMChips,LEMPlayer,LEMActions,LEMMenus,LEMInfo,LEMComments,LEMSeek};
static NSHashTable<UIView *> *fullHosts;
static NSUInteger moduleHooks[7],moduleSeen[7];
@interface LEMGlass23Chrome : UIView
@property(nonatomic,strong) UIVisualEffectView *material;
@property(nonatomic,strong) CAGradientLayer *shine;
@property(nonatomic) NSInteger module;
@property(nonatomic) BOOL selectedChip;
@property(nonatomic) BOOL shadeOnly;
- (void)updateStyle;
@end
@implementation LEMGlass23Chrome
- (instancetype)initWithFrame:(CGRect)f{
    if((self=[super initWithFrame:f])){
        self.userInteractionEnabled=NO;self.accessibilityElementsHidden=YES;self.opaque=NO;self.backgroundColor=UIColor.clearColor;self.layer.cornerCurve=kCACornerCurveContinuous;self.clipsToBounds=YES;
        self.material=[[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial]];
        self.material.userInteractionEnabled=NO;self.material.backgroundColor=UIColor.clearColor;[self addSubview:self.material];
        self.shine=[CAGradientLayer layer];self.shine.startPoint=CGPointMake(.15,0);self.shine.endPoint=CGPointMake(.8,1);self.shine.locations=@[@0,@.36,@.72,@1];[self.layer addSublayer:self.shine];
    }return self;
}
- (void)updateStyle{
    BOOL dark=self.traitCollection.userInterfaceStyle!=UIUserInterfaceStyleLight;
    BOOL panel=self.module==LEMMenus||self.module==LEMInfo||self.module==LEMComments;
    CGFloat h=self.bounds.size.height,w=self.bounds.size.width;
    self.layer.cornerRadius=panel?MIN(23,MIN(h,w)*.19):MIN(h,w)*.5;
    BOOL reduce=UIAccessibilityIsReduceTransparencyEnabled();
    self.material.hidden=self.shadeOnly||self.selectedChip||reduce;
    self.material.alpha=self.module==LEMMenus?(economy()?.66:.94):economy()?.32:MIN(.86,.28+studioBlur*.024+studioTint*.48);
    self.backgroundColor=(self.shadeOnly||self.selectedChip)?UIColor.clearColor:reduce?UIColor.secondarySystemBackgroundColor:[(dark?UIColor.blackColor:UIColor.whiteColor) colorWithAlphaComponent:self.module==LEMMenus?.38:.035];
    CGFloat l=MIN(.25,.095+studioTint*.27),b=MIN(.17,.04+studioTint*.18);
    if(self.selectedChip){l=.13;b=.04;}
    if(self.shadeOnly){l*=.65;b*=.65;}
    self.shine.colors=dark||self.selectedChip?@[(id)[UIColor colorWithWhite:1 alpha:l].CGColor,(id)[UIColor colorWithWhite:1 alpha:.025].CGColor,(id)[UIColor colorWithWhite:1 alpha:0].CGColor,(id)[UIColor colorWithWhite:1 alpha:b].CGColor]:@[(id)[UIColor colorWithWhite:1 alpha:.30].CGColor,(id)[UIColor colorWithWhite:1 alpha:.06].CGColor,(id)[UIColor colorWithWhite:0 alpha:0].CGColor,(id)[UIColor colorWithWhite:0 alpha:.035].CGColor];
    self.shine.hidden=reduce;
}
- (void)layoutSubviews{[super layoutSubviews];[CATransaction begin];[CATransaction setDisableActions:YES];self.material.frame=self.bounds;self.shine.frame=self.bounds;[self updateStyle];[CATransaction commit];}
@end
static void removeFull(UIView *v){
    LEMGlass23Chrome *plate=objc_getAssociatedObject(v,&fullPlateKey);
    NSDictionary *state=objc_getAssociatedObject(v,&fullStateKey);
    if(plate)[plate removeFromSuperview];objc_setAssociatedObject(v,&fullPlateKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if(state){
        id color=state[@"color"];if(v.backgroundColor==nil||CGColorGetAlpha(v.backgroundColor.CGColor)<.005)v.backgroundColor=color==NSNull.null?nil:color;
        v.opaque=[state[@"opaque"] boolValue];
        objc_setAssociatedObject(v,&fullStateKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}
static BOOL ancestorMatches(UIView *v,NSArray<NSString *> *names){
    for(UIView *p=v;p&&p!=v.window;p=p.superview){
        for(NSString *n in names){Class c=NSClassFromString(n);if(c&&[p isKindOfClass:c])return YES;}
    }return NO;
}
static BOOL fullGeometry(UIView *v,NSInteger module){
    if(!visible(v)||[v isKindOfClass:UITextField.class]||[v isKindOfClass:UITextView.class]||[v isKindOfClass:UIImageView.class])return NO;
    CGSize z=v.bounds.size;CGFloat ww=v.window.bounds.size.width,wh=v.window.bounds.size.height;
    if(!isfinite(z.width)||!isfinite(z.height)||z.width<22||z.height<22)return NO;
    if(module==LEMChips)return z.width<=ww*.85&&z.height<=65;
    if(module==LEMPlayer)return z.width<=110&&z.height<=110&&ancestorMatches(v,@[@"YTMainAppVideoPlayerOverlayView",@"YTWatchFloatingMiniplayerWithPersistentControlsView"]);
    if(module==LEMActions)return z.height<=84&&z.width<=ww*.95;
    if(module==LEMMenus)return z.width>=ww*.38&&z.width<=ww+1&&z.height>=40&&z.height<wh*.90;
    return z.width>=ww*.5&&z.width<=ww+1&&z.height<=220;
}
static void fullApply(UIView *v,NSInteger module,BOOL shadeOnly){
    if(!v||module<0||module>5)return;
    if(!studioModules[module]||!fullGeometry(v,module)){if(objc_getAssociatedObject(v,&fullPlateKey))removeFull(v);return;}
    LEMGlass23Chrome *plate=objc_getAssociatedObject(v,&fullPlateKey);
    if(plate&&plate.module!=module)return; // one material per host
    BOOL activeChip=module==LEMChips&&selected(v);
    if(module==LEMChips&&!activeChip){
        CGFloat white=0,alpha=0;
        UIColor *color=[v.backgroundColor resolvedColorWithTraitCollection:v.traitCollection];
        if([color getWhite:&white alpha:&alpha]&&white>.78&&alpha>.7)activeChip=YES;
    }
    // Preserve selected chip contrast and any native panel backgrounds. Only clear
    // a compact, non-selected host's own fill, not its children or controls.
    BOOL preserve=shadeOnly||activeChip||module==LEMInfo||module==LEMComments;
    NSDictionary *saved=objc_getAssociatedObject(v,&fullStateKey);
    if(!preserve){
        UIColor *bg=v.backgroundColor;
        if(!saved|| (bg&&CGColorGetAlpha(bg.CGColor)>.005)){
            saved=@{@"color":bg?:NSNull.null,@"opaque":@(saved?[saved[@"opaque"] boolValue]:v.opaque)};
            objc_setAssociatedObject(v,&fullStateKey,saved,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if(bg&&CGColorGetAlpha(bg.CGColor)>.005)v.backgroundColor=UIColor.clearColor;
        v.opaque=NO;
    }else if(saved){
        id c=saved[@"color"];if(!v.backgroundColor||CGColorGetAlpha(v.backgroundColor.CGColor)<.005)v.backgroundColor=c==NSNull.null?nil:c;
        v.opaque=[saved[@"opaque"] boolValue];objc_setAssociatedObject(v,&fullStateKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if(!plate){
        plate=[[LEMGlass23Chrome alloc] initWithFrame:v.bounds];plate.module=module;objc_setAssociatedObject(v,&fullPlateKey,plate,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [fullHosts addObject:v];moduleSeen[module]++;
    }
    plate.selectedChip=activeChip;plate.shadeOnly=preserve&&!activeChip;
    CGRect rect=CGRectInset(v.bounds,module==LEMInfo||module==LEMComments?3:0,module==LEMInfo||module==LEMComments?2:0);
    if(!CGRectEqualToRect(plate.frame,rect))plate.frame=rect;
    // Native labels, video and button hit regions always remain untouched.
    if(preserve){
        if(plate.superview!=v)[v addSubview:plate];else if(v.subviews.lastObject!=plate)[v bringSubviewToFront:plate];
    }else if(plate.superview!=v)[v insertSubview:plate atIndex:0];else if(v.subviews.firstObject!=plate)[v sendSubviewToBack:plate];
    [plate updateStyle];
}
static void fullViewHook(NSString *name,NSInteger module,BOOL shade){
    Class c=NSClassFromString(name);SEL sel=@selector(layoutSubviews);
    if(!c||![c isSubclassOfClass:UIView.class])return;
    Method m=class_getInstanceMethod(c,sel);char rt[8]={0};
    if(!m||method_getNumberOfArguments(m)!=2)return;method_getReturnType(m,rt,sizeof rt);if(rt[0]!='v')return;
    IMP orig=method_getImplementation(m);
    IMP impl=imp_implementationWithBlock(^(UIView *v){((void(*)(id,SEL))orig)(v,sel);@try{fullApply(v,module,shade);}@catch(NSException *e){NSLog(@"[LEM Full] %@: %@",name,e.reason);}});
    class_replaceMethod(c,sel,impl,method_getTypeEncoding(m));moduleHooks[module]++;
}
static void decorateActionButtons(UIView *root,NSUInteger depth){
    if(!root||depth>4)return;
    for(UIView *v in [root.subviews copy]){
        if([v isKindOfClass:LEMGlass23Chrome.class])continue;
        if([v isKindOfClass:UIControl.class]&&v.bounds.size.width>=24&&v.bounds.size.height>=24&&v.bounds.size.width<=210&&v.bounds.size.height<=74){fullApply(v,LEMActions,NO);continue;}
        decorateActionButtons(v,depth+1);
    }
}
static void fullActionContainer(NSString *name){
    Class c=NSClassFromString(name);SEL sel=@selector(layoutSubviews);Method m=c?class_getInstanceMethod(c,sel):NULL;char rt[8]={0};
    if(!c||![c isSubclassOfClass:UIView.class]||!m||method_getNumberOfArguments(m)!=2)return;method_getReturnType(m,rt,sizeof rt);if(rt[0]!='v')return;
    IMP orig=method_getImplementation(m);IMP impl=imp_implementationWithBlock(^(UIView *v){((void(*)(id,SEL))orig)(v,sel);@try{decorateActionButtons(v,0);}@catch(NSException *e){}});
    class_replaceMethod(c,sel,impl,method_getTypeEncoding(m));moduleHooks[LEMActions]++;
}
// Select a single menu panel. Never decorate the entire modal root or scrim.
static UIView *sheetCandidate(UIView *root,NSUInteger depth){
    if(!root||depth>5||root.hidden||root.alpha<.1||[root isKindOfClass:UILabel.class]||[root isKindOfClass:UIControl.class]||[root isKindOfClass:UIImageView.class]||[root isKindOfClass:LEMGlass23Chrome.class]||[root isKindOfClass:UIVisualEffectView.class])return nil;
    UIColor *c=[root.backgroundColor resolvedColorWithTraitCollection:root.traitCollection];
    CGRect f=[root convertRect:root.bounds toView:root.window];
    BOOL lower=CGRectGetMinY(f)>root.window.bounds.size.height*.18;
    if(fullGeometry(root,LEMMenus)&&lower&&((c&&CGColorGetAlpha(c.CGColor)>.45)||objc_getAssociatedObject(root,&fullPlateKey))&&root.subviews.count)return root;
    for(UIView *child in [root.subviews reverseObjectEnumerator]){UIView *found=sheetCandidate(child,depth+1);if(found)return found;}
    return nil;
}
static void sheetTree(UIView *v,NSUInteger depth){
    UIView *panel=sheetCandidate(v,depth);if(!panel||!studioModules[LEMMenus])return;
    for(UIView *p=panel.superview;p&&p!=panel.window;p=p.superview){LEMGlass23Chrome *other=objc_getAssociatedObject(p,&fullPlateKey);if(other&&other.module==LEMMenus)return;}
    for(UIView *p in fullHosts.allObjects){LEMGlass23Chrome *other=objc_getAssociatedObject(p,&fullPlateKey);if(p!=panel&&other&&other.module==LEMMenus&&[p isDescendantOfView:panel])removeFull(p);}
    BOOL first=objc_getAssociatedObject(panel,&fullPlateKey)==nil;
    fullApply(panel,LEMMenus,NO);
    LEMGlass23Chrome *plate=objc_getAssociatedObject(panel,&fullPlateKey);
    if(first&&plate&&!economy()&&!UIAccessibilityIsReduceMotionEnabled()){
        CABasicAnimation *fade=[CABasicAnimation animationWithKeyPath:@"opacity"];fade.fromValue=@.45;fade.toValue=@1;fade.duration=.23;[plate.layer addAnimation:fade forKey:@"lem.menu.fade"];
    }
}
static void fullSheetHook(NSString *name){
    Class c=NSClassFromString(name);SEL sel=@selector(viewDidLayoutSubviews);
    if(!c||![c isSubclassOfClass:UIViewController.class])return;
    Method m=class_getInstanceMethod(c,sel);char rt[8]={0};if(!m||method_getNumberOfArguments(m)!=2)return;method_getReturnType(m,rt,sizeof rt);if(rt[0]!='v')return;
    IMP orig=method_getImplementation(m);
    IMP impl=imp_implementationWithBlock(^(UIViewController *vc){((void(*)(id,SEL))orig)(vc,sel);@try{if(studioModules[LEMMenus]&&vc.viewIfLoaded.window)sheetTree(vc.viewIfLoaded,0);}@catch(NSException *e){}});
    class_replaceMethod(c,sel,impl,method_getTypeEncoding(m));moduleHooks[LEMMenus]++;
}
static void fullSheetView(NSString *name){
    Class c=NSClassFromString(name);SEL sel=@selector(layoutSubviews);Method m=c?class_getInstanceMethod(c,sel):NULL;char rt[8]={0};
    if(!c||![c isSubclassOfClass:UIView.class]||!m||method_getNumberOfArguments(m)!=2)return;method_getReturnType(m,rt,sizeof rt);if(rt[0]!='v')return;
    IMP orig=method_getImplementation(m);IMP impl=imp_implementationWithBlock(^(UIView *v){((void(*)(id,SEL))orig)(v,sel);@try{sheetTree(v,0);}@catch(NSException *e){}});
    class_replaceMethod(c,sel,impl,method_getTypeEncoding(m));moduleHooks[LEMMenus]++;
}
// Cosmetic feedback only; the native player retains all seek actions.
@interface LEMGlass23Seek : NSObject<UIGestureRecognizerDelegate>
@property(nonatomic,weak) UIView *host;
@property(nonatomic,strong) UIView *bubble;
@property(nonatomic,strong) UILongPressGestureRecognizer *gesture;
- (void)touch:(UILongPressGestureRecognizer *)g;
@end
@implementation LEMGlass23Seek
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)g{return studioModules[LEMSeek]&&visible(self.host)&&!UIAccessibilityIsReduceMotionEnabled()&&!economy();}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other{return YES;}
- (void)touch:(UILongPressGestureRecognizer *)g{
    UIView *v=self.host;UIWindow *w=v.window;
    if(!studioModules[LEMSeek]||!w||g.state==UIGestureRecognizerStateEnded||g.state==UIGestureRecognizerStateCancelled||g.state==UIGestureRecognizerStateFailed){
        UIView *bubble=self.bubble;self.bubble=nil;
        [UIView animateWithDuration:.16 animations:^{bubble.alpha=0;bubble.transform=CGAffineTransformMakeScale(.5,.5);} completion:^(BOOL ok){[bubble removeFromSuperview];}];return;
    }
    if(g.state!=UIGestureRecognizerStateBegan&&g.state!=UIGestureRecognizerStateChanged)return;
    CGPoint p=[g locationInView:v];p.x=MAX(CGRectGetMinX(v.bounds)+2,MIN(CGRectGetMaxX(v.bounds)-2,p.x));p.y=CGRectGetMidY(v.bounds);
    p=[v convertPoint:p toView:w];
    if(!self.bubble){
        LEMGlass23Chrome *b=[[LEMGlass23Chrome alloc] initWithFrame:CGRectMake(0,0,34,24)];b.module=LEMSeek;b.accessibilityElementsHidden=YES;
        self.bubble=b;[w addSubview:b];b.center=p;b.alpha=0;b.transform=CGAffineTransformMakeScale(.65,.65);
        [UIView animateWithDuration:.26 delay:0 usingSpringWithDamping:.68 initialSpringVelocity:0 options:UIViewAnimationOptionAllowUserInteraction animations:^{b.alpha=1;b.transform=CGAffineTransformIdentity;} completion:nil];
        if(studioHaptics){UISelectionFeedbackGenerator *f=[UISelectionFeedbackGenerator new];[f selectionChanged];}
    }
    self.bubble.center=p;
}
- (void)dealloc{[self.bubble removeFromSuperview];}
@end
static BOOL seekGeometry(UIView *v){
    return visible(v)&&v.bounds.size.width>=120&&v.bounds.size.height>=5&&v.bounds.size.height<=54&&ancestorMatches(v,@[@"YTMainAppVideoPlayerOverlayView",@"YTInlinePlayerBarContainerView"]);
}
static void seekApply(UIView *v){
    if(!studioModules[LEMSeek]||!seekGeometry(v)||objc_getAssociatedObject(v,&seekKey))return;
    for(UIView *p=v.superview;p&&p!=v.window;p=p.superview)if(objc_getAssociatedObject(p,&seekKey))return;
    LEMGlass23Seek *d=[LEMGlass23Seek new];d.host=v;
    UILongPressGestureRecognizer *g=[[UILongPressGestureRecognizer alloc] initWithTarget:d action:@selector(touch:)];g.minimumPressDuration=.04;g.allowableMovement=1000;g.cancelsTouchesInView=NO;g.delaysTouchesBegan=NO;g.delaysTouchesEnded=NO;g.delegate=d;d.gesture=g;
    [v addGestureRecognizer:g];objc_setAssociatedObject(v,&seekKey,d,OBJC_ASSOCIATION_RETAIN_NONATOMIC);moduleSeen[LEMSeek]++;
}
static void seekHook(NSString *name){
    Class c=NSClassFromString(name);SEL sel=@selector(layoutSubviews);Method m=c?class_getInstanceMethod(c,sel):NULL;char rt[8]={0};
    if(!c||![c isSubclassOfClass:UIView.class]||!m||method_getNumberOfArguments(m)!=2)return;method_getReturnType(m,rt,sizeof rt);if(rt[0]!='v')return;
    IMP orig=method_getImplementation(m);IMP impl=imp_implementationWithBlock(^(UIView *v){((void(*)(id,SEL))orig)(v,sel);@try{seekApply(v);}@catch(NSException *e){}});
    class_replaceMethod(c,sel,impl,method_getTypeEncoding(m));moduleHooks[LEMSeek]++;
}
static void installFullGlass(void){
    fullHosts=[NSHashTable weakObjectsHashTable];
    for(NSString *n in @[@"YTPlayerBarView",@"YTInlinePlayerBarView",@"YTPlayerBarScrubberView",@"YTPlayerScrubberView",@"YTProgressBarView"])seekHook(n);
    fullViewHook(@"YTChipCloudChipView",LEMChips,NO);
    fullViewHook(@"YTPlayerButton",LEMPlayer,NO);
    fullViewHook(@"YTTransportControlsButtonView",LEMPlayer,NO);
    fullViewHook(@"YTWatchFloatingMiniplayerActionButtonView",LEMPlayer,NO);
    fullActionContainer(@"YTSlimVideoScrollableDetailsActionsView");
    fullViewHook(@"YTSlimVideoDetailsActionView",LEMActions,NO);
    fullSheetView(@"YTOverflowMenuView");
    fullSheetHook(@"YTActionSheetController");fullSheetHook(@"YTActionSheetDialogViewController");fullSheetHook(@"YTBottomSheetController");fullSheetHook(@"YTElementsActionSheetController");fullSheetHook(@"YTOverflowMenuViewController");
    fullViewHook(@"YTSlimVideoInformationCell",LEMInfo,YES);fullViewHook(@"YTSlimVideoDescriptionCell",LEMInfo,YES);
    fullViewHook(@"YTCommentsHeaderView",LEMComments,YES);
}
static void studioRefresh(void){
    loadStudio();
    for(UIView *v in fullHosts.allObjects){
        LEMGlass23Chrome *p=objc_getAssociatedObject(v,&fullPlateKey);
        if(p&&!studioModules[p.module])removeFull(v);else if(p)fullApply(v,p.module,p.shadeOnly);
    }
    for(UITextField *f in studioSearchFields.allObjects){if(studioSearch)applySearch(f,NO);else restoreSearch(f);}
    for(LEMGlass23Surface *v in studioSurfaces.allObjects){
        v.nextCapture=0;
        [v.host setNeedsLayout];[v refresh];
    }
    [currentPivot setNeedsLayout];
}
@interface LEMGlass23Settings : UITableViewController
@end
@implementation LEMGlass23Settings
- (void)viewDidLoad{
    [super viewDidLoad];self.title=@"LEM Glass Studio";
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(closeStudio)];
    self.tableView.rowHeight=62;
}
- (void)closeStudio{[self dismissViewControllerAnimated:YES completion:nil];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t{return 5;}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s{return s==0?3:s==1?4:s==2?5:s==3?7:1;}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s{return @[@"Phong cách",@"Tinh chỉnh kính",@"Hiệu ứng",@"Full Glass UI",@"Khôi phục"][s];}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s{
    if(s==0)return @"Chọn nhanh một kiểu kính hoặc tự chỉnh bên dưới.";
    if(s==2)return @"Chế độ nhẹ tự dùng blur khi máy nóng hoặc tiết kiệm pin. Hiệu ứng video phụ thuộc hook tương thích.";
    if(s==3)return @"Các module mới chỉ thay giao diện; tắt riêng nếu có lỗi. Hook đã cài chưa đồng nghĩa hiệu ứng đã hiện.";
    if(s==4)return @"LEM Glass Studio 2.3 • YouTube 21.33.6 • iOS 16+";
    return nil;
}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip{
    UITableViewCell *c=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    if(ip.section==0){
        c.textLabel.text=@[@"Trong suốt",@"Cân bằng",@"Tiết kiệm hiệu năng"][ip.row];c.detailTextLabel.text=@[@"Kính nhẹ, ít phủ màu",@"Khúc xạ và tương phản cân đối",@"Blur nhẹ, không lấy mẫu quang học"][ip.row];
        c.accessoryType=studioPreset==ip.row+1?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;
    }else if(ip.section==1){
        NSArray *titles=@[@"Độ phủ màu",@"Độ mờ nền",@"Độ đàn hồi",@"Khúc xạ"];
        NSArray *values=@[@(studioTint*100),@(studioBlur),@(studioElastic*100),@(studioRefraction*100)];
        c.textLabel.text=titles[ip.row];c.detailTextLabel.text=[NSString stringWithFormat:@"%.0f%@",[values[ip.row] doubleValue],ip.row==1?@"":@"%"];
        UISlider *slider=[[UISlider alloc] initWithFrame:CGRectMake(0,0,146,36)];
        slider.minimumValue=0;slider.maximumValue=[@[@60,@20,@100,@150][ip.row] floatValue];slider.value=[values[ip.row] floatValue];slider.tag=ip.row;slider.accessibilityLabel=titles[ip.row];[slider addTarget:self action:@selector(slide:) forControlEvents:UIControlEventValueChanged];c.accessoryView=slider;c.selectionStyle=UITableViewCellSelectionStyleNone;
    }else if(ip.section==2){
        NSArray *titles=@[@"Rung phản hồi",@"Tự giảm hiệu ứng khi máy nóng",@"Video Morph (thử nghiệm)",@"Ambient Color (thử nghiệm)",@"Glass Search (ô tìm kiếm)"];
        NSArray *values=@[@(studioHaptics),@(studioPower),@(studioMorph),@(studioAmbient),@(studioSearch)];
        c.textLabel.text=titles[ip.row];c.textLabel.font=[UIFont systemFontOfSize:15];
        UISwitch *sw=[UISwitch new];sw.on=[values[ip.row] boolValue];sw.tag=ip.row;sw.accessibilityLabel=titles[ip.row];[sw addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];c.accessoryView=sw;c.selectionStyle=UITableViewCellSelectionStyleNone;
    }else if(ip.section==3){
        NSUInteger i=ip.row;c.textLabel.text=moduleTitles()[i];c.textLabel.font=[UIFont systemFontOfSize:15];
        c.detailTextLabel.text=[NSString stringWithFormat:@"Hook: %lu • Đã nhận diện: %lu",(unsigned long)moduleHooks[i],(unsigned long)moduleSeen[i]];
        UISwitch *sw=[UISwitch new];sw.on=studioModules[i];sw.tag=100+i;sw.enabled=moduleHooks[i]>0;[sw addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];c.accessoryView=sw;c.selectionStyle=UITableViewCellSelectionStyleNone;
    }else c.textLabel.text=@"Đặt lại mặc định";
    return c;
}
- (void)slide:(UISlider *)slider{
    NSInteger row=slider.tag;if(row<0||row>3)return;
    NSUserDefaults *d=NSUserDefaults.standardUserDefaults;NSString *key=@[@"LEM.Studio.tint",@"LEM.Studio.blur",@"LEM.Studio.elastic",@"LEM.Studio.refraction"][row];
    [d setDouble:row==1?round(slider.value):slider.value/100. forKey:key];
    if(studioPreset!=3)[d setInteger:0 forKey:@"LEM.Studio.preset"];
    loadStudio();[currentPivot setNeedsLayout];
    UITableViewCell *c=[self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:1]];
    c.detailTextLabel.text=[NSString stringWithFormat:@"%.0f%@",slider.value,row==1?@"":@"%"];
    for(NSInteger i=0;i<3;i++)[self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:i inSection:0]].accessoryType=studioPreset==i+1?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;
}
- (void)toggle:(UISwitch *)sw{
    if(sw.tag>=100&&sw.tag<107){[NSUserDefaults.standardUserDefaults setBool:sw.on forKey:[@"LEM.Studio." stringByAppendingString:moduleKeys()[sw.tag-100]]];studioRefresh();return;}
    if(sw.tag<0||sw.tag>4)return;
    NSString *key=@[@"LEM.Studio.haptic",@"LEM.Studio.power",@"LEM.Studio.morph",@"LEM.Studio.ambient",@"LEM.Studio.search"][sw.tag];
    [NSUserDefaults.standardUserDefaults setBool:sw.on forKey:key];studioRefresh();
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip{
    [t deselectRowAtIndexPath:ip animated:YES];NSUserDefaults *d=NSUserDefaults.standardUserDefaults;
    if(ip.section==0){
        [d setInteger:ip.row+1 forKey:@"LEM.Studio.preset"];
        [d setDouble:[@[@.05,@.15,@.18][ip.row] doubleValue] forKey:@"LEM.Studio.tint"];
        [d setInteger:[@[@2,@6,@8][ip.row] integerValue] forKey:@"LEM.Studio.blur"];
        [d setDouble:ip.row==2?.25:.8 forKey:@"LEM.Studio.elastic"];
        [d setDouble:ip.row==0?1.2:1. forKey:@"LEM.Studio.refraction"];
    }else if(ip.section==4){
        for(NSString *k in moduleKeys())[d removeObjectForKey:[@"LEM.Studio." stringByAppendingString:k]];
        for(NSString *k in @[@"tint",@"blur",@"elastic",@"refraction",@"haptic",@"power",@"morph",@"ambient",@"search",@"preset"])[d removeObjectForKey:[@"LEM.Studio." stringByAppendingString:k]];
    }else return;
    studioRefresh();[t reloadData];
}
@end
static void openStudio(UIViewController *vc,SEL sel,id sender){
    if(!vc.viewIfLoaded.window||vc.presentedViewController)return;
    LEMGlass23Settings *p=[[LEMGlass23Settings alloc] initWithStyle:UITableViewStyleInsetGrouped];UINavigationController *nav=[[UINavigationController alloc] initWithRootViewController:p];nav.modalPresentationStyle=UIModalPresentationPageSheet;[vc presentViewController:nav animated:YES completion:nil];
}
static void studioEntry(UIViewController *vc){
    UIView *v=vc.viewIfLoaded;if(!v.window||v.bounds.size.width<200||v.bounds.size.height<160)return;
    UIViewController *parent=vc.parentViewController;Class a=NSClassFromString(@"YTSettingsViewController"),b=NSClassFromString(@"YTSearchableSettingsViewController");
    if(parent&&((a&&[parent isKindOfClass:a])||(b&&[parent isKindOfClass:b])))return;
    UIButton *button=objc_getAssociatedObject(vc,&studioEntryKey);
    if(!button){button=[UIButton buttonWithType:UIButtonTypeSystem];[button setTitle:@"Glass Studio" forState:UIControlStateNormal];button.titleLabel.font=[UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];button.backgroundColor=UIColor.secondarySystemBackgroundColor;button.layer.cornerRadius=16;button.accessibilityLabel=@"LEM Glass Studio";[button addTarget:vc action:NSSelectorFromString(@"lemOpenGlassStudio:") forControlEvents:UIControlEventTouchUpInside];[v addSubview:button];objc_setAssociatedObject(vc,&studioEntryKey,button,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
    button.frame=CGRectMake(v.bounds.size.width-v.safeAreaInsets.right-116,v.safeAreaInsets.top+7,104,32);[v bringSubviewToFront:button];
}
static void settingsLayout(UIViewController *vc,SEL s){((void(*)(id,SEL))oldSettingsLayout)(vc,s);studioEntry(vc);}
static void searchSettingsLayout(UIViewController *vc,SEL s){((void(*)(id,SEL))oldSearchSettingsLayout)(vc,s);studioEntry(vc);}
static IMP attach(Class c,SEL sel,IMP replacement,const char *types,unsigned n){
    Method m=c?class_getInstanceMethod(c,sel):NULL;
    if(!m||method_getNumberOfArguments(m)!=n)return NULL;
    char a[8]={0};method_getReturnType(m,a,sizeof a);if(a[0]!=types[0])return NULL;
    for(unsigned i=2;i<n;i++){method_getArgumentType(m,i,a,sizeof a);if(a[0]!=types[i-1])return NULL;}
    IMP p=method_getImplementation(m);if(!p)return NULL;class_replaceMethod(c,sel,replacement,method_getTypeEncoding(m));return p;
}
static void flag(NSString *name){
    Class c=NSClassFromString(@"YTColdConfig");SEL sel=NSSelectorFromString(name);
    Method m=c?class_getInstanceMethod(c,sel):NULL;char a[8]={0};if(!m||method_getNumberOfArguments(m)!=2)return;method_getReturnType(m,a,sizeof a);if(a[0]!='B'&&a[0]!='c')return;
    IMP impl=imp_implementationWithBlock(^BOOL(id x){return YES;});class_replaceMethod(c,sel,impl,method_getTypeEncoding(m));
}
__attribute__((constructor)) static void start(void){
    @autoreleasepool{
        NSBundle *b=NSBundle.mainBundle;
        if(![b.bundleIdentifier isEqualToString:@"com.google.ios.youtube"]||![[b objectForInfoDictionaryKey:@"CFBundleShortVersionString"] isEqualToString:@"21.33.6"])return;
        dispatch_async(dispatch_get_main_queue(),^{
            loadStudio();studioSurfaces=[NSHashTable weakObjectsHashTable];installSearchObserver();installFullGlass();
            // Keep native content-under-tab layout, not the old colored blur plate.
            flag(@"mainAppCoreClientEnableModernIaFrostedBottomBar");flag(@"mainAppCoreClientEnableModernIaFrostedPivotBar");
            Class p=NSClassFromString(@"YTPivotBarView");
            if(p&&[p isSubclassOfClass:UIView.class]){
                oldPivot=attach(p,@selector(layoutSubviews),(IMP)pivotLayout,"v",2);
                if(oldPivot){oldSelect=attach(p,NSSelectorFromString(@"selectItemWithPivotIdentifier:"),(IMP)selectTab,"v@",3);oldStyle=attach(p,NSSelectorFromString(@"styleBackgroundColors"),(IMP)styleChrome,"v",2);
                    SEL hs=@selector(hitTest:withEvent:);Method hm=class_getInstanceMethod(p,hs);char ht[12]={0},ha[96]={0},he[12]={0};
                    if(hm&&method_getNumberOfArguments(hm)==4){method_getReturnType(hm,ht,sizeof ht);method_getArgumentType(hm,2,ha,sizeof ha);method_getArgumentType(hm,3,he,sizeof he);if(ht[0]=='@'&&strncmp(ha,"{CGPoint=",9)==0&&he[0]=='@'){oldPivotHit=method_getImplementation(hm);class_replaceMethod(p,hs,(IMP)pivotHit,method_getTypeEncoding(hm));}}
                }
            }
            Class right=NSClassFromString(@"YTRightNavigationButtons");
            if(right&&[right isSubclassOfClass:UIView.class])oldRight=attach(right,@selector(layoutSubviews),(IMP)rightLayout,"v",2);
            Class mini=NSClassFromString(@"YTWatchFloatingMiniplayerWithPersistentControlsView");
            if(mini&&[mini isSubclassOfClass:UIView.class]){
                SEL fs=@selector(setFrame:);Method fm=class_getInstanceMethod(mini,fs);char rt[16]={0},arg[128]={0};
                if(fm&&method_getNumberOfArguments(fm)==3){method_getReturnType(fm,rt,sizeof rt);method_getArgumentType(fm,2,arg,sizeof arg);if(rt[0]=='v'&&strncmp(arg,"{CGRect=",8)==0){oldMiniFrame=method_getImplementation(fm);class_replaceMethod(mini,fs,(IMP)miniFrame,method_getTypeEncoding(fm));}}
                if(oldMiniFrame){
                    oldMiniLayout=attach(mini,@selector(layoutSubviews),(IMP)miniLayout,"v",2);
                    oldMiniMove=attach(mini,@selector(didMoveToWindow),(IMP)miniMove,"v",2);
                }
            }
            Class layer=NSClassFromString(@"YTWatchLayerView");
            if(oldMiniFrame&&layer&&[layer isSubclassOfClass:UIView.class])oldLayerLayout=attach(layer,@selector(layoutSubviews),(IMP)layerLayout,"v",2);
            Class watch=NSClassFromString(@"YTMainAppVideoPlayerOverlayViewController");
            if(watch&&[watch isSubclassOfClass:UIViewController.class]){
                oldWatchLayout=attach(watch,@selector(viewDidLayoutSubviews),(IMP)watchLayout,"v",2);
                oldWatchDisappear=attach(watch,@selector(viewDidDisappear:),(IMP)watchDisappear,"vB",3);
            }
            Class search=NSClassFromString(@"YTSearchBoxView");
            if(search&&[search isSubclassOfClass:UIView.class])oldSearchLayout=attach(search,@selector(layoutSubviews),(IMP)searchLayout,"v",2);
            Class settings=NSClassFromString(@"YTSettingsViewController"),searchSettings=NSClassFromString(@"YTSearchableSettingsViewController");SEL action=NSSelectorFromString(@"lemOpenGlassStudio:");
            if(settings&&[settings isSubclassOfClass:UIViewController.class]){class_addMethod(settings,action,(IMP)openStudio,"v@:@");oldSettingsLayout=attach(settings,@selector(viewDidLayoutSubviews),(IMP)settingsLayout,"v",2);}
            if(searchSettings&&searchSettings!=settings&&[searchSettings isSubclassOfClass:UIViewController.class]){if(!class_getInstanceMethod(searchSettings,action))class_addMethod(searchSettings,action,(IMP)openStudio,"v@:@");oldSearchSettingsLayout=attach(searchSettings,@selector(viewDidLayoutSubviews),(IMP)searchSettingsLayout,"v",2);}
            NSLog(@"[%@] pivot=%d mini=%d motion=%d search=%d studio=%d",buildName,oldPivot!=NULL,oldMiniFrame!=NULL,oldWatchLayout!=NULL,oldSearchLayout!=NULL,(oldSettingsLayout||oldSearchSettingsLayout)!=0);
        });
    }
}
