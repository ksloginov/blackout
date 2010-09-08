/*
 * Copyright (C) 2010 Michael Dippery <mdippery@gmail.com>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#import "BOBundle.h"


@implementation BOBundle

+ (NSBundle *)preferencePaneBundle
{
    NSBundle *bundle = [NSBundle bundleWithIdentifier:@"com.monkey-robot.Blackout.prefpane"];
    if (!bundle) {
        //NSLog(@"Could retrieve Blackout.prefPane bundle -- trying the hard way");
        NSString *appPath = [[BOBundle helperBundle] bundlePath];
        NSString *bundlePath = [[[appPath stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
        //NSLog(@"Checking for bundle at path %@", bundlePath);
        bundle = [NSBundle bundleWithPath:bundlePath];
    }
    //NSLog(@"Cool, we got the Blackout.prefPane bundle: %@", bundle);
    return bundle;
}

+ (NSBundle *)helperBundle
{
    NSBundle *bundle = [NSBundle bundleWithIdentifier:@"com.monkey-robot.Blackout"];
    if (!bundle) {
        //NSLog(@"Couldn't retrieve Blackout.app bundle -- trying the hard way");
        NSBundle *prefBundle = [BOBundle preferencePaneBundle];
        NSString *appPath = [prefBundle pathForResource:@"Blackout" ofType:@"app"];
        if (!appPath) {
            //NSLog(@"Could not get path to Blackout.app -- now we're really boned");
            return nil;
        }
        bundle = [NSBundle bundleWithPath:appPath];
    }
    //NSLog(@"Cool, we got the Blackout.app bundle: %@", bundle);
    return bundle;
}

@end
