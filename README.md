# Objective-C NuREPL for iOS

Give instructions directly to a running iOS app in the simulator, through a clojure repl. You can play with whatever objects that are synthesized ie., accessible.
The code syntax used for sending instructions is Nu Lisp.
http://programming.nu/reference

Thanks to Tim Burks for Nu Lisp!

# Usage

Add the static libraries and .h .m files in the "Remote" folder into your XCode project.

In the app delegate .h file add the following above @interface:

    @class SPNuRemote;

Declare in the app delegate interface an SPNuRemote object

    SPNuRemote *remote;

In the app delegate .m file

    #import "NuRemote/SPNuRemote.h"

and somewhere in the function

    - (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions

write

    remote = [SPNuRemote new];
    [remote run];

Thats it!

# Running

First run the simulator app.
Then do a

     lein swank

in objc-repl and complile the core.clj

To execute a line of code in iOS simulator call the sim function.

For example to do

    NSLog("Hello ObjC from Clojure")

Use the following method

    objc-repl.core> (sim "(log \"Hello ObjC from Clojure\")")

General syntax is

    (sim "Nu Code")

Nu code is Objective-C code but with square brackets replaced with round ones.
NSStrings are just "string" instead of @"string"
Selectors are defined as "showScreen" instead of @selector(showScreen)
and, structs like CGRect for frames are lists

# Example:

Support there is a button synthesized inside a class rootViewController, and we want to change its backgroundcolor:

    objc-repl.core> (sim "(set root (((UIApplication sharedApplication) delegate) viewController))")
    objc-repl.core> (sim "((root button) setBackgroundColor:(UIColor greenColor))")

Like changing a button frame

    objc-repl.core> (sim "(button setFrame:'(10 10 20 20))")


Creating a cutom button

For example UIButtonTypeCustom is 0 and UIControlStateNormal is also 0

    objc-repl.core> (sim "(set button (UIButton buttonWithType:'0))")
    objc-repl.core> (sim "(button setFrame:'(0 0 80 50))")
    objc-repl.core> (sim "(button setTitle:\"Click Me\" forState:'0)")
    objc-repl.core> (sim "((rootViewController view) addSubview:button)")

Enjoy!
