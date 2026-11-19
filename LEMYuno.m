/* LEM Yuno Glass Only 1.1 — independent UIKit implementation.
   Visual reference: https://github.com/danielkanan/Yuno/tree/v1.1.1
   No ad, player, network or account hooks. */
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <math.h>

static NSString *const buildName=@"LEM Glass Only 1.1";
static char surfaceKey,pillKey,bgKey,oldHiddenKey;
static IMP oldPivot,oldRight,oldSelect;
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
static void clear(UIView *v){
    if(!v)return;
    if(!objc_getAssociatedObject(v,&bgKey))objc_setAssociatedObject(v,&bgKey,v.backgroundColor?:NSNull.null,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if(v.backgroundColor&&!CGColorEqualToColor(v.backgroundColor.CGColor,UIColor.clearColor.CGColor))v.backgroundColor=UIColor.clearColor;
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
static CGImageRef opticalImage(UIView *source,CGRect rect) CF_RETURNS_RETAINED;
static CGImageRef opticalImage(UIView *source,CGRect rect){
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
    int opaque=0;float lo=255,hi=0;
    for(int i=0;i<w*h;i++)if(raw[i*4+3]>225){opaque++;float y=.2126f*raw[i*4]+.7152f*raw[i*4+1]+.0722f*raw[i*4+2];lo=fminf(lo,y);hi=fmaxf(hi,y);}
    // A video surface or empty snapshot can return black; leave it transparent instead.
    if(opaque<w*h*.92||hi-lo<9)goto cleanup;
    for(int y=0;y<h;y++)for(int x=0;x<w;x++)for(int k=0;k<3;k++){
        int sum=0;for(int j=-2;j<=2;j++)sum+=raw[(y*w+clamp(x+j,0,w-1))*4+k];tmp[(y*w+x)*4+k]=sum/5;
    }
    for(int y=0;y<h;y++)for(int x=0;x<w;x++)for(int k=0;k<3;k++){
        int sum=0;for(int j=-2;j<=2;j++)sum+=tmp[(clamp(y+j,0,h-1)*w+x)*4+k];soft[(y*w+x)*4+k]=sum/5;
    }
    for(int y=0;y<h;y++)for(int x=0;x<w;x++){
        float radius=fminf(w,h)*.5f,px=x+.5f-w*.5f,py=y+.5f-h*.5f;
        float half=fmaxf(0,w*.5f-radius),cx=fmaxf(-half,fminf(half,px)),dx=px-cx,dy=py,d=hypotf(dx,dy);
        float u=fmaxf(0,fminf(1,1-(radius-d)/fmaxf(4,radius*.65f)));
        float nx=d>.001f?dx/d:0,ny=d>.001f?dy/d:0;
        float rgb[3];
        for(int k=0;k<3;k++){
            float shift=(7.0f+(1-k)*.45f)*u*u;
            rgb[k]=sample(soft,w,h,x-nx*shift,y-ny*shift,k);
        }
        float l=.2126f*rgb[0]+.7152f*rgb[1]+.0722f*rgb[2];
        for(int k=0;k<3;k++){
            float value=l+(rgb[k]-l)*1.32f;
            // Clear glass rather than the old charcoal tint. Bright edge, no black fill.
            value=value*.94f+7.f+12.f*u*u;
            dst[(y*w+x)*4+k]=(unsigned char)fmaxf(0,fminf(255,value));
        }
        dst[(y*w+x)*4+3]=255;
    }
    result=CGBitmapContextCreateImage(out);
cleanup:
    if(c)CGContextRelease(c);if(out)CGContextRelease(out);free(tmp);free(soft);return result;
}

@interface LEMGlass11Surface : UIView
@property(nonatomic,weak) UIView *host;
@property(nonatomic,strong) CALayer *picture;
@property(nonatomic,strong) CAGradientLayer *edge;
@property(nonatomic,strong) CAShapeLayer *edgeMask;
@property(nonatomic,strong) CAGradientLayer *gleam;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic) CFTimeInterval nextCapture;
@property(nonatomic) BOOL topChrome;
- (void)refresh;
@end
@implementation LEMGlass11Surface
- (instancetype)initWithFrame:(CGRect)f {
    if((self=[super initWithFrame:f])){
        self.userInteractionEnabled=NO;self.opaque=NO;self.backgroundColor=UIColor.clearColor;
        self.layer.masksToBounds=YES;self.layer.cornerCurve=kCACornerCurveContinuous;
        self.picture=[CALayer layer];self.picture.contentsGravity=kCAGravityResize;[self.layer addSublayer:self.picture];
        self.gleam=[CAGradientLayer layer];self.gleam.colors=@[(id)[UIColor colorWithWhite:1 alpha:.11].CGColor,(id)[UIColor colorWithWhite:1 alpha:.015].CGColor,(id)[UIColor colorWithWhite:1 alpha:.07].CGColor];self.gleam.locations=@[@0,@.50,@1];[self.layer addSublayer:self.gleam];
        self.edge=[CAGradientLayer layer];self.edge.startPoint=CGPointMake(.1,0);self.edge.endPoint=CGPointMake(.9,1);
        self.edge.colors=@[(id)[UIColor colorWithWhite:1 alpha:.66].CGColor,(id)[UIColor colorWithWhite:1 alpha:.10].CGColor,(id)[UIColor colorWithWhite:1 alpha:.36].CGColor];self.edge.locations=@[@0,@.48,@1];
        self.edgeMask=[CAShapeLayer layer];self.edgeMask.fillColor=nil;self.edgeMask.strokeColor=UIColor.whiteColor.CGColor;self.edgeMask.lineWidth=.55;self.edge.mask=self.edgeMask;[self.layer addSublayer:self.edge];
    }return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat r=MIN(self.bounds.size.height,self.bounds.size.width)*.5;
    [CATransaction begin];[CATransaction setDisableActions:YES];
    self.layer.cornerRadius=r;self.picture.frame=self.bounds;self.gleam.frame=self.bounds;self.edge.frame=self.bounds;self.edgeMask.frame=self.bounds;
    self.edgeMask.path=[UIBezierPath bezierPathWithRoundedRect:CGRectInset(self.bounds,.55,.55) cornerRadius:MAX(1,r-.55)].CGPath;
    [CATransaction commit];
}
- (void)refresh {
    if(!self.window||!self.host||self.hidden||self.host.hidden||self.host.alpha<.05||UIApplication.sharedApplication.applicationState!=UIApplicationStateActive)return;
    if(UIAccessibilityIsReduceTransparencyEnabled()){
        self.picture.contents=nil;self.backgroundColor=UIColor.secondarySystemBackgroundColor;return;
    }
    self.backgroundColor=UIColor.clearColor;
    if(CACurrentMediaTime()<self.nextCapture)return;
    CGRect region=[self convertRect:self.bounds toView:self.window];
    UIView *src=backdrop(self.host,region);
    if(!src){self.picture.contents=nil;return;}
    CFTimeInterval start=CACurrentMediaTime();
    CGImageRef image=opticalImage(src,[src convertRect:region fromView:self.window]);
    [CATransaction begin];[CATransaction setDisableActions:YES];self.picture.contents=image?(__bridge id)image:nil;[CATransaction commit];if(image)CGImageRelease(image);
    CFTimeInterval elapsed=CACurrentMediaTime()-start;
    self.nextCapture=CACurrentMediaTime()+(elapsed>.018?.48:NSProcessInfo.processInfo.lowPowerModeEnabled?.5:.11);
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self.timer invalidate];self.timer=nil;
    if(!self.window){self.picture.contents=nil;return;}
    __weak typeof(self) weak=self;
    self.timer=[NSTimer timerWithTimeInterval:.14 repeats:YES block:^(NSTimer *t){LEMGlass11Surface *s=weak;if(!s){[t invalidate];return;}[s refresh];}];
    self.timer.tolerance=.025;[[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
}
- (void)dealloc{[self.timer invalidate];}
@end

static LEMGlass11Surface *ensureSurface(UIView *host,CGRect f){
    LEMGlass11Surface *s=objc_getAssociatedObject(host,&surfaceKey);
    if(!s){s=[[LEMGlass11Surface alloc] initWithFrame:f];s.host=host;objc_setAssociatedObject(host,&surfaceKey,s,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
    if(s.superview!=host)[host insertSubview:s atIndex:0];else if(host.subviews.firstObject!=s)[host sendSubviewToBack:s];
    if(!CGRectEqualToRect(s.frame,f))s.frame=f;
    return s;
}
static void updatePivot(UIView *host){
    if(!host.window||host.bounds.size.width<160||host.bounds.size.height<30)return;
    NSArray<UIView *> *items=tabs(host);if(items.count<2)return;
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
    // Remove the native dark plate. Only explicitly known background views.
    clear(host);if(content&&content!=host)clear(content);
    if(blur&&blur!=host&&[blur isDescendantOfView:host])hideSafe(blur,protected);
    if(sep&&sep!=host&&[sep isDescendantOfView:host])hideSafe(sep,protected);
    // Some builds mount a separate flat background inside contentView.
    // Hide only full-width, decorative plain/image/effect views, never buttons or tab ancestors.
    NSArray *holders=content&&content!=host?@[host,content]:@[host];
    for(UIView *parent in holders)for(UIView *v in [parent.subviews copy]){
        if(v==blur||v==sep||v==content||[v isKindOfClass:LEMGlass11Surface.class]||v==objc_getAssociatedObject(host,&pillKey))continue;
        if(v.bounds.size.width<parent.bounds.size.width*.87||v.bounds.size.height<25||v.bounds.size.height>180)continue;
        NSString *name=NSStringFromClass(v.class).lowercaseString;
        BOOL decorative=[v isKindOfClass:UIVisualEffectView.class]||[v isKindOfClass:UIImageView.class]||(!v.userInteractionEnabled&&([name containsString:@"background"]||[name containsString:@"backdrop"]||[name containsString:@"blur"]));
        if(decorative)hideSafe(v,protected);
    }
    LEMGlass11Surface *surface=ensureSurface(host,frame);
    UIView *pill=objc_getAssociatedObject(host,&pillKey);
    UIView *parent=content&&content!=host&&[content isDescendantOfView:host]?content:host;
    if(!pill){
        pill=[UIView new];pill.userInteractionEnabled=NO;pill.opaque=NO;pill.alpha=0;pill.layer.cornerCurve=kCACornerCurveContinuous;
        pill.layer.borderColor=[UIColor colorWithWhite:1 alpha:.17].CGColor;pill.layer.borderWidth=.5;objc_setAssociatedObject(host,&pillKey,pill,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if(pill.superview!=parent){
        if(parent==host)[host insertSubview:pill aboveSubview:surface];else [parent insertSubview:pill atIndex:0];
    }
    if(CGRectIsNull(chosen)){pill.alpha=0;return;}
    CGRect target=CGRectIntersection(CGRectInset(frame,4,4),CGRectInset(chosen,3,0));
    if(CGRectIsNull(target)||target.size.height<20||target.size.width<12){pill.alpha=0;return;}
    target=[host convertRect:target toView:parent];
    pill.backgroundColor=[UIColor colorWithWhite:1 alpha:.14];
    CGFloat rad=MIN(target.size.height,target.size.width)*.5;
    if(pill.alpha==0||UIAccessibilityIsReduceMotionEnabled()){pill.frame=target;pill.layer.cornerRadius=rad;pill.alpha=1;}
    else if(!CGRectEqualToRect(pill.frame,target)){
        [UIView animateWithDuration:.36 delay:0 usingSpringWithDamping:.72 initialSpringVelocity:.1 options:UIViewAnimationOptionBeginFromCurrentState|UIViewAnimationOptionAllowUserInteraction animations:^{pill.frame=target;pill.layer.cornerRadius=rad;} completion:nil];
    }
}
static void pivotLayout(UIView *v,SEL s){((void(*)(id,SEL))oldPivot)(v,s);@try{updatePivot(v);}@catch(NSException *e){NSLog(@"[LEM Glass] %@",e.reason);}}
static void selectTab(UIView *v,SEL s,id key){((void(*)(id,SEL,id))oldSelect)(v,s,key);[v setNeedsLayout];}
static void rightLayout(UIView *v,SEL s){
    ((void(*)(id,SEL))oldRight)(v,s);
    if(!v.window||v.bounds.size.width<35||v.bounds.size.width>260||v.bounds.size.height<25||v.bounds.size.height>90)return;
    @try{
        CGRect f=CGRectInset(v.bounds,2,3);if(f.size.width<28||f.size.height<24)return;
        clear(v);LEMGlass11Surface *surface=ensureSurface(v,f);surface.topChrome=YES;
    }@catch(NSException *e){}
}
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
            // Keep native content-under-tab layout, not the old colored blur plate.
            flag(@"mainAppCoreClientEnableModernIaFrostedBottomBar");flag(@"mainAppCoreClientEnableModernIaFrostedPivotBar");
            Class p=NSClassFromString(@"YTPivotBarView");
            if(p&&[p isSubclassOfClass:UIView.class]){
                oldPivot=attach(p,@selector(layoutSubviews),(IMP)pivotLayout,"v",2);
                if(oldPivot)oldSelect=attach(p,NSSelectorFromString(@"selectItemWithPivotIdentifier:"),(IMP)selectTab,"v@",3);
            }
            Class right=NSClassFromString(@"YTRightNavigationButtons");
            if(right&&[right isSubclassOfClass:UIView.class])oldRight=attach(right,@selector(layoutSubviews),(IMP)rightLayout,"v",2);
            NSLog(@"[%@] pivot=%d right=%d",buildName,oldPivot!=NULL,oldRight!=NULL);
        });
    }
}
