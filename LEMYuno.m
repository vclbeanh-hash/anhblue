/* LEM Yuno v0.3 — independent iOS tweak, inspired by Yuno.
   Runtime selector references: https://github.com/dayanch96/YTLite
   Design reference: https://github.com/danielkanan/Yuno/tree/v1.0.0 */
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <math.h>

static NSString * const Kbg=@"LEMYuno.background";
static NSString * const Kad=@"LEMYuno.adResponse";
static NSString * const Krate=@"LEMYuno.speed";
static char videoKey;
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
    if([NSUserDefaults.standardUserDefaults objectForKey:Krate]){
        if(!applyRate(t,savedRate()))applyRate(t.parentViewController,savedRate());
    }
}
static BOOL available(id obj,SEL sel,unsigned int argc){
    if(!obj||![obj respondsToSelector:sel])return NO;
    Method m=class_getInstanceMethod(object_getClass(obj),sel);
    return m&&method_getNumberOfArguments(m)==argc;
}
static id switches(NSString *title,NSString *description,NSString *key){
    Class c=NSClassFromString(@"YTSettingsSectionItem");
    SEL s=NSSelectorFromString(@"switchItemWithTitle:titleDescription:accessibilityIdentifier:switchOn:switchBlock:settingItemId:");
    if(!available(c,s,8))return nil;
    BOOL (^block)(id,BOOL)=^BOOL(id cell,BOOL on){
        [NSUserDefaults.standardUserDefaults setBool:on forKey:key];return YES;
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
        if(available(vc,modern,8))((void(*)(id,SEL,id,NSUInteger,id,id,id,BOOL))objc_msgSend)(vc,modern,rows,LemCategory,@"LEM Yuno",nil,@"v0.3",NO);
        else if(available(vc,legacy,7))((void(*)(id,SEL,id,NSUInteger,id,id,BOOL))objc_msgSend)(vc,legacy,rows,LemCategory,@"LEM Yuno",@"v0.3",NO);
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
__attribute__((constructor)) static void initialize(void){
 @autoreleasepool {
  NSBundle *bundle=NSBundle.mainBundle;
  if(![bundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"])return;
  if(![[bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] isEqualToString:@"21.33.6"])return;
  [NSUserDefaults.standardUserDefaults registerDefaults:@{Kbg:@YES,Kad:@YES}];
  dispatch_async(dispatch_get_main_queue(), ^{
    Class c=NSClassFromString(@"YTMainAppVideoPlayerOverlayViewController");
    SEL s=@selector(viewDidLayoutSubviews);
    if(c)origLayout=hook(c,s,(IMP)layout,NO);
    origBG=hook(NSClassFromString(@"YTIPlayabilityStatus"),NSSelectorFromString(@"isPlayableInBackground"),(IMP)yesBG,YES);
    origML=hook(NSClassFromString(@"MLVideo"),NSSelectorFromString(@"playableInBackground"),(IMP)yesML,YES);
    origAd=hook(NSClassFromString(@"YTIPlayerResponse"),NSSelectorFromString(@"isMonetized"),(IMP)noAd,YES);
    installSettings();
    NSLog(@"[LEMYuno] Loaded settings=%d background=%d ad=%d",origOrder!=NULL,(origBG||origML)!=0,origAd!=NULL);
  });
 }
}
