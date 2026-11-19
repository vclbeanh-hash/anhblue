/* LEM Yuno v0.5 — independent iOS tweak, inspired by Yuno.
   Runtime selector references: https://github.com/dayanch96/YTLite
   Design reference: https://github.com/danielkanan/Yuno/tree/v1.0.0 */
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
static void pivot(UIView *t,SEL s){
    ((void(*)(id,SEL))origPivot)(t,s);
    if(!t.window||t.bounds.size.width<120||t.bounds.size.height<30)return;
    UIVisualEffectView *glass=objc_getAssociatedObject(t,&glassKey);
    id blur=getObj(t,@"blurView");
    if(!enabled(Kglass)){
        if(glass){[glass removeFromSuperview];objc_setAssociatedObject(t,&glassKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
        id original=objc_getAssociatedObject(t,&glassBgKey);
        if(original){t.backgroundColor=original==NSNull.null?nil:original;objc_setAssociatedObject(t,&glassBgKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
        if([blur isKindOfClass:UIVisualEffectView.class]){
            id effect=objc_getAssociatedObject(blur,&glassEffectKey);
            if(effect){((UIVisualEffectView *)blur).effect=effect==NSNull.null?nil:effect;objc_setAssociatedObject(blur,&glassEffectKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
        }
        return;
    }
    if(!objc_getAssociatedObject(t,&glassBgKey))objc_setAssociatedObject(t,&glassBgKey,t.backgroundColor?:NSNull.null,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    t.backgroundColor=UIColor.clearColor;
    if([blur isKindOfClass:UIVisualEffectView.class]){
        if(glass){[glass removeFromSuperview];objc_setAssociatedObject(t,&glassKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
        UIVisualEffectView *native=blur;
        if(!objc_getAssociatedObject(native,&glassEffectKey)){
            objc_setAssociatedObject(native,&glassEffectKey,native.effect?:NSNull.null,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            native.effect=[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial];
        }
        return;
    }
    if(!glass){
        glass=[[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial]];
        glass.userInteractionEnabled=NO;glass.layer.cornerRadius=20;glass.clipsToBounds=YES;
        glass.layer.borderWidth=.75;glass.layer.borderColor=[UIColor colorWithWhite:1 alpha:.24].CGColor;
        [t insertSubview:glass atIndex:0];objc_setAssociatedObject(t,&glassKey,glass,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    CGRect f=t.bounds;f.origin.x+=5;f.origin.y+=3;f.size.width-=10;f.size.height=MIN(f.size.height-6,72);glass.frame=f;
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
        [NSUserDefaults.standardUserDefaults setBool:on forKey:key];if([key isEqual:Ksb]&&!on)resetSponsor();if([key isEqual:Khd])qualityID=nil;return YES;
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
        if(available(vc,modern,8))((void(*)(id,SEL,id,NSUInteger,id,id,id,BOOL))objc_msgSend)(vc,modern,rows,LemCategory,@"LEM Yuno",nil,@"v0.5",NO);
        else if(available(vc,legacy,7))((void(*)(id,SEL,id,NSUInteger,id,id,BOOL))objc_msgSend)(vc,legacy,rows,LemCategory,@"LEM Yuno",@"v0.5",NO);
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

// v0.5: settings entry independent of YouTube's changing category model.
@interface LEMYunoPreferencesController : UITableViewController
@property(nonatomic,strong) NSArray<NSDictionary *> *options;
@end
@implementation LEMYunoPreferencesController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title=@"LEM Yuno";
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(lemClose)];
    self.options=@[
      @{@"key":Kad,@"title":@"Chặn quảng cáo",@"note":@"Giảm quảng cáo (thử nghiệm)"},
      @{@"key":Kbg,@"title":@"Phát nền",@"note":@"Nghe khi tắt màn hình"},
      @{@"key":Ksb,@"title":@"SponsorBlock",@"note":@"Tra cứu ID video trên SponsorBlock"},
      @{@"key":Khd,@"title":@"Ưu tiên 1080p",@"note":@"Khi chất lượng video có sẵn"},
      @{@"key":Kglass,@"title":@"Liquid Glass",@"note":@"Thanh điều hướng (thử nghiệm)"},
      @{@"key":Kmini,@"title":@"Mini Player tăng cường",@"note":@"Cho phép phát trong mini player khi chế độ chỉ tạm dừng được yêu cầu"}
    ];
    self.tableView.rowHeight=66;
}
- (void)lemClose {[self dismissViewControllerAnimated:YES completion:nil];}
- (void)viewWillAppear:(BOOL)animated {[super viewWillAppear:animated];[self.tableView reloadData];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView{return 2;}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)section{return section==0?self.options.count:1;}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)section{return section==0?@"Tính năng":@"Trình phát";}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)section{return section==0?@"Các lựa chọn được lưu tự động. PiP, Shorts và Google giữ nguyên từ ứng dụng YouTube.":@"LEM Yuno v0.5 • YouTube 21.33.6";}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip{
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    if(ip.section==0){
        NSDictionary *row=self.options[ip.row]; NSString *key=row[@"key"];
        cell.textLabel.text=row[@"title"];cell.detailTextLabel.text=row[@"note"];cell.detailTextLabel.numberOfLines=2;
        UISwitch *sw=[UISwitch new];sw.on=enabled(key);sw.tag=ip.row;
        BOOL supported=([key isEqual:Kad]?origAd!=NULL:[key isEqual:Kbg]?(origBG||origML)!=0:([key isEqual:Ksb]||[key isEqual:Khd])?origTick!=NULL:[key isEqual:Kglass]?origPivot!=NULL:origMini!=NULL);
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
    installSettingsEntry();
    NSLog(@"[LEMYuno] Loaded settings=%d background=%d ad=%d",(origSettingsLayout||origSearchSettingsLayout)!=0,(origBG||origML)!=0,origAd!=NULL);
  });
 }
}
