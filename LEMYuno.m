/* LEM Yuno v0.2 — independent iOS tweak, inspired by Yuno.
   Runtime selector references: https://github.com/dayanch96/YTLite
   Design reference: https://github.com/danielkanan/Yuno/tree/v1.0.0 */
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

static NSString * const Kbg=@"LEMYuno.background";
static NSString * const Kad=@"LEMYuno.adResponse";
static char glassKey;
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
static void menu(UIViewController *self,SEL cmd,id sender){
  (void)cmd;(void)sender;
  UIViewController *presenter=self;
  for(int i=0;i<6 && presenter.parentViewController;i++)presenter=presenter.parentViewController;
  if(presenter.presentedViewController||!presenter.viewIfLoaded.window)return;
  UIAlertController *a=[UIAlertController alertControllerWithTitle:@"LEM Yuno · 21.33.6"
     message:@"Tốc độ phát / Chế độ phát nền" preferredStyle:UIAlertControllerStyleAlert];
  __weak UIViewController *weakSelf=self;
  for(NSNumber *n in @[@0.5,@1,@1.5,@2,@2.5,@3]){
    double rate=n.doubleValue;
    [a addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@x",n] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){
      UIViewController *p=weakSelf;
      if(!applyRate(p,rate)&&!applyRate(p.parentViewController,rate))
        NSLog(@"[LEMYuno] Playback rate selector unavailable");
    }]];
  }
  if(origBG||origML)[a addAction:[UIAlertAction actionWithTitle:enabled(Kbg)?@"Phát nền: TẮT":@"Phát nền: BẬT" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x){toggle(Kbg);}]];
  if(origAd)[a addAction:[UIAlertAction actionWithTitle:enabled(Kad)?@"Giảm quảng cáo (thử nghiệm): TẮT":@"Giảm quảng cáo (thử nghiệm): BẬT" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x){toggle(Kad);}]];
  [a addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];
  [presenter presentViewController:a animated:YES completion:nil];
}
static void layout(UIViewController *t,SEL s){
  ((void(*)(id,SEL))origLayout)(t,s);
  UIView *v=t.viewIfLoaded; CGRect b=v.bounds;
  if(!v.window||b.size.width<170||b.size.height<100)return;
  UIVisualEffectView *glass=objc_getAssociatedObject(t,&glassKey);
  if(!glass){
    glass=[[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
    glass.clipsToBounds=YES;glass.layer.cornerRadius=16;
    glass.layer.borderWidth=.65;glass.layer.borderColor=[UIColor colorWithWhite:1 alpha:.35].CGColor;
    UIButton *btn=[UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame=CGRectMake(0,0,58,32);
    [btn setTitle:@"LEM" forState:UIControlStateNormal];
    [btn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    btn.titleLabel.font=[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    [btn addTarget:t action:NSSelectorFromString(@"lemYunoMenu:") forControlEvents:UIControlEventTouchUpInside];
    [glass.contentView addSubview:btn];[v addSubview:glass];
    objc_setAssociatedObject(t,&glassKey,glass,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  }else if(glass.superview!=v)[v addSubview:glass];
  glass.frame=CGRectMake(10,b.size.height*.48-16,58,32);
}
__attribute__((constructor)) static void initialize(void){
 @autoreleasepool {
  NSBundle *bundle=NSBundle.mainBundle;
  if(![bundle.bundleIdentifier isEqualToString:@"com.google.ios.youtube"])return;
  if(![[bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] isEqualToString:@"21.33.6"])return;
  dispatch_async(dispatch_get_main_queue(), ^{
    Class c=NSClassFromString(@"YTMainAppVideoPlayerOverlayViewController");
    SEL s=@selector(viewDidLayoutSubviews);
    if(c&&class_getInstanceMethod(c,s)&&class_addMethod(c,NSSelectorFromString(@"lemYunoMenu:"),(IMP)menu,"v@:@"))origLayout=hook(c,s,(IMP)layout,NO);
    origBG=hook(NSClassFromString(@"YTIPlayabilityStatus"),NSSelectorFromString(@"isPlayableInBackground"),(IMP)yesBG,YES);
    origML=hook(NSClassFromString(@"MLVideo"),NSSelectorFromString(@"playableInBackground"),(IMP)yesML,YES);
    origAd=hook(NSClassFromString(@"YTIPlayerResponse"),NSSelectorFromString(@"isMonetized"),(IMP)noAd,YES);
    NSLog(@"[LEMYuno] Loaded menu=%d background=%d ad=%d",origLayout!=NULL,(origBG||origML)!=0,origAd!=NULL);
  });
 }
}
